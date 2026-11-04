#!/usr/bin/env python3
"""Türkçe kaynak metinleri toplayıp ana bundle String Catalog'unu günceller (D12).

Neden: Metinler Swift Package modüllerinde ama `Bundle.main` üzerinden çözülüyor
(`Text("…")`, `String(localized: "…")`). Xcode paket kodundan uygulamanın kataloğuna otomatik
çıkarım yapmadığı için anahtarları bu betik toplar.

    python3 scripts/extract_strings.py            # kataloğu güncelle
    python3 scripts/extract_strings.py --check    # eksik İngilizce çevirileri listele (CI)

İngilizce çeviriler `scripts/l10n/en.json` içinde (anahtar → çeviri) tutulur; betik bunları kataloğa yazar.
Var olan katalogdaki elle girilmiş çeviriler korunur.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCES = [ROOT / "ios/MamaKit/Sources", ROOT / "ios/App/Sources"]
CATALOG = ROOT / "ios/App/Resources/Localizable.xcstrings"
EN_FILE = ROOT / "scripts/l10n/en.json"

STRING = r'"((?:[^"\\\n]|\\.)*)"'
CALLS = (
    r"Text|Button|Label|navigationTitle|TextField|SecureField|Toggle|Section|Picker|Stepper|"
    r"ContentUnavailableView|confirmationDialog|alert|SectionHeader|QuickActionTile|BannerView|"
    r"MamaTextButton|ChoiceCard|TagChip|SelectableChip|showToast|LoadingView|accessibilityLabel|"
    r"accessibilityHint|LabeledContent|Link|ShareLink|DisclosureGroup|Menu"
)
CALL_RE = re.compile(rf"\b(?:{CALLS})\(\s*{STRING}")
LOCALIZED_RE = re.compile(rf"String\(localized:\s*{STRING}")
NAMED_RE = re.compile(rf"\b(?:title|subtitle|message|actionTitle|label|prompt|placeholder):\s*{STRING}")
ERROR_FILE = "MamaError.swift"
RETURN_RE = re.compile(rf"return\s+{STRING}")

INT_HINT = re.compile(r"(count|Count|limit|quantity|number|Number|index|step|current|hours|minutes|days|kg|sent|total)\b")


def to_key(literal: str) -> str | None:
    if "\\(" in literal:
        def repl(match: re.Match) -> str:
            expr = match.group(1)
            return "%lld" if INT_HINT.search(expr) else "%@"
        literal = re.sub(r"\\\(((?:[^()]|\([^()]*\))*)\)", repl, literal)
    if "\\(" in literal:
        return None  # iç içe tırnaklı interpolasyon: güvenilir çıkarılamaz
    literal = literal.replace('\\"', '"').replace("\\n", "\n")
    if not re.search(r"[A-Za-zÇĞİÖŞÜçğıöşü]", literal.replace("%lld", "").replace("%@", "")):
        return None
    if re.fullmatch(r"[a-z0-9_.\-]+", literal) and ("." in literal or "_" in literal):
        return None  # tanımlayıcı (kuyruk adı, anahtar), kullanıcı metni değil
    return literal


def collect() -> dict[str, set[str]]:
    keys: dict[str, set[str]] = {}
    for base in SOURCES:
        for path in sorted(base.rglob("*.swift")):
            rel = path.relative_to(ROOT).as_posix()
            if "/MamaCore/" in rel and not rel.endswith(ERROR_FILE):
                continue  # MamaCore saf mantık; kullanıcı metni yalnızca MamaError'da
            if "/MamaSupabase/" in rel or "/MamaPersistence/" in rel:
                continue
            text = path.read_text(encoding="utf-8")
            patterns = [RETURN_RE] if rel.endswith(ERROR_FILE) else [CALL_RE, LOCALIZED_RE, NAMED_RE]
            for pattern in patterns:
                for match in pattern.finditer(text):
                    key = to_key(match.group(1))
                    if key:
                        keys.setdefault(key, set()).add(rel)
    return keys


def main() -> int:
    check = "--check" in sys.argv
    keys = collect()
    en = json.loads(EN_FILE.read_text(encoding="utf-8")) if EN_FILE.exists() else {}
    catalog = json.loads(CATALOG.read_text(encoding="utf-8")) if CATALOG.exists() else {
        "sourceLanguage": "tr", "version": "1.0", "strings": {}
    }
    strings = catalog.setdefault("strings", {})

    missing = []
    for key in sorted(keys):
        entry = strings.setdefault(key, {})
        entry["extractionState"] = "manual"
        locs = entry.setdefault("localizations", {})
        locs["tr"] = {"stringUnit": {"state": "translated", "value": key}}
        current = locs.get("en", {}).get("stringUnit", {})
        if key in en:
            locs["en"] = {"stringUnit": {"state": "translated", "value": en[key]}}
        elif current.get("value"):
            pass  # Xcode'da elle girilmiş çeviri
        else:
            locs.pop("en", None)
            missing.append(key)

    stale = [k for k, v in strings.items() if v.get("extractionState") == "manual" and k not in keys]
    for key in stale:
        strings[key]["extractionState"] = "stale"

    if check:
        print(f"{len(keys)} anahtar, {len(missing)} eksik İngilizce çeviri, {len(stale)} eski anahtar")
        for key in missing:
            print(f"  - {key!r}")
        return 1 if missing else 0

    catalog["strings"] = dict(sorted(strings.items()))
    CATALOG.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"{CATALOG.relative_to(ROOT)}: {len(keys)} anahtar ({len(missing)} çevirisiz, {len(stale)} eski)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
