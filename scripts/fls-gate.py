#!/usr/bin/env python3
"""fls-gate.py — verhindert, dass ein Feld ohne wirksame FLS ausgeliefert wird.

Zwei Prüfungen, die zwei verschiedene Lücken schliessen:

  A  Entwurfslücke   neues/geändertes Feld, das kein Permission Set erwähnt
  B  Zuweisungslücke Permission Set, das das Feld gewährt, aber niemandem
                     zugewiesen ist (braucht Org-Zugang)

Lücke B hat SCRUM-382, 386, 388, 390, 398 und 421 erwischt — jedes Mal mit der
Regel bereits in AGENTS.md. Deshalb ein Gate und kein Satz.

  scripts/fls-gate.py --base origin/master [--org Test-Org]
  scripts/fls-gate.py --files a.field-meta.xml ... [--org Test-Org]
"""
import argparse, pathlib, re, subprocess, sys

FIELD_RE = re.compile(r"force-app/.*/objects/([^/]+)/fields/([^/]+)\.field-meta\.xml$")


class GateBroken(Exception):
    """Das Gate konnte seine Frage nicht stellen — nicht dasselbe wie eine Antwort."""


def sh(*cmd):
    """Gibt stdout zurück und wirft, wenn der Befehl scheitert.

    Wichtig: ein fehlgeschlagener Befehl liefert leeres stdout, und eine leere
    Antwort ist hier nie harmlos. Bei `git diff` würde sie "keine Felder
    geändert" bedeuten und das Gate still abschalten (falsch-grün); bei der
    PermissionSetAssignment-Abfrage "niemandem zugewiesen" und einen korrekten
    PR blockieren (falsch-rot). Beides muss laut scheitern.
    """
    p = subprocess.run(cmd, capture_output=True, text=True)
    if p.returncode != 0:
        raise GateBroken(f"{' '.join(cmd[:3])}… endete mit {p.returncode}: "
                         f"{(p.stderr or p.stdout).strip()[:300]}")
    return p.stdout


def changed_field_files(base):
    # Existenz der Basis zuerst prüfen: ein unbekannter Ref ist der Weg, auf dem
    # ein Gate unbemerkt aufhört zu prüfen.
    sh("git", "rev-parse", "--verify", "--quiet", f"{base}^{{commit}}")
    out = sh("git", "diff", "--name-only", "--diff-filter=AM", f"{base}...HEAD")
    return [l for l in out.splitlines() if FIELD_RE.search(l)]


def is_fls_relevant(obj):
    """Custom-Metadata-Felder kennen keine FLS — die Prüfung schützt dort nichts.

    Gemessen am 25.09.2026 in Test-Org: `SELECT Bereich__c, Keyword__c FROM
    SCRUM428_KategorierRegel__mdt` liefert Zeilen, obwohl kein einziges
    fieldPermissions in force-app diese Felder gewährt. Die Falle, gegen die
    dieses Gate existiert — Feld unsichtbar, SOQL meldet 'No such column' —
    kann es bei __mdt also nicht geben.

    Die Metadata API nimmt einen fieldPermissions-Eintrag für ein __mdt-Feld
    durchaus an (Prüf-Deployment erfolgreich; ein erfundener Feldname wird mit
    "no CustomField named ..." abgelehnt, die Referenz wird also wirklich
    aufgelöst). Der Eintrag wäre demnach möglich, aber reine Form: er gewährt
    Zugriff, der ohnehin besteht. Ein Gate, das Form verlangt, bringt den
    Agenten bei, Gates mit Form zu bedienen.
    """
    return not obj.endswith("__mdt")


def is_fls_settable(path):
    """Pflichtfelder sind nicht FLS-steuerbar — Salesforce erzwingt Lesezugriff."""
    try:
        xml = pathlib.Path(path).read_text(encoding="utf-8")
    except OSError:
        return True
    return "<required>true</required>" not in xml


def granting_permsets(obj, fld):
    hits = []
    for ps in pathlib.Path("force-app").rglob("*.permissionset-meta.xml"):
        xml = ps.read_text(encoding="utf-8", errors="replace")
        if f"<field>{obj}.{fld}</field>" in xml:
            hits.append(ps.name.removesuffix(".permissionset-meta.xml"))
    return hits


def assignment_count(ps, org):
    q = ("SELECT Assignee.Username FROM PermissionSetAssignment "
         f"WHERE PermissionSet.Name='{ps}'")
    out = sh("sf", "data", "query", "-o", org, "-q", q, "-r", "csv")
    lines = [l for l in out.splitlines() if l.strip() and not l.startswith("Querying")]
    if not lines:
        # Auch bei Rückgabecode 0: ohne Kopfzeile hat die CLI nicht geantwortet,
        # und "null Zuweisungen" wäre hier eine erfundene Antwort.
        raise GateBroken(f"PermissionSetAssignment-Abfrage für '{ps}' lieferte "
                         f"keine Kopfzeile — Org '{org}' nicht erreichbar?")
    return len(lines) - 1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base")
    ap.add_argument("--files", nargs="*")
    ap.add_argument("--org")
    a = ap.parse_args()

    files = a.files if a.files else changed_field_files(a.base or "origin/master")
    if not files:
        print("FLS-Gate: keine geänderten Felder in diesem Diff — nichts zu prüfen.")
        return 0

    failures = []
    print(f"FLS-Gate: {len(files)} geändertes/neue Feld(er)\n")
    for path in files:
        m = FIELD_RE.search(path)
        if not m:
            continue
        obj, fld = m.group(1), m.group(2)
        label = f"{obj}.{fld}"

        if not is_fls_relevant(obj):
            print(f"  {label:<44} übersprungen (Custom Metadata, FLS wird nicht erzwungen)")
            continue

        if not is_fls_settable(path):
            print(f"  {label:<44} übersprungen (required=true, FLS nicht steuerbar)")
            continue

        ps_list = granting_permsets(obj, fld)
        if not ps_list:
            print(f"  {label:<44} A: KEIN Permission Set gewährt Zugriff")
            failures.append((label, "A", "kein fieldPermissions-Eintrag in force-app"))
            continue

        if not a.org:
            print(f"  {label:<44} A: ok ({', '.join(ps_list)}) — B ungeprüft, keine Org")
            continue

        unassigned = [ps for ps in ps_list if assignment_count(ps, a.org) == 0]
        if unassigned and len(unassigned) == len(ps_list):
            print(f"  {label:<44} B: PS ohne Zuweisung: {', '.join(unassigned)}")
            failures.append((label, "B", f"{', '.join(unassigned)} niemandem zugewiesen"))
        else:
            print(f"  {label:<44} ok ({', '.join(ps_list)})")

    if not failures:
        print("\nFLS-Gate grün.")
        return 0

    print(f"\nFLS-Gate ROT — {len(failures)} Feld(er):\n")
    for label, kind, why in failures:
        print(f"  {label}: {why}")
    print("""
Warum das blockiert: ein Feld ohne wirksame FLS ist für alle unsichtbar, und
SOQL sowie Apex melden darauf 'No such column' — nicht unterscheidbar von einem
fehlenden Feld. Das hat in diesem Projekt sechs Tickets Zeit gekostet.

  Lücke A  fieldPermissions-Eintrag in ein Permission Set aufnehmen
  Lücke B  sf org assign permset -n <PS> -b <CLI-Benutzer> -o <org>
           und an den menschlichen Testaccount

Diagnose eines einzelnen Feldes: scripts/fls-check.sh <Objekt> <Feld>
Hintergrund: Skill 'salesforce-describe-first' §4""")
    return 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except GateBroken as e:
        print(f"\nFLS-Gate KONNTE NICHT PRUEFEN: {e}", file=sys.stderr)
        print("Das ist kein Befund, sondern ein kaputtes Gate. Exit 2 — weder "
              "grün noch rot.", file=sys.stderr)
        sys.exit(2)
