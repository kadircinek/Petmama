#!/usr/bin/env bash
# MamaKit paketini Linux'ta (Docker, Swift 6.0) derler ve test eder.
# SwiftUI/MapKit dosyaları `#if canImport(SwiftUI)` ile sarılı olduğundan Linux'ta atlanır;
# domain kuralları, ViewModel'ler ve veri katmanı derlenir.
#
# Kullanım: scripts/linux-swift.sh [build|test] [ek swift argümanları...]
#   SCRATCH=/tmp/mama-build  → derleme dizini (paralel çalıştırmalar için farklı verin)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CMD="${1:-test}"; shift || true
SCRATCH="${SCRATCH:-/tmp/mama-swift-build}"
mkdir -p "$SCRATCH"

PROXY_ARGS=()
if [[ -n "${HTTPS_PROXY:-}" ]]; then
  PROXY_ARGS+=(-e HTTPS_PROXY -e HTTP_PROXY -e NO_PROXY -e https_proxy="${HTTPS_PROXY}" -e http_proxy="${HTTP_PROXY:-$HTTPS_PROXY}")
fi
if [[ -f /root/.ccr/ca-bundle.crt ]]; then
  PROXY_ARGS+=(-v /root/.ccr/ca-bundle.crt:/etc/ssl/certs/proxy-ca.crt:ro -e GIT_SSL_CAINFO=/etc/ssl/certs/proxy-ca.crt -e SSL_CERT_FILE=/etc/ssl/certs/proxy-ca.crt)
fi

# Swift 6.0 Linux araç zincirinde libswiftObservation.so çözümsüz bir sembol (`swift::threading::fatal`)
# içeriyor; @Observable kullanan test paketleri ancak bu bayrakla bağlanıyor.
EXTRA=()
if [[ "$CMD" == "test" ]]; then EXTRA+=(-Xlinker --allow-shlib-undefined); fi

exec docker run --rm --network host "${PROXY_ARGS[@]}" \
  -v "$ROOT/ios/MamaKit:/pkg" -v "$SCRATCH:/build" -w /pkg \
  swift:6.0-noble swift "$CMD" --scratch-path /build "${EXTRA[@]}" "$@"
