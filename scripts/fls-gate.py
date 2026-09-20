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


def sh(*cmd):
    return subprocess.run(cmd, capture_output=True, text=True).stdout


def changed_field_files(base):
    out = sh("git", "diff", "--name-only", "--diff-filter=AM", f"{base}...HEAD")
    return [l for l in out.splitlines() if FIELD_RE.search(l)]


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
    rows = [l for l in out.splitlines()[1:] if l.strip() and not l.startswith("Querying")]
    return len(rows)


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
    sys.exit(main())
