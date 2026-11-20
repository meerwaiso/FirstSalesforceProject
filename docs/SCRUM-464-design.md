# SCRUM-464 — Design & Build-Spec: Drittparty-Produkt => Fabrikant from a controlled list

Story: SCRUM-464 · Branch: `feature/SCRUM-464-thirdparty-fabrikante` (cut from `origin/master` @ `3eb2ac1`, already carries this file) · Survey: `git fetch origin` + `git show origin/master:...` on 2026-11-20, live org read via `sf ... --target-org Test-Org`.

## Ziel

A closed Case whose problem was caused by a third-party product names the manufacturer from
a company list that only service team leads may extend, optionally carries ONE repair-cost
figure, and the service director sees a monthly overview per manufacturer (case count, total
and average known cost) — nothing automatic, historical cases untouched.

## 1. Verified facts (measured, not assumed)

| # | Fact | How verified |
|---|---|---|
| F1 | The cause concept EXISTS on Case: `Ursache__c`, type Picklist, `groupable/filterable/aggregatable`, `restrictedPicklist=false` | `sf sobject describe --sobject Case --target-org Test-Org` |
| F2 | Deployed `Ursache__c` has exactly 5 values: `HowToAnfrage`, `RechnungAbrechnung`, `TechnischerFehler`, `Fehlkonfiguration`, `KeinFehlerKeineMassnahme` | same describe (`picklistValues`), 5/5 |
| F3 | Source of that field + an ACTIVE rule `Ursache_PflichtBeiGeschlossen` (`AND(OR(IsClosed, ISPICKVAL(Status,'Closed')), ISBLANK(TEXT(Ursache__c)))`) | `git show origin/master:force-app/main/default/objects/Case/fields/Ursache__c.field-meta.xml` + `git show origin/master:force-app/main/default/objects/Case/validationRules/Ursache_PflichtBeiGeschlossen.validationRule-meta.xml` |
| F4 | House pattern for "controlled list + team-lead-only extension + director overview" already shipped in SCRUM-461/462: object `Competitor__c`, Lookup `Opportunity.Competitor_Lost_To__c`, Currency `Competitor_Price__c`, denominator formula `Competitor_Price_Known__c`, rule `Competitor_PflichtBeiWettbewerber` (with `errorDisplayField`), guard `CompetitorNameGuard`, PS pair `_List_Read`/`_List_Teamleitung`, report pair `...` + `..._Meine` (scope organization / user) | `git ls-tree -r origin/master` + those files |
| F5 | **No collision**: Test-Org has no manufacturer object; custom objects matching fabrik/manuf/producent = none (only `Competitor__c`, `OpportunityCompetitor`); Case (82 fields) has none matching `drittp`, `fabrik`, `fixkosten`, `last_12` | `sf sobject list` + `sf sobject describe` |
| F6 | Case record page is the legacy layout `layouts/Case-Case Layout.layout-meta.xml` (blob `5394823d913cb3de0f146d93bebeeb6cdce37c02`); it already carries a custom section `Rückschau` with `Ursache__c`, and a final `System Information` section | `git show origin/master:...layout-meta.xml` |
| F7 | `PermissionSetFieldPermissions` = `{ editable, field, readable? }` only — **there is no separate "clear/delete value" capability in FLS** | `@salesforce/types/lib/metadata.d.ts` (`/usr/lib/node_modules/@salesforce/cli/node_modules/@salesforce/types/lib/metadata.d.ts` line 10262) |
| F8 | `ReportGrouping` = `{ aggregateType?, dateGranularity?, field, sortByName?, sortOrder, sortType? }` — exactly ONE sort key → a secondary tie-break sort is NOT expressible in report XML | same file line 11286 |
| F9 | `UserDateInterval` has **no rolling last-12-months value** (…`INTERVAL_LAST90`, `INTERVAL_LAST120`, `INTERVAL_PREVY`, `INTERVAL_CUSTOM`…) → the window must be a formula-gate field + `INTERVAL_CUSTOM` (house SCRUM-461 F8/F9, `Lost_Last_12M__c`) | same file line 586 |
| F10 | House trigger `apiVersion` 62.0 / Apex cls 67.0; house PS assignment pair = `devops-agent@cline.test` + human test account `meerwais.osmani@resourceful-bear-6f1u4j.com` (2/2 `PermissionSetAssignment` rows for SCRUM434_Ursache, SCRUM428_ServiceTeam, SCRUM461_*_List_*) | `sf data query --use-tooling-api … PermissionSetAssignment` |

**Test-Org baseline, measured 2026-11-20 (carry into design note + coverage table):**
Cases total **675** · closed **46** · closed with any `Ursache__c` **4** · third-party cases **0** (the value does not exist yet) · manufacturer records **0** (object not created) · records with a repair cost **0**.

⚠️ **AC2, AC5, AC7, AC8 match ZERO records today.** Per the PO's counting rule they are *untested* until the Tester creates third-party closed cases (with and without a cost), counts them and states the numbers.

## 2. Components (exact paths, Developer builds these)

### C1 — Controlled manufacturer list = custom object `Fabrikant__c`
`force-app/main/default/objects/Fabrikant__c/Fabrikant__c.object-meta.xml`
Shape copied from `Competitor__c` (F4): one record per company, the **Name IS the company name** (Text).
```xml
<fullName>Fabrikant__c</fullName>
<label>Fabrikant</label> <pluralLabel>Fabrikanten</pluralLabel>
<nameField><label>Fabrikant Name</label><type>Text</type></nameField>
<deploymentStatus>Deployed</deploymentStatus>
<sharingModel>ReadWrite</sharingModel> <externalSharingModel>Private</externalSharingModel>
<visibility>Public</visibility>
<enableSearch>true</enableSearch> <enableSharing>true</enableSharing> <enableStreamingApi>true</enableStreamingApi>
<enableFeeds>false</enableFeeds> <enableHistory>false</enableHistory> <enableReports>false</enableReports>
<enableActivities>false</enableActivities> <allowInChatterGroups>false</allowInChatterGroups>
```
No `Wert`-fields needed. Expected size: tens of records.

### C2 — Lookup on Case: `Case.Drittparty_Fabrikant__c`
`force-app/main/default/objects/Case/fields/Drittparty_Fabrikant__c.field-meta.xml`
```xml
<fullName>Drittparty_Fabrikant__c</fullName>
<label>Fabrikant (Drittparty-Produkt)</label>
<type>Lookup</type> <required>false</required>
<referenceTo>Fabrikant__c</referenceTo>
<relationshipLabel>Faelle</relationshipLabel>
<relationshipName>Cases_Drittparty_Fabrikant</relationshipName>
<trackFeedHistory>false</trackFeedHistory> <trackHistory>false</trackHistory>
```
The picker can only offer existing `Fabrikant__c` records → free text impossible (AC5). The relationship makes the cases of one manufacturer visible on the Fabrikant record for the service meeting; it must NOT be added to any Account/Contact related list (AC12).

### C3 — One cost figure: `Case.Drittparty_Fixkosten__c`
Currency (org default currency, no per-record currency — PO decision), blank when unknown:
```xml
<fullName>Drittparty_Fixkosten__c</fullName>
<label>Fixkosten (Teile + Spesen + Zusathre)</label>
<type>Currency</type> <precision>18</precision> <scale>2</scale> <required>false</required>
<trackFeedHistory>false</trackFeedHistory> <trackHistory>false</trackHistory>
```

### C4 — Average denominator: `Case.Drittparty_Fixkosten_Known__c` (system, read-only)
```xml
<fullName>Drittparty_Fixkosten_Known__c</fullName>
<type>Number</type> <precision>18</precision> <scale>0</scale> <unique>false</unique>
<formula>IF(ISBLANK(Drittparty_Fixkosten__c), 0, 1)</formula>
<formulaTreatBlanksAs>BlankAsZero</formulaTreatBlanksAs>
```
House shape `Competitor_Price_Known__c` (AC7: unknown cost counts in the count, not in total/average).

### C5 — Rolling window gate: `Case.Closed_Last_12M__c` (system, read-only)
```xml
<fullName>Closed_Last_12M__c</fullName>
<type>Checkbox</type>
<formula>AND(IsClosed, NOT(ISBLANK(ClosedDate)), ClosedDate >= ADDMONTHS(TODAY(), -12))</formula>
<formulaTreatBlanksAs>BlankAsZero</formulaTreatBlanksAs>
```
House shape `Lost_Last_12M__c` (F9: no rolling interval in the metadata enum). Window anchored on `ClosedDate`; cases without one are outside and never retro-fixed (PO decision).

### C6 — Cause value (adds ONE value, never a competing field)
Edit `force-app/main/default/objects/Case/fields/Ursache__c.field-meta.xml`: keep the 5 existing `<value>` entries verbatim, append
```xml
<value><fullName>DrittpartyProdukt</fullName><default>false</default><label>Drittparty / Fremdfabrik Produkt</label></value>
```
Do not touch `Ursache_PflichtBeiGeschlosed`… it stays active and unchanged (AC3/AC4). Deploy of the whole value set keeps existing values (F1 `restrictedPicklist=false`).

### C7 — ValidationRule `Fabrikant_PflichtBeiDrittpartyClosed` (AC2)
`force-app/main/default/objects/Case/validationRules/Fabrikant_PflichtBeiDrittpartyClosed.validationRule-meta.xml`
```xml
<active>true</active>
<errorConditionFormula>AND(OR(IsClosed, ISPICKVAL(Status, 'Closed')), ISPICKVAL(Ursache__c, 'DrittpartyProdukt'), ISBLANK(Drittparty_Fabrikant__c))</errorConditionFormula>
<errorDisplayField>Drittparty_Fabrikant__c</errorDisplayField>
<errorMessage>Was farab ein Fabrikant? Ist die Fall caused by a third-party product, pick the manufacturer from the list - the case cannot be closed without.</errorMessage>
```
Fires only on records being saved → historical closed cases stay saveable (AC10). Shape = `Competitor_PflichtBeiWettbewerber` (incl. `errorDisplayField`).

### C8 — ValidationRules `Fabrikant_NurBeiDrittparty` + `Fixkosten_NurBeiDrittparty` (AC4)
```xml
<fullName>Fabrikant_NurBeiDrittparty</fullName>
<errorConditionFormula>AND(NOT(ISBLANK(Drittparty_Fabrikant__c)), NOT(ISPICKVAL(Ursache__c, 'DrittpartyProdukt')))</errorConditionFormula>
<errorDisplayField>Drittparty_Fabrikant__c</errorDisplayField>
```
```xml
<fullName>Fixkosten_NurBeiDrittparty</fullName>
<errorConditionFormula>AND(NOT(ISBLANK(Drittparty_Fixkosten__c)), NOT(ISPICKVAL(Ursache__c, 'DrittpartyProdukt')))</errorConditionFormula>
<errorDisplayField>Drittparty_Fixkosten__c</errorDisplayField>
```
PO decision realised as **refuse-a-value**, not auto-clear: no record is ever rewritten behind the user's back, no automatic write of any kind (AC11). No rule requires a cost (AC7 optional).

### C9 — Permission Sets (three, house pair shape)
1. `permissionsets/SCRUM464_Drittparty_Team.permissionset-meta.xml` — FLS on the 4 new Case fields; **no object CRUD** (house 421/428 shape):
   `Drittparty_Fabrikant__c` editable/readable=true · `Drittparty_Fixkosten__c` editable/readable=true · `Drittparty_Fixkosten_Known__c` editable=false/readable=true · `Closed_Last_12M__c` editable=false/readable=true
2. `permissionsets/SCRUM464_Fabrikant_List_Read.permissionset-meta.xml` — `objectPermissions` on `Fabrikant__c`: allowRead=true, create/edit/delete=false, viewAllRecords=false, modifyAllRecords=false (house `SCRUM461_Competitor_List_Read`). Needed so a plain service agent can open the picker (AC6 second half).
3. `permissionsets/SCRUM464_Fabrikant_List_Lead.permissionset-meta.xml` — same object, allowCreate/allowEdit/allowDelete/allowRead=true (house `SCRUM461_Competitor_List_Teamleitung`). **Only team leads get this one** (AC6 first half, PO CRUD row "list entry: create/edit/delete only team leads").

`Case.Ursache__c` needs NO new FLS entry: SCRUM434_Ursache already grants read+edit and must not be edited by this ticket (its 2/2 assignments verified in F10).

### C10 — Case record page: new layout section
`layouts/Case-Case Layout.layout-meta.xml` — insert a NEW custom section (house rule: own section so parallel tickets never collide) directly **before** `System Information`, after the existing `Rückschau`/`SLA` sections:
```xml
<layoutSections>
  <customLabel>true</customLabel><detailHeading>true</detailHeading><editHeading>true</editHeading>
  <label>Drittparty Factory</label>
  <layoutColumns>
    <layoutItems><behavior>Edit</behavior><field>Drittparty_Fabrikant__c</field></layoutItems>
    <layoutItems><behavior>Edit</behavior><field>Drittparty_Fixkosten__c</field></layoutItems>
  </layoutColumns>
  <style>OneColumn</style>
</layoutSections>
```
Nothing is added to any portal/customer surface (AC12).

### C11/C12 — Overview reports (Service folder), house pair from SCRUM-461
`reports/Service/Faelle_Drittparty_Fabrikante.report-meta.xml` (`<scope>organization</scope>` — director + team leads, AC8)
`reports/Service/Faelle_Drittparty_Fabrikante_Meine.report-meta.xml` (`<scope>user</scope>` — agent sees only own cases, AC9)
```xml
<reportType>Case</reportType>
<format>Summary</format>
<groupingsDown>
  <field>Case.Drittparty_Fabrikant__c</field>
  <aggregateType>RowCount</aggregateType>
  <sortByName>RowCount</sortByName><sortOrder>Desc</sortOrder><sortType>Aggregate</sortType>
</groupingsDown>
<columns><aggregateTypes>Sum</aggregateTypes><field>Case.Drittparty_Fixkosten__c</field></columns>
<aggregates>
  <calculatedFormula>IF(Case.Drittparty_Fixkosten_Known__c:SUM = 0, NULL, Case.Drittparty_Fixkosten__c:SUM / Case.Drittparty_Fixkosten_Known__c:SUM)</calculatedFormula>
  <datatype>currency</datatype><developerName>FORMULA1</developerName>
  <downGroupingContext>Case.Drittparty_Fabrikant__c</downGroupingContext>
  <isActive>true</isActive><isCrossBlock>false</isCrossBlock>
  <masterLabel>Durchschnitt Fixkosten (known)</masterLabel><scale>2</scale>
</aggregates>
<filter>  CLOSED = 1 · Case.Ursache__c = DrittpartyProdukt · Case.Closed_Last_12M__c = 1 </filter>
<timeFrameFilter><dateColumn>CLOSED_DATE</dateColumn><interval>INTERVAL_CUSTOM</interval>
  <startDate>2000-01-01</startDate><endDate>2099-12-31</endDate></timeFrameFilter>
<showSubTotals>false</showSubTotals> <showGrandTotal>true</showGrandTotal> <showDetails>false</showDetails>
```
Sort = most cases first (AC8). Unknown cost is NULL in the average, never 0 (AC7). Total = Sum of the Currency column (blank adds nothing).
Filter value = the picklist **fullName** `DrittpartyProdukt` (house SCRUM-461 filtered `Opportunity.Loss_Reason__c` with the fullName, not the label).

### C13 — Duplicate guard on the list (reuse, do not redesign)
`classes/FabrikantNameGuard.cls` + `triggers/FabrikantNameGuard.trigger` (`before insert, before update` on `Fabrikant__c`) — copy of `CompetitorNameGuard`: one SOQL per batch (`WHERE Name IN :names`, case-insensitive → "SIEMENS" == "Siemens" is one company), refuse via the house `System.AssertEquals(false, true, '<name> already on the list')` idiom (an `AuraHandledException` is runtime-restricted and unusable in a trigger — comment in the house class). Nothing else fires here: no email, no task, no feed, no alert (AC11).

## 3. ADR — decisions and why

1. **Apex+declarative, no Flow.** Only metadata (fields, rules, PS, report, layout) plus one before-insert/update guard. A Flow could not express "team-lead-only extension of a value list" nor a per-record cross-field rule with a named field in the message; flows have repeatedly broken deployment here. Everything automatic-free stays free: the only Apex fires on `Fabrikant__c` save and only throws.
2. **List = custom object + Lookup (not a Picklist).** A Case picklist for the manufacturer cannot be extended by a user at runtime — picklist values are Setup metadata, writable by anyone with Setup rights, not role-restricted. The Lookup picker offers only existing records, so free text is impossible and the "Siemens / Siemens AG / SIEMENS" drift is closed by C13. This is exactly SCRUM-461's shipped shape (F4).
3. **Manufacturer value added to the existing `Ursache__c`, no competing cause field** (F1–F3). One value `DrittpartyProdukt` appended, 5 existing untouched.
4. **One cost figure = Currency 18/2 + a 0/1 formula denominator** (PO decision), not three numbers, no per-record currency. The average is the report aggregate `SUM(cost)/SUM(known)`, NULL when nothing known — average is not expressible as a rollup (`summaryOperation` = count/sum/min/max only; house finding SCRUM-461 F11).
5. **12-month window = formula gate + `INTERVAL_CUSTOM`** (F9: no rolling interval exists). ⚠️ Caveat measured in the metadata semantics: formula fields are recalculated on save, so a gate that became TRUE stays TRUE until the record is saved again → the window can over-include cases just past the boundary (it never under-includes). Closed cases in Test-Org = 46 today, so the boundary error is bounded; if the PO wants an exact rolling boundary, the house escalation is a nightly `...Rebuilder`/`...Scheduler` pair (SCRUM-388/436/442 shape) — that writes records, which the PO's "old cases stay as they are" argues against. **Default = formula gate, PO veto requested.**
6. **"Own cases" vs "all cases" = ownership + report `scope`, not sharing** (house SCRUM-394/461): Case OWD, sharing rules and case owners are **unchanged**; no ADR needed for the sharing model. `scope` is source-persistable; report-level "who may open" is an Org step (C11/C12 note).
7. **Refuse, never auto-clear/auto-fill** (PO decision): the two `..._NurBeiDrittparty` rules refuse a manufacturer/cost on a non-third-party case; nothing is ever written by the system. Historical records are untouched because all rules fire only on records being saved (AC10).
8. ⚠️ **FLS cannot separate "set" from "clear"** (F7: `fieldPermissions` = `editable`/`readable` only). So the PO CRUD column "delete/clear: team leads only" is **not expressible** on the Case fields: a service agent who may edit the field may also blank it. What IS expressible — and is enforced — is the list-entry level: create/edit/delete of `Fabrikant__c` records only via `SCRUM464_Fabrikant_List_Lead`. This is the same reading the house shipped in SCRUM-461 ("only team leads may add or clear a competitor" = the list object). PO veto requested if he wants a Case-level protection: that would need a runtime "does this user hold PS X" check in Apex, and **no such pattern exists in this repo** (all role logic lives in Permission Sets; the repo's Apex never inspects permissions) — I verified by `git grep`, so the escalation is new code, not a reuse.
9. ⚠️ **Tie-break "equal case count → higher total cost first" is not expressible** in report XML (F8: one `sortByName` only). Default: sort by case count Desc, ties in report order. If the ordering inside ties must be exact, the overview has to become an Apex artefact (out of house scope, and against "look at it once a month" simplicity). PO veto requested.

## 4. Data model, sharing, governor limits

**Data model:** +1 object (`Fabrikant__c`, tens of records), +4 fields on Case (1 Lookup, 1 Currency, 2 formula), +1 Lookup relationship (`relationshipName Cases_Drittparty_Fabrikant`), +1 `Ursache__c` picklist value, +3 validation rules, +3 PSs, +2 reports, +1 layout section, +1 guard class + trigger.

**Sharing model:** untouched — Case OWD/sharing rules/owners unchanged; ownership gives the "own cases" semantics; `Fabrikant__c` uses `sharingModel ReadWrite` + `externalSharingModel Private` with the PS bounds of C9 on top (house Competitor__c).

**Governor limits:** validation rules and formula fields are per-record formulas, no SOQL → bulk-safe, no 10k-record problem. C13 guard: one SOQL per batch, never per record (house). Reports: no Apex. No SOQL in loops. `System.runAs` is required in the FLS test class (fls-gate.py reddens a test class touching new fields without it), never in production code.

**Data classification:** manufacturer + cost are internal-only; they exist solely in `SCRUM464_*` PSs and the Service report folder. Org step (DevOps): read back that no portal/Experience Cloud/related list on Account/Contact exposes them, and that no customer-facing layout references them (AC12).

## 5. Technical acceptance criteria (on top of the PO's AC1–AC13)

| ID | Criterion | Artefact |
|---|---|---|
| TAC1 | Closed Case with `Ursache__c = DrittpartyProdukt` and empty `Drittparty_Fabrikant__c` → `ValidationError` whose message names the manufacturer and whose error field is `Drittparty_Fabrikant__c` | Apex test |
| TAC2 | Closed Case with `Ursache__c = Fehlkonfiguration` and no manufacturer saves clean | Apex test |
| TAC3 | A non-third-party save that fills `Drittparty_Fabrikant__c` / `Drittparty_Fixkosten__c` is refused | Apex test |
| TAC4 | Third-party case closed with manufacturer and **no** cost saves; `Drittparty_Fixkosten_Known__c` reads 0 (not 1) | Apex test |
| TAC5 | `Drittparty_Fixkosten_Known__c` = 1 when the cost is filled | Apex test |
| TAC6 | `Closed_Last_12M__c` FALSE for `ClosedDate` older than 12 months, TRUE inside, FALSE when `ClosedDate` blank | Apex test |
| TAC7 | A user holding `SCRUM464_Fabrikant_List_Read` cannot create a `Fabrikant__c` record; a user holding `..._Lead` can, and the new record is immediately pickable by a user holding only `_Read` | Apex test + E2E |
| TAC8 | A user holding none of the PSs cannot read or edit `Drittparty_Fabrikant__c` / `Drittparty_Fixkosten__c` (negative probe, `WITH USER_MODE`) | Apex test |
| TAC9 | Adding the 6th picklist value leaves the 5 existing values and the still-active `Ursache_PflichtBeiGeschlossen` unchanged | deploy read-back (`sf sobject describe` 6/6 values) |
| TAC10 | A second `Fabrikant__c` record whose Name equals an existing one (different case, e.g. `SIEMENS` vs `Siemens`) is refused; the overview shows the company once | Apex test + E2E |
| TAC11 | A historical closed case (no new data) opens, lists and re-saves unchanged | E2E |
| TAC12 | Report row count = number of manufacturers with ≥1 qualifying closed case; top row = highest count | E2E |
| TAC13 | The `_Meine` report of an agent counts fewer cases than the org-wide report (the difference belongs to other owners) | E2E |
| TAC14 | No `EmailMessage`/`Task`/`FeedItem`/`ApexPush` artefact exists for this ticket | CI grep + Apex test (no side effects) |

## 6. Test coverage the PR must carry (PR gate, not a bonus)

- `classes/SCRUM464DrittpartyTest.cls` — TAC1–TAC6, TAC10 (behaviour, bulk-safe inserts).
- `classes/SCRUM464DrittpartyFlsTest.cls` — TAC7, TAC8, `System.runAs` mandatory, PSs created in-test + `PermissionSetAssignment` inserted (house shape SCRUM378/386/461).
- `tests/e2e/SCRUM-464-drittparty-fabrikante-ueberseeit.spec.ts` — AC8/AC9/AC5/AC10 in the UI; frontdoor.jsp exchange in globalSetup + shared storageState, **no** login page, **no** sid cookie, **no** `networkidle` on Lightning; assert the header's "Select N items" count, never rendered row count (house SCRUM-449).
- Test data must be CREATED and counted (baseline: 0 third-party cases, F §Counts). Coverage table carries: closed cases, third-party cases, those with manufacturer, those with cost. A row whose Observed = 0 is not a PASS.

## 7. Org steps (DevOps owns, not CI gates)

| Step | Where | Read-back |
|---|---|---|
| Assign `SCRUM464_Drittparty_Team` + `SCRUM464_Fabrikant_List_Read` to the service agents, team leads, the director, the CLI user and the human test account; `SCRUM464_Fabrikant_List_Lead` to team leads ONLY | Setup → Permission Sets | `sf data query --use-tooling-api -q "SELECT Assignee.Username FROM PermissionSetAssignment WHERE PermissionSet.Name='<ps>'"` per PS + one field read through a real session (`WITH USER_MODE`) |
| Report-level sharing of `Faelle_Drittparty_Fabrikante`: director + team leads may open; `_Meine` for agents | Report → Settings (never source) | API read / screenshot |
| Place the org-wide report where the director opens it (Service meeting) | App Builder / tab | — |
| Confirm no customer-facing surface shows the two fields | Portal / Experience Cloud / related lists | read-back |

## 8. Open points (do not block the implementation)

- [ ] ADR-8 and ADR-9 (clear-rights at field level, tie-break sort) — PO veto requested, defaults documented above. Owner: @po-agent
- [ ] Report tokens (`CLOSED_DATE` as `dateColumn`, `Case.Ursache__c`/`Case.Closed_Last_12M__c` as filter columns, `Case.Drittparty_Fixkosten__c` as a Sum column, reportType `Case` vs `CaseList`) are deploy-validate-verified, never assumed (house SCRUM-432/434/418): run `sf project deploy validate --source-dir force-app --test-level NoTestRun`-free equivalent is NOT available — validate with the CI smoke job. If the aggregate on reportType `Case` is rejected, fall back to `CaseList` and say so in the handoff. Owner: @developer-agent
- [ ] Lightning/FlexiPage record pages are not in the repo (house finding): visibility on the modern UI = FLS grant (repo) + placement (Org step). Owner: @devops-agent
- [ ] Exact test-data counts for AC2/AC5/AC7/AC8 (zero today). Owner: @tester-agent
