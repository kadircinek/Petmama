#!/usr/bin/env bash
# Mama Haritası — veritabanı testleri.
#
# Geçici bir PostgreSQL açar, supabase/migrations/*.sql'i sırayla, ardından seed.sql'i uygular ve
# supabase/tests/[1-9][0-9]_*.sql dosyalarını çalıştırır. Her test dosyası kendi transaction'ında
# çalışır ve rollback eder. Başarısız assert psql'i durdurur.
#
# Kullanım:
#   supabase/tests/run.sh                 # otomatik: Docker varsa supabase/postgres, yoksa yerel PG
#   MAMA_TEST_MODE=docker supabase/tests/run.sh
#   MAMA_TEST_MODE=local  supabase/tests/run.sh   # /usr/lib/postgresql/16/bin + PostGIS
#   MAMA_TEST_KEEP=1 ...                  # bitince veritabanını kapatma (hata ayıklama)
#   supabase/tests/run.sh 20_checkin.sql  # yalnızca verilen test dosyaları
#
# Ortam değişkenleri: MAMA_PG_IMAGE (varsayılan supabase/postgres:15.8.1.085), MAMA_TEST_PORT,
#                     MAMA_TEST_WORKDIR (yerel mod veri dizini), PG_BIN (yerel mod bin dizini)

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUPA="$(cd "$HERE/.." && pwd)"
MODE="${MAMA_TEST_MODE:-auto}"
IMAGE="${MAMA_PG_IMAGE:-supabase/postgres:15.8.1.085}"
PORT="${MAMA_TEST_PORT:-55432}"
WORK="${MAMA_TEST_WORKDIR:-${TMPDIR:-/tmp}/mama-haritasi-db-tests}"
PG_BIN="${PG_BIN:-/usr/lib/postgresql/16/bin}"
KEEP="${MAMA_TEST_KEEP:-0}"
CONTAINER="mama-haritasi-test-$$"
PGDATA_DIR=""
LOG="$WORK/run.log"

mkdir -p "$WORK"
: > "$LOG"

if [[ "$MODE" == "auto" ]]; then
  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then MODE=docker; else MODE=local; fi
fi

export PGHOST=127.0.0.1 PGPORT="$PORT" PGUSER=postgres PGPASSWORD=postgres PGDATABASE=postgres
PSQL=(psql -X -q -v ON_ERROR_STOP=1)

cleanup() {
  if [[ "$KEEP" == "1" ]]; then
    echo "MAMA_TEST_KEEP=1 → veritabanı açık bırakıldı (port $PORT)"
    return
  fi
  if [[ "$MODE" == "docker" ]]; then
    docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
  else
    if [[ -n "${PGDATA_DIR:-}" && -d "$PGDATA_DIR" ]]; then
      as_pg "$PG_BIN/pg_ctl" -D "$PGDATA_DIR" -m immediate stop >/dev/null 2>&1 || true
      [[ "$PGDATA_DIR" == /tmp/mama-haritasi-pg.* ]] && rm -rf "$PGDATA_DIR"
    fi
  fi
}
trap cleanup EXIT

as_pg() {
  # postgres sunucusu root olarak çalışmaz
  if [[ "$(id -u)" == "0" ]]; then runuser -u postgres -- "$@"; else "$@"; fi
}

wait_ready() {
  local i
  for i in $(seq 1 120); do
    if "${PSQL[@]}" -tAc "select 1" >/dev/null 2>&1; then return 0; fi
    sleep 1
  done
  echo "veritabanı hazır olmadı" >&2
  return 1
}

start_docker() {
  echo "→ docker: $IMAGE (port $PORT)"
  docker run -d --name "$CONTAINER" -e POSTGRES_PASSWORD=postgres -p "$PORT:5432" "$IMAGE" >/dev/null
  # imaj init sırasında postgres'i bir kez yeniden başlatır: init tamamlanana dek bekle
  local i
  for i in $(seq 1 120); do
    if docker logs "$CONTAINER" 2>&1 | grep -q "PostgreSQL init process complete"; then break; fi
    sleep 1
  done
  wait_ready
}

start_local() {
  PGDATA_DIR="$WORK/pgdata"
  if [[ "$(id -u)" == "0" ]] && ! runuser -u postgres -- test -x "$WORK" 2>/dev/null; then
    # root ile çalışırken postgres kullanıcısı WORK'e erişemiyorsa (ör. 700 izinli üst dizin)
    PGDATA_DIR="$(mktemp -d /tmp/mama-haritasi-pg.XXXXXX)"
  fi
  echo "→ yerel PostgreSQL: $PG_BIN (port $PORT, veri: $PGDATA_DIR)"
  rm -rf "$PGDATA_DIR"
  mkdir -p "$PGDATA_DIR"
  if [[ "$(id -u)" == "0" ]]; then chown -R postgres: "$PGDATA_DIR"; fi
  as_pg "$PG_BIN/initdb" -D "$PGDATA_DIR" -U postgres --auth=trust -E UTF8 --locale=C.UTF-8 >>"$LOG" 2>&1
  as_pg "$PG_BIN/pg_ctl" -D "$PGDATA_DIR" -l "$PGDATA_DIR/postgres.log" \
    -o "-p $PORT -k $PGDATA_DIR -c listen_addresses=127.0.0.1" -w start >>"$LOG" 2>&1
  wait_ready
}

run_file() {
  local f="$1" label="$2"
  if ! "${PSQL[@]}" -f "$f" >>"$LOG" 2>&1; then
    echo "✗ $label" >&2
    grep -E "ERROR|FAIL" "$LOG" | tail -5 >&2
    exit 1
  fi
}

if [[ "$MODE" == "docker" ]]; then start_docker; else start_local; fi

echo "→ shim"
run_file "$HERE/00_supabase_shim.sql" "00_supabase_shim.sql"

echo "→ migrations"
for f in "$SUPA"/migrations/*.sql; do
  # her migration tek transaction (supabase db push gibi)
  if ! "${PSQL[@]}" -1 -f "$f" >>"$LOG" 2>&1; then
    echo "✗ migration $(basename "$f")" >&2
    grep -E "ERROR" "$LOG" | tail -5 >&2
    exit 1
  fi
  echo "   ✓ $(basename "$f")"
done

echo "→ seed"
run_file "$SUPA/seed.sql" "seed.sql"
run_file "$SUPA/seed.sql" "seed.sql (2. kez — idempotent)"
run_file "$HERE/01_helpers.sql" "01_helpers.sql"

if [[ $# -gt 0 ]]; then
  TESTS=()
  for a in "$@"; do TESTS+=("$HERE/$(basename "$a")"); done
else
  TESTS=("$HERE"/[1-9][0-9]_*.sql)
fi

total=0
failed=0
echo "→ tests"
for f in "${TESTS[@]}"; do
  name="$(basename "$f")"
  out="$WORK/${name%.sql}.out"
  if "${PSQL[@]}" -f "$f" >"$out" 2>&1; then
    n=$(grep -c "PASS:" "$out" || true)
    total=$((total + n))
    printf "   ✓ %-28s %3d assertions\n" "$name" "$n"
  else
    n=$(grep -c "PASS:" "$out" || true)
    total=$((total + n))
    failed=$((failed + 1))
    printf "   ✗ %-28s (%d passed before failure)\n" "$name" "$n"
    grep -E "ERROR|FAIL|CONTEXT" "$out" | head -6 | sed 's/^/       /'
  fi
  cat "$out" >>"$LOG"
done

echo
if [[ $failed -gt 0 ]]; then
  echo "SONUÇ: $failed dosya başarısız, $total assertion geçti (mod: $MODE). Log: $LOG"
  exit 1
fi
echo "SONUÇ: ${#TESTS[@]} dosya, $total assertion — hepsi geçti (mod: $MODE)"
