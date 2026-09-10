# SCRUM-407 — Design: Driftsicheres Prod-Contact-Layout (Pfad A)

**Status:** Freigegeben für Implementierung (PO-OK, Jira-Kommentar 17732, 2026-09-10)  
**Ticket:** SCRUM-407 (*Blocks*-Link zu SCRUM-405)  
**Autor:** Architect-Agent · 2026-09-10  
**Org-Ziel:** Prod-Org (Deploy nur durch DevOps; Architect vermisst read-only)  
**Gilt für:** Nur Pfad A. Pfad B (8-Ticket-Backport) = **SCRUM-408**, eigenes Ticket.

---

## 0. Scope (PO-Entscheidung 17732)

Pfad A ist der komplette Scope von SCRUM-407. Er erfüllt **AC 7 von SCRUM-405**  
(„Firmennummer rendert direkt am Kontakt in Lightning + Classic") drift-sicher,  
ohne die anderen fehlenden Felder einzubeziehen.

---

## 1. Goal

`Firmen_Telefonnummer__c` (bereits in Prod: Feld + Formula `Account.Phone` + Label  
„Telefonnummer der Firma" + FLS-PS + 1 Assignee — alles Read-back'd) wird in das  
**live Prod-Contact-Layout** eingetragen und nur dieses Layout zurückdeployet.  
Nichts anderes ändert sich.

---

## 2. Measured Prod-Inventory (read-only, 2026-09-10)

### 2.1 SCRUM-405 in Prod — vollständig bis auf das Layout

| Artefakt | Prod-Status | Evidence |
|----------|-------------|----------|
| `Contact.Firmen_Telefonnummer__c` | ✅ Feld, Formula `Account.Phone`, Label korrekt | `sobject describe`, Live-SOQL ADR-5 |
| FLS-PS `SCRUM405_FirmenTelefonnummer` | ✅ vorhanden, 1 Assignee (Prod-User) | `PermissionSetAssignment` |

→ **405 fehlt NICHTS außer die Layout-Zeile.**

### 2.2 Master-Contact-Layout vs. Prod (9 Felder fehlen — Hintergrund, **nicht** Teil von 407)

Das commitierte `master`-Layout referenziert 11 Custom Fields. In Prod sind nur 2  
davon vorhanden (403). Die anderen 9 — aus **acht** Tickets (314, 344, 353, 359, 365,  
370, 396 + WebLink 367) — sind noch nicht in Prod. **SCRUM-408** behandelt den  
Backport dieser Felder. Für 407 ist nur relevant, dass das `master`-Layout  
drumsicher **nicht** deploybar ist: Es referenziert Felder, die in Prod fehlen.

| Feld (API-Name) | In Prod? | Herkunft-Ticket | FLS-PS auf master |
|-----------------|----------|-----------------|-------------------|
| `Last_Case_Date__c` | ✅ | SCRUM-403 | SCRUM403_LastCaseDate |
| `Time_Since_Last_Case__c` | ✅ | SCRUM-403 | SCRUM403_LastCaseDate |
| `Betreuungsstufe__c` | ❌ | **SCRUM-396** (Formula: `IF(Open_Cases_Count__c>=3, "hoch", …)`) | SCRUM396_Betreuungsstufe |
| `Open_Cases_Count__c` | ❌ | **SCRUM-365** (Number, trigger-befüllt) | SCRUM365_OpenCasesCount |
| `Open_Cases_Rating__c` | ❌ | **SCRUM-370** (Picklist) | SCRUM365_OpenCasesCount |
| `ConsentDate__c` | ❌ | **SCRUM-359** (Date) | SCRUM359_NewsletterConsent |
| `NewsletterConsent__c` | ❌ | **SCRUM-359** (Checkbox) | SCRUM359_NewsletterConsent |
| `Friendly__c` | ❌ | **SCRUM-314** (Text) | SCRUM314_ContractFields |
| `Additional_Comment__c` | ❌ | **SCRUM-314** (LongTextArea) | SCRUM314_ContractFields |
| `Detailed_Comment__c` | ❌ | **SCRUM-344** (Text 255) | SCRUM344_DetailedComment |
| `FeldFinoIlsede__c` | ❌ | **SCRUM-353** (Text 255) | SCRUM353_FeldFinoIlsede |
| WebLink `Rebuild_Offene_Faelle` | ❌ | **SCRUM-367** (Objekt `CaseRebuildRun__c` in Prod ✅) | n/a |

→ **Alle 9 Felder haben bereits FLS-PS auf master** — der Backport (408) ist reines  
Deploy + Assign, kein neues FLS-Design.

### 2.3 Harte Formel-Abhängigkeit (relevant nur für 408)

```
Betreuungsstufe__c (396)
  └─ Formula: IF(Open_Cases_Count__c >= 3, "hoch", …)
       └─ Open_Cases_Count__c (365)  ← in Prod FELD-ABWESENT
            └─ CaseOpenCountTrigger (365)  ← befüllt Open_Cases_Count__c
```
396 deployt **nicht** vor 365.

---

## 3. ADR-1: Live-Prod-Layout statt master-Layout

**Entscheidung:** 407 deployt das **Master-Contact-Layout von GitHub NICHT**.  
Es retrieve-t das **tatsächlich in Prod aktive Layout** und ergänzt dort genau  
ein Feld.

**Begründung:**

1. **Drift-Sicherheit** — Das Master-Layout ist eine 8-Ticket-Union und referenziert  
   9 Felder, die in Prod fehlen. Deployen würde `validate` fehlschlagen  
   (Feld-Referenz-Error) und/oder — falls es doch durchkommt — 9 to-dead-Fields  
   in ein echtes Prod-Layout schreiben (SCRUM-403-Drift-Lektion).

2. **Scope-Fit** — 405 ist die Firmennummer. Seine Schuld ist ein Feld.  
   Pfad A deployt ein Feld. Die 8 anderen Tickets sind eigene Releases.

3. **Kein FLS-Design nötig** — `Firmen_Telefonnummer__c` hat seine FLS-PS  
   bereits (`SCRUM405_FirmenTelefonnummer`, 1 Assignee). Keine neue Berechtigung.

4. **AC 7 erfüllt** — Ein Feld im Layout, das Lightning tatsächlich rendert,  
   erfüllt „Firmennummer rendert am Kontakt" unabhängig von den anderen Feldern.

**Einordnung:** Der PO hatte 407 als „396-Feld + Layout-Deploy" geframed.  
Die Messung zeigt, dass das Layout an **neun** Feldern blockiert ist (acht Tickets).  
Pfad A ist die korrekte, minimale Ausprägung von 407. Der Rest ist 408.

---

## 4. Deploy-Reihenfolge — Pfad A

### 4.1 Vorher-/Nachher-Read-back-Plan (verbindlich)

Jeder Schritt wird **nach** dem Deploy mit Read-back aus der Org bestätigt, **vor**  
dem nächsten Schritt. „Deploy" ≠ „Rendert" — nur der ui-api-Read-back beweist Sichtbarkeit.

| # | Schritt | Wer | Aktion | Read-back (Beweis) |
|---|---------|-----|--------|--------------------|
| 0 | **Pre-Flight** | DevOps | CI grün (Lint, Smoke, Drift-Gate); PR gemerged. **Layout-DeveloperName ermitteln:** `sf project retrieve start --metadata "Layout:Contact.*" -o Prod-Org --dry-run` oder `sf data query -t -o Prod-Org -q "SELECT Id, DeveloperName, Label FROM LayoutEntity ..."` — welcher Kontakt-Layout DeveloperName ist in Prod aktiv? | CI grün; Layout-Name dokumentiert im Ticket |
| 1 | **Live-Layout retrieven** | DevOps | `sf project retrieve start --metadata "Layout:Contact.<DeveloperName>" -o Prod-Org` → das **wirkliche** Prod-Layout landet im Repo. **Vorher-Dokumentation:** `git diff --stat` — welches Layout ist vorher im repo? (Master-Version). | Retrieve Exit 0; neue `Contact-Contact Layout.layout-meta.xml` liegt in `force-app/main/default/layouts/`; **`git diff` zeigt die Abweichung zwischen Master- und Prod-Version** → DevOps dokumentiert beide im Ticket |
| 2 | **Feld eintragen** | Developer | Im **retrieften** Layout: `<field>Firmen_Telefonnummer__c</field>` in die „Contact Information"-Sektion, Spalte 2, direkt nach `<field>Phone</field>` einfügen. **Nur diese eine Zeile.** | `git diff -- "force-app/main/default/layouts/Contact-Contact Layout.layout-meta.xml"` zeigt **genau eine** neue Zeile (`+<field>Firmen_Telefonnummer__c</field>`), nichts anderes |
| 3 | **validate** | DevOps | `sf project deploy validate --target-org Prod-Org --manifest manifest/scr407-layout.xml` | validate grün, **keine** Feld-Fehler → Layout referenziert nur in-Prod-existinges |
| 4 | **deploy** | DevOps | `sf project deploy start --target-org Prod-Org --manifest manifest/scr407-layout.xml` | Deploy: 1/1 Layout erfolgreich |
| 5 | **FLS-Read-back** | DevOps | `sf data query -t -o Prod-Org -q "SELECT Assignee.Username, PermissionSet.Name FROM PermissionSetAssignment WHERE PermissionSet.Name='SCRUM405_FirmenTelefonnummer'"` | ≥ 1 Zeile zurück |
| 6 | **ui-api-Read-back (positiv)** | Tester/DevOps | `sf api request rest "/services/data/v62.0/ui-api/record-ui/{Contact.Id}?layoutTypes=Full&modes=View"` — **als User mit `SCRUM405_FirmenTelefonnummer`** (Prod-User). Ein Kontakt **mit** Account. | Response enthält `Firmen_Telefonnummer__c` in der Contact-Section, Wert = `Account.Phone` → **Rendert** bewiesen |
| 7 | **Negativ-Fall (S4)** | Tester | 1 Test-Kontakt **ohne** Account in Prod anlegen (Dokumentation + Aufräumen danach). `ui-api` für diesen Kontakt. | `Firmen_Telefonnummer__c` = `null` / leer in der Response |
| 8 | **Rollback-Check (optional, nur bei Auffälligkeit)** | DevOps | `Firmen_Telefonnummer__c` aus dem Layout entfernen, re-deploy, `ui-api` erneut prüfen. | Feld wieder nicht in Response |

**Rollback-Plan (im Fehlerfall 5/6/7):** Layout ohne `Firmen_Telefonnummer__c`  
re-deployen (1 Feld entfernen). Keine Daten, keine Felder verloren — nur eine  
Layout-Zeile.

### 4.2 Manifest `manifest/scr407-layout.xml`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<Package xmlns="http://soap.sforce.com/2006/04/metadata">
  <types>
    <members>Layout:Contact.Contact Layout</members>
    <!-- ⚠️ DeveloperName aus Schritt 0 eintragen!
         Falls der Live-Prod-Layout einen anderen Namen hat, hier ersetzen. -->
  </types>
  <version>62.0</version>
</Package>
```

### 4.3 Wer macht was

| Rolle | Auftrag |
|-------|---------|
| **Architect** | Dieses Design + Read-back-Plan. Kein Deploy. |
| **Developer** | Schritt 2: `Firmen_Telefonnummer__c` ins **retrievene** Layout eintragen (1 Zeile), PR auf Branch `feature/scr407-prod-layout-405` |
| **DevOps** | Schritt 0 (Pre-Flight + Layout-Name), 1 (retrieve), 3 (validate), 4 (deploy), 5 (FLS-Read-back). **Einzig** mit Prod-Deploy-Recht. |
| **Tester** | Schritt 6 (positiv ui-api), 7 (Negativ-Fall, inkl. Test-Kontakt anlegen + Aufräumen), Final-AC7-UI-Check |

### 4.4 UI-Check per `ui-api` (Tester-Frage 17699, Antwort)

**Kein** Playwright auf Prod, **keine** Login-Seite, **kein** sid-Cookie. Der Beweis
„rendert in Lightning" kommt aus der **gleichen API**, die Lightning selbst rendert:

```
GET /services/data/v62.0/ui-api/record-ui/{Contact.ID}?layoutTypes=Full&modes=View
```

- Gespeichert **als der User mit** `SCRUM405_FirmenTelefonnummer` (der prod User,
  der in 405-Step 5 geprüft wird). Die `ui-api`-Respektiert FLS: was hier NICHT
  erscheint, rendert auch NICHT. Der Call beantwortet Sichtbarkeit und Berechtigung
  gleichzeitig, ohne Browser.
- Test-Org-Playwright bleibt für alle anderen E2E-Anforderungen. Für die 407/405
  Prod-Abnahme ist `ui-api` der richtige Mechanismus.

### 4.5 Technical acceptance criteria (zusätzlich zu PO-AK)

- **AC-T1:** `git diff` (Schritt 2) = **genau eine** neue `<field>`-Zeile, keine anderen Änderungen im Layout-File.
- **AC-T2:** `sf project deploy validate` (Schritt 3) grün, **ohne** Feld-Referenz-Fehler.
- **AC-T3:** `sf project deploy start` (Schritt 4): 1/1 Layout erfolgreich.
- **AC-T4:** `ui-api/record-ui` für Kontakt **mit** Account: `Firmen_Telefonnummer__c` in Response, Wert = `Account.Phone`.
- **AC-T5:** `ui-api/record-ui` für Kontakt **ohne** Account (Test-Kontakt): `Firmen_Telefonnummer__c` = null/leer.
- **AC-T6:** `PermissionSetAssignment`-Query: `SCRUM405_FirmenTelefonnummer` ≥ 1 Assignee (vor Schritt 6).
- **AC-T7:** Test-Kontakt nach Schritt 7 **entfernt** (Aufräumen dokumentiert).

---

## 5. Risikoregister (Pfad A)

| Risiko | Likelihood | Mitigation |
|--------|-----------|------------|
| Live-Prod-Layout hat **anderen DeveloperName** als `Contact-Contact Layout` | mittel | Schritt 0 ermittelt den echten Namen; Manifest + retrieve-Parameter daran anpassen. DevOps dokumentiert den Namen. |
| `ui-api` zeigt das Feld **nicht** trotz erfolgreichem Deploy | niedrig | FLS-PS-Assignee prüfen (Schritt 5), Read-back als **genau der** zugewiesene User ausführen. Fehlt PS → `sf org permission assign`. |
| Retrieve holt **mehr** (anderes Prod-Live-Layout, andere Sektionen) | niedrig | `git diff` (AC-T1) muss **genau 1 Zeile** zeigen. Mehr → STOP, Scope-Review mit Architect. |
| Test-Kontakt lässt sich in Prod **nicht** anlegen (OWD) | niedrig | DevOps legt ihn als Admin an; Aufräumen dokumentiert. `ui-api`-Read-back funktioniert auch ohne OWD-Zugriff (FLS-genug). |
| `ui-api`-Version in Prod != v62.0 | niedrig | `sf api request rest` mit tatsächlichem API-Level der Org; `sf api runtime version` ermitteln. |

---

## 6. Offene Punkte (vor Start)

- [ ] Schritt 0: Echter **DeveloperName** des Live-Prod-Contact-Layouts ermitteln (DevOps, vor PR).
- [ ] Bestätigung: `SCRUM405_FirmenTelefonnummer` ist **noch** zugewiesen (Step 5-Read-back). Falls nicht, `sf org permission assign -o Prod-Org --assignee <user> --permission-set SCRUM405_FirmenTelefonnummer`.
- [ ] Branch-Name bestätigt: `feature/scr407-prod-layout-405` (Developer).

---

## 7. Handoff: Developer

**Branch:** `feature/scr407-prod-layout-405` (neu von `master`)

**Task (einzig):**
1. Warte auf DevOps: Live-Contact-Layout aus Prod retrieve (`sf project retrieve start --metadata "Layout:Contact.<DeveloperName>" -o Prod-Org`).
2. Im **retrievenen** File `force-app/main/default/layouts/Contact-<DeveloperName>.layout-meta.xml`: `<field>Firmen_Telefonnummer__c</field>` einfügen an die Position nach `<field>Phone</field>` in der „Contact Information"-Sektion (Spalte 2, `TwoColumnsTopToBottom`).
3. `git diff` prüfen: **genau eine** neue Zeile.
4. Commit + PR (Titel: `[Architect][SCRUM-407] Prod-Contact-Layout: Firmen_Telefonnummer__c eintragen`), Branch `feature/scr407-prod-layout-405`.
5. Jira-Kommentar mit PR-Link + Branch, Ticket an Architect zurück in „Review" (Transition 24 = *In Überprüfung*), Architect-Agent zuweisen.

**Nichts anderes anfassen.** Kein Master-Layout, keine anderen Felder, keine PS-Änderungen

