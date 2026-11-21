# SCRUM-467 — Tester notizen (measured, with the command that produced it)

Start: 2026-11-21 nachmittag. Ticket "Testen", assignee tester-agent (read back via
jira_get_issue fields=status,assignee before the first tool call).

## Org facts (Test-Org, alias `Test-Org`)

| Fact | Value | Command |
|---|---|---|
| open Opportunities | 76 | `sf data query -o Test-Org -q "SELECT COUNT(Name) FROM Opportunity WHERE IsClosed=false"` |
| records with offer data (before seeding) | 0 | same query + `AND Offer_Sent_On__c != null` |
| PS `SCRUM467_Offer_Dates` assigned to | 2 users: Meerwais Osmani, devops-agent | `SELECT Assignee.Name, PermissionSet.Name FROM PermissionSetAssignment WHERE PermissionSet.Name='SCRUM467_Offer_Dates'` --use-tooling-api |
| ApexTestQueueItem rows, rolling 24 h | 215 (ceiling max(500, 10 x classes) = 500 -> ~285 slack) | `sf data query -o Test-Org -t -q "SELECT COUNT(Id) FROM ApexTestQueueItem WHERE CreatedDate = LAST_N_DAYS:1"` |

## Naming facts that saved a guess

- The two Reports on the branch are `Sales/SCRUM467_Offer_Expired_Renewals` and
  `Sales/SCRUM467_Offer_Renewals_Due_14D` — NOT the design-doc names
  `Offers_Already_Expired` / `Offers_Expire_14D`. The branch is authoritative; the design
  Components table is superseded by §11 "Verified shapes".
- ValidationRule errorMessage strings the Apex tests assert on (verified in the branch
  files, they match): `Der angebot already expired - ... Renew it first ...` (contains
  "already expired" + "Renew it first"), `The deal is already closed - ...` (contains
  "already closed").
- `FieldDefinition` has no `CapabilityType` and no `Type` column (both rejected
  "No such column" 2026-11-21) — `sf sobject describe --sobject Opportunity` answers the
  field question instead.
- `sf apex run test -l RunSpecifiedTests` returns async by default; results come from
  `sf apex get test -i <jobId> -o Test-Org -r json`. Job for this run: 707WU00001Valek.

## Artefacts already on the branch (Developer)

- `SCRUM467OfferExpiryTest.cls` — AC1-AC8 (10 test methods).
- `SCRUM467OfferFlsTest.cls` — AC12 positive / AC13 negative via System.runAs.
- `SCRUM467_TestObjectAccess` permissionset — fixture users' object-level CRUD (test-local).
- NO Playwright spec for AC9/AC10 (nor for the record page) on the branch: `tests/e2e/`
  has no SCRUM-467 file -> the Tester owns that spec.

## Tester duties still open (from the ticket + design §Counts)

- (a) open without offer data, (b) expiring within 14 days, (c) already expired:
  all three must be seeded non-zero by me; the org has 0 offer records today.
- AC9/AC10 have NO automated artefact at all (Architect comment 23715 says exactly that).
