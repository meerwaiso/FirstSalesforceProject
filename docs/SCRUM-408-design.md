# SCRUM-408 — Prod-Backport Betreuungsstufe__c + driftsicheres Contact-Layout

**Status:** Freigegeben (User-Go 2026-09-11). **Autoritative Build-Spec** — diese Datei ist
die Einzige-Wahrheit für Namen, Pfade, XML und Deploy-Reihenfolge. Jira-Kommentare dürfen bei
Markup-Artefakten abweichen (bekannter Jira-Konverter-Vorfall). Der DevOps/Developer baut von hier.

**Ticket:** [SCRUM-408](https://meerwaisosmani.atlassian.net/browse/SCRUM-408)
**Entwurf:** Architect-Agent · 2026-09-11
**Org-Ziel:** **Prod-Org only** — Deploy **nur** durch DevOps-Agent (Ticket in *Release* + DevOps-Zuweisung).
Architect/PO deployen nirgends.

---

## 0. Scope — KURZ und exakt (vermessen, nicht geschätzt)

Das Ticket-Dox sprach von "9 Fehlenden Feldern in Prod". Das ist **falsch** (Jira-Kommentar 17805,
vom User bestätigt). FLS-**unabhängiger** exaktnamen-Retrieve in sauberes SFDX-Projekt
(`sf project retrieve start --metadata "CustomField:Contact.<Name>"`, FLS-filtrierte
`sobject describe`/`ui-api` liefern hier falsch "fehlt") ergibt (verifiziert 2026-09-11):

- **11/12** Custom Fields des Contact-Layouts sind **SCHON** in Prod.
- **1 Feld schema-abwesend:** `Betreuungsstufe__c` (SCRUM-396, Text-Formel, read-only).
  `Last_Case_Date__c` + `Time_Since_Last_Case__c` (SCRUM-403) sind **vorhanden** — nur aus dem **Layout** fehlt.

**Echter Scope (3 Schritte, alles Deploy/Assign, kein neues Code):**
1. Feld `Betreuungsstufe__c` + FLS-PS `SCRUM396_Betreuungsstufe` → Prod.
2. Driftsicheres Layout: die 3 fehlenden Feld-Blöcke in die Sektion "Offene Faelle" eintragen (live-Layout-Basis, **NICHT** die committed-Repo-Version).
3. FLS-PS `SCRUM396_Betreuungsstufe` den Prod-User(s) zuweisen.

**NICHT nötig:** Trigger-Deploy — `CaseOpenCountTrigger` (SCRUM-365, befüllt `Open_Cases_Count__c`,
worüber die Formel rechnet) ist **bereits in Prod** (Retrieve verifiziert 2026-09-11). Kein Apex/Flow.
Kein neues FLS-Design — das PS existiert auf master.

---

## 1. ADR-1: Driftsichere Layout-Deployment = live-Layout, nicht Master-Datei

**Entscheidung:** Das **committierte** `master`-Contact-Layout wird **NICHT** in Prod deployt.
Statt dessen live-Prod-Layout retrieven, **genau 3 Feld-Blöcke** eintragen, nur dieses eine Layout deployen.

**Warum (gemessen, 2026-09-11):**

| Merkmal | committed master-Datei | live Prod-Layout |
|---|---|---|
| Custom-Field-Referenzen | 12 | 9 (3 fehlen: Betreuungsstufe/Last_Case_Date/Time_Since_Last_Case) |
| `platformActionList*` | **0** | **25** |
| `summaryLayout` | **0** | **2** |
| `<label>` | 6 | 6 |
| `customButtons` | 1 | 1 |

Die committed-Repo-Datei ist eine **reduzierte/hand gepflegte Variante** ohne Lightning
`platformActionList`/`summaryLayout`. Würde man sie in Prod deployen, würden **alle 25
`platformActionListItems` + 2 `summaryLayout`-Blöcke gelöscht** — exakt das SCRUM-403-Drift-Unfallmuster.
**Die live-Layout-Basis behält alle Lightning-Aktionen.** Deshalb: live retrieve → 3 Blöcke ergänzen → deploy.

(Die 11 vorhandenen Felder + die 10 Standardfelder sind in master und live **identisch**; der einzige
Inhalt-Differenz im Feldbereich sind die 3 fehlenden Blöcke. Labels: identisch, 6=6. customButtons: identisch, `Rebuild_Offene_Faelle` in beiden.)

---

## 2. Drift-sichere Layout-Ergänzung (exakt 3 Feld-Blöcke)

Basis = **live Prod-Layout** (FullName `Contact-Contact Layout`, verifiziert per Tooling `Layout WHERE Name='Contact Layout'`).
Sektion "Offene Faelle" (`style TwoColumnsTopToBottom`) — heute:

```
Col1: Open_Cases_Zähler__c          (nur Open_Cases_Count__c)
Col2: Open_Cases_Rating__c          (nur Open_Cases_Rating__c)
```

Zielform (corresponds to master, drift-safe):

```
Col1: Open_Cases_Count__c,  + Last_Case_Date__c
Col2: Open_Cases_Rating__c, + Betreuungsstufe__c, + Time_Since_Last_Case__c
```

**Genau diese 3 `<layoutItems>` einfügen, alles `behavior=Readonly`:**

- **Col1** — direkt **nach** `</layoutItems>` von `Open_Cases_Count__c`:
  ```xml
  <layoutItems>
      <behavior>Readonly</behavior>
      <field>Last_Case_Date__c</field>
  </layoutItems>
  ```
- **Col2** — direkt **nach** `</layoutItems>` von `Open_Cases_Rating__c` (Reihenfolge Betreuungsstufe, dann Time_Since):
  ```xml
  <layoutItems>
      <behavior>Readonly</behavior>
      <field>Betreuungsstufe__c</field>
  </layoutItems>
  <layoutItems>
      <behavior>Readonly</behavior>
      <field>Time_Since_Last_Case__c</field>
  </layoutItems>
  ```

**Nichts anderes** im Layout ändern. Kein `platformActionList`/`summaryLayout`/`customButtons`/sonstige
Sektionen anfassen. Ergebnis muss `git diff` = **genau 3 neue `layoutItems`** zeigen.

- **AC-T1:** `git diff` des Layout-Files = **genau 3** neue `<layoutItems>`-Blöcke, nichts anderes.

---

## 3. Feld + FLS-PS (alles schon auf master — nur deployen)

### 3.1 `Contact.Betreuungsstufe__c` (SCRUM-396) — bereits auf master
Read-only Text-Formel. **Kein** `<length>` (Formel, deploy-geprüftes Haus-Muster SCRUM-394/403/405):

```xml
<formula>IF(Open_Cases_Count__c &gt;= 3, &quot;hoch&quot;, IF(Open_Cases_Count__c &gt;= 1, &quot;normal&quot;, &quot;keine&quot;))</formula>
<formulaTreatBlanksAs>BlankAsZero</formulaTreatBlanksAs>
<type>Text</type>
<required>false</required>
```

Kein Infix-`AND`/`OR` in der Formel (hier gar keins) — nur verschachtelte `IF()`. XML: `<` bleibt `&lt;`.

### 3.2 FLS-PS `SCRUM396_Betreuungsstufe` — bereits auf master

```xml
<fieldPermissions>
    <editable>false</editable>
    <field>Contact.Betreuungsstufe__c</field>
    <readable>true</readable>
</fieldPermissions>
```

read-only, `hasActivationRequired=false`. **Kein** Profile-Edit, **kein** neues FLS-Design.

---

## 4. Deploy-Reihenfolge + Read-back-Plan (verbindlich, Prod-Org, nur DevOps)

"Deploy" ≠ "rendert" — jeder Schritt wird **nach** dem Deploy via Read-back aus der Org bestätigt,
**vor** dem nächsten. (FLS-filtrierte `sobject describe`/`ui-api` sind hier **nicht** verlässlich —
Präsenz immer per exaktnamen-Retrieve in sauberes Projekt prüfen.)

| # | Schritt | Aktion | Read-back (Beweis) |
|---|---------|--------|--------------------|
| 0 | **Pre-Flight** | CI grün (Lint, Smoke, **Prod-Org Drift-Gate**). Layout-`FullName` = `Contact-Contact Layout` (Tooling `SELECT FullName, Name FROM Layout WHERE Name='Contact Layout'`). | CI grün; FullName dokumentiert |
| 1 | **Feld+Trigger-Präsenz prüfen** | (nur Nachweis, kein Deploy) | `Betreuungsstufe__c` ABSENT, `CaseOpenCountTrigger` + `Open_Cases_Count__c` PRESENT — exaktnamen-Retrieve in sauberes SFDX-Projekt, 1 Feld pro Call |
| 2 | **Feld + PS deployen** | `sf project deploy start -o Prod-Org --manifest manifest/scr408-phase1-field.xml` (Feld `Contact.Betreuungsstufe__c` + PS `SCRUM396_Betreuungsstufe`) | Deploy 2/2 erfolgreich; danach exaktnamen-Retrieve `Betreuungsstufe__c` → **PRESENT** |
| 3 | **PS zuordnen** | `sf org permission assign -o Prod-Org --permission-set SCRUM396_Betreuungsstufe --assignee <user>` für jeden Ziel-User (s.u.) | `SELECT PermissionSet.Name, Assignee.Username FROM PermissionSetAssignment WHERE PermissionSet.Name='SCRUM396_Betreuungsstufe'` → 1 Zeile pro User |
| 4 | **Live-Layout retrieve** | `sf project retrieve start --metadata "Layout:Contact-Contact Layout" -o Prod-Org` → landet in `force-app/main/default/layouts/Contact-Contact Layout.layout-meta.xml` | Retrieve `Status: Succeeded`, 1 Layout; `git diff --stat` zeigt **nur** die 3 Blöcke (AC-T1) |
| 5 | **Layout-Edit (3 Blöcke)** | §2 eintragen, Commit, PR auf Branch `feature/scr408-prod-backport` | `git diff` = genau 3 neue `<layoutItems>` |
| 6 | **Layout validate** | `sf project deploy validate -o Prod-Org --manifest manifest/scr408-layout.xml` | validate grün, **keine** Feld-/Layout-Fehler |
| 7 | **Layout deploy** | `sf project deploy start -o Prod-Org --manifest manifest/scr408-layout.xml` (NUR `Layout:Contact-Contact Layout`) | Deploy 1/1 Layout erfolgreich; **kein** Verlust der 25 `platformActionListItems` (Read-back: live-Layout hat weiterhin 25 + 2 summaryLayout) |
| 8 | **ui-api positiv (Lightning rendert)** | Als **zugewiesener** User: `GET /services/data/v62.0/ui-api/record-ui/{ContactId}?layoutTypes=Full&modes=View` für Kontakt **mit** offenen Fällen | `Betreuungsstufe__c` **und** `Last_Case_Date__c` **und** `Time_Since_Last_Case__c` in Response, Werte korrekt → rendert bewiesen |
| 9 | **Negativ-Fall / Aufräumen** | Test-Kontakt (falls in Schritt 8 neu angelegt) entfernen, Aufräumen dokumentiert. | Kontakt weg |

**Rollback (Fehler 7/8):** Layout ohne die 3 Blöcke re-deployen (aus dem vorherigen Retrieve-Stand).
Keine Daten, kein Feld verloren — nur 3 Layout-Zeilen. (Feld/PS-Rollback separat: Feld nur, wenn es
noch nirgendwo referenziert wird — i. d. R. bei reiner Layout-Umkehr NICHT nötig.)

---

## 5. FLS-Zuweisung — Ziel-User-Satz

`Betreuungsstufe__c`, `Last_Case_Date__c`, `Time_Since_Last_Case__c` stehen **alle drei in der
gleichen** Sektion "Offene Faelle". Damit die Sektion in Lightning **konsistent** rendert, muss der
Ziel-User jede der drei sichtbar haben.

- `SCRUM403_LastCaseDate` (deckt Last_Case_Date + Time_Since) ist in Prod **bereits** zugewiesen an:
  `devops-agent@cline.de`, `epic.b2c4330b9cb1@orgfarm.salesforce.com`, `meerwais.osmani.3ecaf61ebe28@agentforce.com` (verifiziert 2026-09-11).
- **Regel (Default, für DevOps/PO zu bestätigen):** `SCRUM396_Betreuungsstufe` an **genau dieselbe** User-Menge wie `SCRUM403_LastCaseDate` zuweisen → Offene-Faelle-Sektion rendert ohne "Feld fehlt wegen FLS"-Löcher.
  - CLI target-org user (`devops-agent@cline.de`) **und** der menschliche Test-Account — beide sind in der 403-Menge (Guardrail: PS deployen = nur die Hälfte; Assign + 1-Feld-Read-back via echter Session ist Pflicht).

**Offene Bestätigung (nicht blockierend):** Falls ein **weiterer** Prod-User die Sektion brauchen
soll, nennt DevOps/PO den Namen vor Schritt 3. Default = 403-Menge.

---

## 6. Manifeste

### 6.1 `manifest/scr408-phase1-field.xml`
```xml
<?xml version="1.0" encoding="UTF-8"?>
<Package xmlns="http://soap.sforce.com/2006/04/metadata">
    <types>
        <members>Contact.Betreuungsstufe__c</members>
        <name>CustomField</name>
    </types>
    <types>
        <members>SCRUM396_Betreuungsstufe</members>
        <name>PermissionSet</name>
    </types>
    <version>67.0</version>
</Package>
```

### 6.2 `manifest/scr408-layout.xml`  (NUR das Layout — drift-safe)
```xml
<?xml version="1.0" encoding="UTF-8"?>
<Package xmlns="http://soap.sforce.com/2006/04/metadata">
    <types>
        <members>Layout:Contact-Contact Layout</members>
        <name>Layout</name>
    </types>
    <version>67.0</version>
</Package>
```
> `Layout:Contact-Contact Layout` ist die **retrieve-Bezeichnung** mit Bindestrich (verifiziert per
> Tooling `FullName`, SCRUM-407-Lektion: Wildcard `Contact.*` / Punkt-`Contact.Contact Layout`
> liefern "cannot be found" = Name-Mismatch, **kein** Permission-Fehler).

---

## 7. Wer macht was

| Rolle | Auftrag |
|---|---|
| **Architect** | Dieses Design + Read-back-Plan. Kein Deploy. |
| **Developer** | Schritt 4–5: live-Layout retrieve, **genau 3** Feld-Blöcke eintragen, Commit + PR auf `feature/scr408-prod-backport`. |
| **DevOps** | 0, 1, 2, 3, 6, 7 (Prod-Deploy). **Einzig** mit Prod-Deploy-Recht (Ticket in *Release*). |
| **Tester** | 8 (ui-api positiv, als zugewiesener User), 9 (Negativ/Aufräumen). **Kein** Playwright/Login auf Prod. |

---

## 8. Technical acceptance criteria (zusätzlich zu PO-AK)
- **AC-T1:** Layout `git diff` = **genau 3** neue `<layoutItems>`, nichts anderes.
- **AC-T2:** `Betreuungsstufe__c` exaktnamen-Retrieve → **PRESENT** (nach Schritt 2).
- **AC-T3:** `SCRUM396_Betreuungsstufe` → ≥ 1 `PermissionSetAssignment`-Zeile pro Ziel-User (Schritt 3).
- **AC-T4:** `sf project deploy validate` (Layout) grün, **keine** Feld-/Layout-Fehler.
- **AC-T5:** `sf project deploy start` (Layout) 1/1 erfolgreich; Read-back: live-Layout behält **25 platformActionListItems + 2 summaryLayout** (kein Drift-Verlust).
- **AC-T6:** `ui-api/record-ui` (zugewiesener User, Kontakt **mit** offenen Fällen): `Betreuungsstufe__c`, `Last_Case_Date__c`, `Time_Since_Last_Case__c` alle in Response mit korrekten Werten.
- **AC-T7:** Test-Kontakt (falls neu) **entfernt**, Aufräumen dokumentiert.

---

## 9. Risiko-Register

| Risiko | Likelihood | Mitigation |
|---|---|---|
| Committed master-Layout wird versehentlich deployed (löscht 25 platformActionList/2 summaryLayout) | mittel | **Nur** `manifest/scr408-layout.xml` deployen (1 Layout); AC-T5-Read-back zwingt Nachweis. Layout immer vom **live retrieve**, nie von committed Datei. |
| `sf project retrieve`-Feldbezeichnung falsch (Wildcard/Punkt) → "cannot be found" | niedrig | FullName via Tooling lesen (`Contact-Contact Layout`), dann Bindestrich-Bezeichnung `Layout:Contact-Contact Layout`. |
| FLS-filtrierter Read-back (`sobject describe`/`ui-api`) meldet "fehlt" → falsches Schluss | mittel | Präsenz **immer** per exaktnamen-Retrieve in sauberes SFDX-Projekt; `ui-api` **nur** für Sichtbarkeit (Schritt 8). |
| `Betreuungsstufe__c` rendert `keine`/leer obwohl Fall offen | niedrig | Formel rechnet über `Open_Cases_Count__c` — Trigger in Prod vorhanden; Wert via ui-api (Schritt 8) gegen eine offene Case prüfen. |
| Layout-Deploy scheitert auf fehlender Feld-Kennung | **entfällt** | Prä-Voraussetzung Schritt 2: `Betreuungsstufe__c` **vor** Layout deployen (Abhängigkeit 396 nach 365 — 365 vorhanden). |

---

## 10. Handoff

**Branch:** `feature/scr408-prod-backport` (neu von `master`).
**Developer:** Schritt 4–5 (live-Layout retrieve + 3 Blöcke + PR), dann PR-Link + Branch in Jira,
Ticket an Architect zurück in "Review" (Transition **31** = *In Überprüfung*), Architect-Agent zuweisen.
**Nichts anderes** anfassen: keine committed-Layout-Version, keine anderen Felder, keine PS-Änderungen
außer `SCRUM396_Betreuungsstufe`.
