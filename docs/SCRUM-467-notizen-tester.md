# SCRUM-467 — Tester notizen (measured, with the command that produced it)

Start: 2026-11-21 nachmittag. Ticket "Testen", assignee tester-agent (read back via
jira_get_issue fields=status,assignee before the first tool call).

## Org facts (Test-Org, alias `Test-Org`)

| Fact                                     | Value                                                    | Command                                                                                                                                   |
| ---------------------------------------- | -------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| open Opportunities                       | 76                                                       | `sf data query -o Test-Org -q "SELECT COUNT(Name) FROM Opportunity WHERE IsClosed=false"`                                                 |
| records with offer data (before seeding) | 0                                                        | same query + `AND Offer_Sent_On__c != null`                                                                                               |
| PS `SCRUM467_Offer_Dates` assigned to    | 2 users: Meerwais Osmani, devops-agent                   | `SELECT Assignee.Name, PermissionSet.Name FROM PermissionSetAssignment WHERE PermissionSet.Name='SCRUM467_Offer_Dates'` --use-tooling-api |
| ApexTestQueueItem rows, rolling 24 h     | 215 (ceiling max(500, 10 x classes) = 500 -> ~285 slack) | `sf data query -o Test-Org -t -q "SELECT COUNT(Id) FROM ApexTestQueueItem WHERE CreatedDate = LAST_N_DAYS:1"`                             |

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

## Measured late on 2026-11-21 (report + Apex + DOM)

- Apex run 707WU00001Valek: 12/12 Pass, failRate 0%, testTotalTime 15523 ms, user devops-agent@cline.test.
  Methods: SCRUM467OfferExpiryTest ac1_bothDates_readBackAsTyped, ac2_defaultValidity_sentPlusThirty_endInclusive,
  ac3_atAGlance_live_lastValidDay_expired, ac4_noOffer_neverLooksExpired, ac4_noOffer_stillClosableAsWon,
  ac5_expiredOffer_closeWonRefused_recordUnchanged, ac6_renewal_movesBothDates_thenClosable,
  ac6_renewedOffer_closableAsWon, ac7_expiredOffer_canStillBeLost, ac8_closedDeal_datesFrozen_historyUntouched;
  SCRUM467OfferFlsTest ac12_psHolder_recordsOnForeignOpenOpportunity, ac13_userWithoutTheSet_offerFieldsNotReadableNotUpdatable.
  Read-back: `sf apex get test -i 707WU00001Valek --target-org Test-Org -r json` (NO -w flag exists).
- Both report metas (branch): groupingsDown = Opportunity.Offer_Expires_On**c, Day, Asc
  -> the leading cell of a detail row IS the expiry date, "soonest expiry first" = group order.
  Filters: Offer_Expiring_14D**c / Offer_Expired**c equals 1 AND STAGE_NAME notEqual 'Closed Won,Closed Lost'.
  timeFrameFilter dateColumn=CREATED_DATE, INTERVAL_CUSTOM 2000-01-01..2099-12-31.
  Columns Due_14D: OPPORTUNITY_NAME, ACCOUNT_NAME, FULL_NAME, AMOUNT, STAGE_NAME, Offer_Sent_On**c, Offer_Status**c.
  Expired additionally has Offer_Valid_Until**c (no Offer_Days_Left\_\_c by design).
- Live report DOM: the tables have NO <tbody>. `table tbody tr` -> 0 rows; `tr` under `table` is the shape.
- Record page aria: `listitem: Offer status offer valid for 14 more days`; `Offer expired False Offer expired`
  (the label repeats around the boolean -> value parser must handle both sides);
  `Offer days left 14`; `Offer expiry (last valid day) 03.12.2026`; buttons `Edit Stage`,
  `Edit Verlustgrund`, `Edit Offer sent on`, `Edit Offer valid until`; the Labels appear TWICE
  (field row + inline-edit area) -> label locators need .last(), never a count-1 guard.
- Picklists: `combobox "<Label>"`, options exist only after the combobox click; `listbox "Path Options"`
  (the Stage path) already contains options -> the open-state check is a DELTA on the option count.
- Loss_Reason\_\_c picklist values (`sf sobject describe --sobject Opportunity`): Zu teuer, An einen Wettbewerber
  verloren, Kein Budget, Zeitpunkt passte nicht, Kein Bedarf mehr, Kontakt abgebrochen, Sonstiges.
- EntityDefinition has QualifiedApiName/DeveloperName/Label (NO Name, NO Queryable) -> AC11 uses
  `SELECT QualifiedApiName, Label FROM EntityDefinition WHERE QualifiedApiName LIKE 'Offer%'` (-t) -> 0 rows.
- Harness bugs in MY spec (fixed, commit 9f0165d): FIXTURES was module-level and accumulated across the six
  describe blocks (Playwright runs beforeAll once per block), so fixtureId() returned an id an earlier afterAll
  had DELETED -> later blocks opened 404 record pages. Fixed with FIXTURES.length = 0 + latest-match lookup.
- `sf project retrieve` round-trips rewrote the two report metas (comments stripped, True -> 1): phantom dirty
  files, discarded with `git restore`, NOT committed.
- Run 1 (proc_63b277f9b6c4): 3 pass / 9 fail (10.2 min). Run 2 (proc_3cb76710521d): log
  /home/fino/.hermes/profiles/tester-agent/cache/scratch/scr467-e2e-run2.log.
