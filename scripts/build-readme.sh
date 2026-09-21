#!/usr/bin/env bash
# build-readme.sh — erzeugt README.md aus docs/RELEASE-NOTES.md.
#
#   scripts/build-readme.sh            schreibt README.md neu
#   scripts/build-readme.sh --check    prueft nur, aendert nichts (Exit 1 bei Abweichung)
#
# Warum: GitHub zeigt als Startseite ausschliesslich README.md im Wurzelverzeichnis.
# Die Release Notes sollen dort stehen, ihre Quelle bleibt aber docs/RELEASE-NOTES.md,
# weil der PO dort schreibt. Statt zwei Dateien von Hand gleichzuhalten — was sie
# nachweislich auseinanderlaufen laesst — wird README.md erzeugt.
#
# QUELLE ist docs/RELEASE-NOTES.md. README.md nie von Hand bearbeiten.
set -euo pipefail

cd "$(dirname "$0")/.."
SRC="docs/RELEASE-NOTES.md"
OUT="README.md"
[ -r "$SRC" ] || { echo "build-readme: $SRC fehlt" >&2; exit 2; }

header() {
cat <<'HEADER'
<!-- ERZEUGT AUS docs/RELEASE-NOTES.md — NICHT VON HAND BEARBEITEN.
     Neu erzeugen mit: scripts/build-readme.sh -->

# FirstSalesforceProject

Salesforce-Entwicklung mit einem Team aus fuenf Agenten — PO, Architekt,
Developer, Tester, DevOps.

| Wohin | Wofuer |
|---|---|
| [`AGENTS.md`](AGENTS.md) | die Regeln, nach denen alle fuenf arbeiten |
| [`scripts/README.md`](scripts/README.md) | welche Werkzeuge es gibt und wer sie aufruft |
| [`docs/`](docs/) | Design-Dokumente je Ticket |
| [`force-app/`](force-app/) | die Salesforce-Metadaten |

Aufsetzen, CLI-Befehle und Projektstruktur stehen in der
[Salesforce-DX-Dokumentation](https://developer.salesforce.com/tools/salesforcecli).

---

HEADER
}

BUILT=$(mktemp)
trap 'rm -f "$BUILT"' EXIT
{ header; cat "$SRC"; } > "$BUILT"

if [ "${1:-}" = "--check" ]; then
  if diff -q "$BUILT" "$OUT" >/dev/null 2>&1; then
    echo "README.md ist aktuell."
    exit 0
  fi
  echo "README.md weicht von $SRC ab."
  echo
  diff -u "$OUT" "$BUILT" | head -30 || true
  echo
  echo "Beheben: scripts/build-readme.sh  (dann committen)"
  echo "README.md wird ERZEUGT — Aenderungen gehoeren in $SRC."
  exit 1
fi

cp "$BUILT" "$OUT"
echo "README.md neu erzeugt aus $SRC ($(wc -l < "$OUT") Zeilen)."
