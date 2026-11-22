# SCRUM-468 Tester-Notizen

Hard-won facts, one line each. Read this first after every compaction.

## Fixture seed (Test-Org, 2026-11-21, TAG '[TEST-SCRUM-468]')

- Org baseline war 0 live records — Tester seeds all of it (PO comment: counts to create).
- Accounts: A=001WU00002LkYeHYAV B=001WU00002LkS94YAF C=001WU00002LkKUsYAN
- Devices: D1=a08WU00000kxdSfYAI (DEV-0008, Lent_Out, overdue 30) D2=a08WU00000kxdUHYAY (DEV-0009, Lent_Out, overdue 15) D3=a08WU00000kxdVtYAI (DEV-0010, Available) D4=a08WU00000kxXOyYAM (DEV-0011, Written_Off)
- Loans (LOAN-0007..0012): L1=a09WU00000W1ZHZYA3 (D1,A open, due 2026-10-22) L2=a09WU00000W1iJ7YAJ (D2,A open, due 2026-11-06) L3=a09WU00000W1ZarYAF (D3,A ret 2026-10-21, dur 14) L4=a09WU00000W1iRBYAZ (D3,B ret, dur 14) L5=a09WU00000W1iUPYAZ (D4,B ret, dur 25) L6=a09WU00000W1cdZYAR (D4,C ret, dur 28)
- Measured read-back: devices 4 (2 Lent_Out Overdue_Today=true overdue 30/15, 1 Available, 1 Written_Off), loans 6 (2 open, 4 returned), customers 3, colleagues U1=005WU000017tBhRYAU (Meerwais Osmani) U2=005WU000017tBpVYAU (Integration User).
- Overdue report ground truth in org right now: exactly D1(30) and D2(15).

## Guard behaviour measured over REST (LoanRecordGuard fires on create)

- Loans for ONE device must be sequential: creating a second loan while the first is open is REJECTED with "device DEV-xxxx is already on loan to ... — a device may be with exactly one customer at a time" (FIELD_CUSTOM_VALIDATION_EXCEPTION, rc=1). That is AC4 proven at REST level.
- LoanRecordGuard afterInsert fills device Current\_\* half and sets Status\_\_c=Lent_Out automatically.
- Updating Loan_Return_Datum\_\_c flips device back to Available (LoanReturnGuard).
- Setting Status\_\_c='Written_Off' via sf data update record succeeded for the CLI user (holds SCRUM468_Writeoff).
- `sf data create record -s X -v "A=1 B=2"` pairs separated by SPACES; refused create exits rc 1 with JSON error body — execSync-style callers must read stdout, not assume ids.

## CI verdict measured 2026-11-21 on PR #190 head 9f91b7b

gh pr checks 190 on run 44950552347 (head ad7714c): Lint & Format pass 46s | Metadata, Apex & Session Smoke pass 4m3s | Prod-Org Drift Gate pass 12m30s | README pass 6s — four green on THAT head. On the last pushes (5c32cd5..2353c95) Smoke and Drift were still pending when last read (run 44954500269) - DevOps reads the verdicts of the head it merges. (architect/dev open item closed).

## Test budget measured before Apex run

ApexTestQueueItem rows in 24h: 255 vs ceiling 500 (max(500, 10×classes)) — room for the scoped 2-class run.

## Commands that behaved differently

- `sf data update record` exists (subcommands: bulk/record). Used -s/-i/-v.

- RECORD PAGE headless — CORRECTED 2026-11-22 (the 2026-11-21 read was blind):
  `document.body.innerText` really is blind to the record body (1.3 kB, no
  related-list text), but **ariaSnapshot pierces the closed Shadow-Root** and
  carries the whole Related tabpanel. Open the Related tab
  (`getByRole('tab',{name:'Related'})`) — the page opens on Details.
  Demo_Devic__c page: section `Loan records (2)` renders a GRID
  (`row "…"` = rowheader customer-link + gridcells start/due/return, /url
  /related/Loan_Records_History__r/view). Columnheaders rendered:
  "Lent to customer | Loan start date | Loan due date | Return date | Action" —
  the layout's 5th <fields> Loan_Duration_Days__c (label "Loan duration in days")
  is NOT rendered -> AC7 duration half = gap, not a locator problem.
  Account page: section heading `Devices on loan` present but with NO count,
  NO /related/ link and NO row, while the standard sections render
  "Contacts (0)" + link -> AC5 rows missing = real defect.
  Never click `Toggle Panel` in a test: it opens a "DX Inspector Terms &
  Conditions" dialog that replaces the whole page (measured 2026-11-22).

- PS read-back (SOQL, --use-tooling-api): 3 sets SCRUM468_Loan/Read/Writeoff; PermissionSetAssignment per set: 2 rows each (devops-agent@cline.test = CLI target-org user, and the human test account) = 6 rows total. Marker set = membership only (no CRUD): proven by the green negative Apex test - a colleague holding SCRUM468_Loan/Read WITHOUT SCRUM468_Writeoff is refused the write-off, and the positive test passes with it.
- Live field reads through the session: ListView SCRUM468_Overdue rendered Current_Loan_Overdue_Days**c 30/15 and Loan_Colleague**c (fields readable via session holding SCRUM468_Loan/Read); Loan_Record**c Loan_Due_Datum**c + Loan_Status**c rendered in the same rows. fls-check.sh: Overdue_Today**c Formula granted read in Loan and Read, 2 users each.

Loan_Record**c field census (deployed): Loan_Colleague**c Loan_Customer**c Loan_Devic**c Loan_Due_Datum**c Loan_Duration_Days**c Loan_Return_Datum**c Loan_Start_Datum**c — NO Loan_Status**c. "Returned" = Loan_Return_Datum**c != null. Seeding historical loans must interleave lend -> return (the one-customer guard refuses a 2nd OPEN loan on a device).

## Measured 2026-11-22 (Tester, second pass — the 2026-11-21 record-page note was wrong)

- **Bug SCRUM-469 ("AC5/AC7: record pages lack the lending related lists") is
  stale in its "Actual" half.** On the branch (head 9a927f2) the layouts DO carry
  the entries: Account layout `<relatedList>Demo_Devic__c.Current_Customer__c
  /Current_Loan_Colleague__c/Current_Loan_Due_Date__c</relatedList>`; device
  layout `<relatedList>Loan_Record__c.Loan_Devic__c</relatedList>` with 5 fields.
  Live, the DEVICE page renders `Loan records (2)` as a grid with one row per
  loan; the ACCOUNT page renders the section heading `Devices on loan` but no
  count, no /related/ link and NO row. So AC7 rows now exist, AC5 rows do not.
- ariaSnapshot must be taken at PAGE level (`page.ariaSnapshot()`, returns 20 kB
  incl. the closed Shadow-Root). `page.locator('body').ariaSnapshot()` is a
  different call and missed the grid rows.
- The aria heading line carries the related-list COUNT (`heading "Loan records
  (2)" level=2`) — match the section name as a PREFIX, an exact `"Name"` match
  never fires. That was the reason AC7 read 0 rows on the first run.
- Run 1 (2026-11-22 09:30, head 4002f29): 7 passed / 2 failed — AC5 rows 0
  (expected 2), AC7 rows 0 (heading-name bug). Run 2 (head 9a927f2) pending.
- PR #190 = branch feature/SCRUM-468-lend-devices, titled "closes Bug SCRUM-469".

### Measured 2026-11-21 (Tester, first pass)

- PermissionSet census (SOQL, --use-tooling-api): SCRUM468_Loan 0PSWU00000Y7biS4AR, SCRUM468_Read 0PSWU00000Y7biT4AR, SCRUM468_Writeoff 0PSWU00000Y7biU4AR.
- PermissionSetAssignment read-back: working predicate is `PermissionSet.Name = '<dev name>'` (NOT PermissionSetName -> 0 rows). Each of the three sets -> 2 rows: devops-agent@cline.test (CLI Test-Org user, = the Playwright session user) AND meerwais.osmani@resourceful-bear-6f1u4j.com.
- Serial guard (live): refusal text `serial "GUARD-SERIAL-1" is already on device DEV-0059 - one serial number may belong to exactly one device.` Fixture record Names are DEV-xxxx (auto), Designation_Name\_\_c carries the [TEST-...] tag.
- EmailMessage EXISTS in Test-Org (EntityDefinition totalSize 1); `SELECT Id, Subject FROM EmailMessage` = 0 records (MessageSubject does NOT exist).
- Apex scoped run: 8 tests, Pass Rate 100%. Playwright spec: 9/9 green (2.1 min) at head 8bcdf9e.
- CI smoke TypeError earlier = spec's `test.configure` -> house `test.describe.configure`.
- afterAll cleanup verified: loans live 0, devices live 0 (baseline restored).

## Acceptance criteria of SCRUM-468 (verbatim from the ticket, 2026-11-22 09:36) — for the coverage table

- AC1 Device recorded: save designation+serial -> exactly one device record, shows serial, status Available.
- AC2 Serial unique: second device, same serial -> REJECTED, answer names the device that already has it.
- AC3 Lending: available device + start + due -> device shows Lent_Out, customer, start, due, the colleague; exactly ONE loan record.
- AC4 One customer at a time: lend busy device to B -> REJECTED, device still shows A, open loans for that device still 1.
- AC5 Customer view: 2 devices on loan + 1 returned -> the two CURRENT devices listed WITH due dates on the customer page, returned one not listed as current, its loan still in the history.
- AC6 Return: return date -> device Available, customer no longer lists it as current, loan keeps start/due/actual return.
- AC7 History on the device: EVERY loan appears with customer, start, due, actual return AND how long it lasted; row count = loans created for that device.
- AC8 Overdue report for team leads: each overdue device once with device, customer, colleague, days overdue, most overdue first, no Available/Written-Off row.
- AC9 Write-off by team lead: device Written_Off, lending attempt REJECTED, history still fully visible.
- AC9n Negative write-off: Sales employee (not team lead) -> REJECTED; same for Service employee.
- AC11 Service can read: reads every device, status, which customer has it; can neither lend nor record a return.
- AC12 Nothing automatic: overdue device, time passes -> no email, no reminder, no task, no Flow/scheduled alert, status unchanged on its own.
- PO test data: 4 devices, 6 loans, >=2 open past due, >=1 returned, >=1 written off, 3 customers, 2 colleagues; Account anchor named in the report.

## Fix-shape evidence for AC5/AC7 (measured 2026-11-22, for the bug)

- Device layout: `<relatedLists><fields>Loan_Customer__c</fields><fields>Loan_Start_Datum__c</fields><fields>Loan_Due_Datum__c</fields><fields>Loan_Return_Datum__c</fields><fields>Loan_Duration_Days__c</fields><relatedList>Loan_Record__c.Loan_Devic__c</relatedList></relatedLists>` — renders 4 columns (Lent to customer | Loan start date | Loan due date | Return date); `Loan_Duration_Days__c` is a Formula (Number) per fls-check existence line, granted read to the session user by SCRUM468_Loan + SCRUM468_Read (2 users each).
- Account layout (line 377-384): `<relatedLists><fields>Designation_Name__c</fields><fields>Serial_Number__c</fields><fields>Status__c</fields><fields>Current_Loan_Due_Date__c</fields><relatedList>Demo_Devic__c.Current_Customer__c</relatedList></relatedLists>`; `Current_Customer__c.field-meta.xml` type=Lookup, relationshipName=Devices_On_Loan, relationshipLabel="Devices on loan", referenceTo=Account. Section paints heading only.
- Docs (developer.salesforce.com api_meta_layouts): `<relatedLists><relatedList>` is the documented element; SOOverflow case shows chained-lookup `objectB__c.ObjectC__c` failing at DEPLOY time ("Could not find related list ... for entity ...") — our deploy SUCCEEDED, so element-name is not the proven cause. Fix shape is the Developer's call.

