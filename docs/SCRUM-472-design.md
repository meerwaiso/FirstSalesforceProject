# SCRUM-472 — Company Size on Lead: Architektur-Design

Build spec for developer-agent. Author: architect-agent, 2026-11-23.
Surveyed against `origin/master` @ **31eeee5** (git fetch origin before survey).

## Goal

One hand-filled Picklist on the standard object `Lead` — four fixed employee ranges, blank allowed, no default — visible next to `Company`, Read+Edit via one Permission Set, zero logic, zero side effects.

## Data model (BEFORE implementation)

| Item | Value |
|---|---|
| Object | `Lead` (standard, Sales Cloud) — no new object |
| New field | `Company_Size__c` (API name; no umlauts, no collision: Lead tracks `Data_Quality__c, Duplicate_Of__c, Email_Norm__c, Interesting__c, Is_Due__c, Last_Attempt_Date__c, Likely_Duplicate__c` — none matches) |
| Type | `Picklist` |
| Label | `Company Size` |
| Blank | allowed (`<required>false</required>`, no `<defaultValue>`) |
| Values (API name → label) | `up_to_10` → `up to 10 employees` · `11_to_50` → `11 to 50 employees` · `51_to_250` → `51 to 250 employees` · `more_than_250` → `more than 250 employees` |
| Relationships / record types | none |
| Existing fields | untouched; **`Lead.NumberOfEmployees` (standard) is NOT repurposed or written** — see ⚠️-1 |

## Components (exact paths, all under `force-app/main/default/`)

1. **Field** — `objects/Lead/fields/Company_Size__c.field-meta.xml` (ONE file; there is no `.field` marker — a bare `.field` file breaks every deploy):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Company_Size__c</fullName>
    <description>Employee-size band of the company behind the Lead (SCRUM-472): hand-set by the colleague, blank = not known yet. Nothing computes it, nothing defaults it.</description>
    <externalId>false</externalId>
    <label>Company Size</label>
    <required>false</required>
    <trackTrending>false</trackTrending>
    <type>Picklist</type>
    <valueSet>
        <valueSetDefinition>
            <sorted>false</sorted>
            <value><fullName>up_to_10</fullName><default>false</default><label>up to 10 employees</label></value>
            <value><fullName>11_to_50</fullName><default>false</default><label>11 to 50 employees</label></value>
            <value><fullName>51_to_250</fullName><default>false</default><label>51 to 250 employees</label></value>
            <value><fullName>more_than_250</fullName><default>false</default><label>more than 250 employees</label></value>
        </valueSetDefinition>
    </valueSet>
</CustomField>
```

Shape copied verbatim from the live picklist `objects/Contact/fields/Preferred_Contact_Method__c.field-meta.xml` (SCRUM-470, deployed Prod as `0Afg500000H3X7JCAV`) — the only in-repo working Picklist. Note: `<valueSet>` (this house shape), NOT `<picklist>/<picklistValues>`.

2. **Layout insertion** — `layouts/Lead-Lead Layout.layout-meta.xml`, inside the FIRST `layoutSection` ("Lead Information"), immediately after the `Company` layoutItem (which is `behavior Required` on master):

```xml
<layoutItems>
    <behavior>Edit</behavior>
    <field>Company_Size__c</field>
</layoutItems>
```

`Edit` (not `Required`, not `Readonly`) → blank stays saveable, value stays hand-changeable. Branch file = master's file + this one block; do not overwrite the org file.

3. **Permission Set** — `permissionsets/SCRUM472_CompanySize.permissionset-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<PermissionSet xmlns="http://soap.sforce.com/2006/04/metadata">
    <description>SCRUM-472: Read + Edit on Lead.Company_Size__c for everyone who works with Leads. Clearing a band is Edit, never Delete. No object-level permissions, no profile edits.</description>
    <fieldPermissions>
        <editable>true</editable>
        <field>Lead.Company_Size__c</field>
        <readable>true</readable>
    </fieldPermissions>
    <hasActivationRequired>false</hasActivationRequired>
    <label>SCRUM472_CompanySize</label>
</PermissionSet>
```

No `<objectPermissions>` block: a PS must not grant broader object access (house shape, SCRUM467 probe comment) — and it must not add Delete rights.

4. **Assignment is deploy-time duty of the Developer** (mandatory, see Handoff-Checklist): `PermissionSetAssignment` for (a) the CLI target-org user, (b) the human test account, (c) every user already holding a Lead-granting PS: `SELECT Id,Assignee.Name,PermissionSet.Name FROM PermissionSetAssignment WHERE PermissionSet.Name IN ('SCRUM318_InterestingLead','SCRUM378_LeadNachfassung','SCRUM386_LeadDuplicate','SCRUM394_LeadDataQuality','SCRUM464_Fabrikant_List_Read')`. Read-back required: assignment list + one `Company_Size__c` read through a real session.

## ADR — why Picklist metadata, no Apex, no Flow

- **ADR-1 (declarative over Apex):** the requirement is one stored enum value, hand-typed, with four hard boundaries. Metadata's Picklist *is* the model; Apex/Flow would model nothing. The Apex-over-Flow rule is respected — neither is used, so there is nothing to justify Flow for.
- **ADR-2 (Picklist, not Text/Multiselect):** "exactly four fixed ranges" + invalid entry rejected + groupable for sort/filter = restricted Picklist, platform-enforced (AC "not one of the four → rejected" and "group by the exact range" both hold).
- **ADR-3 (PS, not Profile):** house rule — FLS is never inherited and never touched at Profile level; PSs can grant, not revoke, and this ticket only grants a NEW field, so one additive PS suffices:

```xml
<fieldPermissions><editable>true</editable><field>Lead.Company_Size__c</field><readable>true</readable></fieldPermissions>
```

- **ADR-4 (zero side effects):** no trigger, no Flow, no Validation Rule, no formula, no default. A Picklist is inert on save, so the AC "no email, no task, no re-assignment, no extra record" holds structurally — and is verified by the negative test, not asserted by prose.
- **Governor limits:** none. No code, no SOQL.

## ⚠️ Befund (measured)

1. **`Lead.NumberOfEmployees` exists** — the PO's "no size/employee field" is imprecise. Verified with
   `python3: [f['name'] for f in json.load(open('.sfdx/tools/soqlMetadata/standardObjects/Lead.json'))['fields'] if 'employee' in f['name'].lower() or 'size' in f['name'].lower() or 'compan' in f['name'].lower()` → `['Company','NumberOfEmployees','CompanyDunsNumber','DandbCompanyId']`.
   Design choice: the band field stays SEPARATE (`Company_Size__c`) — PO says no existing field is changed. Consequence for Tester: never compare or cross-fill the two.
2. **Org holds four layout variants per standard object, the repo tracks the default only** (SCRUM-468/469, not re-verified). The branch layout file must be master's file + the one `layoutItems` block, never a retrieved org file (retrieved Test-Org files redden the Prod Drift Gate).
3. **Existing Lead list views / Sales reports are out of scope** (PO decision). `objects/Lead/listViews/Nachfassliste.listView-meta.xml` and the Sales reports get no new column. House column token for a custom field is the full `Lead.X__c` (measured on that file: `<columns>Lead.Last_Attempt_Date__c</columns>`) — if the user wants the column, that token shape is already proven.
4. **No `.field` marker file.** A bare `<ApiName>.field` (metadata format inside a source-format dir) breaks EVERY deploy from this repo; `git log --all --name-only -- '*.field'` = zero hits (skill reference).

## Open points (non-blocking)

- [ ] PO's "extend *every* Permission Set that grants Lead access" vs. **one** dedicated PS assigned to that same user set → decision: dedicated `SCRUM472_CompanySize` + assignment (item 4). Churn/impact avoided: 5 PSs would otherwise be redeployed AND reassigned. Developer: if he disagrees, the acceptance test is identical; do NOT edit Permission Profiles.
- [ ] Lightning visibility on the record detail page = FLS grant (repo artefact) + App Builder placement (Org step, @devops-agent). If the default Lead detail page renders the source layout, no org step is needed.
- [ ] Sort/filter AC: needs a visible column somewhere. Out of scope per PO → Tester verifies the Picklist values as distinct groups via report/list view ONLY after the user opts in; otherwise report as not exercisable.
