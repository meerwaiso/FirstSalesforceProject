# SCRUM-381 — Verlustgrund bei Opportunities · Authoritative Build-Spec

> **This file is the source of truth for the exact XML and API names.**
> The Jira comments (SCRUM-381) are mangled by Jira's markdown converter
> (double underscores → bold, closing XML tags dropped — verified on this
> project 2026-08-30/31 and re-confirmed 2026-09-01). Build the files from
> THIS doc, cross-check against the in-repo reference files named below.
> Do not copy names out of the Jira comment.

## Goal
Beim Setzen des Stands auf „Closed Lost" wird ein Verlustgrund aus einer
feste Picklist (`Loss_Reason__c`) erzwungen (Validierungsregel); bei Reopen
oder „Closed Won" leert sich das Feld automatisch (Apex, im bestehenden
Opportunity-Trigger). Sichtbar im Stage-Abschnitt des Opportunity-Layouts,
Read+Edit nur für Vertrieb über Permission Set (FLS, nie Profile).

## Branch
`feature/SCRUM-381-lost-reason` von `master` frisch abziehen.
Hinweis: Auf dem geteilten Tree liegen SCRUM-378/380-Artefakte
(`.gitignore` modifiziert, `scr378-report-final.zip` untracked) — weder
commiten noch löschen, nur explizit eigene Pfade stageen.

## Stage-Werte in Test-Org (live verifiziert, 2026-09-01)
`sf api request rest /services/data/v67.0/sobjects/Opportunity/describe -o Test-Org`
liefert exakt 10 Picklist-Werte (keine deutschen Labels):
`Prospecting, Qualification, Needs Analysis, Value Proposition,
Id. Decision Makers, Perception Analysis, Proposal/Price Quote,
Negotiation/Review, Closed Won, Closed Lost`.
→ Alle Formeln und Apex-Code referenzieren **`'Closed Lost'`** und
**`'Closed Won'`** exakt so. Bestätigt zusätzlich durch
`OpportunityOverdueService.cls` (SCRUM-319), die dieselben Werte produktiv nutzt.

## ADR

### ADR-1: Pflicht bei Closed Lost → Validierungsregel (kein Layout-Required)
Layout-`Required` blockiert nur das UI-Field; API-, Flow- und Bulk-API-
Speichern umgehen es. Validierungsregeln greifen auf **jedem** Schreibpfad
(UI, API, Flow, Bulk). Formel im Function-Fundament (`AND(...)`), nie infix
`a AND b` — Syntax error in Salesforce Formulas.

### ADR-2: Auto-Clear (AC4/AC5) → Apex, im BESTEHENDEN Opportunity-Trigger
- **Kein Flow** — Schema-Drift / apiVersion-Problematik, wiederholt
  dokumentiert.
- **Kein zweiter Trigger-File**: Auf Opportunity existiert bereits
  `OpportunityOverdueReset.trigger` (SCRUM-319, `before update`) mit
  Handler-Pattern. Wir erweitern **denselben Trigger** um einen zweiten
  Handler-Callout — etabliertes Muster, ein Trigger pro Objekt.
- **Simple null-clear, kein Shadow-Field / kein Space-Trick**: Validierung
  wird in Salesforce auf den **Endstand des Records** in der Transaktion
  ausgewertet — also NACH dem Before-Update-Trigger. Beim Clearing ändert
  der Trigger die Stage weg von `'Closed Lost'`, daher ist das Gate
  `StageName = 'Closed Lost'` der ValRule im selben Moment schon `FALSE`;
  ein gleichzeitiges Setzen auf `null` kann die Regel nicht triggern.
  Der einzig blockiercase ist der gewollte: Stage bleibt `'Closed Lost'`
  und das Feld wird leer → Blockieren mit deutschem Hinweis.

| Option | Pros | Cons | Decision |
|---|---|---|---|
| Layout Required | trivial | umgeht API/Flow/Bulk | ❌ |
| **Validation Rule** | greift auf jedem Pfad, keine Extra-Dateien | eine Formel | ✅ |
| Flow (Field Update) | — | Schema-Drift, apiVersion, Timing | ❌ |
| Apex + Shadow-Field + Space-Konvention | — | Over-Engineering, Extra-Feld, falsche Voraussetzung | ❌ (verworfen) |

### ADR-3: FLS → Permission Set (kein Profil, nie Objektfeld)
Neues Feld `Loss_Reason__c`: Standard-FLS = Default (kein Zugriff).
Das Permission Set `SCRUM381_LeadFollowUp` gibt Read+Edit. Wer das PS
aktiviert, hat Zugriff; wer Opportunities nicht bearbeitet, bleibt draußen
(AC7 wird über das Fehlbilden des PS erfüllt — die Rolle selbst hat
bereits kein Opportunity-CRUD).

### ADR-4: Picklist-Feld-Deploy in 2 Phasen
Haus-Standard (siehe `scrum378-phase1-fields.xml` /
`scrum378-phase2-referencing.xml`): Phase 1 = nur Felddefinitionen,
Phase 2 = alles, was das Feld referenziert (ValRule, Layout, Permission
Set, Trigger, Apex). Grund: Referenz-Deploy auf nicht-existierendes Feld
→ Schema-Fehler beim ersten Versuch.

## Governor Limits
1 Before-Update-Handler, **0 SOQL**, keine Cross-Object-Referenz, 1
Feld-Zuweisung pro geänderter Record (bulk-safe, Loop über `new`/`oldMap`).
Rekursion: `StageName` wird vom neuen Handler nie geändert → die
Clear-Logik feuert höchstens 1× pro Record pro Transaktion. Das vorhandene
`hasFired`-Flag des SCRUM-319-Handlers bleibt unberührt; der neue Handler
hat sein eigenes.

## Dateien — exakte Pfade & XML

In-repo Reference files (deployen sie heute, kopiere die Shapes):
- `force-app/main/default/objects/Contact/fields/Open_Cases_Rating__c.field-meta.xml` (Picklist-Shape)
- `force-app/main/default/objects/Opportunity/fields/Is_Overdue__c.field-meta.xml` (Feed-History-Attribut)
- `force-app/main/default/objects/Contact/validationRules/NewsletterConsent_DatumKeineZukunft.validationRule-meta.xml` (ValRule-Shape, `AND(...)`-Form)
- `force-app/main/default/permissionsets/SCRUM319_OverdueOpportunity.permissionset-meta.xml` (Permission-Set-Shape)
- `force-app/main/default/triggers/OpportunityOverdueReset.trigger` + `OpportunityOverdueResetHandler.cls` (Trigger-Shape)
- `force-app/main/default/layouts/Opportunity-Opportunity Layout.layout-meta.xml` (Layout — Stage-Section, linker `layoutColumns`)

### 1 (NEU). `force-app/main/default/objects/Opportunity/fields/Loss_Reason__c.field-meta.xml`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Loss_Reason__c</fullName>
    <description>Grund, warum die Chance verloren ging (SCRUM-381). Nur relevant wenn Stage = Closed Lost (ValRule erzwingt). Wird automatisch geleert wenn die Chance wieder geoffnet oder als gewonnen markiert wird (OpportunityLossReasonClearHandler). Kein PII.</description>
    <label>Verlustgrund</label>
    <required>false</required>
    <trackFeedHistory>false</trackFeedHistory>
    <type>Picklist</type>
    <valueSet>
        <valueSetDefinition>
            <sorted>false</sorted>
            <value>
                <fullName>ZuTeuer</fullName>
                <default>false</default>
                <label>Zu teuer</label>
            </value>
            <value>
                <fullName>Wettbewerber</fullName>
                <default>false</default>
                <label>An einen Wettbewerber verloren</label>
            </value>
            <value>
                <fullName>KeinBudget</fullName>
                <default>false</default>
                <label>Kein Budget</label>
            </value>
            <value>
                <fullName>ZeitpunktNichtPasst</fullName>
                <default>false</default>
                <label>Zeitpunkt passte nicht</label>
            </value>
            <value>
                <fullName>KeinBedarfMehr</fullName>
                <default>false</default>
                <label>Kein Bedarf mehr</label>
            </value>
            <value>
                <fullName>KontaktAbgebrochen</fullName>
                <default>false</default>
                <label>Kontakt abgebrochen</label>
            </value>
            <value>
                <fullName>Sonstiges</fullName>
                <default>false</default>
                <label>Sonstiges</label>
            </value>
        </valueSetDefinition>
    </valueSet>
</CustomField>
```

### 2 (NEU). `force-app/main/default/objects/Opportunity/validationRules/LossReason_PflichtBeiClosedLost.validationRule-meta.xml`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<ValidationRule xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>LossReason_PflichtBeiClosedLost</fullName>
    <active>true</active>
    <description>SCRUM-381: Verlustgrund wird erzwungen wenn die Opportunity als Closed Lost gespeichert wird. Auto-Clear-Case (Stage wird weg von Closed Lost gesetzt) wird nicht tangiert, weil die ValRule auf den Endstand des Records nach dem Before-Update-Trigger ausgewertet wird.</description>
    <errorConditionFormula>AND(StageName = &apos;Closed Lost&apos;, ISBLANK(Loss_Reason__c))</errorConditionFormula>
    <errorMessage>Bitte wählen Sie einen Verlustgrund, bevor Sie die Chance als verloren markieren.</errorMessage>
    <visible>true</visible>
</ValidationRule>
```

### 3 (NEU). `force-app/main/default/permissionsets/SCRUM381_LeadFollowUp.permissionset-meta.xml`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<PermissionSet xmlns="http://soap.sforce.com/2006/04/metadata">
    <fieldPermissions>
        <editable>true</editable>
        <field>Opportunity.Loss_Reason__c</field>
        <readable>true</readable>
    </fieldPermissions>
    <hasActivationRequired>false</hasActivationRequired>
    <label>SCRUM381_LeadFollowUp</label>
    <description>Read+Edit auf Verlustgrund (Loss_Reason__c) für Vertriebsbenutzer (SCRUM-381). Standard-FLS des Felds bleibt Default (kein Zugriff) — nur über dieses PS erreichbar.</description>
</PermissionSet>
```

### 4 (NEU). `force-app/main/default/classes/OpportunityLossReasonClearHandler.cls`

```apex
/**
 * OpportunityLossReasonClearHandler — TRIGGER handler for auto-clearing
 * Loss_Reason__c (SCRUM-381).
 *
 * Fired from OpportunityOverdueReset.trigger (before update).
 *
 * Behavior:
 *   Whenever an Opportunity's StageName changes FROM 'Closed Lost' TO any
 *   other stage (Reopen, Closed Won, etc.), Loss_Reason__c is set to null.
 *
 * Why null, no space-Convention:
 *   The ValidationRule LossReason_PflichtBeiClosedLost is evaluated on the
 *   FINAL record state of the transaction — i.e. AFTER this Before-Update-
 *   trigger. If we clear only when leaving 'Closed Lost', the rule's gate
 *   (StageName = 'Closed Lost') is already false in the same transaction,
 *   so the clear cannot trigger a false-positive block.
 */
public without sharing class OpportunityLossReasonClearHandler {

    @Testvisible
    private static boolean hasFired = false;

    public static void HandleBeforeUpdate(List<Opportunity> NewRecords, Map<Id, Opportunity> OldMap) {
        if (hasFired) {
            return;
        }
        hasFired = true;

        for (Opportunity Opp : NewRecords) {
            Opportunity OldOpp = OldMap.get(Opp.Id);

            // ONLY clear when the stage actually changes OUT of Closed Lost.
            // StageName is never modified by this handler → no recursion.
            if (OldOpp != null
                && OldOpp.StageName == 'Closed Lost'
                && Opp.StageName != 'Closed Lost') {
                Opp.Loss_Reason__c = null;
            }
        }
    }
}
```

### 5 (MODIFIED). `force-app/main/default/triggers/OpportunityOverdueReset.trigger`

```apex
/**
 * Trigger for Opportunities — two responsibilities:
 *   1. Auto-reset Is_Overdue__c on any update (SCRUM-319, existing)
 *   2. Auto-clear Loss_Reason__c on stage-change OUT of Closed Lost (SCRUM-381, new)
 */
trigger OpportunityOverdueReset on Opportunity (before update) {
    OpportunityOverdueResetHandler.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
    OpportunityLossReasonClearHandler.HandleBeforeUpdate(Trigger.new, Trigger.oldMap);
}
```

### 6 (MODIFIED). `force-app/main/default/layouts/Opportunity-Opportunity Layout.layout-meta.xml`

Add a `layoutItems` block for `Loss_Reason__c` **immediately after the
StageName item**, in the same `layoutColumns` (left column of the
„Opportunity Information" section):

```xml
<layoutItems>
    <behavior>Edit</behavior>
    <field>Loss_Reason__c</field>
</layoutItems>
```

Do NOT touch any other layoutItem. Preserve the original 4-space indent.

### 7 (NEU). `force-app/main/default/classes/SCRUM381LeadFollowUpTest.cls`

Apex-Tests — same style as `SCRUM319OverdueOpportunityTest.cls`. 7 methods:

1. **`test_Create_ClosedLost_NoReason_ShouldThrow`** — insert an Opportunity
   with `StageName='Closed Lost'`, no `Loss_Reason__c` → expect
   `DmlException` with an message containing „Verlustgrund".
2. **`test_Create_ClosedLost_WithReason_ShouldSave`** — set
   `Loss_Reason__c='ZuTeuer'`, insert, verify the record persists and the
   field value is `ZuTeuer` (query back, not trust the insert's return value).
3. **`test_Open_Opportunity_WithoutReason_ShouldSave`** — `StageName='Prospecting'`,
   no reason → save succeeds, reason remains null.
4. **`test_Reopen_ClearsLossReason`** — insert `Closed Lost` + `ZuTeuer`,
   update with `StageName='Prospecting'` (no write to reason field) →
   after commit, `Loss_Reason__c` is **null** (query back!).
5. **`test_ClosedWon_ClearsLossReason`** — same pattern, update to
   `StageName='Closed Won'` → `Loss_Reason__c` is null.
6. **`test_Update_WithoutStageChange_ShouldKeepReason`** — insert
   `Closed Lost` + `ZuTeuer`, update only `NextStep` (stage stays
   `Closed Lost`) → `Loss_Reason__c` remains `'ZuTeuer'` (trigger must NOT
   clear it — no StageName change).
7. **`test_FLS_NoPermissionSet_CannotReadField`** —
   `System.runAs(testUserWithoutPS)`: try `SELECT Loss_Reason__c FROM
   Opportunity WHERE Id=...` → expect `SecurityException` (test user is
   created in the same test file, role = minimal, no PS; if a minimal
   user already exists in the org — reuse, see `SCRUM378LeadNachfassungFlsTest.cls`
   for the pattern).

**E2E (Playwright)** — written by Tester, 4 tests:
1. Open an Opportunity (Prospecting), set Stage = Closed Lost without
   reason, click Save → validation error with the exact German message
   from ADR-1.
2. Same flow, pick a Loss Reason → Save succeeds, record is persisted.
3. Open a Closed Lost Opportunity that has a reason, change Stage to
   Prospecting → Save → reload → field is empty.
4. Same, change Stage to Closed Won → Save → reload → field is empty.

### 8a. `manifest/scr381-phase1-fields.xml`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<Package xmlns="http://soap.sforce.com/2006/04/metadata">
    <types>
        <members>Opportunity.Loss_Reason__c</members>
        <name>CustomField</name>
    </types>
    <version>67.0</version>
</Package>
```

### 8b. `manifest/scr381-phase2-referencing.xml`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<Package xmlns="http://soap.sforce.com/2006/04/metadata">
    <types>
        <members>Opportunity.LossReason_PflichtBeiClosedLost</members>
        <name>ValidationRule</name>
    </types>
    <types>
        <members>Opportunity-Opportunity Layout</members>
        <name>Layout</name>
    </types>
    <types>
        <members>SCRUM381_LeadFollowUp</members>
        <name>PermissionSet</name>
    </types>
    <types>
        <members>OpportunityOverdueReset</members>
        <name>ApexTrigger</name>
    </types>
    <types>
        <members>OpportunityLossReasonClearHandler</members>
        <members>SCRUM381LeadFollowUpTest</members>
        <name>ApexClass</name>
    </types>
    <version>67.0</version>
</Package>
```

## Technical Acceptance (add to PO ACs)

| # | Criterion | Artifact |
|---|---|---|
| T1 | `LossReason_PflichtBeiClosedLost` blocks Closed Lost saves without reason on ALL write paths (UI + API + Bulk — ValRule, not layout) | Apex test `test_Create_ClosedLost_NoReason_ShouldThrow` |
| T2 | Auto-Clear fires when StageName changes OUT of Closed Lost (any target stage), sets null | Apex tests `test_Reopen_ClearsLossReason` + `test_ClosedWon_ClearsLossReason` |
| T3 | Auto-Clear does NOT fire when StageName does not change (e.g. NextStep-only update keeps the reason intact) | Apex test `test_Update_WithoutStageChange_ShouldKeepReason` |
| T4 | Layout shows `Loss_Reason__c` in the Stage-Section (left column of „Opportunity Information", right after StageName) | Playwright (visual) |
| T5 | FLS: only users with `SCRUM381_LeadFollowUp` have Read+Edit; without PS: no Read, no Edit | Apex test `test_FLS_NoPermissionSet_CannotReadField` |
| T6 | German error message: „Bitte wählen Sie einen Verlustgrund, bevor Sie die Chance als verloren markieren." | Playwright (error text assert) |
| T7 | Deploy: Phase 1 fields green, Phase 2 referencing green — 2× `sf project deploy start`, no validation skip | DevOps deploy log |
| T8 | Existing `OpportunityOverdueReset` behavior (Is_Overdue__c reset) not regressed | Existing `SCRUM319OverdueOpportunityTest` remains green |

## Sharing Model
No change. Field visibility follows Opportunity sharing (PO: „erbt die
Sichtbarkeitsregeln der Opportunity"); FLS layer added on top via ADR-3.

## Data Classification
Nicht-PII, interne Geschäftsdaten (PO: keine personenbezogenen Daten).

## Deploy / Verify (DevOps)

```bash
# Branch existiert bereits (feature/SCRUM-381-lost-reason, auf master-Basis)
# und haelt NUR den Design-Doc im Basis-Commit (git log zeigt ihn). Von
# dort aus alle Dateien aus diesem Doc anlegen/modifizieren, eigene Pfade
# explizit stageen.
git checkout feature/SCRUM-381-lost-reason
# ... alle Dateien aus diesem Doc anlegen/modifizieren ...
git add force-app/main/default/objects/Opportunity/fields/Loss_Reason__c.field-meta.xml \
        force-app/main/default/objects/Opportunity/validationRules/LossReason_PflichtBeiClosedLost.validationRule-meta.xml \
        force-app/main/default/permissionsets/SCRUM381_LeadFollowUp.permissionset-meta.xml \
        force-app/main/default/classes/OpportunityLossReasonClearHandler.cls \
        force-app/main/default/classes/OpportunityLossReasonClearHandler.cls-meta.xml \
        force-app/main/default/classes/SCRUM381LeadFollowUpTest.cls \
        force-app/main/default/classes/SCRUM381LeadFollowUpTest.cls-meta.xml \
        force-app/main/default/triggers/OpportunityOverdueReset.trigger \
        "force-app/main/default/layouts/Opportunity-Opportunity Layout.layout-meta.xml" \
        manifest/scr381-phase1-fields.xml \
        manifest/scr381-phase2-referencing.xml
git diff --cached --name-only   # ONLY die 11 eigenen Dateien
git commit -m "[SCRUM-381] Loss Reason: Feld, ValRule, Trigger-Handler, PS, Layout, Manifests"

# Phase 1: fields only
sf project deploy start -o Test-Org -m manifest/scr381-phase1-fields.xml
# Phase 2: referencing
sf project deploy start -o Test-Org -m manifest/scr381-phase2-referencing.xml
# Tests run
sf apex run test -o Test-Org -t SCRUM381LeadFollowUpTest
sf apex run test -o Test-Org -t SCRUM319OverdueOpportunityTest   # Regression

# Read-back against the org (verify at the target system, 2026-08-24 lesson)
sf data query  -o Test-Org -q "SELECT Id, StageName, Loss_Reason__c FROM Opportunity WHERE IsDeleted = false LIMIT 5"
sf layout describe "Opportunity-Opportunity Layout" -o Test-Org | grep -A1 Loss_Reason__c
sf pdx describe permissionset -o Test-Org 2>/dev/null | grep SCRUM381_LeadFollowUp
```
