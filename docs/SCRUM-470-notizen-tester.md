# SCRUM-470 — Tester-Notizen (measured in this session, 2026-11-22)

Nur Measured-Flashes. Each line names the command. Read this file first after every
compression — files survive, context does not.

## Org-Baseline (Test-Org, CLI-User devops-agent@cline.test)
- default org = Test-Org, alias `Test-Org`, instance `resourceful-bear-6f1u4j-dev-ed.trailblaze.my.salesforce.com`
  (`sf org display --json`) → org.ts resolves Lightning-Host from it, never hardcoded.
- `SELECT COUNT() FROM Contact` → **676** Contact-Records.
- `SELECT Id, Preferred_Contact_Method__c FROM Contact WHERE Preferred_Contact_Method__c != null` → **0** before the fixtures.
- Field `Contact.Preferred_Contact_Method__c` exists as **Picklist** (`scripts/fls-check.sh Contact Preferred_Contact_Method__c Test-Org`).
- Field-Label (org/branch): `Favorit Kontaktmethod` · Value-Labels: `telefon` / `email` / `Letter`
  (branch XML `force-app/main/default/objects/Contact/fields/Preferred_Contact_Method__c.field-meta.xml`).
- `scripts/fls-check.sh`: granted by `SCRUM470_ContactContactWay` (read+edit) AND by `AncCrmIntegrationUser`
  (read=true, edit=false) — the latter assigned to **nobody**. → no profile-owned grant, negative FLS-Probe is a real oracle.
- `SELECT Assignee.Name, Assignee.Username, PermissionSet.Name FROM PermissionSetAssignment WHERE
  PermissionSet.Name='SCRUM470_ContactContactWay'` → **2 rows**: devops-agent@cline.test,
  meerwais.osmani@resourceful-bear-6f1u4j.com.

## Fixtures (created this session, `sf data create record -s Contact`)
LastName-Prefix `TEST-SCRUM-470-<AC>-<ts>`; ts = 1795369957.
- 003WU00001ukmaMYAQ  AC1 — **no** preference (empty stays valid)
- 003WU00001ukzVxYAI  AC2 — Email
- 003WU00001ukzXZYAY  AC4 — Phone
- 003WU00001ukzZBYAY  AC5 — Letter
after creation: `WHERE Preferred_Contact_Method__c != null` → **3**.
Cleanup at end of session: `sf data delete record -s Contact -i <id>`.

## S3 — which Contact-Layout is profile-active (Tooling SOQL)
- `SELECT Name, Id FROM Layout WHERE TableEnumOrId='Contact'` → 4 layouts:
  `Contact Layout` (00hWU00000XBoy1YAD), `Contact (Sales) Layout`, `Contact (Support) Layout`, `Contact (Marketing) Layout`.
- `SELECT Layout.Name, Profile.Name FROM ProfileLayout WHERE TableEnumOrId='Contact'` → 43 rows:
  Standard User / System Administrator / Standard Platform User → **Contact Layout** (= the tracked file),
  Custom: Sales Profile → **Contact (Sales) Layout**, Custom: Support Profile → **Contact (Support) Layout**,
  Custom: Marketing Profile → **Contact (Marketing) Layout**.
- `sf api request rest "/services/data/v68.0/ui-api/record-ui/003WU00001ukzVxYAI?layoutTypes=Full&modes=View"`
  → ONE layout `012000000000000AAA`, section `Contact Information` contains Phone, Email,
  **Preferred_Contact_Method__c (editableForUpdate=true)** → for the session user the tracked layout renders, no FlexiPage-Shadow (⚠-2 answered).

## S4 — sharing read-back (classic Setup page in frontdoor-Session)
- `scratch/scr470_owd_probe.mjs` → `/p/own/OrgSharingDetail?setupid=SecuritySharing`, body.innerText:
  row `Contact` = Default Internal Access **Controlled by Parent** / Default External Access **Controlled by Parent**
  ("Grant Access Using Hierarchies"-column renders EMPTY — not readable this way, skill salesforce-platform-quirks).
  `sf api request rest` alone returns only the redirect-shell (1647 bytes) — the browser-session route works.

## CI / Apex
- (pending)
