# SCRUM-459 — DevOps release notizen (Prod-Org, 2026-11-01)

Hard-won findings, one line each. Verified via the named command.

## Release state
- Prod deploy authorized: ticket in "Release" + assignee devops-agent, read back from tracker before first deploy command (Jira comment 23600 PO ACCEPTED 17:36).
- Merge commit tagged: `release/2026-11-01-SCRUM-459` → f4fb858bf5f23776c93ff46f1348e62c49712878 (read back via `git cat-file -p refs/tags/...` → object f4fb858).
- Prod-Org = alias `Prod-Org`, orgId 00Dg500000DkTtzEAF, username devops-agent@cline.de (`sf org list`). Test-Org is the IS-DEFAULT — every Prod command carried `-o Prod-Org` explicitly.

## Deploy (house 3-phase pattern)
- Phase 1: 8× `sf project deploy start --manifest manifest/scr459-phase{1,2,2b,2c,3,3b,4}*.xml + scr460-recordpages.xml -o Prod-Org --test-level NoTestRun`, in dependency order (object+fields → PS → ListView → WritePS → handler alone → triggers → test pair → layouts). All exit 0.
- Deploy report: everything `Created` EXCEPT `Opportunity-Opportunity Layout` = `Changed` (Prod already had the base layout; the release adds the "Follow-up Monitoring" section).
- Component read-back in Prod (`sf data query -t`): 3 ApexClass (handler + 2 tests), 3 ApexTrigger, 3 PermissionSet.

## PS assignment + read-back (Phase 2)
- `sf org assign permset -n <PS> -b <user> -b <user> -o Prod-Org` (flag is `--on-behalf-of`, there is NO `-u`; `-o` defaults to Test-Org!).
- 3 PS × 2 users (meerwais.osmani.3ecaf61ebe28@agentforce.com + devops-agent@cline.de) → read-back `SELECT Assignee.Username, PermissionSet.Name FROM PermissionSetAssignment WHERE PermissionSet.Name LIKE 'SCRUM459%'` = 6 rows.

## Prod test verdict (Phase 3, separate runs)
- `sf apex run test -o Prod-Org --tests <class> --synchronous --json` (one class per call):
  - SCRUM459FollowupMonitorTest: 11/11 Passed (3.1 s)
  - SCRUM459FollowupFlsTest: 2/2 Passed (1.8 s)
  - both: orgId 00Dg500000DkTtzEAF, username devops-agent@cline.de → ran in Prod, not Test.
- 13/13 total = matches the Tester's 13/13 in Test-Org.
- Pitfall: plain `tail` on the run output cuts the summary; use `--json` and read `result.summary.outcome`.

## Org data state after release
- Prod holds no follow-up data (0 obligations) — same baseline as Test-Org per PO comment 23600. Positive acceptance criteria were proven in the Tester fixture run, not by org data.
