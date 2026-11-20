# SCRUM-464 — Notizen (hard-won findings, one line each)

Survey base: `git fetch origin`; origin/master @ `3eb2ac1`; live org read via `sf ... --target-org Test-Org` on 2026-11-20.

- Cause concept already on Case: `Ursache__c` Picklist, deployed **5/5** values, `restrictedPicklist=false` — `sf sobject describe --sobject Case --target-org Test-Org` (picklistValues read from the describe JSON).
- Active rule `Ursache_PflichtBeiGeschlosed` refuses closed + empty cause — `git show origin/master:force-app/main/default/objects/Case/validationRules/Ursache_PflichtBeiGeschlosed.validationRule-meta.xml`.
- SCRUM-461/462 is the sibling for list+role-gate+overview: `Competitor__c` object, Lookup, Currency 18/2, `*_Price_Known__c` 0/1 denominator, rule with `errorDisplayField`, guard `CompetitorNameGuard`, PS pair `_List_Read`/`_List_Teamleitung`, report pair scope organization/user — `git ls-tree -r origin/master`.
- No name collision: custom objects matching fabrik/manuf = none; Case 82 fields, none matching drittp/fabrik/fixkosten/last_12 — `sf sobject list` + `sf sobject describe`.
- Test-Org baseline 2026-11-20: Cases 675 · closed 46 · closed with cause 4 · third-party 0 · manufacturer records 0 — `sf data query --query "SELECT COUNT() FROM Case WHERE IsClosed = true"` etc. NOTE: `--use-tooling-api` + `COUNT() FROM Case` → "sObject type 'Case' is not supported"; without the flag it works.
- `PermissionSetAssignment` columns: `Assignee.Username` works, `Assignee.Profile.Name` does NOT ("No such relation 'Profile'") — measured live.
- Existing service PSs are assigned to exactly 2 users: `devops-agent@cline.test` + `meerwais.osmani@resourceful-bear-6f1u4j.com` (SCRUM434_Ursache, SCRUM428_ServiceTeam, SCRUM428_Teamleitung, SCRUM461_Competitor_List_*) — SOQL above.
- Schema facts from `/usr/lib/node_modules/@salesforce/cli/node_modules/@salesforce/types/lib/metadata.d.ts`:
  - `PermissionSetFieldPermissions = {editable, field, readable?}` (line 10262) → FLS has NO set-vs-clear distinction.
  - `ReportGrouping = {aggregateType?, dateGranularity?, field, sortByName?, sortOrder, sortType?}` (line 11286) → ONE sort key only.
  - `UserDateInterval` (line 586) has no rolling last-12-months value → formula gate + `INTERVAL_CUSTOM`.
- `analytics/reportTypes/CaseList` (reduced beta endpoint) lists only 7 detail columns + RowCount — custom fields are NOT listed there, yet deployed reports group/filter on them; the report-token oracle is deploy-validate, not that endpoint (house SCRUM-432/434).
- Case record page = legacy layout `layouts/Case-Case Layout.layout-meta.xml` blob `5394823d913cb3de0f146d93bebeeb6cdce37c02`; already has a `Rückschau` section with `Ursache__c`.
- Repo's Apex never inspects permissions (all role logic = Permission Sets) — `git grep -iE "PermissionSetApi|checkPermission|PermissionCheck"` over classes hits only test classes creating `PermissionSetAssignment`. So a runtime "does this user hold PS X" guard is NEW code, not reuse.
