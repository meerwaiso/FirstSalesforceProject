# SCRUM-470 notizen (architect-agent, 2026-11-22)

Hard-won findings — every line measured this session; cite the doc for detail.

- Repo surveyed: `origin/master` @ `48ee748ca9310642228c1409f54eb9800dbc0d9a`. The shared checkout sits on `feature/SCRUM-424-first-response` with other tickets' uncommitted files — worktree `scr470-wt`, branch `feature/SCRUM-470-preferred-contact`.
- Test-Org: **676** `Contact` records (656 owned `devops-agent`, 20 `Meerwais Osmani`). Prod-Org: **20**, all owned `OrgFarm EPIC`. Contacts already carrying a channel preference: **0** (field does not exist yet).
- `Contact` layouts in Test-Org: **4** (`Contact Layout`, `(Sales)`, `(Marketing)`, `(Support)`) — repo tracks **1**. Query that worked: `SELECT Id, Name FROM Layout` (`Type`/`EntityName` are NOT columns of `Layout` — measured errors).
- FlexiPages in Test-Org: **9** components (`SELECT Id FROM FlexiPage`; `Name`/`DisplayName` are not columns — measured error). Types NOT re-measured: SCRUM-405 saw 8/8 UtilityBars on 2026-09-10.
- `SELECT … FROM Field WHERE Domain='Contact'` → `sObject type 'Field' is not supported` (measured). `sf api request rest "/services/data/v64.0/sobjects/Contact/describe"` returned 0 custom-field entries.
- `SalesCloudSharingModel:Contact` retrieve → `Missing metadata type definition in registry` → sharing has no source artefact; Setup-only, so no Apex oracle for sharing ACs.
- Profiles (8) incl. `Standard User`, `Read Only`, `Custom: Sales/Marketing/Support`. Users (8): `Meerwais Osmani`, `devops-agent`, `Integration User`, `Automated Process`, `Data.com Clean`, `Security User`, `Chatter Expert`, `Platform Integration User`.
- House PS targets: `SCRUM405_FirmenTelefonnummer`, `SCRUM453_ContactLeft_Set/_Read`, `SCRUM428_ServiceTeam/_Teamleitung` are all assigned to exactly `devops-agent` + `Meerwais Osmani`.
- House shapes copied (do not re-invent): picklist on a standard object = `Rueckruf_Zeitfenster__c.field-meta.xml` (no `<restricted>`, no `<length>`); Read+Edit PS = `SCRUM453_ContactLeft_Set.permissionset-meta.xml`; FLS test = `SCRUM382CustomerSinceDaysFlsTest.cls` (temp `User` on `Standard User`, `de_DE` rejected, `UTC` rejected → `en_US`/`America/Los_Angeles`); run configs = `manifest/scr467-phase4-apextests.xml` @ `version 67.0`.
- Test-Org licences 2/2 System Administrators (house, quoted in SCRUM-405 E2E) → no second low-privilege browser session; AC6 negative belongs to the Apex FLS class.
