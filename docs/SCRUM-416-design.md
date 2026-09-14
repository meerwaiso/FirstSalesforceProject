# SCRUM-416 — Offene Chancen je Kunde auf einen Blick

**Autor:** architect-agent · **Status:** freigegeben
**Objekte:** Account (Parent), Opportunity (Standard-Child) · **Repo:** force-app/main/default
**Repo-Stand zur Konzeption:** `origin/master` @ `59df7cf` (abgefragt 2026-09-14)

---

## Ziel
Zwei live gepflegte Zahlen auf der Kunden-Seite — Anzahl offener Chancen und Summe der offenen Beträge (Won/Lost exklusive) — plus ein nach offenem Wert absteigend sortierbarer Report über alle Kunden; beide Zahlen bleiben bei Gewinn, Verlust, Umwertung und Umhängen korrekt.

## Komponenten

### 1. Feld 1: Anzahl offener Chancen
**Pfad:** `force-app/main/default/objects/Account/fields/Open_Opportunity_Count__c.field-meta.xml`
**Typ:** Number(6,0), read-only, systemmaintained · **Muster:** `Contact.Open_Cases_Count__c` (SCRUM-365)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Open_Opportunity_Count__c</fullName>
    <label>Offene Chancen</label>
    <description>Anzahl der offenen Chancen (IsClosed = false) des Accounts. Wird ausschliesslich vom System gepflegt (Opportunity-Trigger + OpenOpportunityRollupHandler, SCRUM-416); von Hand nicht änderbar.</description>
    <type>Number</type>
    <precision>6</precision>
    <scale>0</scale>
    <required>false</required>
    <unique>false</unique>
    <defaultValue>0</defaultValue>
    <externalId>false</externalId>
    <trackTrending>false</trackTrending>
</CustomField>
```

### 2. Feld 2: Summe offener Beträge
**Pfad:** `force-app/main/default/objects/Account/fields/Open_Opportunity_Value__c.field-meta.xml`
**Typ:** Currency, read-only, systemmaintained

```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Open_Opportunity_Value__c</fullName>
    <label>Wert offener Chancen</label>
    <description>Summe der Amount-Beträge aller offenen Chancen (IsClosed = false) des Accounts, fehlende Beträge zählen als 0. Wird ausschliesslich vom System gepflegt (Opportunity-Trigger + OpenOpportunityRollupHandler, SCRUM-416); von Hand nicht änderbar.</description>
    <type>Currency</type>
    <required>false</required>
    <unique>false</unique>
    <externalId>false</externalId>
    <trackTrending>false</trackTrending>
</CustomField>
```

### 3. Permission Set — read-only FLS
**Pfad:** `force-app/main/default/permissionsets/SCRUM416_OpenOpportunities.permissionset-meta.xml`
**Muster:** `SCRUM365_OpenCasesCount` · **Kein Edit für niemanden.** Systemwrites laufen im System-Kontext und umgehen FLS (SCRUM-365-Vorgang).

```xml
<?xml version="1.0" encoding="UTF-8"?>
<PermissionSet xmlns="http://soap.sforce.com/2006/04/metadata">
    <fieldPermissions>
        <editable>false</editable>
        <field>Account.Open_Opportunity_Count__c</field>
        <readable>true</readable>
    </fieldPermissions>
    <fieldPermissions>
        <editable>false</editable>
        <field>Account.Open_Opportunity_Value__c</field>
        <readable>true</readable>
    </fieldPermissions>
    <hasActivationRequired>false</hasActivationRequired>
    <label>SCRUM416_OpenOpportunities</label>
    <description>Read-only FLS für Account.Open_Opportunity_Count__c und Account.Open_Opportunity_Value__c (SCRUM-416). Felder sind systemmaintained (Opportunity-Trigger) — kein Update für irgendwen. PO-Festlegung: Vertrieb, Key Account, Admin. Summenwert ist umsatzkonfidentiell: PS nicht breit streuen.</description>
</PermissionSet>
```

### 4. Classic-Layouts — beide Zahlen oben
**Pfade:**
- `force-app/main/default/layouts/Account-Account Layout.layout-meta.xml`
- `force-app/main/default/layouts/Account-Account %28Sales%29 Layout.layout-meta.xml`

**Einfügestelle:** In beidem die **beiden** Felder als `layoutItems` mit `behavior=Readonly` **ans Ende des ersten `layoutColumns`** der ersten `layoutSections` („Account Information"), direkt nach `AnnualRevenue`:

```xml
<layoutItems>
    <behavior>Readonly</behavior>
    <field>Open_Opportunity_Count__c</field>
</layoutItems>
<layoutItems>
    <behavior>Readonly</behavior>
    <field>Open_Opportunity_Value__c</field>
</layoutItems>
```

Marketing- und Support-Layout bewusst **nicht** geändert (Target Group = Vertrieb/KAM).

### 5. Trigger-Erweiterung + Handler
**Existing:** `force-app/main/default/triggers/OpportunityOverdueReset.trigger` (before insert, before update)
**Aktion:** Kontext auf `before insert, before update, after insert, after update, after delete` erweitern; bestehende Calls bleiben im `isBefore`-Block **unverändert**, der neue After-Block delegiert an den Handler. Ziel-Zustand des Trigger-Files:

```apex
trigger OpportunityOverdueReset on Opportunity (
    before insert, before update, after insert, after update, after delete) {
    if (Trigger.isBefore) {
        if (Trigger.isUpdate) {
            OpportunityOverdueResetHandler.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
            OpportunityLossReasonClearHandler.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
        }
        if (Trigger.isInsert) {
            OpportunityLockedAccountGuard.handleBeforeInsert(Trigger.new);
        }
    } else {
        // SCRUM-416: Rollup der offenen Chancen auf den Account
        if (Trigger.isInsert) {
            OpenOpportunityRollupHandler.onOpportunityInsert(Trigger.new);
        } else if (Trigger.isUpdate) {
            OpenOpportunityRollupHandler.onOpportunityUpdate(Trigger.new, Trigger.oldMap);
        } else if (Trigger.isDelete) {
            OpenOpportunityRollupHandler.onOpportunityDelete(Trigger.old);
        }
    }
}
```

**Pfad (neu):** `force-app/main/default/classes/OpenOpportunityRollupHandler.cls` (+ `.cls-meta.xml`, apiVersion wie die übrigen Handler-Klassen, aktuell 62.0)
**Muster:** Handler-Klasse pro Verantwortung hinter dem Opportunity-Trigger (`OpportunityOverdueResetHandler`, `OpportunityLossReasonClearHandler`) + Bulk-Recompute wie `CaseOpenCountTrigger.recompute` (SCRUM-365).

```apex
public without sharing class OpenOpportunityRollupHandler {

    // insert: alle Opportunities mit AccountId
    public static void onOpportunityInsert(List<Opportunity> newOpps) {
        Set<Id> ids = accountIds(newOpps);
        if (!ids.isEmpty()) { recompute(ids); }
    }

    // delete: AccountIds aus old
    public static void onOpportunityDelete(List<Opportunity> oldOpps) {
        Set<Id> ids = accountIds(oldOpps);
        if (!ids.isEmpty()) { recompute(ids); }
    }

    // update: nur wenn sich AccountId (Umhängen), IsClosed (gewonnen/verloren/geöffnet)
    // oder Amount (Umwertung) geändert hat — dann alter UND neuer Account.
    public static void onOpportunityUpdate(List<Opportunity> newOpps,
                                           Map<Id, Opportunity> oldMap) {
        Set<Id> ids = new Set<Id>();
        for (Opportunity o : newOpps) {
            Opportunity old = oldMap.get(o.Id);
            if (o.AccountId != old.AccountId
                    || o.IsClosed != old.IsClosed
                    || o.Amount != old.Amount) {
                if (o.AccountId != null) { ids.add(o.AccountId); }
                if (old.AccountId != null) { ids.add(old.AccountId); }
            }
        }
        if (!ids.isEmpty()) { recompute(ids); }
    }

    public static Set<Id> accountIds(List<Opportunity> opps) {
        Set<Id> ids = new Set<Id>();
        for (Opportunity o : opps) {
            if (o.AccountId != null) { ids.add(o.AccountId); }
        }
        return ids;
    }

    // Vollrecompute pro betroffener Account: idempotent, heilt Drift und
    // Reassign selbst. Write nur bei tatsächlicher Änderung.
    public static void recompute(Set<Id> accountIds) {
        Map<Id, Account> current = new Map<Id, Account>(
            [SELECT Id, Open_Opportunity_Count__c, Open_Opportunity_Value__c
             FROM Account WHERE Id IN :accountIds]);

        Map<Id, Decimal> sumById = new Map<Id, Decimal>();
        Map<Id, Integer> cntById = new Map<Id, Integer>();
        for (Aggregate a : [SELECT AccountId acc, COUNT(Id) cnt, SUM(Amount) amt
                            FROM Opportunity
                            WHERE AccountId IN :accountIds AND IsClosed = false
                            GROUP BY AccountId]) {
            Id accId = (Id) a.get('acc');
            cntById.put(accId, (Integer) a.get('cnt'));
            sumById.put(accId, (Decimal) a.get('amt'));
        }

        List<Account> toUpdate = new List<Account>();
        for (Id accId : accountIds) {
            Account acc = current.get(accId);
            if (acc == null) { continue; }
            Integer newCount = cntById.containsKey(accId) ? cntById.get(accId) : 0;
            Decimal newValue = sumById.containsKey(accId)
                ? sumById.get(accId) : 0;
            if (acc.Open_Opportunity_Count__c != newCount
                    || acc.Open_Opportunity_Value__c != newValue) {
                acc.Open_Opportunity_Count__c = newCount;
                acc.Open_Opportunity_Value__c = newValue;
                toUpdate.add(acc);
            }
        }
        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }
}
```

**Relevanz der Update-Prüfung:** Nur `AccountId`/`IsClosed`/`Amount` bewegen die Zahlen. Eine reine Stage-Änderung innerhalb offener Stage (IsClosed bleibt false) rechnet nicht neu — korrekt, da weder Anzahl noch Summe sich ändern.

### 6. Report — nach offenem Wert sortierbar
**Pfad:** `force-app/main/default/reports/Sales/Offene_Werte_nach_Kunde.report-meta.xml`
**Muster:** `Betreuungslast_nach_Firma` (scope-Element) + Standard-Reporttyp `AccountList` statt Custom Report Type.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<Report xmlns="http://soap.sforce.com/2006/04/metadata">
    <columns>
        <field>ACCOUNT.NAME</field>
    </columns>
    <columns>
        <field>Account.Open_Opportunity_Count__c</field>
    </columns>
    <columns>
        <aggregateTypes>Sum</aggregateTypes>
        <field>Account.Open_Opportunity_Value__c</field>
    </columns>
    <description>Kunden nach offenem Chancenwert (absteigend): Anzahl offener Chancen + Summe der offenen Beträge (IsClosed = false), alle Kunden der Org inkl. 0/0.</description>
    <format>Summary</format>
    <name>Offene_Werte_nach_Kunde</name>
    <reportType>AccountList</reportType>
    <scope>organization</scope>
    <showDetails>true</showDetails>
    <sortColumn>Account.Open_Opportunity_Value__c</sortColumn>
    <sortOrder>Desc</sortOrder>
</Report>
```

**Template-Befund (2026-09-14, Review PR #109):** Die ursprüngliche Vorlage hier hatte zwei Fehler, die der Developer beim Build über die Deploy-Validate korrigiert hat — das jetzt gezeigte XML ist die **deployverifizierte** Fassung: (1) `sortOrder`/`sortColumn` gibt top-level im `Report`-Element, **nicht** im einzelnen ReportColumn; (2) Report-Feldreferenzen tragen den Objekt-Präfix (`ACCOUNT.NAME`, `Account.Open_Opportunity_Value__c`).

Format `Summary` ohne Gruppierung = flache Tabelle, Standardsortierung absteigend nach Wert (AC5); jeder Kunde erscheint, auch ohne offene Chancen (0/0).

### 7. Tests (PR-Gate, house-Pattern)
- **Apex-Funktionaltest** `force-app/main/default/classes/SCRUM416OpenOpportunityRollupTest.cls`
  - TA-1 ≙ AK1: 3 offen + 1 won + 2 lost → Count = 3, Value = Summe gerade der 3 Offenen.
  - TA-2 ≙ AK2: offene Chance `IsClosed` → true (won und lost) → fällt aus Count **und** Summe.
  - TA-3 ≙ AK3: offene Chance Amount X → Y → Summe weicht um Y − X; **Negativfall:** won-Chance umwerten → Account-Werte bleiben unverändert.
  - TA-4 ≙ AK4: offene Chance auf anderen Account umhängen → alter Count −1/Value −x, neuer +1/+x, beide korrekt.
  - TA-5: offene Chance mit leerem Amount → zählt in Count, 0 in Value.
  - TA-6: Bulk — 200 Opportunities in einem Batch über 10 Accounts → exakt ein `recompute`-Aufruf, Governor Limits grün.
- **FLS-Test** `SCRUM416OpenOpportunityFlsTest.cls` (house-Paar-Form, Muster `SCRUM382…FlsTest`): Felder existieren, nicht editierbar ohne PS.
- **E2E** `tests/e2e/SCRUM-416_offene-werte.spec.ts` (Muster `SCRUM-378_lead-nachfassliste.spec.ts`): Report rendert, Standardsortierung absteigend nach Wert.
- **Manifests** (Muster `scr413-*`):
  - `manifest/scr416-phase1-datamodel.xml` — CustomField ×2, PermissionSet, Layout ×2
  - `manifest/scr416-phase2-trigger.xml` — ApexClass `OpenOpportunityRollupHandler`, ApexTrigger `OpportunityOverdueReset`
  - `manifest/scr416-phase3-tests-report.xml` — ApexClass ×2 (Tests), Report

## Architektur-Entscheidungen (ADR)

### ADR-1: Apex-Trigger + bulkified GROUP-BY-Handler
**Entscheidung:** Der bestehende Opportunity-Trigger (`OpportunityOverdueReset`) gewinnt den After-Kontext und delegiert an `OpenOpportunityRollupHandler.recompute(Set<Id>)`, der die betroffenen Accounts per `GROUP BY`-Query neu berechnet.

**Begründung:**
- Nicht-Flow: Die Logik ist branchy und bulk — Flow hat in diesem Projekt wiederholt Deploy-/Schema-Validierungsprobleme verursacht; Haus-Regel ist Apex für nicht-Triviales.
- Kein deklarativ/Rollup: Standard- und Cross-Object-Rollup filtern **nicht** nach `IsClosed` — die zentrale Akzeptanz (Won/Lost exkludiert) wäre damit nicht darstellbar.
- Kein Cross-Object-Formula: nicht in dieser Org verfügbar.
- Muster exists: `CaseOpenCountTrigger.recompute` (SCRUM-365) ist derselbe Fall (gefilterte Child-Zählung auf Parent) und im Repo deployed; Trigger-Hinter-Handler-Klassen ist das hausübliche Muster des Opportunity-Triggers selbst.

**Alternativen abgelehnt:** Flow (Deploy-/Validierungsrisiko), Custom-Rollup-Package (keine Stage-Filter + extern), Batch-only (nicht „live", AK1–AK4 verlangen Immediate-Reaktion).

### ADR-2: Vollrecompute statt Inkrementaldelta
Pro Ereignis rechnet der Handler die betroffenen Accounts **komplett** neu (`GROUP BY`) und schreibt nur, was sich geändert hat. Idempotent, driftfrei, heilt Reassign (AK4) und manuelle Reparatur selbst — kein Laufzeit-Zustand, der inkonsistent werden kann.

### ADR-3: `IsClosed = false` als Single Source of Truth
`IsClosed` ist das Standard-Feld, das bei Closed Won/Closed Lost true wird (UI **und** API/Stage-Wechsel). Es deckt AK2 exakt ab und entspricht der PO-Definition. Stage-Zuordnung bleibt damit aus der Formel heraus — keine Abhängigkeit vom Stage-Label im Org (kein „Closed Lost"-String-Vergleich).

### ADR-4: Report auf Standard-Reporttype `AccountList`, nicht Custom Report Type
Die persistierten Account-Felder machen den Report deklarativ und source-persistierbar (Muster `Betreuungslast_nach_Firma`, `<scope>organization</scope>` im Repo deploy-verifiziert):
- Alle Kunden erscheinen — auch mit 0/0. (Eine Custom Cross-Object-ReportType `Account + Opportunity` würde Kunden **ohne** offene Chancen aus der Tabelle lassen — genau der Fall, den der User abdecken will.)
- Kein drittes Report-Objekt, kein org-seitiger Report-Type-Aufbau.
- Sortierung absteigend nach Summe als Default im Report; User kann zusätzlich pro Spalte sortieren (AC5).

### ADR-5: FLS read-only, kein Edit für niemanden
Die PO-CRUD-Festlegung („kein Create/Edit/Delete über UI") wird umsatzkonfidentiell ausgelegt: das PS gewährt **nur Read** auf beide Felder; Edit wird für niemanden erteilt. Der Trigger schreibt im System-Kontext und umgeht FLS (Vorgang SCRUM-365, im PS-Description dokumentiert).

### ADR-6: Layout-Auswahl
Default- und „(Sales)"-Layout erhalten beide Felder oben (erste Section, erste Spalte, `Readonly`) — Target Group Vertrieb/KAM. Marketing/Support-Layouts bleiben unverändert.

## Governor-Limits
- 1 `GROUP BY`-SOQL + 1 `SELECT Account` + 1 `update` pro Trigger-Batch, unabhängig von Batchgröße (kein SOQL in Loop).
- Relevanz-Filter im Update-Branch reduziert Recomputes auf die tatsächlich betroffenen Accounts.
- Account-Update löst keinen Opportunity-Trigger aus → keine Rekursion.
- 200er-Batch-Test (TA-6) ist der Nachweis.

## Sharing
Keine Änderung am Sharing-Modell. Die neuen Felder erben die Account-Sichtbarkeit; Report `scope=organization` zeigt zusätzlich nur, was der Report-Nutzer datenseitig sehen darf; FLS des PS steuert die Sichtbarkeit der Werte (PO: nur Vertrieb/KAM/Admin → PS dementsprechend zuweisen).

## ⚠️ Befund — Org-Stufen (blocken die Implementierung NICHT)
1. **Lightning-Record-Page:** Das Repo trägt nur die Classic-Layouts; die „oben"-Platzierung auf der Lightning-Seite (AK6) ist ein **App-Builder-Schritt in der Org nach Phase-1-Deploy** → @devops-agent. FLS kommt aus dem Repo.
2. **PS-Zuweisung:** Deployment ≠ Zuweisung — `SCRUM416_OpenOpportunities` muss in der Org den Zielprofilen/Nutzern zugewiesen werden (Vertrieb, KAM, Admin) → @devops-agent. Ohne Zuweisung: Feld unsichtbar (PS-Assignment = 0 ⇒ FLS ungewährt).
3. **Report-Sharing:** Scope steht in Source (`organization`); wer den Report überhaupt öffnen darf, ist org-seitig (Report → Settings) → @devops-agent.

## Offene Punkte (blocken NICHT)
- [ ] PS-Namens-/Zuweisungsliste (konkrete Profile vs. Nutzer) → @devops-agent bei der Deployment-Phase.
- [ ] E2E-Report-Acceptance: Standardsortierung visuell verifizieren → @tester-agent.

---
**Freigabe:** Design ist vollständig; Story geht an @developer-agent (Column Implementierung). Die Repo-Files und dieses Doc sind die autoritative Build-Spec — nicht der Jira-Kommentar.
