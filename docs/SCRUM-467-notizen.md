# SCRUM-467 — Notizen (Architect, 2026-11-21)

Hard-won facts only; each names the command that produced it. Read this first after any compaction.

- `origin/master` @ `31da29f70f808377b3ca1d2e2022660dc37f4d07` (git fetch + git log -1) — shared checkout sat on `feature/SCRUM-424-first-response` with foreign leftovers; I work in worktree `scr467-wt`, branch `feature/SCRUM-467-offer-validity`.
- Test-Org latest API = `68.0` (`sf api request rest /services/data/`).
- Opportunity has `OwnerId` ("Owner ID", reference); 81 fields; **no** `Offer*` custom field → no naming collision (`sf sobject describe --sobject Opportunity --json`).
- Opportunity report-type column tokens (`sf api request rest /services/data/v68.0/analytics/reportTypes/Opportunity` → `reportExtendedMetadata.detailColumnInfo`): `ACCOUNT_NAME`, `FULL_NAME` = "Opportunity Owner", `AMOUNT`, `OPPORTUNITY_NAME`, `STAGE_NAME`, `CLOSE_DATE`; custom fields as `Opportunity.X__c` (live proof `Hoeh_Risk_Chancen.report` on master).
- Profiles in Test-Org = standard set only, no "Account Manager"/"Sales Team Lead" (`sf data query -t "SELECT Id,Name FROM Profile"`, 41 rows) → the AC12/AC13 boundary cannot come from profiles; SCRUM-457 says roles are unassigned → not from roles either. **⇒ Blocking point written up.**
- PS assignments in Test-Org: only two users ("Meerwais Osmani", "devops-agent"), both holding every SCRUM-445/451/459 PS (`SELECT Id,Assignee.Name,PermissionSet.Name FROM PermissionSetAssignment WHERE PermissionSet.Name IN (...)`) → sharing/roles give no second population.
- Opportunity counts: 76 open, 63 closed; **0** with offer data (`sf data query COUNT(Name) WHERE IsClosed=false/true`) → AC9/AC10 are zero-record criteria until the Tester seeds fixtures.
- **Check-only validation is the shape oracle and it works**: `sf project deploy validate -o Test-Org --source-dir <dir> --test-level RunRelevantTests --async --json`, poll `sf project deploy report -o Test-Org -i <op>`; it needs a real `sfdx-project.json` + the parent `objects/Opportunity/Opportunity.object-meta.xml` next to the metadata. Final op `0AfWU00000dIgjt0AC` → **Succeeded 13/13, checkOnly true**, org read-back still 0 `Offer_` fields. Never use `--test-level RunLocalTests` for such a probe: it queued 506 org tests (480 had run before I cancelled `0AfWU00000dIf330AC`) against the 24 h Test-Org test budget.
- `ISCHANGED()` in a validation rule **takes a field** ("Expected 1, received 0"); `PREVIOUS(StageName)` is **rejected** ("picklist fields are only supported in certain functions") → the already-closed guard uses `NOT(ISCHANGED(StageName))` + `ISCHANGED(<date>)`. Measured in ops `0AfWU00000dIfkb0AC` / `0AfWU00000dIfvt0AC`.
- A leading XML comment on a `.validationRule-meta.xml` breaks the CLI conversion ("Invalid XML tags or unable to find matching parent xml file"); comments in `.report-meta.xml` files are fine (house files carry them).
- Report `description` and VR `description` max **255 characters**; the grouping field must NOT also appear in `<columns>` ("You can't include groupings in the selected columns list").
- Layout: inserting the new `<layoutSections>` after the LAST section fails ("Element layoutSections is duplicated at this location") — insert it **after the first** `</layoutSections>`; the resulting file passed check-only (`0AfWU00000dIgjt0AC`).
- Verified shapes live in `docs/SCRUM-467-shapes/` (13 files + the parent object file); the Developer copies them into `force-app/main/default/…`.
- House VR shape for "cannot close as Won": `No_Won_Without_Approval` + `Competitor_PflichtBeiWettbewerber` (with `errorDisplayField`); a VR fires only on records being saved → AC8 historical records untouched.
- Report sort IS source (`Kunde_ohne_Kontaktperson` `<sortColumn>`/`<sortOrder>`); ListView schema has NO sort (SCRUM-432 note) → Reports are the authoritative overview artefacts.
- `timeFrameFilter`: deploying without the element does NOT clear an existing one (comment inside `Hoeh_Risk_Chancen.report-meta.xml`) → set an explicit custom span.
- Opportunity layout in repo: exactly one, `layouts/Opportunity-Opportunity Layout.layout-meta.xml`, sections incl. "Discount Approval", "Risk Level", "Follow-up Monitoring" → new section goes after "Verloren Chancen" (~line 248). Lightning page placement stays an Org step.

## Phase 4 — Apex tests (measured 2026-11-21)

- `deploy validate --test-level RunSpecifiedTests --tests SCRUM467OfferExpiryTest --tests
  SCRUM467OfferFlsTest` → op `0AfWU00000dIklt0AC`, **Succeeded, 12/12 tests, 0 failures**,
  3 components (2 classes + `SCRUM467_TestObjectAccess`). Earlier ops on the same manifest:
  `0AfWU00000dIkcD0AS` (1 failure = AC13 read-back), `0AfWU00000dIkkH0AS` (1 failure = AC13
  SOQL probe).
- **tmpVar1 (extern, house SCRUM-438/437 pattern):** every Opportunity save that changes
  `IsClosed` **under `System.runAs`** dies in Test-Org with
  `QueryException: Variable does not exist: tmpVar1` at `FollowupMonitoringHandler.recalculate`
  line 112/133. Verified the LIVE class == the repo file
  (`sf project retrieve start --metadata "ApexClass:FollowupMonitoringHandler"` — diff: only a
  trailing newline), so it is not org drift but a Test-Org Apex quirk on the follow-up handler's
  child-object query. Consequence: AC4/AC6/AC7 (the close saves) run **System-context** in
  `SCRUM467OfferExpiryTest`; AC5 (the refusal) stays `runAs`, it is refused by the ValidationRule
  before the handler runs. `Amount` is carried on every update sObject so the handler's
  relevance filter (`IsClosed`/`Amount` only, line 86) stays quiet for the non-closing saves.
- **Apex is "on the inside" of FLS:** measured on op `0AfWU00000dIkcD0AS` — an Apex `update`
  by a user without `SCRUM467_Offer_Dates` was NOT refused and DID move the stored dates
  (Expected 2026-11-13, Actual 2027-01-20); a later Apex SOQL read also returned the values.
  The enforceable negative is `getDescribe().isAccessible()/isUpdateable() == false` (house
  pattern, `SCRUM464DrittpartyFlsTest`) plus the UI/API surface, where `scripts/fls-check.sh`
  shows zero `FieldPermissions` rows. AC13 asserts exactly that; the record-page / API negative
  is the Tester's check.
- `SCRUM467_TestObjectAccess` = TEST-LOCAL (house pattern SCRUM442/451/464): object CRUD on
  `Opportunity` + `Followup_Obligation__c`, Read of all 33 OTHER Opportunity custom fields,
  `editable=false` for the 8 formula fields. It names none of the seven Offer fields. Never
  assigned to a real user; only the fixture users inside the test classes get it.
  Why it is needed at all: measured — an Opportunity save by a non-admin runs
  `OpportunityFollowupMonitorTrigger → FollowupMonitoringHandler.recalculate`, whose SOQL reads
  `Followup_Required__c` etc.; without those grants the save dies with
  `No such column 'Followup_Required__c' on entity Opportunity`.
