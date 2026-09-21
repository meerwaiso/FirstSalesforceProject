#!/usr/bin/env bash
# apex-probe.sh — "gibt es diese Apex-API, und was liefert sie?" in einem Befehl.
#
#   scripts/apex-probe.sh 'System.debug(Math.mod(17, 7));'
#   scripts/apex-probe.sh -o Prod-Org 'System.debug(UserInfo.getTimeZone());'
#   scripts/apex-probe.sh -f probe.apex
#
# Warum das existiert: um herauszufinden, ob eine Klasse oder Signatur
# existiert, wurde in SCRUM-424 rund fuenfzehnmal eine Probe als Deploy in die
# Org geschickt — jedes Mal ein Roundtrip von ~30-60 s. Anonymes Apex
# beantwortet dieselbe Frage in ~5 s. Der Compiler ist in beiden Faellen
# derselbe; nur der Weg dorthin ist zwanzigmal kuerzer.
#
# Ausgabe: nur Deine System.debug-Zeilen und, falls vorhanden, die
# Compiler-Meldung. Exit 0 = kompiliert und gelaufen, 1 = Compile-/Laufzeitfehler.
set -uo pipefail

ORG="Test-Org"
FILE=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o|--target-org) ORG="$2"; shift 2 ;;
    -f|--file)       FILE="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) break ;;
  esac
done

TMP=""
cleanup() { [ -n "$TMP" ] && rm -f "$TMP"; }
trap cleanup EXIT

if [ -n "$FILE" ]; then
  [ -r "$FILE" ] || { echo "apex-probe: Datei nicht lesbar: $FILE" >&2; exit 2; }
  SRC="$FILE"
else
  SNIPPET="${1:-}"
  [ -n "$SNIPPET" ] || { echo "usage: $0 [-o <org>] '<apex>'   |   $0 -f <datei>" >&2; exit 2; }
  TMP=$(mktemp --suffix=.apex)
  printf '%s\n' "$SNIPPET" > "$TMP"
  SRC="$TMP"
fi

OUT=$(sf apex run --file "$SRC" -o "$ORG" 2>&1)

# Compile-Fehler: die CLI meldet sie vor jedem Log.
if echo "$OUT" | grep -qiE "executeCompileFailure|Compile error|Unexpected token"; then
  echo "KOMPILIERT NICHT ($ORG):"
  # Die CLI schreibt "Compilation failed at Line X column Y with the error:",
  # dann eine LEERZEILE und erst danach die Ursache. Alles ab der Fehlerzeile
  # nehmen und Leerzeilen wegwerfen — sonst steht da eine Meldung ohne Fehler.
  echo "$OUT" | sed -n '/executeCompileFailure\|Compilation failed\|Compile error/,$p' \
    | grep -v '^[[:space:]]*$' | head -5 | sed 's/^/  /'
  # Haeufigster Anfaengerfehler, aber nur zeigen wenn er zutrifft:
  if grep -q '"' "$SRC"; then
    echo
    echo "  Hinweis: Apex-Strings stehen in EINFACHEN Anfuehrungszeichen;"
    echo "  doppelte sind kein gueltiges Apex."
  fi
  exit 1
fi

# Laufzeitfehler
if echo "$OUT" | grep -qiE "executeRuntimeFailure|System\.[A-Za-z]+Exception"; then
  echo "LAEUFT NICHT ($ORG):"
  echo "$OUT" | grep -oE "System\.[A-Za-z]+Exception[^|]*" | sed 's/^/  /' | head -5
  exit 1
fi

# Erfolg: nur die eigenen Debug-Zeilen zeigen.
DEBUGS=$(echo "$OUT" | grep -oP '(?<=\|DEBUG\|).*' | sed 's/^/  /')
if [ -n "$DEBUGS" ]; then
  echo "$DEBUGS"
else
  echo "  (kompiliert und gelaufen, keine System.debug-Ausgabe)"
fi
exit 0
