# SCRUM-467 — Notizen (Architect, 2026-11-21)

Hard-won facts only; each names the command that produced it. Read this first after any compaction.

- `origin/master` @ `31da29f70f808377b3ca1d2e2022660dc37f4d07` (git fetch + git log -1) — shared checkout sat on `feature/SCRUM-424-first-response` with foreign leftovers; I work in worktree `scr467-wt`, branch `feature/SCRUM-467-offer-validity`.
- Test-Org latest API = `68.0` (`sf api request rest /services/data/`).
- Opportunity has `OwnerId` ("Owner ID", reference); 81 fields; **no** `Offer*` custom field → no naming collision (`sf sobject describe --sobject Opportunity --json`).
- Opportunity report-type column tokens (`sf api request rest /services/data/v68.0/analytics/reportTypes/Opportunity` → `reportExtendedMetadata.detailColumnInfo`): `ACCOUNT_NAME`, `FULL_NAME` = "Opportunity Owner", `AMOUNT`, `OPPORTUNITY_NAME`, `STAGE_NAME`, `CLOSE_DATE`; custom fields as `Opportunity.X__c` (live proof `Hoeh_Risk_Chancen.report` on master).
- Profiles in Test-Org = standard set only, no "Account Manager"/"Sales Team Lead" (`sf data query -t "SELECT Id,Name FROM Profile"`, 41 rows) → the AC12/AC13 boundary cannot come from profiles; SCRUM-457 says roles are unassigned → not from roles either. **⇒ Blocking point written up.**
- PS assignments in Test-Org: only two users ("Meerwais Osmani", "devops-agent"), both holding every SCRUM-445/451/459 PS (`SELECT Id,Assignee.Name,PermissionSet.Name FROM PermissionSetAssignment WHERE PermissionSet.Name IN (...)`) → sharing/roles give no second population.
- Opportunity counts: 76 open, 63 closed; **0** with offer data (`sf data query COUNT(Name) WHERE IsClosed=false/true`) → AC9/AC10 are zero-record criteria until the Tester seeds fixtures.
- House has **no** Date-typed formula field and **no** `PREVIOUS()` usage anywhere (`git grep PREVIOUS origin/master`, loop over `*.field-meta.xml`) → both shapes flagged as deploy-validate items, not asserted.
- House VR shape for "cannot close as Won": `No_Won_Without_Approval` + `Competitor_PflichtBeiWettbewerber` (with `errorDisplayField`); a VR fires only on records being saved → AC8 historical records untouched.
- Report sort IS source (`Kunde_ohne_Kontaktperson` `<sortColumn>`/`<sortOrder>`); ListView schema has NO sort (SCRUM-432 note) → Reports are the authoritative overview artefacts.
- `timeFrameFilter`: deploying without the element does NOT clear an existing one (comment inside `Hoeh_Risk_Chancen.report-meta.xml`) → set an explicit custom span.
- Opportunity layout in repo: exactly one, `layouts/Opportunity-Opportunity Layout.layout-meta.xml`, sections incl. "Discount Approval", "Risk Level", "Follow-up Monitoring" → new section goes after "Verloren Chancen" (~line 248). Lightning page placement stays an Org step.
