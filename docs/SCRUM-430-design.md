# SCRUM-430 — Architektur-Design

**Kontakt: Picklist-Feld für bevorzugtes Rückruf-Zeitfenster (Vormittags/Nachmittags/Abends)**
Status: **freigegeben** | 2026-09-25 | survey base commit `de9ccef` (origin/master)

---

## 1. Ziel

Neues, optionales Picklist-Feld `Rueckruf_Zeitfenster__c` auf `Contact` mit exakt den
Werten `Vormittags`, `Nachmittags`, `Abends`, direkt auf der Kontaktseite sichtbar
(ohne Aufklappen) und für Vertrieb + Service lesbar/änderbar — reines
Metadata-Ticket: ein CustomField + eine Layout-Zeile + ein PermissionSet +
das House-Testpaar (Funktion + FLS). Kein Apex, kein Trigger, kein Flow,
kein Sharing-Wechsel.

---

## 2. Bestand (surveyed on `de9ccef`, 2026-09-25)

| Fakt | Beleg |
|---|---|
| Picklist-House-Shape auf Contact | `objects/Contact/fields/Open_Cases_Rating__c.field-meta.xml` (SCRUM-370): `<type>Picklist</type>` + `<valueSet><valueSetDefinition><sorted>false</sorted>` + `<value><fullName/><default/><label/></value>` |
| Picklist-Shape auf Case (2. Beispiel) | `objects/Case/fields/Servicebereich__c.field-meta.xml` (SCRUM-421) |
| FLS-PS-Shape (nur fieldPermissions, kein CRUD) | `permissionsets/SCRUM421_Zuordnung.permissionset-meta.xml`, `SCRUM428_ServiceTeam…` |
| Kontakt-Layout: 1 Datei, Classic, 363 Zeilen | `layouts/Contact-Contact Layout.layout-meta.xml`; Sektion „Contact Information" = `TwoColumnsTopToBottom`, 8 layoutItems pro Spalte, letzte `ConsentDate__c` (rechts) |
| **Kein Kontakt-FlexiPage getrackt und keins in der Org** | Repo: nur `User/flexiPages/BetreuungsuebergabePage` (User-Objekt); Org-Query `SELECT Id, DeveloperName FROM FlexiPage` (Test-Org) → 9 Seiten, **null davon Contact-RecordPage** (nur UtilityBars + BetreuungsuebergabePage) |
| Haus-ApiVersion für diese Metadaten | `67.0` (alle `scrNNN-phase*.xml` Manifeste) |
| Manifest-Naming | `manifest/<tkt>-phase1-fields.xml`, `<tkt>-phase1-ref.xml`, `<tkt>-phase2-apextests.xml` (Shape SCRUM-428) |
| Test-Paar-Haus-Shape | `SCRUM421QueueAssignmentTest` + `SCRUM421QueueAssignmentFlsTest`; FLS-Test: Standard-User-Profil, Vorbedingungs-Assert (Objekt-Zugriff), negativer und positiver Block, `WITH USER_MODE` bei SOQL-Prüfung |

Org-Fakten (Test-Org, 2026-09-25):

- `Contact` hat 83 Felder; **keins** mit „Rückruf"/„Zeitfenster" im Namen →
  kein Namenskonflikt für `Rueckruf_Zeitfenster__c`.
- `Betreuungsstufe__c` (repo) ist in der Org deployed → Test-Org und master
  aktuell konsistent.
- Keine Kontakt-RecordPage → Lightning rendert für Contact das **Classic-Layout**
  als Fallback. Die Sektion „Contact Information" des Classic-Layouts ist damit
  die Lightning-Hauptsicht.
- **FLS-Default neu geprüfter Custom Fields:** Standard-User-Profil erhält
  automatisch ReadEdit auf neue Felder (gemessen 2026-09-22, SCRUM-421:
  FLS-Negativtests rot, bis das Feld im Profil manuell gesperrt war;
  `editable=false` in einem PS **kann** Profil-FLS nicht widerrufen).
  Konsequenz für AC4: ohne Org-Setup-Schritt S1 kann der Negativtest
  AC4 nicht erfüllt werden — PS allein reicht nicht.

---

## 3. Architektur-Entscheidungen (ADRs)

### ADR-1 — Deklaratives Picklist-Feld, kein Apex, kein Flow

Reine Picklist mit 3 Werten, optional, ohne Logik. Das ist der einfachste
möglichste Fall: kein Apex-Grund, kein Flow. Apex/Flow sind hier reiner
Ballast (Deployment/Schema-Risiko, ohne Nutzen). Flow wird nicht verwendet
→ kein Flow-apiVersion festzulegen (Pre-Handoff-Checkliste: „nicht zutreffend"
mit Begründung).

### ADR-2 — Ein PermissionSet, nicht zwei (Vertrieb + Service)

Das Ticket verlangt für **beide** Rollen identische FLS auf dem neuen Feld:
read + edit. Zwei PS mit identischem Inhalt wären duplizierte Metadaten mit
zweifacher Zuweisungs- und Testlast. **Ein PS** `SCRUM430_RueckrufZeitfenster`
deckt beide Rollen — die Zuweisung an Vertrieb- und Service-User ist ein
Zuweisungsschritt, kein Designunterschied. House-Konvention
(„Profile unverändert, FLS läuft ausschließlich über Permission Sets") bleibt
gehalten: das PS grantet nur Feldrechte, kein Objekt-CRUD (Contact-CRUD kommt
aus den bestehenden Profilen, wie SCRUM-421 es dokumentiert).

System Administrator: Vollzugriff aus dem Profil, kein PS nötig (House-Konvention).

### ADR-3 — Layout-Eintrag in der klassischen Kontakt-Layout, Sektion „Contact Information"

AC2 verlangt Sichtbarkeit **ohne Aufklappen** auf der Kontaktseite. Kontakt hat
keine Lightning-RecordPage (Bestand, s. o.) → Lightning zeigt das Classic-Layout
als Fallback. Der Eintrag gehört in die Sektion „Contact Information"
(`TwoColumnsTopToBottom`), zweite Spalte, direkt hinter `ConsentDate__c`.
`<behavior>Edit</behavior>` (optional, also kein `Required`).

Kein neuer Abschnitt: das Feld ist eine persönliche Präferenz des Kontakts und
gehört zur Basis-Kontaktinformation; ein eigenes Abschnitt wäre Overkill und
würde die Sektionsstruktur für alle anderen User stören.

> **AC2-Zerlegung für Tester (wichtig!):** „Sichtbar in Lightning ohne
> Aufklappen" ist hier **nur** über das Classic-Fallback-Layout erfüllbar —
> es gibt keine Kontakt-RecordPage, auf die ein App-Builder-Schritt laufen
> könnte. Die E2E-Prüfung ist: Lightning-Kontaktseite öffnen, Feld in der
> „Contact Information"-Sektion sichtbar (nicht in einer aufklappbaren
> Section). Das ist ein **Repo-Check** (Layout-XML enthält das Feld in einer
> Section mit `detailHeading=true` bzw. Standard-Section), keine Org-App-Builder-
> Verifikation. Falls AC2 später „explizit auf einer Lightning-RecordPage"
> heißen sollte, wäre dass **ein neues Ticket** (RecordPage anlegen/ändern,
> App-Builder), kein Scope-Zusatz hier.

### ADR-4 — Picklist als `Picklist` (valueSet/valueSetDefinition), nicht global value set

3 Werte, ein Objekt, keine Cross-Object-Benötigung bekannt. Globale Value Sets
vergrößern die Metadaten- und die Deploy-Kopplung ohne Gegenwert. House-Shape
ist `valueSetDefinition` (SCRUM-370 `Open_Cases_Rating__c`).

### ADR-5 — Name: `Rueckruf_Zeitfenster__c`, Label „Rückruf-Zeitfenster"

- API-Name aus dem Ticket-Begriff: „Rückruf-Zeitfenster" → Salesforce
  Konvention (Umlaut → ä→ae, ü→ue, Bindestrich wird zu Unterstrich):
  API-Name `Rueckruf_Zeitfenster__c`, **Label** „Rückruf-Zeitfenster"
  (Original-Schreibweise als Label, House-Konvention).
- Kein Kollision in der Org (s. Bestand-Query oben).

### ADR-6 — Optional / leer lassbar: `required=false`, kein Default

`<required>false</required>` und **kein** `<default>`-Wert mit `default=true`.
AC1 „kann der Wert leer bleiben" + „bei den meisten Kontakten unbekannt" →
Null ist der Normalzustand. Keine Standardwert-Falle.

### ADR-7 — Kein Sharing-Wechsel

Ticket sagt es explizit: OWD/Sharing-Rules/Role-Hierarchie bleiben unverändert.
Feldzugriff ist per ADR-2 über PS geregelt, keine Sharing-Frage. **Kein Impact**
(Pre-Handoff-Checkliste: „kein Impact" mit Verweis auf Ticket-Text).

---

## 4. Komponenten (exact Paths, auf Branch `feature/SCRUM-430-rueckruf-zeitfenster`)

### 4.1 CustomField

**`force-app/main/default/objects/Contact/fields/Rueckruf_Zeitfenster__c.field-meta.xml`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Rueckruf_Zeitfenster__c</fullName>
    <description>Bevorzugtes Rueckruf-Zeitfenster des Kontakts (SCRUM-430): Vormittags / Nachmittags / Abends. Optional — bei den meisten Kontakten unbekannt (leer). Reine Praeferenz, keine PII.</description>
    <externalId>false</externalId>
    <label>Rückruf-Zeitfenster</label>
    <required>false</required>
    <trackTrending>false</trackTrending>
    <type>Picklist</type>
    <valueSet>
        <valueSetDefinition>
            <sorted>false</sorted>
            <value>
                <fullName>Vormittags</fullName>
                <default>false</default>
                <label>Vormittags</label>
            </value>
            <value>
                <fullName>Nachmittags</fullName>
                <default>false</default>
                <label>Nachmittags</label>
            </value>
            <value>
                <fullName>Abends</fullName>
                <default>false</default>
                <label>Abends</label>
            </value>
        </valueSetDefinition>
    </valueSet>
</CustomField>
```

Shape 1:1 zu `Open_Cases_Rating__c` (SCRUM-370), ohne Default-Wert (ADR-6).

### 4.2 Layout-Änderung

**`force-app/main/default/layouts/Contact-Contact Layout.layout-meta.xml`**

Zweite `<layoutColumns>` der Sektion „Contact Information", direkt nach dem
`ConsentDate__c`-layoutItem (aktuell das letzte Item dieser Spalte):

```xml
            <layoutItems>
                <behavior>Edit</behavior>
                <field>ConsentDate__c</field>
            </layoutItems>
            <layoutItems>
                <behavior>Edit</behavior>
                <field>Rueckruf_Zeitfenster__c</field>
            </layoutItems>
```

Keine andere Spalte/Section. `<behavior>Edit</behavior>` (optional = kein `Required`).

### 4.3 PermissionSet

**`force-app/main/default/permissionsets/SCRUM430_RueckrufZeitfenster.permissionset-meta.xml`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<PermissionSet xmlns="http://soap.sforce.com/2006/04/metadata">
    <description>SCRUM-430: FLS auf Contact.Rueckruf_Zeitfenster__c (bevorzugtes Rueckruf-Zeitfenster) — Vertrieb + Service: lesbar + änderbar. Nur Feldrechte, kein Objekt-CRUD (Contact-CRUD kommt aus den bestehenden Profilen, House-Konvention SCRUM-421).</description>
    <fieldPermissions>
        <editable>true</editable>
        <field>Contact.Rueckruf_Zeitfenster__c</field>
        <readable>true</readable>
    </fieldPermissions>
    <hasActivationRequired>false</hasActivationRequired>
    <label>SCRUM430_RueckrufZeitfenster</label>
</PermissionSet>
```

Shape 1:1 zu `SCRUM421_Zuordnung` (nur Feldberechtigungen, kein CRUD-Block →
das PS grantet **nur** FLS, Objekt-CRUD kommt aus dem Profil).

**Zuweisung (Developer-Pflicht, House-Regel — Deploy ≠ Assign!):**

```bash
# nach dem Deploy auf Test-Org, BEVOR der Handoff-Kommentar geschrieben wird:
sf org assign permset -n SCRUM430_RueckrufZeitfenster -o Test-Org
# + an den menschlichen Test-Account (meerwais.osmani@resourceful-bear-6f1u4j.com)
# + Read-back:
sf data query -o Test-Org -q "SELECT Assignee.Username FROM PermissionSetAssignment WHERE PermissionSet.Name='SCRUM430_RueckrufZeitfenster'"
# + ein Feld in echter Session per WITH USER_MODE lesen (Beweis, s. SCRUM-421)
```

Der Developer-Handoff-Kommentar **muss** den Read-back (Zuweisungsliste +
einen WITH-USER_MODE-Feldwert) enthalten — ohne ihn ist der Handoff
unvollständig und ich sende ihn zurück (AGENTS.md-Handoff-Regel).

### 4.4 Apex-Tests (House-Paar, Phase 2)

**4.4a `force-app/main/default/classes/SCRUM430RueckrufZeitfensterTest.cls`**
(+ `.cls-meta.xml`, apiVersion 67.0)

Funktionstest für AC1 (Wertematrix + Optional). Shape:
`SCRUM396BetreuungsstufeTest` (ein `makeContact()`, je Wert ein Test,
read-back via SELECT). Exakte Vorgaben:

| TC | Setup | Erwartung | AK |
|---|---|---|---|
| `defaultValue_empty` | `Contact { LastName=…, Rueckruf_Zeitfenster__c unset }` insert → SELECT | Feld == null | AC1 „kann leer bleiben" |
| `value_vormittags` | insert mit `Rueckruf_Zeitfenster__c='Vormittags'` → SELECT | Wert bleibt `Vormittags` | AC1 |
| `value_nachmittags` | idem, `'Nachmittags'` | bleibt `Nachmittags` | AC1 |
| `value_abends` | idem, `'Abends'` | bleibt `Abends` | AC1 |
| `overwrite_vormittags_to_abends` | insert `'Vormittags'` → update auf `'Abends'` → SELECT | `Abends` (frei änderbar, AC3-Grundlage) | AC3 |
| `reject_invalid_value` | update auf `'Mittags'` (nicht in der Picklist) → SELECT | Expect `IllegalArgumentException` / `FIELD_CUSTOM_VALIDATION_EXCEPTION` o. ä. (Salesforce-Standard-Ablehnung für fremden Picklist-Wert) | AC1 „exakt 3 Werte" |

`@isTest private class SCRUM430RueckrufZeitfensterTest { … }`
Jeder Test eigene `@isTest static void`. Kein `System.runAs` nötig (reines
DML+SELECT, kein FLS).

**4.4b `force-app/main/default/classes/SCRUM430RueckrufZeitfensterFlsTest.cls`**
(+ `.cls-meta.xml`, apiVersion 67.0)

FLS-positiv/negativ für AC3/AC4. Shape: `SCRUM421QueueAssignmentFlsTest`
(Standard-User-Profil, Vorbedingungs-Assert, eigener `mkTestUser()`,
`WITH USER_MODE` bei SOQL, eigenständige `System.runAs`-Blöcke, kein nested runAs).
Exakte Vorgaben:

| TC | Setup | Erwartung | AK |
|---|---|---|---|
| `precondition_contactReadable` | `runAs(tempUser) { Contact.SObjectType.getDescribe().isAccessible() }` | `true` (sonst wäre jeder FLS-Assert aus dem falschen Grund grün) | Vorbedingung |
| `withoutPS_fieldInvisible` | **VORAUSSETZUNG: S1 (Org-Setup, Tabelle S1 unter §6) ist vor diesem Test ausgeführt** (Feld im Standard-User-Profil gesperrt) + `runAs(tempUser)` + `[SELECT Rueckruf_Zeitfenster__c FROM Contact WITH USER_MODE LIMIT 1]` | Throws (SecurityException/`No such column`) | AC4 (Negativ) |
| `withPS_readableAndWritable` | `System.runAs(grantedUser)` + INSERT Contact mit `Rueckruf_Zeitfenster__c='Abends'` + UPDATE auf `'Vormittags'` + SELECT | Alles durch; Wert = `'Vormittags'` | AC3 (positiv) |

**Wichtig für Developer + Tester:** Der Negativ-Test `withoutPS_fieldInvisible`
läuft **nur** nach Org-Setup-Schritt **S1** (Feld im Standard-User-Profil
sperrbar). Ohne S1 scheitert der Test — und er scheitert **korrekt**, weil
AC4 in der Org dann tatsächlich nicht erfüllt ist (Profil-Default ReadEdit).
S1 ist kein optionaler „nice to have", er ist die technische Voraussetzung für
AC4. Siehe §6.

> **Tester-Hinweis (AC4 UI-Prüfung):** Der Apex-FLS-Test prüft FLS auf
> SOQL/DML-Ebene. Die Lightning-UI-Sichtbarkeit (Feld unsichtbar für eingeschränkten
> User) ist eine **zusätzliche E2E-Prüfung** (Playwright, eingeloggter User ohne
> PS + Profil-SPerrung) — der Tester legt sie an. Sie ist ein **Test-Artefakt**,
> kein Produktiv-Komponent. Die Vorbedingung dafür ist dieselbe S1.

### 4.5 Manifeste

**`manifest/scr430-phase1-fields.xml`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!-- SCRUM-430 Phase 1: Picklist field (Contact) -->
<Package xmlns="http://soap.sforce.com/2006/04/metadata">
    <types>
        <members>Contact.Rueckruf_Zeitfenster__c</members>
        <name>CustomField</name>
    </types>
    <version>67.0</version>
</Package>
```

**`manifest/scr430-phase1-ref.xml`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!-- SCRUM-430 Phase 1b: layout + permission set (both reference Contact.Rueckruf_Zeitfenster__c) -->
<Package xmlns="http://soap.sforce.com/2006/04/metadata">
    <types>
        <members>Contact-Contact Layout</members>
        <name>Layout</name>
    </types>
    <types>
        <members>SCRUM430_RueckrufZeitfenster</members>
        <name>PermissionSet</name>
    </types>
    <version>67.0</version>
</Package>
```

**`manifest/scr430-phase2-apextests.xml`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!-- SCRUM-430 Phase 2: Apex tests (house pattern SCRUM396/421) -->
<Package xmlns="http://soap.sforce.com/2006/04/metadata">
    <types>
        <members>SCRUM430RueckrufZeitfensterTest</members>
        <members>SCRUM430RueckrufZeitfensterFlsTest</members>
        <name>ApexClass</name>
    </types>
    <version>67.0</version>
</Package>
```

Deploy-Reihenfolge: **Phase 1 → Phase 1b → Phase 2** (Feld zuerst, dann
Referenzen, dann Tests — House-Reihenfolge, s. SCRUM-396). Jeder Deploy mit
`--test-level RunSpecifiedTests --tests SCRUM430RueckrufZeitfensterTest,SCRUM430RueckrufZeitfensterFlsTest`
für Phase 2; für Phase 1/1b `--test-level NoTestRun` ist **nicht** verfügbar
(Validierung läuft immer Tests) → für Phase 1/1b `--test-level RunLocalTests`.

---

## 5. Governor-Limit-Risiken (Pre-Handoff-Checkliste)

**Keine Risikos identifiziert.**

- Kein Apex außer Tests → keine SOQL-in-Loop-, keine Bulkification-Frage.
- Tests: je Test 1–2 DML + 1 SELECT, weit unter den Limits.
- Deklarative Metadaten (Feld, Layout, PS) verbrauchen keine Governor Limits
  zur Laufzeit.

---

## 6. Org-Setup-Schritte (blocken NICHT die Implementierung, WELDEN aber für AC4!)

Diese Schritte laufen **vor** der Tester-Phase, nicht im Deploy und nicht als
Apex-Test (Org-Konfiguration ≠ Quell-Artefakt — House-Regel §SCRUM-424 ADR).
Der DevOps-Agent führt sie aus; der Tester verifiziert per Read-back.

| # | Schritt | Wer | Read-back (Pflicht im Handoff/Release-Kommentar) |
|---|---|---|---|
| S1 | **Feld `Rueckruf_Zeitfenster__c` im Standard-User-Profil auf „nicht sichtbar" sperren** (Setup → Objekte → Kontakt → Felder → Feld-Sicherheitsrechte). Grund: Standard-User-Profil erhält bei jedem neu deployten Custom Field automatisch ReadEdit (SCRUM-421-Lesson). Ohne S1 ist AC4 technisch nicht erfüllbar und der Negativ-FLS-Test scheitert. | DevOps (vor Test-Phase) | `SELECT PermissionsRead, PermissionsEdit FROM FieldPermissions WHERE SobjectType='Contact' AND Field='Contact.Rueckruf_Zeitfenster__c'` → Zeile mit `Parent.IsOwnedByProfile=true`, `PermissionsRead=false` |
| S2 | PS `SCRUM430_RueckrufZeitfenster` an alle Vertrieb- und Service-User in der Test-Org zuweisen (s. §4.3) | Developer (nach Deploy) | `SELECT Assignee.Username FROM PermissionSetAssignment WHERE PermissionSet.Name='SCRUM430_RueckrufZeitfenster'` + WITH-USER_MODE-Feldlesung |

> **Warum S1 ein eigener Schritt und kein Deploy-Artefakt ist:** Profile sind
> in diesem Repo nicht getrackt (House-Konvention, SCRUM-421). Eine Profil-
> Änderung ist ein Org-Setup-Schritt, kein File. S1 wird in der Test-Org
> manuell gesetzt und für Prod-Org im Release-Kommentar als DevOps-Schritt
> dokumentiert.

---

## 7. Pre-Handoff-Checkliste (Architect → Developer)

| Punkt | Status |
|---|---|
| Datenmodell dokumentiert (ADR-1, ADR-5, ADR-6: 1 neues Picklist-Feld auf Contact, optional, 3 Werte) | ✅ |
| Permission-Set-/FLS-Design dokumentiert (ADR-2, §4.3) | ✅ |
| Sharing-Modell-Impact: **kein Impact** (ADR-7, Ticket-Text) | ✅ |
| Governor-Limit-Risiken dokumentiert (§5, keine) | ✅ |
| Flow: **nicht verwendet** (ADR-1) → kein Flow-apiVersion festzulegen | ✅ (explizit) |
| Bestehende Muster wiederverwendet (Picklist: SCRUM-370; PS: SCRUM-421; Tests: SCRUM-421/396; Manifest: SCRUM-428) | ✅ |
| Org-Setup-Schritte identifiziert (S1 Profil-Sperre für AC4, S2 PS-Zuweisung) | ✅ |

---

## 8. Offene Punkte (NICHT implementierungs-blockierend)

- [ ] S1 (Profil-Sperre) ist ein **Org-Setup** und gehört nicht ins Repo —
  DevOps führt ihn aus; der Read-back gehört in den DevOps-Release-Kommentar
  für Prod-Org. @devops-agent
- [ ] AC2 „Sichtbar in Lightning" ist über das **Classic-Fallback-Layout**
  erfüllt (kein Kontakt-FlexiPage in der Org). Falls die PO-Agent „explizit
  eine Lightning-RecordPage" meint, wäre das ein **eigenes Ticket**.
  @po-agent (Klärung, nicht blockierend)
- [ ] Wer sind konkret die „Vertriebs-Nutzer" und „Service-Nutzer" in der
  Test-Org (Usernamen/Profile für die S2-Zuweisung)? House-Verfahren:
  DevOps-Agent-Test-Account + PO-Test-Account (s. SCRUM-421/428-Zuweisungen).
  @developer-agent (klärt bei Implementierung)

---

## 9. Für @user — was sich in Salesforce ändert (Einfach-Deutsch)

- **Neues Feld „Rückruf-Zeitfenster" auf jeder Kontaktseite:** Man kann bei
  jedem Kontakt auswählen, wann man am liebsten angerufen werden möchte —
  „Vormittags", „Nachmittags" oder „Abends". Das Feld ist optional;
  man kann es leer lassen, wenn man es nicht weiß.
- **Direkt sichtbar, ohne Kippen:** Das Feld erscheint in der
  „Kontakt-Informationen"-Sektion oben auf der Kontaktseite — man muss
  nichts aufklappen.
- **Service kann es ändern, Vertrieb sieht es:** Beide Teams dürfen den Wert
  setzen und ändern. Jeder sieht, was der andere eingetragen hat.
- **Sicherheit:** Nutzer ohne Berechtigung sehen das Feld nicht (Negativtest
  als AC4). Dafür muss die Standard-Benutzerrechte für das neue Feld
  org-seitig eingeschränkt sein (Setup-Schritt von DevOps, §6 S1) — das
  passiert automatisch und ist im Test verifiziert.
- **Nichts anderes ändert sich:** Keine Automatisierung, keine Benachrichtigungen,
  keine Auswertungen. Das Feld ist eine reine Notiz für den Anrufer.
