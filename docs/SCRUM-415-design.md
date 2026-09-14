# SCRUM-415 — Pfad B: Master auf Prod zurückziehen

**Produktentscheidung (PO, 18884): B.** API-Name `Is_Overdue__c` in den 7
Repo-Dateien, Label **„Inaktiv“ bleibt**. Keine neue Felder, keine Daten-
Migration, keine Änderung am SCRUM-319-Verhalten in Prod.

## ADR
- **Mechanismus: reiner Repo-Return + Label-only-Deploy.** Kein Apex/Flow/Flow-
  Change; kein `sf field rename` (existiert nicht). Die 7 Dateien referenzieren
  wieder das in Prod **existierende** Feld — die Drift entsteht dadurch, dass
  414 das Repo-Feld umbenannt hatte, Prod aber nie den 319-Release erhalten
  hat.
- **Layout-Deploy gehört dazu** (wichtig, 414-Lücke): Das 414-Prod-Manifest
  (`b8814e3`) hat das Layout **bewusst ausgelassen** (Referenz auf
  `Is_Inactive__c`). Prod-Träger des Opportunity-Layout fehlt deshalb die
  Section „Überschrittene Abschlüsse“ (414-Felder nicht platziert) + das
  319-Layout-Item trägt dort noch Label „Is Overdue“. Pfad B deployt das
  Layout einmal, beides auf einmal: Item-Label „Inaktiv“ + 414-Section
  (414-AC „sichtbar im Layout“ wird damit **in Prod** erfüllt — Gap, den ich
  bei der Review der 414-Prod-Fassung nicht genug hervorgehoben habe).

## 7 Repo-Dateien (alle: `Is_Inactive__c` → `Is_Overdue__c`, Label bleibt)
1. `force-app/main/default/objects/Opportunity/fields/Is_Inactive__c.field-meta.xml`
   → **File-Rename** auf `Is_Overdue__c.field-meta.xml` + `<fullName>Is_Overdue__c</fullName>`.
   Label `Inaktiv`, type Checkbox, defaultValue false, trackFeedHistory false —
   unverändert. Deploy aktualisiert das **existierende** Prod-Feld in-Place
   (Label „Is Overdue“ → „Inaktiv“).
2. `force-app/main/default/classes/OpportunityOverdueService.cls`
3. `force-app/main/default/classes/OpportunityOverdueResetHandler.cls`
4. `force-app/main/default/classes/SCRUM319OverdueOpportunityTest.cls`
5. `force-app/main/default/permissionsets/SCRUM319_OverdueOpportunity.permissionset-meta.xml`
6. `force-app/main/default/layouts/Opportunity-Opportunity Layout.layout-meta.xml`
   — **nur** das Item in der bestehenden Section: `Is_Inactive__c` →
   `Is_Overdue__c`. Die 414-Section „Überschrittene Abschlüsse“ bleibt
   exakt wie sie ist.
7. `force-app/main/default/triggers/OpportunityOverdueReset.trigger`
   — Kommentarzeile 1 (Logik unverändert).

Repo-weit: danach keine einzige `Is_Inactive__c`-Referenz auf `Opportunity`
(Control: `grep -r "Is_Inactive__c" force-app` → nur Account-Objekt
`Account.Is_Inactive__c`, anderes Objekt).

**NICHT anfassen:** `OpportunityOverdueScheduler.cls`,
`OpportunityOverdueNotification.cls` (referenzieren kein Feld),
414-Komponenten, `Case.Is_Overdue__c`.

## Deploy (Production)
- Neues Manifest `manifest/scr415-pathb-prod.xml`:
```
CustomField:     Opportunity.Is_Overdue__c
ApexClass:       OpportunityOverdueService, OpportunityOverdueResetHandler,
                 SCRUM319OverdueOpportunityTest
PermissionSet:   SCRUM319_OverdueOpportunity
Layout:          Opportunity-Opportunity Layout
ApexTrigger:     OpportunityOverdueReset
```
- Prod-Vorlauf: `sf project deploy validate --manifest manifest/scr415-pathb-prod.xml -o Prod-Org --test-level RunSpecifiedTests --tests SCRUM319OverdueOpportunityTest`
  → expect grün, **14/14** Tests ausführen (nicht skipped).
- Deploy: gleiches Manifest, dann **AC-Verifikation per Read-Back**:
  1. FieldDefinition-SOQL: `Is_Overdue__c` in Prod: Label = „Inaktiv“, type
     Checkbox (in-Place-Update, **keine** zweiten Felder, `Is_Inactive__c`
     existiert in Prod nachher weiterhin NICHT).
  2. `sf project deploy validate --source-dir force-app -o Prod-Org`
     (komplette App, RunSpecifiedTests auf relevanten Klassen) → **grün** —
     AC „komplette force-app-Validierung gegen Prod grün“.
  3. Layout-Read-Back (UI-API `record-ui` als User ohne 414-PS ist
     FLS-blind → besser: FlexiPage/record-ui als @user mit PS): Section
     „Überschrittene Abschlüsse“ mit beiden 414-Feldern + 319-Item mit Label
     „Inaktiv“.
  4. PS-Zuweisungen `SCRUM319_OverdueOpportunity`: unverändert (Deploy
     aktualisiert das PS, Assignments bleiben — Read-Back der
     Assignment-Liste).
- FLS: neues PS-XML referenziert `Opportunity.Is_Overdue__c` = **das** in Prod
  bestehende Feld → kein FLS-Gap, keine Re-Assignment nötig.

## Governor-Limits / Risiken
- Keine Apex-Logik-Änderung (Namen-Return), keine SOQL-Änderung, keine neue
  Governor-Risiken.
- Einziges Risiko: Deploy überschreibt Prod-Trigger/Classes durch die 1:1
  identische (nur kommentierte/greifende) Master-Version — erwartbar,
  durch 14/14 Regression gedeckt.
- `Is_Overdue__c`-Daten in Prod bleiben unberührt (same Field, kein Move).

## Technisches AC-Mapping (Developer/Tester)
- **T1:** 7 Dateien auf `Is_Overdue__c`, Label „Inaktiv“ (File-Rename inkl.
  `<fullName>`).
- **T2:** Control-Grep: keine Opportunity-`Is_Inactive__c`-Referenz mehr.
- **T3:** Manifest `scr415-pathb-prod.xml` deployed, validate grün, 14/14
  SCRUM-319 in Prod.
- **T4:** Komplette `force-app`-Validierung gegen Prod grün.
- **T5:** Prod-Layout: Section „Überschrittene Abschlüsse“ sichtbar
  (@user/Tester per UI-Read-Back) + 319-Item Label „Inaktiv“.
- **T6:** 414-Funktion in Prod unbeeinflusst (Quick-Check: 13 offene
  überfällig, 0 geschlossene, `Is_Close_Date_Overdue__c`-ListView intakt).
