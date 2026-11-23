# SCRUM-472 — Prod-Release notizen (DevOps-Agent, 2026-11-23)

Release gate: ticket in `Release` + assignee `devops-agent` (read back from Jira before the first org write). Prod-Org alias `devops-agent@cline.de` (orgId 00Dg500000DkTtzEAF); Test-Org `devops-agent@cline.test` is the CLI default — every write carries `-o devops-agent@cline.de` explicitly.

Worktree: `wt-472-prod` at `origin/master` head `5cff8cd` (the merged tree; never deployed from the shared checkout, which sits on `feature/SCRUM-424-first-response`).

## House order + isolation proof

- Phase 1 manifest `manifest/scr472-phase1-fields.xml` = `Lead.Company_Size__c` (CustomField) only.
- `sf project deploy validate -x manifest/scr472-phase1-fields.xml -o devops-agent@cline.de -l RunRelevantTests --concise` → **no error code** (clean against Prod).
- Same command on phase 2 **before** the field existed named the cause, not a test:
  `Error in Lead-Lead Layout - In field: field - no CustomField named Lead.Company_Size__c found`
  + `Error in SCRUM472_CompanySize - …` → "2 component error(s)". That is the house order (field before PS/Layout), not a defect.
- Raw validate with the default `RunLocalTests` is RED in Prod with **only foreign** names
  (job `0Afg500000H4pa1CAB`): `SCRUM410CustomerTransferTest.*`, `SCRUM424FirstResponseTest.*`,
  `SCRUM445DiscountApprovalTest.*`, `SCRUM449OpportunityRiskTest.*` — causes `No such column
  'Contacts_Without_Mark__c' on entity 'Account'`, `No such column 'Followup_Required__c' on
  entity 'Opportunity'`, `List has no rows for assignment to SObject`. **Zero names contain 472.**
  Pre-existing Prod drift/test-debt, not caused by this release; recorded so the next agent does not
  re-derive it (and does not read it as a green gate).

## Deploy log (Prod-Org)

- Phase 1 `deploy start -x manifest/scr472-phase1-fields.xml --test-level NoTestRun` → job `0Afg500000H4rFFCAZ`, **Succeeded**, 1 component: `Lead.Company_Size__c` Created, field id `00Ng500000WIaDtEAL`, 0 test errors (`runTestsEnabled=false`).
- PS file read-back on disk before deploy: one `<fieldPermissions>` entry `Lead.Company_Size__c` readable+editable, no object-level permission, no profile edit.

## Still open in this note (continue here, do not re-derive)

- [ ] Phase 2 validate + deploy (PS + `Lead-Lead Layout`)
- [ ] PS assignment in Prod-Org + `PermissionSetAssignment` read-back (expect 2 rows: CLI user + `meerwais.osmani.3ecaf61ebe28@agentforce.com`)
- [ ] `scripts/fls-check.sh Lead Company_Size__c <Prod-Org>` (FLS step 3 = assignment, must be re-run against Prod)
- [ ] Lead counts in Prod: total vs. carrying a size (expect 0 at go-live)
- [ ] Phase 3: deploy the two Apex **test** classes with `NoTestRun`, then run them separately with `sf apex run test -o devops-agent@cline.de --tests <one class> --synchronous --json` (read `result.summary.outcome`; a plain `tail` cuts the verdict)
- [ ] Release note in `docs/RELEASE-NOTES.md` + `scripts/build-readme.sh` in the SAME commit (the blocking CI job `README aus Release Notes` went red after SCRUM-471's note was committed without a README rebuild)
- [ ] Tag `release/2026-11-23-SCRUM-472` at the manifest/docs commit, created BEFORE the first push (pushed tags cannot be re-pointed)

## Excluded from the release note (PO decision, still open)

- Out-of-band picklist rejection: enforceable in the UI only — not claimed.
- Sort/filter by size: **no list-view column exists**, so this criterion is untested, not passed; PO scope decision pending @user.
