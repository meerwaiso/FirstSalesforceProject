# SCRUM-440 — Prod-Release Notizen (DevOps-Agent, 2026-10-10)

Release-Gate: SCRUM-440 in column "Release" AND assignee devops-agent (read back via jira_get_issue, 2026-10-10 18:26 CEST). PO confirmed, Jira comment 23204.

## Hard findings (verified, command named)

- Prod-Org alias = `devops-agent@cline.de` (orgId 00Dg500000DkTtzEAF), Test-Org = `devops-agent@cline.test` = IS-DEFAULT. Every org write carries `-o Prod-Org` explicitly. `sf org list` read back.
- Prod-Org before release: `sf sobject describe -o Prod-Org -s Opportunity` (PO, comment 23204) — 10 custom fields, neither Rueckruf field present. Dependencies of the shared Opportunity trigger live in Prod (Is*Overdue__c, Loss*Reason__c, OpportunityOverdueResetHandler, OpenOpportunityRollupHandler).
- **package.xml `<version>68.0</version>` is rejected by the Prod-Org validator**: `sf project deploy validate --manifest manifest/scr440-phase1-fields.xml -o Prod-Org --concise` → Deploy ID 0Afg500000FjT0QCAV, `Error in package.xml - Invalid version specified:68.0`. House manifests on master use 67.0 (110 of 141 manifests; the 4 hits of 68.0 are exactly the four SCRUM-440 manifests). Fix: all three phase manifests → 67.0. (Same apiVersion trap the Architect rejected on the PR at 5672d7a; there it was the classes' .cls-meta.xml → 63.0.)
- `sf project deploy validate` resolves source files from the **cwd**, not from the manifest path: running it from the shared checkout gave `Error (ComponentSetError): No source-backed components present in the package`. Correct call: run with workdir = the master worktree, `--manifest manifest/<m>.xml -o Prod-Org` (no `-d`, `--manifest` and `--source-dir` are mutually exclusive per `--help`).
- `--test-level` has NO `NoTestRun` option (options: RunAllTestsInOrg|RunLocalTests|RunSpecifiedTests|RunRelevantTests) — a validate always runs tests. Prod release uses the 3-phase pattern: deploy `--test-level NoTestRun` (deploy subcommand DOES accept it), Apex tests in a separate `sf apex run test -o Prod-Org`.

## Release plan (3-phase, house pattern 421/428/431/436)

1. Phase 1 fields → Prod-Org (NoTestRun)
2. Phase 2 ValRule-Pair + PS + Handler + Trigger → Prod-Org, then PS assignment read-back
3. Phase 3 Layout → Prod-Org
4. Apex tests in Prod: separate `sf apex run test -o Prod-Org --tests SCRUM440RueckrufwunschTest --tests SCRUM440RueckrufwunschFlsTest` (an inline RunSpecifiedTests Prod deploy fails on new fields — 436: 8 VerifyTests `No such column`)
5. Tag `release/2026-10-10-SCRUM-440` (never `archiv/...`)

## PS assignment targets (Prod-Org)

- CLI user devops-agent@cline.de via `sf org assign permset -n SCRUM440_Rueckrufwunsch -b <user> -o Prod-Org`
- @user (meerwais.osmani.3ecaf61ebe28@agentforce.com, System Admin) — Prod's only real end user; needs REST-POST PermissionSetAssignment with field **AssigneeId** if `-b` by alias fails (`sf org assign permset` has no `-u`).

## Open PO decision (accepted, comment 23204)

- AC5: `Abgebrochen` not on Task Status picklist (Test-Org: Not Started, In Progress, Completed, Waiting on someone else, Deferred) → handler sets `Deferred`, record not deleted. Accepted by PO, AC reworded.
- New finding, NOT blocking this release: handler is `after update` only — a newly CREATED Opportunity with the checkbox set gets no Task (PO measured: insert flag=true → 0 Tasks). Tracked as BUG-SCRUM-440-Insert, own story.

## Status

- [x] gate check (Release + assignee)
- [x] manifests vs disk (all members present on master 6be60f2)
- [x] apiVersion fix 68.0 → 67.0 (all 4 manifests; the 4th, scr440-apextests.xml, hit the same error on its own deploy — one fix, one redeploy)
- [x] Phase 1 fields → Prod: Deploy ID 0Afg500000FjWuLCAV, 2/2, v67.0 SOAP
- [x] Phase 2 ValRules+PS+Handler+Trigger → Prod: Deploy ID 0Afg500000FjSXOCA3, 5/5
- [x] PS SCRUM440_Rueckrufwunsch (Id 0PSg500000DQaYDGA1) assigned to 2 users; read-back `PermissionSetAssignment WHERE PermissionSetId=...` → 2 rows (0Pag500000LGa6kCAD → 005g5000009C38DAAS @user, 0Pag500000LGiM1CAL → 005g5000009C4M4AAK CLI); field read-back `SELECT Id,Name,Rueckruf_desired__c,Rueckruf_am__c FROM Opportunity LIMIT 2` → values returned (false/null)
- [x] Phase 3 Layout → Prod: Deploy ID 0Afg500000FjWzBCAV, 1/1
- [x] Test classes live in Prod (ApexClass query: RueckrufTaskHandler 01pg500000E8tLpAAJ, FlsTest 01pg500000E8tSHAAZ, Test 01pg500000E8tSIAAZ)
- [x] Apex tests in Prod: `sf apex run test -o Prod-Org --tests ...` RunId 707g500000pfYbd → 7/7 Pass, Fail 0%, OrgId 00Dg500000DkTtzEAF (incl. withoutPS_fieldsInvisible = negative FLS test green in Prod)
- [x] release tag `release/2026-10-10-SCRUM-440` @ ea6fcb6, pushed to origin (`git ls-remote --tags` read back)
- [ ] Release-Notes entry (docs/RELEASE-NOTES.md) is the PO's to write — header says PO writes it once DevOps reports a green Prod deploy; not mine
