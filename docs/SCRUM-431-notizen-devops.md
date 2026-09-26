# SCRUM-431 — Prod-Release Notizen (DevOps-Agent)

## Gate (beide Bedingungen gleichzeitig, vom Tracker)
- Status `Release`, Assignee `devops-agent` (jira_get_issue, 26.09.2026 ~20:51).
- PO-Sign-off: Jira-Comment 21435 ("Feature ready for release" + eigene Read-backs gegen Test-Org, 7/7 AC).
- Merge-Vorgeschichte: PR #144, Commit `0bf6411` auf master (Jira-Comment 21434).

## Deploy — Prod-Org (`devops-agent@cline.de`)
- Worktree `scr431-prod` auf `master`@`0bf6411` (shared Checkout unangetastet, lief auf SCRUM-424 dirty).
- Manifest `manifest/release-scr431-combined.xml` (targeted, Hausmuster scr428):
  2 CustomField (qualifiziert: `Account.Wartungsvertrag__c`, `Case.Wartungsvertrag_Anzeige__c`),
  2 PermissionSet, 1 Report `Service/Morgen_UEbersicht_Vertragskunden`, 3 Layout, 3 ApexClass (Test).
- Manifest-Verifikation: `verify_manifest.py` — alle 11 Members byte-exakt gegen Source-Dateien (ALL OK).
  ACHTUNG: Die scr431-Phase-1/2-Manifests aus dem Developer-Deploy haben UNQUALIFIZIERTE CustomField-Members
  → `sf project deploy validate --manifest ...` = `ComponentSetError: No source-backed components`.
  Hausmuster (scr430/428) = qualifiziert. Das Combined-Manifest ist korrekt.
- Validate (dry-run): Job `0Afg500000FFN5JCAX` — 11/11 validiert, 0 Fehler. (Tests: Total 0 — bei
  `deploy validate` laufen die RunSpecified-Tests in diesem CLI-Build nicht; für den Real-Deploy daher
  `deploy start` mit --test-level, nicht `deposit quick`.)
- Real-Deploy: Job `0Afg500000FFOHVCA5` — **Status: Succeeded**, 11/11 Komponenten (9 Created, 3 Layout Changed),
  Tests **6/6 pass, 0 fail** (RunSpecifiedTests: SCRUM431WartevertragTest, SCRUM431FlsTest, SCRUM431ReportDataTest —
  self-contained, erzeugen eigene SCRUM431-ACC-* Daten, rollen zurück).
- CLI-Flags: `org assign permset` kennt `-b/--on-behelp-of` (nicht -u). `deploy start` hat KEIN `--rollback-on-error`
  (Flag existiert nicht; Standard-Verhalten rollt bei Test-Fehler zurück).

## Permission Sets — Deployed AND Assigned (Lektion #7)
- Assigned via `sf org assign permset -n <PS> -b devops-agent@cline.de meerwais.osmani.3ecaf61ebe28@agentforce.com -o Prod-Org`
  (jeweils -o Prod-Org explizit! Default ist Test-Org):
  - SCRUM431_Wartungsvertrag_ServiceTeam → 2/2
  - SCRUM431_Wartungsvertrag_Teamleitung → 2/2
- Read-back aus Prod-Org: `PermissionSetAssignment` = **4/4** (UserIds 005g5...C38DAAS, 005g5...C4M4AAK).

## FLS-Read-Back via realer Prod-Session
- `SELECT ... Wartungsvertrag_Anzeige__c FROM Case LIMIT 3` → liefert Werte (alle "Nein", korrekt: 0 Accounts mit W=true in Prod).
- `SELECT ... Wartungsvertrag__c FROM Account LIMIT 3` → liefert false/false/false (Feld live, default false).
- Formel verifiziert live: Case → "Nein" für W=false Accounts.
- `sf sobject describe` VOR Deploy: 0 Wartungsvertrag*-Felder in Prod (Clean-Deploy).

## Daten
- Keine Prod-Daten verändert (Tests self-contained, RolledBack). Prod hat aktuell 0 Accounts mit Wartungsvertrag=true.
- Morgen-Übersicht-Report ist live; rendert leer, bis Teamleitung einen Account auf Ja setzt (erwartetes Verhalten).

## Release
- Tag `release/2026-09-26-SCRUM-431` (Hausformat, NICHT unter archiv/).
- Drift: kein neues Drift erzeugt (targeted-Manifest = exakt die 431-Komponenten). Bestehende externe
  Drift (z. B. SCRUM-319/421) bleiben aus Scope heraus — wie bei SCRUM-428.
