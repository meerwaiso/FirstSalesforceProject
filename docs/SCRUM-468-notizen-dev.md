# SCRUM-468 Notizen (developer-agent)

Started 2026-11-21 on branch feature/SCRUM-468-lend-devices. Read this file first
after every compaction; commit it with the ticket.

## Measured against Test-Org / origin/master (command in brackets)

- No lending object existed in Test-Org before this ticket (PO measurement + my
  Tooling-API EntityDefinition read).
- Real users in Test-Org: only `devops-agent@cline.test` (CLI target-org user,
  `sf org display`) and `meerwais.osmani@resourceful-bear-6f1u4j.com`. There is no
  user "sales employee" or "team lead"; the role split lives in Permission Sets
  (house convention, docs/SCRUM-461-notizen-dev.md).
- `UserInfo.getUserId()` compiles and returns the running user Id (scripts/apex-probe.sh
  q3, Test-Org). `$User` is NOT valid Apex (probe p1-p5: "Variable does not exist: $User").
- PermissionSetAssignment SOQL in Apex: queryable columns are `PermissionSetId` and
  `AssigneeId`; `Assignee` is rejected ("No such column 'Assignee' on entity
  'PermissionSetAssignment'", probe q1). `SELECT Id FROM PermissionSet WHERE Name = :x`
  works; the marker lookup + PSA filter returned rows=1 for the CLI user (probe q3).
- `<sharingModel>` enum, read from the CLI's own schema
  (`@salesforce/types/lib/metadata.d.ts:194`):
  `Private | Read | ReadSelect | ReadWrite | ReadWriteTransfer | FullAccess |
 ControlledByParent | ControlledByLeadOrContact | ControlledByCampaign`.
  The design doc said `Private` -> kept it. My first guess `Locked` was rejected by
  validate ("'Locked' is not a valid value for the enum 'CustomSharingModel'").
  `externalSharingModel Private` is the house value (Competitor\_\_c, origin/master).
- Number formula field shape (house Competitor_Gap\_\_c): fullName, label, description,
  formula, precision, scale, type, unique; no <length>.
- Picklist house shape (Customer_Satisfaction\_\_c): required/restricted/trackFeedHistory/
  trackHistory/type/valueSet; default lives on the <value>.

## Deploy order (memory + manifest)

objects -> fields -> guards+tests -> permission sets -> report.

## AC8 carrier (2026-11-21, Architect review §1)

- Formula Checkbox `Overdue_Today__c` on Demo_Devic**c: `<formula>AND(Text(Status**c) = "Lent_Out", NOT(ISBLANK(Current_Loan_Due_Date**c)), Current_Loan_Due_Date**c &lt; TODAY())</formula>`, `<type>Checkbox</type>`. No `formulaType` element — rejected at this location in type CustomField.
- ListView path is `objects/Demo_Devic__c/listViews/SCRUM468_Overdue.listView-meta.xml`; manifest member `Demo_Devic__c.SCRUM468_Overdue` under `<name>ListView</name>`. `<columns>` take bare API names of the object's own fields; `<columns>Name</columns>` is refused ("Could not resolve list view column: Name"). ListView metadata has NO sort element — longest-overdue-first is a UI sort the Tester asserts.
- Manifests: `manifest/scr468-phase5a-ac8-field-listview.xml` (CustomField before ListView), `manifest/scr468-phase5b-ac8-permsets.xml`. Validate then deploy each: 5a job 0AfWU00000dJ9Vl0AK, 2/2 components Succeeded; 5b 2/2 Succeeded. Guards+tests redeployed RunSpecifiedTests → Passing: 8, Failing: 0, Total: 8 (scratch/d5c.log).
- Formula fields DO evaluate in the Apex test sandbox (new assertion `flagged == 2` over `SELECT Overdue_Today__c FROM Demo_Devic__c` passed); trigger-written rollup fields do NOT (stay NULL until a save touches them). Different semantics — do not assert them the same way.
- `sf data create record -s Demo_Devic__c -v "Name='...'"` fails: INVALID_FIELD_FOR_INSERT_UPDATE "Unable to create/update fields: Name" — the name field is AutoNumber, omit Name. Live read-back record SN-RB-468 (Lent_Out, due 2026-10-31) → Current_Loan_Overdue_Days**c 21, Overdue_Today**c true; deleted afterwards, both objects read 0 records.
- `scripts/fls-check.sh Demo_Devic__c Overdue_Today__c Test-Org` → exists "Formula (Checkbox)", read=true edit=false in SCRUM468_Loan and SCRUM468_Read, 2 users each, verdict visible.
- `reportTypes/SCRUM468_Overdue_Devices.reportType-meta.xml` deleted from the branch: a ReportType renders nothing, and the formula field is refused as columns/sortColumn/groupingsDown ("no CustomField named ... found" — a FormulaField is not a CustomField). AC8 does not rest on it.
- CI at head 1e51102 as seen: Lint & Format and README pass; "Metadata, Apex & Session Smoke" and "Prod-Org Drift Gate" still pending — the merge gate needs those verdicts on THIS head, not on 62477a3.

## AC5/AC7 follow-up (bug SCRUM-469, 21.11.2026) — record pages

- `git diff --name-only origin/master origin/feature/SCRUM-468-lend-devices | grep -i layout` -> LEER
  (Tester claim confirmed: no layout touched). Their `probe468.py` never ran -> DOM expectations unknown.
- Layout metadata member name = `<Object>-<Layout label>` (DASH): "Layout:Account-Account Layout" and
  "Layout:Demo_Devic**c-Demo Device Layout" work; the DOT form "Layout:Demo_Devic**c.Demo Device Layout"
  -> "Entity of type 'Layout' named ... cannot be found". The DOT form made me conclude NO layout existed.
- Deploy reported `Changed` for the device layout -> the org ALREADY had that layout (repo never had it).
  I overwrote an org layout without reading it first; mitigation: my file carries the full field census
  (all 8 fields + System Information); the org read-back kept its trailing <layoutSections> style=CustomLinks
  and my <relatedLists> is at lines 72-78. Repo file then = org read-back + my comment (ADR-7).
- <relatedList> token form (live house example in the org Account layout): <childObject>.<lookupFieldOnChild>
  e.g. OpenOpportunityHistory**c.AccountId**c. Mine: Demo_Devic**c.Current_Customer**c (Account page, AC5),
  Loan_Record**c.Loan_Devic**c (device page, AC7). Both accepted -> deploy 2/2 components.
- record-ui IS readable for the CLI session: /ui-api/record-ui/<recordId>?layoutTypes=Full&modes=View ->
  layouts/<Object>/<recordTypeId>/Full/View/{id, sections}; active Account layout 00hWU00000XBoxxYAD, 10
  sections incl. "Fehlzeit". It returns NO related lists at all (Account metadata has 8 <relatedLists>,
  none in `sections`) -> cannot prove a related list renders. SFC .../layouts/<name>/relatedLists =
  NOT_FOUND on v62.0 AND v60.0. Related-list evidence = deploy acceptance + org read-back + Tester DOM.
- Ops: validate 0AfWU00000dJIu10AG (2/2 components, 8/8 tests), deploy 0AfWU00000dJIvd0AG (NoTestRun,
  both layouts Changed).
- FOREIGN uncommitted file in my worktree: layouts/Account-Account Layout.layout-meta.xml (someone else's
  org-retrieve in progress) -> saved to probe/FOREIGN-Account-layout.xml, restored, then replaced by my
  org-derived version. diff foreign vs committed = my SCRUM-comments + my relatedList only: nothing lost.

## Re-review round on head c40f6e9 (2026-11-22)

- **restricted goes INSIDE valueSet.** As a child of CustomField the org parser rejects it:
  `Error Unable to parse XML for CustomObject Demo_Devic__c in force-app/main/default/objects/Demo_Devic__c/fields/Status__c.field-meta.xml: Error parsing xml: Parse error: Element 'restricted' is invalid at this location` (validate ops 0AfWU00000dJISX0AG and 0AfWU00000dJc370AC, two positions, identical message). Accepted shape `<valueSet><restricted>true</restricted><valueSetDefinition>`: validate 0AfWU00000dJc370AC Succeeded, deploy 0AfWU00000dJc4j0AC State Changed, retrieve probe/rsp3 shows the element back.
  No house precedent: origin/master has zero `<restricted>` in any fields/*.field-meta.xml - first restricted picklist in the repo.
- **Grant census:** SCRUM468_Loan 15 fieldPermissions, SCRUM468_Read 15, SCRUM468_Writeoff 0 (marker only; a Permission Set can only grant, never revoke). Org retrieve probe/psr returns 15/15/0, identical to the branch files.
- **Assignment read-back** scripts/apex-probe.sh -f probe/psa-probe.apex (same query shape as DemoDevicWriteoffGuard): all three sets assigned to devops-agent@cline.test AND to meerwais.osmani@resourceful-bear-6f1u4j.com.
- **Account layout base = master, not the org.** Org file carries section Fehlzeit with layoutItem Absence_Anzeige__c; field in origin/master and in Prod-Org, in no manifest; the Prod-Org Drift Gate reddened with exactly that one unresolved component. Branch file = master + only my relatedLists block (diff 8 lines). Deployed (validate 0AfWU00000dJcCn0AK, deploy 0AfWU00000dJcEP0A0); org read-back: 0 occurrences of Absence_Anzeige__c, relatedList present. Consequence stated: the Test-Org page loses that section, the field untouched; restoring it is a PO decision on SCRUM-457.

## Round 3 - the two AC5/AC7 gaps from the Tester (2026-11-22)

- **A Formula field cannot become a real field, and cannot be deleted while referenced.** Three separate org answers, all mine:
  `Cannot update a field from a Formula to something else` (validate 0AfWU00000dJibZ0AS, Loan_Duration_Days__c Number-with-<formula> -> plain Number),
  `This custom field is referenced elsewhere in salesforce.com. : Apex Class - SCRUM468LendDevicesTest` (`sf project delete source --check-only -r`, op 0AfWU00000dJidB0AS),
  and the compile check `Field is not writeable: Loan_Record__c.Loan_Duration_Days__c` (assigning to it in Apex is illegal regardless of any grant). So the "make the derived column renderable" fix is blocked in both directions in this org.
- **Related-list column census in this org (falsifies a type theory, suggests a cap).** House Account layout list `OpenOpportunityHistory__c.AccountId__c` declares 3 <fields>, SCRUM-417 verified 3 rendered columns. My device list declares 5 <fields>; the Tester censused exactly the FIRST FOUR rendered plus an "Action" column, the 5th (declared last, the formula) missing. Same for my Account block: 4 <fields>, heading renders, no rows. Hypothesis: Lightning renders at most 4 data columns per related list.
  **Experiment deployed:** Loan_Duration_Days__c moved from last to SECOND in the device related list (validate 0AfWU00000dJjfh0AC, deploy Succeeded, component State Changed). Falsifiable: if Loan_Return_Datum__c (now last) drops instead, the cause is the column cap and AC7's five columns do not fit; if the duration column is still missing with all four others rendered, the cause is the formula type.
- **Lookup vs master-detail for a related list on a STANDARD object page.** Org Account layout holds exactly two custom related lists: `OpenOpportunityHistory__c.AccountId__c` (field type MasterDetail, verified 9 rows live by SCRUM-417) and `Demo_Devic__c.Current_Customer__c` (field type Lookup, Tester measured heading with no count, no /related/ link, no row). Second data point for the same rule: SCRUM-459 GAP A, `Followup_Obligation__c` Lookup to Opportunity, "Opportunity page has no related list". The symmetric Lookup DOES render on a CUSTOM object page (device page, Loan_Record__c.Loan_Devic__c, 2 rows). Working hypothesis: a custom Lookup relationship yields no related list on a standard object's record page; master-detail does.
  **Master-detail is not available for Current_Customer__c**: a detail record always has a master (the field can never be blank) and reparenting at every new lend conflicts with reparentableMasterDetail, while LoanReturnGuard must blank Current_Customer__c when a device is Available (AC6, asserted by SCRUM468LendDevicesTest). So AC5's "related list on the customer record page" has no implementable metadata shape here; the house-precedented surface for "this customer's list" is a List View reached from the record page (AC8 pattern: ListView + Setup picker button).
- Layout member names need the DASH form (`Layout:Demo_Devic__c-Demo Device Layout`), retrieve after deploy and commit the ORG version (drift gate): the org file differs from mine only in comments and `<layoutColumns/>` spacing.

# Round 4 (2026-11-22, rework per Architect round-3 + PO decision; ticket read back "In Bearbeitung", assignee developer-agent)

Branch feature/SCRUM-468-lend-devices-rework4 (from origin head 55f67df), worktree .../FirstSalesforceProject/scr468d-wt, PR #190.

## What to build (the two decisions, verbatim intent)
- AC7 (Architect): device history related list = EXACTLY 4 declared columns: Loan_Customer__c, Loan_Start_Datum__c, Loan_Due_Datum__c, Loan_History_Facts__c. Loan_History_Facts__c = real Text field (not formula) on Loan_Record__c: LoanRecordGuard writes "open / due dd.mm.yyyy" at lend, LoanReturnGuard rewrites "returned dd.mm.yyyy / n Tage" at return. FLS: explicit entries in SCRUM468_Loan (editable true) and SCRUM468_Read (editable false); SCRUM468_Writeoff stays marker-only.
- AC5 (PO chose (b), comment 23743): ListView on Loan_Record__c filtered to open loans + picker button; the Account-page related list is off the table -> remove my Demo_Devic__c.Current_Customer__c relatedList block from the Account layout.

## Answers already paid for (do not re-derive)
- Column census device list: 5 declared -> first 4 rendered + Action column; formula last = missing.
- Blocked paths for the duration value: Formula->Number validate reject 0AfWU00000dJibZ0AS ("Cannot update a field from a Formula to something else"); delete blocked by SCRUM468LendDevicesTest reference (0AfWU00000dJidB0AS); Apex write to formula = compile "Field is not writeable".
- Lookup related list: renders on CUSTOM object pages (2 rows), yields heading-with-0-rows on STANDARD (Account); SCRUM-459 GAP A second data point.
- PS assignment read-back (round 3): all three SCRUM468 sets assigned to devops-agent@cline.test AND meerwais.osmani@resourceful-bear-6f1u4j.com.

## House shapes (copy, do not invent)
- ListView: force-app/main/default/objects/Demo_Devic__c/listViews/SCRUM468_Overdue.listView-meta.xml -> <columns>bare custom apiName</columns>, <filterScope>Everything, <filters><field/><operation>equals</operation><value>1</value>. AC8 E2E url: /lightning/o/Demo_Devic__c/list?filterName=SCRUM468_Overdue.
- Text field shape: copy from the org (Loan_Status_Text__c exists in Test-Org; grep repo too). Do not handcraft the Field XML.
## Open TODOs for this round: (1) List Button metadata: grep the CLI's metadataRegistry.json for listButton BEFORE guessing the path; (2) list filter for open loans: use Loan_Status_Text__c equals open (values measured round 2) - house filter shape.
- Deploy: validate -l RunRelevantTests (timeout 560) then deploy start, same manifest; commit BEFORE each deploy; one manifest per unit.

## Round 4 measurements (landed while deploying)
- metadataRegistry.json (CLI SDR registry, grep "list"/"button"): kinds include listView/listViews but NO listButton kind at all (only liveChatButton/liveChatButtons). So a record-page List Button is NOT deployable through this toolchain; the AC5 surface ships as the ListView + the Setup picker route (as in AC8, reached by URL /lightning/o/<Obj>/list?filterName=<Name>).
- Loan_Status_Text__c does NOT exist on Loan_Record__c in Test-Org (validate rejected the ListView filter: "In field: filter.field - no CustomField named Loan_Record__c.Loan_Status_Text__c found"). My round-2 note claiming it existed was wrong; the org field list has Loan_Devic__c, Loan_Start_Datum__c, Loan_Due_Datum__c, Loan_Customer__c, Loan_Return_Datum__c, Loan_Duration_Days__c, Loan_Colleague__c, Loan_Available__c, Loan_Account_Md__c.
- Apex Date-minus-Date on this org's compiler: `Integer days = loan.Loan_Return_Datum__c - loan.Loan_Start_Datum__c;` -> "Date expressions must use Integer or Long (27:36)". Fix used: read the existing formula field Loan_Duration_Days__c (Number) instead of computing in Apex.
- ListView filter used: <field>Loan_Return_Datum__c</field><operation>blank</operation> (open = no return date).
