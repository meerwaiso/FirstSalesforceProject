# SCRUM-384 — Account sperren (Gesperrt + Sperrgrund) · Authoritative Build-Spec

> **This file is the source of truth for the exact XML, API names and Apex.**
> The Jira comments (SCRUM-384) are mangled by Jira's markdown converter
> (double underscores — bold, closing XML tags dropped — verified repeatedly
> on this project). Build the files from THIS doc, cross-check against the
> in-repo reference files named below. Do not copy names out of the Jira comment.

## Goal
Ein Account wird über ein Kennzeichen „Gesperrt“ + Freitext „Sperrgrund“
gesperrt; ohne Grund ist das Sperren nicht speicherbar (AC2), am gesperrten
Account blockt die Anlage neuer Opportunities mit Meldung, die Account-Namen
und Sperrgrund nennt (AC3), und das Aufheben der Sperre leert den Sperrgrund
automatisch (AC4). Sichtbar nur im „Account Layout“; die drei anderen
Account-Layouts bleiben byte-identisch.

## Branch
`feature/SCRUM-384-account-blocking` frisch von `master` abziehen.
Geteilter Tree: `.cline-roles/` und `scr378-report-final.zip` liegen untracked
— weder commiten noch löschen, nur explizit eigene Pfade stageen.
Niemals `git add .` / `-A`.

## ADR

### ADR-1: AC2 (Sperrpflicht) → Validierungsregel auf Account
Greift auf jedem Schreibpfad (UI, API, Flow, Bulk) — stärker als
Layout-`Required`. Formel im **Function-Fundament** `AND(a, b)` — nie infix
`a AND b` (Syntax Error in Salesforce Formulas; dieses Projekt hat dafür
zwei Debug-Zyklen bezahlt).
```
AND(Is_Locked__c, ISBLANK(Lock_Reason__c))
```
Checkbox-Feld ist selbst Bedingung — nie `Is_Locked__c = TRUE`.

### ADR-2: AC3 (Opportunity-Blockade) → APEX-Trigger, NICHT Validierungsregel
Entscheidend: **ValRule-Fehlermeldungen sind statisch Text** — sie können
weder den Account-Namen noch den Sperrgrund dynamisch nennen. AC3 verlangt
explizit: „Die Meldung nennt den Account und den Sperrgrund.“ → nur ein
**Before-Insert-Trigger** auf Opportunity kann die dynamische Meldung
delivern. Trigger feuert auf jedem Anlagepfad (UI, Quick Action, API, Flow
RecordCreate, Bulk) → PO-AC „muss für jede Opportunity-Anlage greifen —
unabhängig vom anlegenden Profil“ erfüllt.
Kein Flow (Schema-Drift/apiVersion, dokumentiert), kein Apex ohne Trigger.

**Trigger-Struktur — Haus-Muster „ein Trigger pro Objekt“** (SCRUM-381):
Auf Opportunity existiert bereits `OpportunityOverdueReset.trigger`
(before update, SCRUM-319/381). Wir **erweitern denselben Trigger-File** um
das `before insert`-Event und guarden die Update-Handler — statt ein zweites
Trigger-File auf demselben Objekt zu legen:

```apex
trigger OpportunityOverdueReset on Opportunity (before insert, before update) {
    if (Trigger.isUpdate) {
        OpportunityOverdueResetHandler.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
        OpportunityLossReasonClearHandler.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
    }
    if (Trigger.isInsert) {
        OpportunityLockedAccountGuard.handleBeforeInsert(Trigger.new);
    }
}
```
Die `.trigger-meta.xml` bleibt UNVERÄNDERT (apiVersion 62.0) — nur der
Body ändert sich. KEIN Rename (Rename = Delete+Create, unnötiges Risiko).

### ADR-3: AC4 (Auto-Clear Sperrgrund) → APEX-Trigger auf Account, SCRUM-381-Pattern 1:1
„Gesperrt“ ist ein Feldwert; eine Validierungsregel kann Felder nicht
leeren (PO-Festlegung im Ticket). → Before-Update-Trigger auf Account mit
Handler im exakten Muster von `OpportunityLossReasonClearHandler`
(SCRUM-381): `hasFired`-Flag, 0 SOQL, null-Zuweisung nur bei
TRUE→FALSE-Wechsel.
**Koexistenz mit ADR-1 ist sicher** (SCRUM-381 ADR-2, bewiesenes Muster):
Die ValRule wird auf dem **Endstand** des Records in der Transaktion
ausgewertet — also NACH dem Before-Update-Trigger. Beim Aufheben ist
`Is_Locked__c` im Endstand bereits FALSE → ValRule-Gate inaktiv → das
Clearing kann nie zu einem falsch-positiven Block führen.

### ADR-4: FLS → ein Permission Set, PO-Tabelle exakt
Ein PS `SCRUM384_AccountBlocking` (beide Felder editable=true,
hasActivationRequired=false), Profile unverändert.
Wichtig (macht die PO-Tabelle ohne zweite „Read-only“-PS umsetzbar):
**Feld-FLS ist eine Obergrenze, kein Boost** — ein User ohne Object-Edit
auf Account nutzt `editable=true` nie praktisch; User mit Account-Edit
bekommen damit genau Field-Edit. PS also an die in der Org vorhandenen
Standard-Gruppen, die alle Account-Nutzer abdecken (in der Org prüfen,
z. B. `Salesforce Internal Users` / Profilgruppen) → @devops-agent-Org-Schritt
nach dem Deploy (blockt NICHT, wie SCRUM-382-Prezedenz). Negativ-Test:
User ohne PS sieht beide Felder nicht (neue Felder sind default unsichtbar).

### ADR-5: API-Namen & Typen (Architect-Festlegung, PO-Tabelle)
| Label (PO) | API-Name | Typ |
|---|---|---|
| Gesperrt | `Is_Locked__c` | Checkbox, defaultValue false |
| Sperrgrund | `Lock_Reason__c` | Text(255) |

Haus-Konvention: englischer API-Name, deutsches Label (`Is_Overdue__c`,
`Loss_Reason__c`, `Customer_Since_Days__c`). Sperrgrund = Freitext (PO:
Textfeld) → Text(255), Hauslänge (`Additional_Comment__c`).

### ADR-6: 2-Phase-Deploy (Haus-Muster SCRUM-381/382)
Phase 1 = nur Felddefinitionen; Phase 2 = alles, was referenziert.
Grund: Referenz-Deploy auf nicht-existierendes Feld → Schema-Fehler.

## Datenmodell
- 2 neue CustomFields: `Account.Is_Locked__c` (Checkbox),
  `Account.Lock_Reason__c` (Text 255).
- 1 neue ValidationRule: `Account.LockReason_PflichtBeiGesperrt`.
- 1 neues Trigger-File: `AccountLockGuard.trigger` (vorher: KEIN Account-Trigger im Repo).
- 1 erweiterter Trigger-File: `OpportunityOverdueReset.trigger` (+ `before insert`).
- 2 neue Apex-Handler: `AccountLockClearHandler`, `OpportunityLockedAccountGuard`.
- 1 neues PS: `SCRUM384_AccountBlocking`; 1 Layout-Change (eine Datei).
- Sharing: **keine Änderung** (PO-Festlegung; Sperre ist Daten-Zustands-Check).

## Dateien — exakte Pfade & XML

In-repo reference files (deployen heutzutage, kopiere Shapes):
- `force-app/main/default/objects/Lead/fields/Interesting__c.field-meta.xml` (Checkbox-Shape, defaultValue)
- `force-app/main/default/objects/Contact/fields/Additional_Comment__c.field-meta.xml` (Text-255-Shape)
- `force-app/main/default/objects/Lead/validationRules/Letzter_Versuch_KeineZukunft.validationRule-meta.xml` (ValRule-Shape)
- `force-app/main/default/classes/OpportunityLossReasonClearHandler.cls` (Clear-Handler-Shape 1:1)
- `force-app/main/default/classes/OpportunityLossReasonClearHandler.cls-meta.xml` (apiVersion 63.0)
- `force-app/main/default/triggers/OpportunityOverdueReset.trigger` + `-meta.xml` (apiVersion 62.0)
- `force-app/main/default/layouts/Account-Account Layout.layout-meta.xml`
- `force-app/main/default/permissionsets/SCRUM378_LeadNachfassung.permissionset-meta.xml` (2-feld PS-Shape)
- `manifest/scr381-phase1-fields.xml` / `scr381-phase2-referencing.xml` (Manifest-Shape, version 67.0)

### Phase 1

#### 1 (NEU). `force-app/main/default/objects/Account/fields/Is_Locked__c.field-meta.xml`
```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Is_Locked__c</fullName>
    <label>Gesperrt</label>
    <description>Kennzeichen: Account ist gesperrt, Zusammenarbeit ausgesetzt (SCRUM-384). Sperre ohne Sperrgrund speicherbar blockiert: ValidationRule LockReason_PflichtBeiGesperrt. Am gesperrten Account blockiert die Anlage neuer Opportunities (OpportunityLockedAccountGuard).</description>
    <defaultValue>false</defaultValue>
    <type>Checkbox</type>
</CustomField>
```

#### 2 (NEU). `force-app/main/default/objects/Account/fields/Lock_Reason__c.field-meta.xml`
```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Lock_Reason__c</fullName>
    <label>Sperrgrund</label>
    <description>Begründung der Sperre (SCRUM-384). Pflicht bei gesperrtem Account (ValRule). Wird automatisch geleert, wenn Gesperrt aufgehoben wird (AccountLockClearHandler). Intern/geschäftssensibel, kein PII.</description>
    <length>255</length>
    <required>false</required>
    <trackTrending>false</trackTrending>
    <type>Text</type>
</CustomField>
```

#### 3. `manifest/scr384-phase1-fields.xml`
```xml
<?xml version="1.0" encoding="UTF-8"?>
<Package xmlns="http://soap.sforce.com/2006/04/metadata">
    <!-- SCRUM-384 Phase 1: nur die zwei neuen Fields (gelangen ZUERST, da ValRule/Layout/PS/Triggers darauf referenzieren). -->
    <types>
        <members>Account.Is_Locked__c</members>
        <members>Account.Lock_Reason__c</members>
        <name>CustomField</name>
    </types>
    <version>67.0</version>
</Package>
```

### Phase 2

#### 4 (NEU). `force-app/main/default/objects/Account/validationRules/LockReason_PflichtBeiGesperrt.validationRule-meta.xml`
```xml
<?xml version="1.0" encoding="UTF-8"?>
<ValidationRule xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>LockReason_PflichtBeiGesperrt</fullName>
    <active>true</active>
    <description>SCRUM-384 AC2: Gesperrt=true ohne Sperrgrund blockiert das Speichern. Auto-Clear-Case (Gesperrt wird auf FALSE gesetzt) wird nicht tangiert, die ValRule wird auf dem Endstand des Records nach dem Before-Update-Trigger ausgewertet — dann ist Is_Locked__c bereits FALSE.</description>
    <errorConditionFormula>AND(Is_Locked__c, ISBLANK(Lock_Reason__c))</errorConditionFormula>
    <errorMessage>Bitte tragen Sie den Sperrgrund in das Feld „Sperrgrund“ in, während der Account gesperrt ist.</errorMessage>
</ValidationRule>
```
(Achtung: `AND(a, b)` Function-Fundament — nie infix `a AND b`.)

#### 5 (NEU). `force-app/main/default/classes/AccountLockClearHandler.cls`
```apex
/**
 * AccountLockClearHandler — Trigger handler fur das automatische Leeren
 * des Sperrgrundes (Account.Lock_Reason__c) beim Aufheben der Sperre,
 * SCRUM-384. SCRUM-381-Muster 1:1.
 *
 * Verhalten:
 *   Jeder Account, dessen Is_Locked__c sich von TRUE auf FALSE andert,
 *   bekommt Lock_Reason__c auf null gesetzt (AC4).
 *
 * Interaktion mit ValRule LockReason_PflichtBeiGesperrt:
 *   Die ValRule wird auf dem ENDSTAND ausgewertet (nach Before-Update).
 *   In derselben Transaktion ist Is_Locked__c schon FALSE, das Gate
 *   ist inaktiv — kein falsch-positiver Block (SCRUM-381-ADR-2).
 *
 * Bulk: 0 SOQL, 1 Zuweisung pro geandertem Record, eigenes hasFired-Flag.
 */
public with sharing class AccountLockClearHandler {
    @testVisible
    private static Boolean hasFired = false;

    public static void handleBeforeUpdate(List<Account> newAccounts, Map<Id, Account> oldMap) {
        if (hasFired) {
            return;
        }
        hasFired = true;

        for (Account acct : newAccounts) {
            Account oldAcct = oldMap.get(acct.Id);
            if (oldAcct != null && oldAcct.Is_Locked__c && !acct.Is_Locked__c) {
                acct.Lock_Reason__c = null;
            }
        }
    }
}
```

#### 6 (NEU). `force-app/main/default/triggers/AccountLockGuard.trigger`
```apex
/**
 * Account-Trigger (SCRUM-384): Auto-Clear von Lock_Reason__c, wenn die
 * Sperre (Is_Locked__c) aufgehoben wird. Ein Trigger pro Objekt.
 * Before update; ValRule wertet danach auf dem Endstand — siehe Handler.
 */
trigger AccountLockGuard on Account (before update) {
    AccountLockClearHandler.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
}
```
`AccountLockGuard.trigger-meta.xml`: exakt wie
`OpportunityOverdueReset.trigger-meta.xml` (apiVersion 62.0).

#### 7 (NEU). `force-app/main/default/classes/OpportunityLockedAccountGuard.cls`
```apex
/**
 * OpportunityLockedAccountGuard — blockiert die ANLAGE von Opportunities
 * am gesperrten Account (SCRUM-384 AC3).
 *
 * Warum Trigger und keine ValRule: AC3 verlangt eine Meldung, die den
 * Account-NAMEN und den SPERRGRUND nennt — ValRule-Meldungen sind statisch
 * Text und können das nicht. Der before-insert-Trigger feuert auf jedem
 * Anlagepfad (UI, Quick Action, API, Flow RecordCreate, Bulk) = PO-AC
 * „unabhängig vom anlegenden Profil“.
 *
 * without sharing (bewusste Entscheidung): Der Block ist ein
 * Sicherheits-Gate. Wäre die Klasse with sharing, würde ein anlegenden
 * User, dem der Account per Sharing unsichtbar ist, die Lookup-Miss geben
 * und die Anlage trotzdem durch — das Gate wäre dann profilabhängig, genau
 * das, was die PO ausschließt. without sharing + SELECT nur auf die
 * nötigen Read-Only-Felder (Name, Is_Locked__c, Lock_Reason__c).
 *
 * Bulk: 1 SOQL im Vorfeld (IN :ids, leerer-Set-Guard), 0 SOQL im Loop,
 * addError pro betroffener Record.
 */
public without sharing class OpportunityLockedAccountGuard {

    public static void handleBeforeInsert(List<Opportunity> newOpportunities) {
        Set<Id> accountIds = new Set<Id>();
        for (Opportunity opp : newOpportunities) {
            if (opp.AccountId != null) {
                accountIds.add(opp.AccountId);
            }
        }
        if (accountIds.isEmpty()) {
            return;
        }
        Map<Id, Account> byId = new Map<Id, Account>([
            SELECT Id, Name, Is_Locked__c, Lock_Reason__c
            FROM Account
            WHERE Id IN :accountIds
        ]);

        for (Opportunity opp : newOpportunities) {
            Account acct = byId.get(opp.AccountId);
            if (acct != null && acct.Is_Locked__c) {
                opp.addError('Anlage blockiert: Der Account „' + acct.Name + '“ ist gesperrt. Sperrgrund: ' + acct.Lock_Reason__c);
            }
        }
    }
}
```
Meldung (wichtig für Tester): enthält exakt beide geforderten Angaben —
Account-Name in Anführungszeichen, dann „Sperrgrund: “ + Wert.

#### 8 (ÄNDERUNG). `force-app/main/default/triggers/OpportunityOverdueReset.trigger`
Neuer Body, meta-File bleibt unverändert (s. ADR-2):
```apex
/**
 * Opportunity-Trigger:
 *   1. Auto-Reset von Is_Overdue__c bei jeglicher Aenderung (SCRUM-319).
 *   2. Auto-Clear von Loss_Reason__c bei Stage weg von 'Closed Lost' (SCRUM-381).
 *   3. Blockade neuer Opportunities am gesperrten Account (SCRUM-384, before insert).
 */
trigger OpportunityOverdueReset on Opportunity (before insert, before update) {
    if (Trigger.isUpdate) {
        OpportunityOverdueResetHandler.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
        OpportunityLossReasonClearHandler.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
    }
    if (Trigger.isInsert) {
        OpportunityLockedAccountGuard.handleBeforeInsert(Trigger.new);
    }
}
```

#### 9 (ÄNDERUNG). `force-app/main/default/layouts/Account-Account Layout.layout-meta.xml`
NEUE Section „Sperre“, beide Felder adjazent, eingefügt NACH der Section
„Additional Information“, VOR „System Information“:
```xml
    <layoutSections>
        <customLabel>true</customLabel>
        <detailHeading>true</detailHeading>
        <editHeading>true</editHeading>
        <label>Sperre</label>
        <layoutColumns>
            <layoutItems>
                <behavior>Edit</behavior>
                <field>Is_Locked__c</field>
            </layoutItems>
        </layoutColumns>
        <layoutColumns>
            <layoutItems>
                <behavior>Edit</behavior>
                <field>Lock_Reason__c</field>
            </layoutItems>
        </layoutColumns>
        <style>TwoColumnsLeftToRight</style>
    </layoutSections>
```
Die anderen drei Account-Layouts (Sales, Marketing, Support) bleiben
**byte-identisch** (Scope-Ausschluss) — der git diff darf diese eine
Layoutdatei und nichts anderes zeigen.

#### 10 (NEU). `force-app/main/default/permissionsets/SCRUM384_AccountBlocking.permissionset-meta.xml`
```xml
<?xml version="1.0" encoding="UTF-8"?>
<PermissionSet xmlns="http://soap.sforce.com/2006/04/metadata">
    <fieldPermissions>
        <editable>true</editable>
        <field>Account.Is_Locked__c</field>
        <readable>true</readable>
    </fieldPermissions>
    <fieldPermissions>
        <editable>true</editable>
        <field>Account.Lock_Reason__c</field>
        <readable>true</readable>
    </fieldPermissions>
    <hasActivationRequired>false</hasActivationRequired>
    <label>SCRUM384_AccountBlocking</label>
    <description>FLS für Gesperrt (Is_Locked__c) und Sperrgrund (Lock_Reason__c), SCRUM-384. PO: Read = alle mit Account-Read, Edit = alle mit Account-Edit; Feld-FLS ist Obergrenze, nie Boost, daher ein PS für beide Rollen. Profile unverändert.</description>
</PermissionSet>
```

#### 11 (NEU). `force-app/main/default/classes/SCRUM384AccountLockTest.cls`
Apex-Tests (System.runAs/SeeAllData wo nötig, SCRUM-381-Test-Style):
1. **AC2-positiv:** Account + Is_Locked=true + Lock_Reason → insert/update ok.
2. **AC2-negativ:** Is_Locked=true, Lock_Reason null/empty → DMLException,
   Meldung enthält „Sperrgrund“.
3. **AC3-negativ:** gesperrter Account (Grund gesetzt) → Opportunity insert
   → DMLException, Meldung enthält Account-Name UND Sperrgrund-Wert.
4. **AC3-positiv:** unge-sperrter Account (Grund leer) → insert ok;
   AccountId=null → insert ok.
5. **AC4:** gesperrt+Grund → ein Update auf Is_Locked=false → Read-Back:
   Lock_Reason__c == null; danach Opportunity insert ok.
6. **Bulk-Governor:** 200 Opportunities gegen 2+1 Accounts (2 gesperrt,
   1 offen) → genau 1 SOQL (Limits.assert), nur die 2 gesperrten blockiert.
7. **FLS-negativ:** System.runAs(User ohne PS) → SELECT beider Felder
   schlägt fehl/nicht sichtbar (Muster SCRUM359NewsletterConsentFlsTest).
Test-Meta: apiVersion 63.0 wie `SCRUM381LostReasonTest.cls-meta.xml`.

#### 12. `manifest/scr384-phase2-referencing.xml`
```xml
<?xml version="1.0" encoding="UTF-8"?>
<Package xmlns="http://soap.sforce.com/2006/04/metadata">
    <!-- SCRUM-384 Phase 2: alles, was auf die Phase-1-Fields referenziert (gelangen ERST NACH Phase 1). -->
    <types>
        <members>Account.LockReason_PflichtBeiGesperrt</members>
        <name>ValidationRule</name>
    </types>
    <types>
        <members>Account-Account Layout</members>
        <name>Layout</name>
    </types>
    <types>
        <members>SCRUM384_AccountBlocking</members>
        <name>PermissionSet</name>
    </types>
    <types>
        <members>AccountLockGuard</members>
        <members>OpportunityOverdueReset</members>
        <name>ApexTrigger</name>
    </types>
    <types>
        <members>AccountLockClearHandler</members>
        <members>OpportunityLockedAccountGuard</members>
        <members>SCRUM384AccountLockTest</members>
        <name>ApexClass</name>
    </types>
    <version>67.0</version>
</Package>
```

## Governor Limits
- `AccountLockClearHandler`: 1 Before-Update-Aufruf, **0 SOQL**, null-Zuweisung
  nur bei TRUE→FALSE (Loop über Trigger.new/oldMap, bulk-safe), eigenes
  `hasFired`-Flag.
- `OpportunityLockedAccountGuard`: **1 SOQL** (IN :accountIds, Guard bei leerem
  Set vor dem Query), 0 SOQL im Loop, `addError` pro Record. Trigger fires
  pro Insert-Batch.
- ValRule: reine Same-Record-Form, keine Cross-Object-Referenz.
- Rekursion: kein Handler ändert Is_Locked__c selbst → Clear-Logik feuert
  max. 1× pro Record pro Transaktion.

## ⚠️ Befund (Repo-Analyse, blockt NICHT)
1. **Repo trackt nur Classic-Layouts.** `Account-Account Layout.layout-meta.xml`
   ist das Classic Page Layout; die Lightning Record Page für Account liegt in
   der Org (App Builder). Nach dem Deploy: beide Felder auf der Lightning
   Account-Record-Page platzieren — Org-Schritt für @devops-agent.
   @tester-agent validiert **beide** UIs (SCRUM-378/382-Prezedenz).
2. **PS-Zuweisung in der Org** (ADR-4): Standard-Gruppe prüfen, die alle
   Account-Nutzer abdeckt → @devops-agent nach dem Deploy.
3. **Coverage-Gate (bekanntes Repo-Problem, SCRUM-378-Prezedenz):** Test-Org
   braucht 75 % Org-Weit, liegt bei ~37 % — ein `deploy validate` kann an der
   Coverage scheitern, egal wie gut diese Metadata ist. Vor dem Deploy
   Coverage-Status prüfen; falls Causa, @devops-agent informieren.
   Kein Read eines failed validation als Defect an dieser Metadata.

## Offene Punkte (blocken die Implementierung NICHT)
- [ ] Lightning-Platzierung beider Felder (Account Record Page) → @devops-agent
- [ ] PS-Anmeldung an Standard-Gruppe(n) (Read-all vs Edit-all, ADR-4) → @devops-agent
- [ ] Validierung beider UIs (Classic + Lightning) im Test-Scope → @tester-agent
