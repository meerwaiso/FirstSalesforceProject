# SCRUM-470 — DevOps-Notizen, Prod-Release-Station (22.11.2026)

Messung per DevOps-Agent. Each value read back from the org or the repo, not assumed.

## Authorization (both conditions read back before any org write)

- `jira_get_issue SCRUM-470` → status **Release**, assignee **devops-agent** (updated 2026-11-22 21:46:43 CET). PO-Agent granted the handoff; Prod-Org deploy authorized.
- Merge station (same day, see `docs/SCRUM-470-notizen-devops.md`): PR #191 squash-merged → `d3ff4f5`, CI run 45057073901 green on head `baa77c6`, all gate steps completed (not skipped).

## Prod-Org state before the deploy (target-system checks)

- `sf sobject describe --sobject Contact --target-org Prod-Org --json` → 78 fields, **no `Preferred_Contact_Method__c`** (so the field is genuinely absent in Prod, not merely invisible).
- `sf data query --target-org Prod-Org --query "SELECT PermissionSet.Name, Assignee.Username FROM PermissionSetAssignment WHERE PermissionSet.Name LIKE 'SCRUM470%'"` → 0 rows (PS not in Prod).
- Layout compared against the org: `sf project retrieve start --metadata "Layout:Contact-Contact Layout" --target-org Prod-Org` in a detach worktree, then
  - **Prod vs pre-feature master (`48ee748`)**: diff = 9 lines, only the SCRUM-453 XML comment (comments are not org state) → Prod layout content == repo baseline, **no foreign drift**.
  - **Prod vs master with feature (`d3ff4f5`)**: diff = the four `<layoutItems>` lines for `Preferred_Contact_Method__c` (+ same comment).
  → deploying master's layout file to Prod adds exactly the one layout item this ticket owns; nothing of Prod state is lost (the SCRUM-467/468 "master's layout blob overwrites Prod state" trap is checked, not assumed).

## Release delta = force-app diff 48ee748..d3ff4f5 (14 files, 4 org components)

| Component | Member form (copied from the Developer's phase manifests) |
|---|---|
| CustomField | `Contact.Preferred_Contact_Method__c` (qualified — bare member fails) |
| PermissionSet | `SCRUM470_ContactContactWay` (Read + Edit field rights) |
| Layout | `Contact-Contact Layout` (DASH form) |
| ApexClass | `SCRUM470PreferredContactMethodTest`, `SCRUM470PreferredContactMethodFlsTest` |

Files verified on disk before the deploy (manifest entry ⇒ file must exist).

## House release order (proven SCRUM-464/467/468)

1. `deploy start --manifest manifest/scr470-prod-release.xml -o Prod-Org --test-level NoTestRun` (CustomField listed first, PS+Layout reference it).
2. PS **assignment** in Prod (`sf org assign permset -n … -b …`) + read-back — deployed-but-unassigned is what produced `No such column` six times.
3. Apex test run in Prod as a separate phase (`sf apex run test -o Prod-Org --synchronous --json --tests <one class per call>`); inline RunSpecifiedTests in admin mode fails (SCRUM-436).
4. Tag `release/2026-11-22-SCRUM-470` at the Prod-release-manifest commit — created with the explicit sha BEFORE the tag is pushed (a pushed tag cannot be re-pointed).

## Measured during the release (all read back, Prod-Org)

- Pre-deploy `sf project deploy validate --manifest manifest/scr470-prod-release.xml --target-org Prod-Org` → **FailedValidationError, job `0Afg500000H3WXpCAN`, 12 findings, ZERO component findings** — all 12 are FOREIGN test methods (`SCRUM410CustomerTransferTest`×3, `SCRUM445DiscountApprovalTest`×8, `SCRUM449OpportunityRiskTest`×1) failing inside the already-live Prod triggers `ContactLeftGuardTrigger` / `OpportunityFollowupMonitorTrigger` because Prod lacks `Account.Contacts_Without_Mark__c` and `Opportunity.Followup_Required__c` (Test-Org-only metadata) and 8 findings are `List has no rows for assignment to SObject` (fixtures name Test-Org users). Classification rule of the CI drift gate (`.github/workflows/ci.yml`, job "Prod-Org Drift Gate", gate = componentFailures only, test/coverage = warning): green for THIS release. `sf project deploy cancel -i 0Afg500000H3WXpCAN` → `CannotCancelDeployError … already completed` (no leftover validation in the org).
- Deploy `sf project deploy start --manifest manifest/scr470-prod-release.xml -o Prod-Org --test-level NoTestRun` → job **`0Afg500000H3X7JCAV`**, componentFailures `[]`, componentSuccesses 5:
  | Component | Org id | created |
  |---|---|---|
  | CustomField `Contact.Preferred_Contact_Method__c` | `00Ng500000WGwFJEA1` | yes |
  | PermissionSet `SCRUM470_ContactContactWay` | `0PSg500000EqCEjGAN` | yes |
  | Layout `Contact-Contact Layout` | `00hg5000008i9UhAAI` | no (updated) |
  | ApexClass `SCRUM470PreferredContactMethodTest` | `01pg500000FdUIYAA3` | yes |
  | ApexClass `SCRUM470PreferredContactMethodFlsTest` | `01pg500000FdUIXAA3` | yes |
  `runTestResult.numTestsRun = 0` — NoTestRun as intended, the test phase is separate.
- PS assignment in Prod (`sf org assign permset -n SCRUM470_ContactContactWay -b <user> -o Prod-Org`, no `-u` flag exists) → 2 successes; read-back `SELECT … FROM PermissionSetAssignment WHERE PermissionSet.Name LIKE 'SCRUM470%'` → **2 rows**: `meerwais.osmani.3ecaf61ebe28@agentforce.com` (@user, System Admin) and `devops-agent@cline.de`.
- Field read-back through a real Prod session (CLI user holds the PS): `SELECT Name, Phone, Email, Preferred_Contact_Method__c FROM Contact LIMIT 3` → 3 rows readable, Phone/Email present, `Preferred_Contact_Method__c` = null on every one.
- Counts in Prod: `SELECT COUNT() FROM Contact` = **20**, `WHERE Preferred_Contact_Method__c != null` = **0** before AND after the deploy → nothing automatic (AC1/AC7 hold in Prod; existing contacts stay empty).
- Apex in Prod, one class per synchronous call (`sf apex run test -o Prod-Org --tests <class> --synchronous --json`): **11/11 green, failRate 0 %** —
  `SCRUM470PreferredContactMethodTest` 8 tests (`schema_exactly_three_values`, `value_phone`, `value_email`, `value_letter`, `empty_stays_empty`, `overwrite_phone_to_letter`, `clear_back_to_empty`, `nothing_automated_side_effect`) and
  `SCRUM470PreferredContactMethodFlsTest` 3 tests (`precondition_contact_object_access`, `withoutPS_field_not_readable`, `withPS_readable_and_writable`).
  Proven to be Prod, not a Test-Org echo: `summary.orgId = 00Dg500000DkTtzEAF`, `summary.username = devops-agent@cline.de`.
  AC6 (negative access) is thus proven **in Prod** as well — `withoutPS_field_not_readable` passed there.
- NOT verifiable by me: the Lightning page rendering (layout item next to Phone/Email) in Prod — the layout component deployed with `changed: true` and the item was diffed into the org file before the deploy, but no browser read-back was run against Prod-Org (Playwright belongs to the Tester).
