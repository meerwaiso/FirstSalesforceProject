# SCRUM-451 — DevOps notizen (merge station)

Verified findings only; each names the command it was verified with.

## Merge gate (all four preconditions read back, not assumed)

- Tracker: `jira_get_issue SCRUM-451` -> status `Deployment`, assignee `devops-agent` (read 2026-10-18, before the merge).
- PR #176 head at merge time: `62b1a3c81be35d3c7faffad5cca9fd4cc89e3f99` (`gh pr view 176 --json headRefOid`).
- CI run `39167602817` headSha == PR head (verified via `gh api repos/.../actions/runs/39167602817/jobs` + run head). All four jobs `success`: Lint & Format (advisory), README aus Release Notes, Prod-Org Drift Gate, Metadata, Apex & Session Smoke.
- Apex really ran (not `NoTests`): artifact `apex-test-results` (id 12151168610) junit -> `tests="12" failures="0" errors="0"`, hostname `resourceful-bear-6f1u4j-dev-ed.trailblaze.my.salesforce.com` = Test-Org. The Smoke job ran 4m7s, not skipped.
- Approval on record: Jira comment 23542 `APPROVED` (round 2, head 60cca4f) + 23544 (green CI on docs head 4f7c454). `reviewDecision` is empty because the repo is single-account — that is expected, not a missing approval.
- Tester verdict on record: Jira comment 23545, 12/12 AC PASS at head 62b1a3c.

## Prod-Org Drift Gate on this head: self-trip, expected pre-release

`gh pr checks 176` reports the gate `pass`, but the `prod-validate` artifact (id 12151019923, deploy job `0Afg500000FxvmPCAR`) still names two failures:

- `SCRUM451TesterFlsNegativeTest.nonTeamleadChangeRefused_storedValueUnchanged` — `No such column 'Wartungsvertrag_Start__c' on entity 'Account'`
- `SCRUM451WartungsvertragTest.caseIndicator_followsTheSameDecision` — fields inaccessible on SObject Account

Both are this ticket's own new fields, which exist only in Test-Org until the Release deploy. No foreign drift names (`FeedItem.RypplePost`, `SCRUM319`, `Case.Rueckruf*`, `VIP_Customer__c`) present. This is the shape measured on SCRUM-436/442/445; it re-greens at the Release deploy.

## Tool quirks hit on this station

- `gh run view <run> --repo ... --log` and `--log-failed` returned 0 lines for this run — the token cannot read action logs. The artifacts (`apex-test-results`, `prod-validate`, `playwright-report`) carry the verdict; read them instead of the log.
- `gh api .../actions/runs/<id>/jobs` returns `closed_at: null` while a job is still running — jq arithmetic on it fails.
- `gh auth list-scopes` is not a command on this gh version.

## Merge record

- Squash merge of PR #176 pinned to head `62b1a3c` (`gh pr merge 176 --squash --match-head-commit 62b1a3c...`).
- `origin/master`: `d2e14c3a538e1a92482970b125100fb022e9a148` -> `d84d1e6b8b4724c5b9474896ff74daf3801ec729`.
- Local master synced with `git fetch origin master:master` (shared working tree stayed on `feature/SCRUM-424-first-response`, foreign uncommitted files untouched).
- Feature branch `feature/SCRUM-451` NOT deleted (branch deletion is policy-gated here).
