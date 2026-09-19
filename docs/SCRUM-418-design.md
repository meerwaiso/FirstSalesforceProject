# SCRUM-418 — Architektur-Design (freigegeben)

**Autor:** architect-agent · 2026-09-18 · Survey-Basis `origin/master` @ a571e00
**Nachreichung 2026-09-19:** Original-Commit `266f638` war nie remote (nur lokal auf einem
nicht-gepushten Branch), PR #116 und master trugen die Datei daher nicht. Hingefügt auf
`origin/master`-Basis mit ADR-5-Korrektur (Kasten in Sektion Report); Übriges = Original unverändert.
**Autoritative Build-Spec.** Dieses Dokument ist die maßgebliche Bauprozedur; der
Jira-Kommentar verweist hierauf. Wo Jira-Markup Identifikatoren verfälscht, gelten
die hier genannten Pfade/Feldnamen und die Repo-Dateien.

---

## Ziel

Auf jedem Case sichtbar machen, ob und wie oft er wiederaufgemacht wurde (Zähler ab 0)
und wann zuletzt — automatisch, sofort beim Wiederaufmachen — plus eine sortierte
Liste der am häufigsten wiederaufgemachten Cases der letzten drei Monate.

## Akzeptanzkriterien (PO)

- **AK1** Zahl („3“) + letztes Datum/Uhrzeit auf dem einzelnen Fall sichtbar.
- **AK2** Liste der letzten 3 Monate, sortiert absteigend nach Reaktivierungszahl, mit Kunde (Account/Contact) + Betreff (Subject).
- **AK3** Neue Fälle: Zähler 0, „Letzte Reaktivierung" leer.
- **AK4** Zunahme sofort nach dem Speichern des Statuswechsels (kein manuelles Trigger, kein Batch, kein nächtlicher Lauf).

**Ausdrücklich nicht enthalten:** Alert/Benachrichtigung, Erfassung von Gründen,
Blockade/Bestätigung beim Wiederaufmachen.

---

## Wiederaufmachen — exakte Definition (Definition of Ready)

`sf sobject describe -s Case` (Org) → Case.Status Picklist = **New (Default) / Working / Escalated / Closed**, `updateable: true`.

- **„offen" (OPEN)** = `New`, `Working`, `Escalated` (ALLES außer `Closed`).
- **„Wiederaufmachen" (REOPEN)** = `old.Status == 'Closed'` **UND** `new.Status ∈ OPEN`.
- **Erstes Öffnen zählt NICHT:** `old.Status != 'Closed'` ⇒ kein Inkrement.
- **Re-Entry-Schutz:** nach der Reaktivierung ist `new.Status != 'Closed'`, der Guard
  `old==Closed && new!=Closed` trifft nie wieder (zweiter Lauf: `old`= offen) ⇒ kein Zähl-Drift, keine After-Update-Zyklen.

Das ist dieselbe Klassifizierung wie Haus-Pattern SCRUM-365
(`CaseOpenCountTrigger.CLOSED_STATUS = 'Closed'`) — konsistent, keine zweite Status-Auslegung.

---

## Komponenten (Konkret, mit Pfaden)

1. **Feld `Reactivation_Count__c`** — `force-app/main/default/objects/Case/fields/Reactivation_Count__c.field-meta.xml`
   Integer, `precision=3, scale=0` (max ~999 genügt; 5/0 auch in Ordnung — Entwickler wählt ≥ 3/0 und dokumentiert),
   `defaultValue=0`, `updateable=false` (form-like), Label **„Reaktivierungszahl"**,
   Beschreibung „Automatisch gezählt: Anzahl Wiederaufmachungen eines geschlossenen Falls. Systemwartung, manuell nicht änderbar."
   → AK1 (Zahl), AK2 (Sortierung), AK3 (0 bei Neu).

2. **Feld `Last_Reactivation__c`** — `force-app/main/default/objects/Case/fields/Last_Reactivation__c.field-meta.xml`
   `type=DateTime` (Datum/Zeit exakt wie gefordert), `updateable=false`, Label **„Letzte Reaktivierung"**. NULL-initial (→ AK3 „leer").

3. **Trigger `CaseReactionTrigger`** — `force-app/main/default/triggers/CaseReactionTrigger.trigger` (+`-meta.xml`)
   `on Case (after update)`. Guard, dann inline `update Trigger.new` (Re-Entry, siehe ADR-1).

4. **Handler `CaseReactionHandler`** — `force-app/main/default/classes/CaseReactionHandler.cls` (+`.cls-meta.xml`)
   `public without sharing`, bulkified `recompute()`. (Klasse getrennt vom Trigger:
   1:1 wie `CaseOpenCountTrigger`, Test- und Rebuilder-kompatibel.)

5. **Permission Set (read-only FLS)** — `force-app/main/default/permissionsets/SCRUM418_Reactivation.permissionset-meta.xml`
   Pattern `SCRUM403_LastCaseDate` / `SCRUM365_OpenCasesCount`: 2× `fieldPermissions`,
   beide `readable=true, editable=false` auf `Case.Reactivation_Count__c` + `Case.Last_Reactivation__c`;
   `hasActivationRequired=false`, Label `SCRUM418_Reactivation`. **Keine Objekt-/Profil-Änderung.**

6. **Layout-Integration** — `force-app/main/default/layouts/Case-Case Layout.layout-meta.xml`
   In Sektion **`Überwachung`** (neben `Processing_Duration__c`, `Eskalationsstufe__c`, `Is_Overdue__c`)
   beide Felder einhängen: `Reactivation_Count__c`, `Last_Reactivation__c`. (Classic-Layout in Repo;
   Lightning-Platzierung = Org-Schritt, s. Befund.)

7. **Report (ausgefüllte Auswertung)** — `force-app/main/default/reports/Service/Wiedereroeffnungen_3Monate.report-meta.xml`
   `caseList`, absteigend sortiert nach `Case.Reactivation_Count__c`, AK2-Fenster 3 Monate.

8. **Apex-Tests**
   - `force-app/main/default/classes/SCRUM418CaseReactionTest.cls` — AK1/AK2-Sort/AK3/AK4-Re-Entry/Bulk (≥200).
   - `force-app/main/default/classes/SCRUM418CaseReactionFlsTest.cls` — FLS negativ/positiv (Pattern `SCRUM403LastCaseDateFlsTest`).

9. **Deployment-Manifest** — `manifest/` (Haus-Muster `scrNNN-phase3-apextests.xml` bzw. das nächstgelegene SCRUM-41x-Manifest).

*(Optionale Zusatz-Komponente, s. ADR-4: E2E-Spec für Report-AK2 — `tests/…/SCRUM-418_reactivation.spec.ts`,
shape `SCRUM-378_lead-nachfassliste.spec.ts`. Empfehlung: mitbringen.)*

---

## Interface / Pseudocode (exakt zu implementieren)

```apex
// CaseReactionHandler.cls  (public without sharing class CaseReactionHandler)
public static final String CLOSED_STATUS = 'Closed';   // 1:1 SCRUM-365

public static Integer recompute(List<Case> reopens) {
    if (reopens == null || reopens.isEmpty()) return 0;
    List<Case> toWrite = new List<Case>();
    for (Case c : reopens) {
        c.Reactivation_Count__c = (c.Reactivation_Count__c == null ? 0 : c.Reactivation_Count__c) + 1;
        c.Last_Reactivation__c  = System.now();         // = Zeitpunkt des Speicherns (AK1/AK4)
        toWrite.add(c);
    }
    if (!toWrite.isEmpty()) update toWrite;             // nach-Trigger-Re-Entry (see ADR-1)
    return toWrite.size();
}
```

```apex
// CaseReactionTrigger.trigger
trigger CaseReactionTrigger on Case (after update) {
    List<Case> reopens = new List<Case>();
    for (Integer i = 0; i < Trigger.new.size(); i++) {
        Case o = Trigger.old[i];  Case n = Trigger.new[i];
        if (n.Status != o.Status) {                       // nur bei Status-Wechsel
            if (o.Status == CaseReactionHandler.CLOSED_STATUS && n.Status != CaseReactionHandler.CLOSED_STATUS) {
                reopens.add(n);
            }
        }
    }
    if (!reopens.isEmpty()) CaseReactionHandler.recompute(reopens);
}
```

**Report (`Wiedereroeffnungen_3Monate.report-meta.xml`):**

```xml
<Report>
  <reportType>caseList</reportType>
  <name>Wiedereroeffnungen_3Monate</name>
  <format>Table</format>
  <scope>allusers</scope>
  <columns><field>CASE_NUMBER</field></columns>
  <columns><field>SUBJECT</field></columns>
  <columns><field>ACCOUNT</field></columns>      <!-- Kunde (Case.Account.Name) -->
  <columns><field>CONTACT</field></columns>      <!-- zugeordneter Kontakt -->
  <columns><field>Case.Reactivation_Count__c</field></columns>
  <columns><field>Case.Last_Reactivation__c</field></columns>
  <filter>
    <filterItems>
      <field>CREATED_DATE</field><operator>exqlast30days</operator>  <!-- ADR-5: 3-Monate-Fenster, exakte Operator-Notation per dry-run prüfen -->
    </filterItems>
    <filterItems>
      <field>Case.Last_Reactivation__c</field><operator>exqlast30days</operator>
    </filterItems>
    <logic>or</logic>
  </filter>
  <groupingsDown><field>Case.Reactivation_Count__c</field><sortOrder>Desc</sortOrder></groupingsDown>
</Report>
```
> **⚠️ ORIGINALE SPEC-VARIANTE — NICHT DEPLOYBAR (Korrektur, s. Kasten darunter).**
> `standardDateFilter` existiert im Report-Typ nicht, und relative `exqlast*`-Operatoren existieren
> in Report-Metadaten nicht (verifiziert per Dry-Run + Org-Metadaten; Belege:
> `docs/SCRUM-418-notizen-dev.md`). `timeFrameFilter` trägt genau EINEN `dateColumn` — das
> OR-Fenster (Erstellt **oder** Reaktiviert) ist in Report-Metadaten nicht darstellbar.

**Korrektur (Review-Verdict 19498, ADR-5-Abweichung akzeptiert, PO-kommuniziert): die ACTUAL
deployte Report-XML** (live in Test-Org und Prod-Org, Report `Wiedereroeffnungen_3Monate`):

```xml
<Report>
  <reportType>caseList</reportType>
  <name>Wiedereroeffnungen_3Monate</name>
  <format>Table</format>
  <scope>allusers</scope>
  <timeFrameFilter>
    <dateColumn>Case.Last_Reactivation__c</dateColumn>
    <interval>INTERVAL_LAST90</interval>
  </timeFrameFilter>
  <!-- Gruppen-Sortierung: absteigend auf Case.Reactivation_Count__c (sortOrder=Desc) -->
  <description>Wiederaufgemachte Cases der letzten 3 Monate (Reaktivierung in 90 Tagen),
       absteigend nach Reaktivierungszahl (SCRUM-418, AK2).</description>
  <!-- Spalten: CASE_NUMBER / SUBJECT / ACCOUNT / Case.Reactivation_Count__c / Case.Last_Reactivation__c -->
</Report>
```

> **Fenstereinschränkung (bewusst, dokumentiert):** „Wiederaufmachen in 90 Tagen" statt wörtlich
> „Erstellt **oder** Reaktiviert in 3 M". Frisch eröffnete, nie reaktivierte Fälle (Zähler 0)
> stehen dadurch NICHT in der Liste — für den Business-Zweck (am häufigsten Wiederaufgemachte
> oben) korrekt; die AK2-Sortierung bleibt 1:1. `exqlast30days` war nie ein gültiger Operator —
> der Platzhalter oben ist als historischer Designstand zu lesen.
> **Kunde** = primär `ACCOUNT`; falls der PO „Account/Contact" wörtlich beide will, zusätzlich `CONTACT`.

---

## Architektur-Entscheidungen (ADRs)

**ADR-1 · Methode = Apex `after update`-Trigger + Handler (kein Flow, kein Batch).**
Grund: AK4 verlangt „sofort nach dem Speichern, ohne manuellen Trigger/Batch". Ein
`after update`-Trigger feuert synchron im selben Transaktionsschritt → garantiert aktuell.
Flow: wird abgelehnt (Haus-Regel „Apex über Flow bei nicht-trivialer Logik"; Flow verursacht
wiederholt Schema-/Deploy-Probleme). Field-Formula: kann `OLD`-Status nicht sehen und ist
nicht für Rollups geeignet → fällt aus. **Re-Entry:** der nach-Trigger `update Trigger.new`
löscht einen neuen `after update`-Lauf; dort ist `old.Status` bereits offen ⇒ Guard=false ⇒
kein Inkrement, keine Rekursion, kein Governor-Loop.

**ADR-2 · Delta-Inkrement statt Voll-Recompute.**
Der Status-Wechsel `Closed→open` zählt exakt eine Wiederaufmachung; das Feld trägt den
Zähler direkt. Im Gegensatz zu SCRUM-365 (Kontakt-Aggregat, muss neu gezählt werden) gibt es
hier nichts, neu zu aggregieren — daher kein GROUP-BY, keine `aggregate`-Query. 0 SOQL pro
Reopen, 1 DML (`update Trigger.new`) pro Batch. Gouverneur: **kein SOQL-in-Loop, bulkified,
Bulk-200-sicher.**

**ADR-3 · read-only FLS via Permission Set (kein Profil-Edit).**
Beide Felder `updateable=false`/editable; Systemwrites laufen im System-Modus und umgehen FLS
(Haus-Pattern SCRUM-365/403). PS gewährt `readable=true, editable=false` → „wer Case-Lese hat,
sieht die Felder; niemand kann sie von Hand ändern". Kein neues Sharing nötig
(Felder gehören zum Case, OWD/sharing-Regeln bleiben unverändert — PO-Bestätigung).
PS-Zuweisung an das konkrete Service-POS = Org-Schritt (drin, s. Offene Punkte).

**ADR-4 · Kein Rebuilder (bewusste Abweichung vom Haus) + Bestand-Datierung.**
- **Bestand:** `defaultValue=0` initialisiert 548 Cases korrekt als „0 / leer" (AK3-konform).
- **Warum kein Rebuilder:** Wiederaufmachungen sind ein **Status-Verlauf**, der in der Org nicht
  rückrekonstruierbar ist — es gibt kein Standard- oder Custom-Feld, das „letzter Zeitpunkt, an
  dem Status ≠ Closed" hergibt. Ein Rebuilder könnte die Felder also nicht korrekt füllen.
  *(Im Gegensatz zu SCRUM-365/403/417, dort bestand das Feld aus gegenwärtigen/abgeleitbaren
  Fakten.)* Der Trigger hält die Felder ab dem Deploy-Moment; frühere Wiederaufmachungen sind
  NICHT nachvollziehbar und werden **nicht erfunden** (SCRUM-417-Lektion: „Live-Felder haben
  keine Vergangenheit" — plausible, aber falsche Werte sind schlimmer als NULL).
- **Folge fürs Rollout:** die 3-Monate-Liste zeigt erst ab dem Deploy echte Reaktivierungen.
  Für einen sauberen Start optional von DevOps ein offener, leerer Bestands-Zustand bestätigen lassen.

**ADR-5 · Report auf Standard-ReportType `caseList` (keine neue ReportType-Datei).**
Die Auswertung braucht nur Case-Felder + `Case.<custom>__c` — das liefert `caseList`
(1:1 wie `Ueberfaellige_Faelle.report-meta.xml`). Custom-Fields werden als
`Case.Reactivation_Count__c` angesprochen (House-Notation). `scope=allusers` = gesamte Service-
Auswertung; Report-level-Sharing ist Org-Schritt. OR-Fenster + Custom-Feld-Sortierung per dry-run
bestätigen (s.o.).

**ADR-6 · Feld-API-Namen.** `Reactivation_Count__c` / `Last_Reactivation__c` (englisch snake_case,
konsistent mit `Open_Cases_Count__c`, `Last_Case_Date__c`); die PO-Deutschschreibung bleibt als
**Label**. Kollisionsfrei (Org-Check).

---

## ⚠️ Befund (Org-/Repo-Analyse)

- **Case.Status Picklist** (Org, `sobject describe`): New/Working/Escalated/Closed — ADR-
  Definition baut darauf. Sollten neue Status in die Picklist kommen, muss der Guard
  „!= Closed" weiter gelten (robust); „offen" bleibt die Negation von Closed.
- **„Auf dem Case-Detailbildschirm sichtbar"** — das Repo trackt das Classic-
  `Case-Case Layout` (Sektion „Überwachung"). **Lightning FlexiPages sind NICHT im Repo**
  (Haus-Befund, z. B. SCRUM-394): Lightning-Sichtbarkeit = FLS (Repo, via PS) **+ App-Builder-
  Platzierung (Org-Schritt, DevOps)**. Tester verifiziert beides.
- **Bestand-Datierung (DR):** echte historische Reaktivierungszahlen sind aus der Org nicht
  rekonstruierbar → Felder starten bei 0/NULL. AK1–AK4 (alle *prospektiv*-formuliert) sind
  davon unbeeinträchtigt.

## Offene Punkte (blocken die Implementierung NICHT)

- [ ] FLS-PS (`SCRUM418_Reactivation`) an das konkrete Service-Permission-Set/Profile zuweisen → **@devops-agent** (Org-Schritt).
- [x] Report-Fenster + `caseList`-Sortierung nach Custom-Feld per Dry-Run bestätigt → **erledigt** (Belege `docs/SCRUM-418-notizen-dev.md`); Ergebnis = `timeFrameFilter INTERVAL_LAST90` statt OR-Fenster (Korrektur-Kasten, ADR-5-Abweichung akzeptiert, Review 19498).
- [ ] Report-opening-Sharing (wer den Report öffnen darf) über Report-Settings → **@devops-agent** (Org-Schritt).
- [ ] Lightning-Platzierung der zwei Felder (App Builder) → **@devops-agent** (Org-Schritt).

**Autoritative Build-Spec:** diese Datei. Story wird an **@developer-agent** übergeben (Spalte Implementierung).
