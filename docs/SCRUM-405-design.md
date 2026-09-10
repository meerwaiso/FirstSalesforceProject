# SCRUM-405 — Kontakt: Telefonnummer der Firma (Account.Phone) direkt am Kontakt

**Status:** Freigegeben für Implementierung (Architect). **Autoritative Build-Spec** — diese Datei ist die
Einzig-Wahrheit für Names, Pfade und XML; Jira-Kommentare dürfen bei Markup-Artefakten abweichen (bekannter
Jira-Konverter-Vorfall: doppelte Unterstriche → Bold, `+`/`-`-Elemente, XML-Endtags). Der Developer baut von hier.

**Ticket:** [SCRUM-405](https://meerwaisosmani.atlassian.net/browse/SCRUM-405) (Sprint 68)
**Entwurf:** architect-agent, 2026-09-10

---

## 1. Ziel

Vertriebs- und Service-Mitarbeiter sehen am Contact die **Telefonnummer der zugeordneten Firma
(Account.Phone)** direkt im Kontakt-Layout, gleich neben der eigenen Durchwahl — automatisch abgeleitet, für
niemanden manuell änderbar, immer aktuell (live-Referenz, nichts doppelt gepflegt).

## 2. ADR

### ADR-1: Text-Formel mit Lookup-Cross-Reference — kein Apex, kein Flow, kein Roll-up

**Entscheidung: reine deklarative Text-Formel `Account.PHONE` am Contact.**

| Option | Bewertung |
|---|---|
| **Text-Formel `Account.PHONE`** | **Genommen.** `Contact.AccountId` ist die Standard-Lookup-Relation zu Account; in Formeln wird das übergeordnete Konto über den Relationsnamen `Account` direkt referenziert (`Account.<Feld>` — `__r` ist hier NICHT nötig, `__r` gilt nur für benannte Custom-Lookups). Die Formel ist eine **live-Referenz**: sie zeigt immer den aktuellen `Account.Phone`. Deckt alle 7 Szenarien nativ: mit/ohne Firma, ohne Nummer, Firma-Nummer geändert (Re-Query zeigt neuen Wert), Umbuchung (neu aufgelöst auf den neuen Account). Zero Code, zero Deploy-Profil, immer in Sync — exakt der PO-Wunsch „sofort die neue stehen, nichts doppelt pflegen". |
| Apex-Trigger | **Verworfen.** Würde `Account.Phone` in ein Contact-Feld *kopieren* → Zweitpflege, Re-Maintainance bei jeder Account-Änderung/Umbuchung nötig, Governor-Limit-Überlegung, genau das Gegenteil vom PO-Wunsch. |
| Flow (Record-Triggered) | **Verworfen.** Gleiche Kopier-Problematik + wiederholte Deploy-/Schema-Validierungsprobleme (Haus-Regel Apex/Formel over Flow). Ein Flow müßte auf Account-Update + Contact-Umbuchung hören, um das Feld aktuell zu halten — fragiler als eine Formel. |
| Roll-Up Reporting | **Verworfen.** Braucht Master-Detail (Contact→Account ist Lookup, kein Master-Detail); liefert keinen Textwert; überdimensioniert. |

**Folgerung:** keine Apex-/Flow-Logik → **keine Governor-Limit-Risiken, kein apiVersion, keine Naming-Konvention für Flow** (alle drei Punkte der Pre-Handoff-Checkliste sind für dieses Ticket durch „rein deklarativ, nicht zutreffend" abgehakt).

### ADR-2: Feldname & Typ

- **API-Name:** `Firmen_Telefonnummer__c` (PO-Vorschlag übernommen; konsistent mit vorhandenen deutschen API-Namen im Repo: `Betreuungsstufe__c`, `Reaktionsfrist__c`, `Erste_Rueckmeldung__c`; kein Umlaut im API-Namen).
- **Label:** `Telefonnummer der Firma` (exakte Nutzer-Schreibung aus PO/AC).
- **Typ:** `Text`-Formel (string-returning). **Kein `<length>`** (deploy-geprüftes Muster SCRUM-394/403, siehe ADR-1 in SCRUM-403-Doc), kein `precision`/`scale` (Number-only), `required=false`, `unique=false`, `externalId=false`.

**Formel (exakt, Salesforce-Formel — keine Infix-`AND`, hier gar keine):**

```
Account.PHONE
```

NULL-Semantik kommt **automatisch** aus der Relation — kein `IF(ISBLANK(...))`-Wrapper nötig:

| Fall | Ergebnis |
|---|---|
| Contact mit Account, Account.Phone gesetzt | `Account.PHONE` = die Nummer (Szenario 1) |
| Contact mit Account, Account.Phone leer | Relation existiert, `PHONE = null` → Feld leer (Szenario 2) |
| Contact ohne Account | Relation auflösbar zu `null` → `Account.PHONE = null` → Feld leer (Szenario 3) |
| Account.Phone geändert | Formel bei jeder Query neu ausgewertet → neuer Wert (Szenario 4) |
| Contact auf andere Firma umgebucht | `Account` zeigt auf den neuen Account → neue Nummer (Szenario 5) |

Text-Formel, die `null` zurückliefert, rendert leer (kein „N/A", keine 0) — exakt Szenario 2/3.

### ADR-3: FLS via Permission Set (Haus-Pattern SCRUM319/394/403/404)

`SCRUM405_FirmenTelefonnummer`, read-only (new field ist standardmäßig FLS-gated → additive Read-Grant reicht, kein Revoke-Profil nötig, kein Profile-Edit):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<PermissionSet xmlns="http://soap.sforce.com/2006/04/metadata">
    <fieldPermissions>
        <editable>false</editable>
        <field>Contact.Firmen_Telefonnummer__c</field>
        <readable>true</readable>
    </fieldPermissions>
    <hasActivationRequired>false</hasActivationRequired>
    <label>SCRUM405_FirmenTelefonnummer</label>
    <description>Read-FLS für Contact.Firmen_Telefonnummer__c (SCRUM-405). Read-only Formel über Account.Phone; kein Write-Zugriff.</description>
</PermissionSet>
```

### ADR-4: Sharing — keine Änderung

Verhält sich wie der Contact (PO-Bestätigung): keine Änderung an OWD, Sharing Rules oder Rollen-Hierarchie. Das Feld
leitet keinen neuen Datenzugriff ab, es spiegelt `Account.Phone`.

### ADR-5: ⚠️ Cross-Reference respektiert die Account-Eignung des Users (Annahme, nicht-Blockierend)

`Account.PHONE` ist eine **Cross-Object-Referenz**: ob der Wert tatsächlich sichtbar ist, hängt zusätzlich von der
**FLS- und Sharing-Zugriff des Users auf `Account.Phone`** ab (eine Formel „umgeht" nicht die Eignung auf dem
referenzierten Feld). In dieser Org sind alle Standard-Profile mit Contact-Lesezugriff (Sales/Service-Rep) zugleich
auch Account-lesend inkl. `Phone` → in der Praxis zeigt das Feld den Wert für alle intended Users und AC-1/5/7 treffen zu.
**Annahme, die @tester-agent mit einem representativen Service-Rep verifizieren soll** (siehe Offene Punkte). Ist sie in
einem Sonderprofil verletzt, bleibt das Feld dort korrekt leer — kein Datenleck, nur „kein Wert". Nicht blockierend.

## 3. Komponenten (Pfade)

1. **Neues Feld (Formel):** `force-app/main/default/objects/Contact/fields/Firmen_Telefonnummer__c.field-meta.xml`
2. **Layout-Integration:** `force-app/main/default/layouts/Contact-Contact Layout.layout-meta.xml` —
   Abschnitt **Contact Information**, **zweite Spalte, direkt nach `Phone`** (= „gleich neben der Durchwahl", PO-Wortlaut).
3. **FLS (Permission Set):** `force-app/main/default/permissionsets/SCRUM405_FirmenTelefonnummer.permissionset-meta.xml`
4. **Apex-Tests** (Value + FLS, Muster SCRUM-382/403):
   - `force-app/main/default/classes/SCRUM405FirmenTelefonnummerTest.cls`
   - `force-app/main/default/classes/SCRUM405FirmenTelefonnummerFlsTest.cls`

### 3.1 Feld (exakt)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Firmen_Telefonnummer__c</fullName>
    <description>Telefonnummer (Hauptnummer) des zugeordneten Accounts, automatisch übernommen aus Account.Phone (SCRUM-405). Read-only Formel — wird nie manuell gepflegt; ohne Firma oder ohne Firmennummer: leer.</description>
    <externalId>false</externalId>
    <formula>Account.PHONE</formula>
    <label>Telefonnummer der Firma</label>
    <required>false</required>
    <type>Text</type>
    <unique>false</unique>
</CustomField>
```

### 3.2 Layout-Eintrag (exakt, Einzug in zweite Spalte nach `<field>Phone</field>`-layoutItem)

```xml
<layoutItems>
    <behavior>Readonly</behavior>
    <field>Firmen_Telefonnummer__c</field>
</layoutItems>
```

**Einfüge-Stelle (eindeutig):** im `layoutSection` mit `<label>Contact Information</label>` (Style `TwoColumnsTopToBottom`),
im **zweiten** `layoutColumns` (der mit `Phone`, `HomePhone`, `MobilePhone`, …), als **nächstes** `layoutItems` direkt nach dem
`<field>Phone</field>`-Eintrag. `behavior=Readonly` (read-only Formel, Muster wie `Time_Since_Last_Case__c`).

### 3.3 Apex-Tests

- **`SCRUM405FirmenTelefonnummerTest`** (Value-Test, Muster **SCRUM-382** `Customer_Since_Days__c`): Formelfelder sind
  nicht auf dem in-memory-SObject nach DML → per Query zurücklesen. Szenarien:
  1. Contact mit Account (Phone gesetzt) → Feld = diese Nummer (AC 1).
  2. Formel-Eigenschaften: `isCalculated()==true` **und** `isUpdateable()==false` (AC 6).
  3. Contact mit Account ohne Phone → Feld `null` (AC 2).
  4. Contact ohne Account → Feld `null` (AC 3).
  5. `Account.Phone` per DML ändern → Re-Query → neuer Wert (AC 4, deterministisch, Formel ist live).
  6. `Contact.AccountId` auf einen zweiten Account umschreiben (mit anderer Nummer) → Re-Query → Nummer des **neuen**
     Accounts, nicht der alten (AC 5, deterministisch).
- **`SCRUM405FirmenTelefonnummerFlsTest`** (FLS-Test, Muster **SCRUM-403** `LastCaseDateFlsTest`):
  temp-User auf `Standard User`-Profil → **Precondition** `Contact`-Object-Zugriff vorhanden →
  **NEGATIV:** ohne PS `isAccessible()==false` **und** `isUpdateable()==false` → PS `SCRUM405_FirmenTelefonnummer`
  zuweisen → **POSITIV:** `isAccessible()==true`, `isUpdateable()==false` (read-only Formel + editable=false).
  (Beides wird im Test bewiesen; ADR-5-Cross-Reference-Zugriff ist ein E2E/Punkt-Test, hier nicht.)

### 3.4 Manifests (2-Phasen-Regel + Apex-Test-Gate, Muster SCRUM-403)

- `manifest/scr405-phase1-fields.xml` — `CustomField Contact.Firmen_Telefonnummer__c` (version 67.0).
- `manifest/scr405-phase2-referencing.xml` — `Layout Contact-Contact Layout` + `PermissionSet SCRUM405_FirmenTelefonnummer`
  + `ApexClass SCRUM405FirmenTelefonnummerTest` + `SCRUM405FirmenTelefonnummerFlsTest` (Test-Klassen im 2. Set, wie SCRUM-403,
  damit die RunSpecifiedTests-Validierung sie als echtes Gate ausführt).
- `manifest/scr405-phase3-apextests.xml` — die beiden `ApexClass`-Tests (version 67.0), für den RunSpecifiedTests-Lauf.

## 4. ⚠️ Relevanter Befund (Repo-Analyse)

**Lightning Record Pages stehen NICHT in der Source Control** (nur Classic `.layout-meta.xml`). AC 7 („Lightning und Classic")
zerlegt sich folglich:

- **Classic:** Layout-Eintrag in der Source — deckt „im Kontakt-Layout sichtbar" für Classic vollständig (Developer-Agent).
- **Lightning:** Sichtbarkeit = FLS-Permission (Source, hier via PS) + **Platzierung auf der Lightning Record Page im App Builder
  (= Org-Schritt, @devops-agent)** — nicht in der Source persistierbar. @devops-agent: nach Deploy die Feld-Sektion `Telefonnummer der Firma`
  auf die Lightning Record Page von Contact ziehen (App Builder), direkt unter „Telefon". @tester-agent: **beide** UIs verifizieren.

## 5. Offene Punkte (blocken die Implementierung NICHT)

- [ ] **Org-Schritt Lightning:** Feld auf Contact Lightning Record Page platzieren → **@devops-agent** (nach grünem Deploy).
- [ ] **AC 7 / ADR-5 live-Verif:** Sichtbarkeit in Lightning + Classic mit einem representativen Service-Rep testen;
      Cross-Reference-Zugriff (User kann Account lesen?) implizit abgedeckt → **@tester-agent**.
- [ ] **Release-PS-Zuweisung:** `SCRUM405_FirmenTelefonnummer` an die Zielprofile/Nutzer im Release zuweisen → **@devops-agent**.

---

## Pre-Handoff-Checklist (Architect)

- [x] Data-Model-Änderung dokumentiert (1 neu: `Contact.Firmen_Telefonnummer__c`, Text-Formel, read-only).
- [x] FLS/Permission-Set-Design dokumentiert (ADR-3, exaktes XML oben).
- [x] Sharing-Modell-Impact: **kein Impact** (ADR-4), explizit.
- [x] Governor-Limit-Risiken: **keine** (rein deklarativ, keine Apex-/Flow-Logik; ADR-1).
- [x] Flow apiVersion / Naming: **nicht zutreffend** (kein Flow; ADR-1).
