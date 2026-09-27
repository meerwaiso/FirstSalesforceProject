# SCRUM-432 — Wiedervorlage auf Case: persönliches Follow-up-Datum + „heute offen“-Liste · Authoritative Build-Spec

> **This file is the source of truth for the exact XML, API names and formulas.**
> Die Jira-Kommentare (SCRUM-432) werden vom Jira-Markdown-Converter verunstaltet
> (doppelte Unterstriche → fett, schließende XML-Tags weggeworfen, `+` gefressen —
> auf diesem Projekt wiederholt verifiziert, selbst in Codeblöcken). Die Dateien
> bauen anhand DIESER Datei; genaue Namen nur hierher kopieren, nicht aus dem
> Jira-Kommentar.

## Goal
„Persönliche Wiedervorlage“ auf dem **Case**: ein Datum (ohne Uhrzeit) + kurze
Notiz, plus eine gespeicherte Listview „Wiedervorlagen – heute offen“, die **nur
die Wiedervorlagen der aktuellen Person** zeigt, deren Datum **heute oder in der
Vergangenheit** liegt (überfällig), sortiert idealerweise nach dem ältesten
Datum. Rein deklarativer Read-/Write auf dem Case: **keine Automation** (keine
Mails/Tasks/Status/Benachrichtigung), keine Sharing-Änderung, kein Apex, kein
Trigger, keine Flow.

## Branch
`feature/SCRUM-432-wiedervorlage` frisch von `origin/master` (Stand: `02ee719`) —
siehe `git worktree`. Geteilter Tree liegt auf `feature/SCRUM-424-first-response`
mit Änderungen/Untracked — von `origin/master` abziehen, **nichts davon mitnehmen,
nichts löschen**. Niemals `git add .` / `-A`; nur explizit eigene Pfade stageen.
Commite auch DIESER Datei (`docs/SCRUM-432-design.md`) in den Branch mit.

---

## ADR

### ADR-1: reine Deklaration (4 Custom Fields + 1 Listview + 1 PS), NICHT Apex/Trigger/Flow
„Wiedervorlage“ ist **persistenter Datensatz** (Datum + Notiz), der gespeichert
wird und in einer Liste gelesen wird — kein abgeleiteter, bei jedem Lesen neu
berechneter Wert.
- **Trigger wird abgelehnt** — der PO-Scope schließt „keine Automatisierung“
  explizit aus (keine Mails, keine Tasks, keine Statusänderung, keine
  Benachrichtigung). Ein Trigger, der z. B. das „gesetzt von“ automatisch pflegen
  würde, wäre genau eine solche Automatik und gehört in das vom PO für später
  zugesagte Erinnerungs-Ticket, nicht hierher.
- **Flow wird abgelehnt** — keine Zustands-/Datenänderung, keine Verzweigung,
  kein Bulk-Prozess. House-Regel: Apex/Flow nur bei nicht-trivialer Logik; hier
  ist alles deklarativ abbildbar.
- **Kein Apex** — keine Logik, die Deklaration nicht leisten kann (siehe ADR-2:
  die „persönlich“-Sicherung ist eine Formel, kein Code).
→ Deklaratives Feature; einzige Code-Artefakte sind die **Haus-Pflicht-Apex-
  Tests** für den PR-Gate (ADR-10), nicht Produktionslogik.

### ADR-2: wie wird „nur eigene Wiedervorlagen sehen“ gesichert (KERN) — Formelfeld gegen `$User`, filtern in Listview

**Die Listview allein reicht NICHT.** Eine gespeicherte Listview (Metadata
`ListView`) trägt ihre Filter als **statische Kriterien** — ein Element „aktuelle
Person / Current User“ existiert dort **nicht**. Verifiziert gegen das eigene,
installierte CLI-Bundle (authoritative Metadata-API-Schema, `@salesforce/types/lib/
metadata.d.ts`):

```
export type ListView = Metadata & {
    booleanFilter?: string; columns: string[]; division?: string;
    filterScope: FilterScope; filters?: ListViewFilter[];
    label: string; language?: Language; queue?: string; sharedTo?: SharedTo;
};
export type ListViewFilter = { field: string; operation: FilterOperation; value?: string; };
```
→ kein `sort`/`orderBy`-Element (beantwortet ADR-7), kein dynamischer
Current-User-Wert. Wer eine Listview baut, die „alle, wo ich dran beteiligt bin“
zeigt, baut sie **pro Benutzer** — das ist genau das, was das Feature vermeiden
soll. (Bestätigt durch Salesforce-Admin-Blog „How I Solved This: List Views for
Object Ownership“ und mehrere StackExchange/Trailhead-Threads: Standard-Antwort
ist eine **Checkbox-Formel `IF(Lookup__r = $User.*, TRUE, FALSE)`**, die die
Listview filtert.)

**Mechanik (deklarativ, zwei zusätzliche Felder, die der PO als „gesetzt von gegen
aktuelle Person“ explizit freigegeben hat):**

1. `Case.Wiedervorlage_Von__c` — **Lookup→User**, optional (SetNull).
   Der/die Nutzer:in der Service-Team wählt beim Legen der Wiedervorlage
   **sich selbst** in den Wiedervorlage-Feldern aus (einzige Benutzer-Aktion;
   s. „Offene Punkte“ unten — Auto-Pflege wäre Automatisierung und liegt im
   späteren Ticket).
2. `Case.Wiedervorlage_Heute_Offen__c` — **Checkbox-Formel** (read-only), die
   die komplette „heute offen + persönlich“-Prüfung bündelt:

   ```
   AND(
     Wiedervorlage_Von__r.Id = $User.Id,          /* AC5/AC6: nur meine */
     NOT(ISBLANK(Wiedervorlage_Datum__c)),        /* AC3: kein Datum  -> NICHT */
     Wiedervorlage_Datum__c <= TODAY()            /* AC3: heute ODER Vergangenheit */
   )
   ```
   (Zukunft wird damit bewusst ausgeschlossen — „heute oder bereits offen“.)
   Das Formelergebnis ist **sessionabhängig**: es wird zum Abfragezeitpunkt für
   die **abfragende** Person ausgewertet, daher ist `$User.Id` die richtige
   Personal-Anker und das Feld ohne Sharing-Änderung „persönlich“ (ADR-4).

3. **Listview filtert** dieses Formelfeld auf `= 1` (exakt das Hausmuster
   `Is_Due__c` auf `Lead`/`Nachfassliste`, SCRUM-378, und `Is_Close_Date_Overdue__c`
   auf `Opportunity`/`Ueberfaellige_Chancen`, SCRUM-414 — beides „Datum<=TODAY“-
   Checkbox-Formel, Listview filtert `=1`, `filterScope=Everything`).
   Der „overdue“-Check wird damit **nicht** als dynamisches Listview-Datumsfilter
   (`lessOrEqual TODAY`) gemacht — das Hausmuster rechnet ihn in eine stabile
   Checkbox-Formel, weil ein relatives Listview-Filterdatum im Metadata nicht
   garantiert round-trippt. Wir übernehmen das geprüfte Muster 1:1.

**Warum Lookup statt Case-`OwnerId`:** Das Feature ist ein **persönliches Memo
des Setsenden** („wer den Fall auf Wiedervorlage legt, sieht nur die eigenen“),
nicht gekoppelt an die Case-Eigentümerschaft. `OwnerId` würde die Sicht an die
Case-Eintrag/OWD binden und AC6 (Kollege versteckt) brechen, sobald die Case-
Sharing-Regeln beiden Zugriff auf denselben Fall geben. Ein eigenes
`Wiedervorlage_Von__c` trennt „persönliche Notiz“ von „Case-Zuordnung“ — ohne die
bestehenden Sharing-Regeln zu berühren (ADR-4).

### ADR-3: FLS via neuem Permission Set (keine Profile-Edit)
Haus-Pflicht (SCRUM-314/381/414/428): **jedes** neue geänderte Feld braucht in
einem Permission Set eine explizite `fieldPermissions`-Eintragung — FLS wird nie
vom Objekt-CRUD vererbt, Standard-Default bleibt „kein Zugriff“.
→ Neues PS `SCRUM432_Wiedervorlage_ServiceTeam` (ADR-8), **Read+Edit** auf die
drei Speicher-Felder (Datum, Notiz, Von), **Read-only** auf dem Formelfeld
`Wiedervorlage_Heute_Offen__c`. Keine Objekt-CRUD-Änderung, kein `viewAllFields`.

### ADR-4: Sharing-Modell = **keine Änderung**
- Case OWD, Sharing Rules, Role-Hierarchy bleiben **unberührt** — das Feature
  ändert an der **Record-Ebene** nichts. Ein Nutzer, der über das bestehende
  Case-Sharing einen Kollegen-Fall öffnen *könnte*, sieht dort weiterhin den Fall;
  die **persönliche Liste** blendet fremde Wiedervorlagen aber per
  `Wiedervorlage_Heute_Offen__c`-Filter aus. Die Filter schmalen die Liste auf die
  eigenen Memos **zusätzlich** zu — nie **breiter** als — der Standard
  record-level security. → „ohne bestehende Sharing-Regeln zu brechen“ = wir
  berühren sie gar nicht.
- AC5/AC6 werden also rein über den **Listview-Filter** (ADR-2) erfüllt, nicht
  über Sharing.

### ADR-5: API-Namen & Typen beider (+Mechanismus-)Felder

| API-Name | Label | Typ | Pflicht | Anmerkung |
|---|---|---|---|---|
| `Wiedervorlage_Datum__c` | Wiedervorlage Datum | `Date` | optional | **nur Datum, keine Uhrzeit** (PO). |
| `Wiedervorlage_Notiz__c` | Wiedervorlage Notiz | `Text` (length 255) | optional | kurzer Freitext (PO). |
| `Wiedervorlage_Von__c` | Gesetzt von | `Lookup` → `User` | optional, `SetNull` | Mechanismus (ADR-2). |
| `Wiedervorlage_Heute_Offen__c` | Wiedervorlage heute offen | Formel → `Checkbox` | read-only | Mechanismus / Listview-Treiber. **Nicht** im Layout, nur in der Liste. |

Casing: PO-Begriffe bleiben als Label; API-Namen Salesforce-Konvention (keine
Umlaute; `Ueber→U`-Umsetzung nur bei Bedarf — hier keine Umlaute nötig außer im
Label). `Wiedervorlage_*` ist im Repo/Org neu (Collision-Scan: kein Feld, keine
Child-Relation mit „wiedervorl“ auf Case vorhanden).

### ADR-6: Listview „Wiedervorlagen – heute offen“
- **fullName** `Wiedervorlagen_heute_offen`, **label** `Wiedervorlagen – heute offen`.
- **Spalten (AC2):** `CASES.CASE_NUMBER` (Fallnummer), **Account-Spalte** (Kunde),
  `CASES.SUBJECT` (Betreff), `Wiedervorlage_Notiz__c` (Notiz),
  `Wiedervorlage_Datum__c` (Datum).
- **filterScope** `Everything` (sonst nur „My Cases“ — wir brauchen alle readable
  Records, gefiltert über die Formel).
- **ein Filter:** `Wiedervorlage_Heute_Offen__c` `equals` `1`.

⚠️ **Eine Spalten-Namens-Meldung (AC, muss beim Validate gelöst werden):**
`CASES.CASE_NUMBER`, `CASES.SUBJECT` sind die **gewiesenen** Tokens aus
`Case/listViews/Eskalierte_Faelle.listView-meta.xml` (im Repo, im Org validiert).
Die **Kunden-Spalte** ist ein cross-object-Token für `AccountId`/`AccountName`:
Das Repo nutzt für den Account auf `Opportunity` das Token `ACCOUNT.NAME` (in
`Hochwertige_Chancen`), ein `Case`-Listenview im Repo zeigt den Account aber mit
`CORE.USERS.ALIAS` (Owner), nicht mit dem Account-Namen. **`ACCOUNT.NAME` ist für
die Case-Listview NICHT verifiziert** (Listviews sind per Tooling-API nicht
querybar, Standard-ListView nicht einzeln retrievebar — read-only nicht
entscheidbar). **Erste Implementierungsaktion des Developers:** `sf project deploy
validate` der Listview mit `ACCOUNT.NAME`; fällt das, Token via
`sf sobject describe -s Account` + Repo-Listenview-Vergleich korrigieren
(Proxy-Namen wie `CASES.ACCOUNTNAME` sind Kandidaten). **Namen aus dem
Validator-Ergebnis übernehmen, nicht raten.** Die übrigen 4 Spalten sind fix.

### ADR-7: Sortierung (AC4 „ältestes Datum oben“) — **plattformbedingt nicht in der Quelle dauerhaft**
Verifiziert gegen das installierte CLI-Metadata-Schema (ADR-2/ADR-6-Quelle):
`type ListView` hat **kein `sort`/`orderBy`-Element** → eine sortierungs-
persistierende Listview lässt sich in der Quelle **nicht** ausdrücken. Die
Listview erscheint in der Org in der **Org-Defaultreihenfolge**; die Nutzer:in
sortiert in der UI per **Klick auf die Spalten-Header „Wiedervorlage Datum“ →
aufsteigend** (funktioniert, da das Datum als echte Spalte angelegt ist).
→ **Kein automatisierter Test** für AC4 möglich (Platform-Limit) — wird wie
„nicht geprüft“ gemeldet, nicht stillschweigend erfüllt (siehe AC-Mapping).
PO-Entscheidung: UI-Sort als Erfüllung annehmen (empfohlen) — „Offene Punkte“.

### ADR-8: Page-Layout-Integration (Case Page Layout)
- Ziel-Layout: `Case-Case Layout` (`force-app/main/default/layouts/Case-Case
  Layout.layout-meta.xml`) — repo-tracktes **Classic**-Layout (siehe Befund).
- **Neue Layout-Sektion** `Wiedervorlage` (two-column, wie die bestehenden
  `Zuordnung` / `Eskalation (Kunde)`), mit drei Feldern, `Edit`-Verhalten:
  ```xml
  <layoutSections>
      <customLabel>true</customLabel>
      <detailHeading>true</detailHeading>
      <editHeading>true</editHeading>
      <label>Wiedervorlage</label>
      <layoutColumns>
          <layoutItems><behavior>Edit</behavior><field>Wiedervorlage_Datum__c</field></layoutItems>
      </layoutColumns>
      <layoutColumns>
          <layoutItems><behavior>Edit</behavior><field>Wiedervorlage_Notiz__c</field></layoutItems>
          <layoutItems><behavior>Edit</behavior><field>Wiedervorlage_Von__c</field></layoutItems>
      </layoutColumns>
      <style>TwoColumnsLeftToRight</style>
  </layoutSections>
  ```
  Einordnung (Detail-Teil, nicht Feed): neben/unter den bestehenden Sektionen
  `Zuordnung` bzw. `Überwachung`; exakte Position wählt der Developer im Detail-Block.
- **`Wiedervorlage_Heute_Offen__c` kommt NICHT ins Layout** (interner Listview-
  Treiber; Record-Page bleibt sauber; FLS/Verwendung sind layout-unabhängig).

⚠️ **Befund — „Auf allen Layouts“ ≠ nur das Repo-Layout.** Das Repo trackt nur
das **Classic** `Case-Case Layout`; die **Lightning**-Record-Page (FlexiPage)
liegt in der **Org** (App Builder). Dass die drei Felder auf der Lightning-Page
erscheinen, ist ein **Org-Schritt (App Builder / DevOps)** — im Deploy-Validate
entdecken und im Test-Org-/Prod-Handoff verifizieren. Tester prüft **beide**
UIs (Classic-Layer + Lightning-Page), wie im Haus üblich.

### ADR-9: Deployment-Sequenz (Haus: `scrNNN-phase1-fields` → `phase2-referencing`)
Abhängigkeiten: die Felder müssen vor PS/ListView/Layout/Tests existieren.

**`manifest/scr432-phase1-fields.xml`**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<Package xmlns="http://soap.sforce.com/2006/04/metadata">
    <types>
        <members>Wiedervorlage_Datum__c</members>
        <members>Wiedervorlage_Notiz__c</members>
        <members>Wiedervorlage_Von__c</members>
        <members>Wiedervorlage_Heute_Offen__c</members>
        <name>CustomField</name>
    </types>
    <version>67.0</version>
</Package>
```
**`manifest/scr432-phase2-referencing.xml`**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<Package xmlns="http://soap.sforce.com/2006/04/metadata">
    <types><members>SCRUM432_Wiedervorlage_ServiceTeam</members><name>PermissionSet</name></types>
    <types><members>Wiedervorlagen_heute_offen</members><name>ListView</name></types>
    <types><members>Case-Case Layout</members><name>Layout</name></types>
    <version>67.0</version>
</Package>
```
**`manifest/scr432-apextests.xml`** (PR-Gate)
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!-- SCRUM-432: Apex tests (house pattern SCRUM382/414/430) -->
<Package xmlns="http://soap.sforce.com/2006/04/metadata">
    <types>
        <members>SCRUM432WiedervorlageTest</members>
        <members>SCRUM432WiedervorlageFlsTest</members>
        <name>ApexClass</name>
    </types>
    <version>67.0</version>
</Package>
```
Deploy: `--test-level RunSpecifiedTests --tests "SCRUM432Wiedervorlage*"`.
**PS-Zuweisung + Read-Back sind Pflicht im Developer-Handoff** (Test-Org): an den
CLI-Targetorg-User UND an ein zweites Service-Testkonto, danach
`PermissionSetAssignment` auslesen + ein Feld **durch eine reale Session** lesen
(Hausexempel-Schmerzpunkt: 6× PS an niemanden zugestellt — SCRUM-382/386/388/390/
394/398).

### ADR-10: Testabdeckung = PR-Gate (nicht Bonus) — exakt Hausmuster
Declarative-Feld-Tickets liefern **Wert-Feld- + FLS-Test-Paar** v67.0
(`SCRUM382CustomerSinceDaysTest`/`...FlsTest`, `SCRUM414CloseDateOverdueTest`,
`SCRUM430RueckrufZeitfensterTest`) + E2E-Spec für Listen-Akzeptanzen (Muster
`tests/e2e/SCRUM-378_lead-nachfassliste.spec.ts`). „Deployed + 1× live“ ist
**kein** Test → sonst PR ablehnen (approved-against-criteria, SCRUM-359).

- `SCRUM432WiedervorlageTest` (Wert/Formel-Verhalten, `@isTest`, v67.0):
  - **AC1:** Case anlegen, Datum+Notiz(+Von=self) setzen, zurücklesen → Werte persistiert.
  - **AC3:** Datum in Vergangenheit → `Wiedervorlage_Heute_Offen__c=true`; Datum heu­te → true; **Datum in Zukunft → false**; **leeres Datum → false**.
  - **AC5/AC6 (personal, sessionabhängige Formel):** zwei User `A`,`B`. `runAs(A)`:
    A's Wiedervorlage (Von=A, Datum≤heute) → `Heute_Offen__c=true`; B's Fall (Von=B)
    → `false`. `runAs(B)`: B's → `true`. (Formel wird im Kontext der abfragenden
    Person ausgewertet → `$User`-Test ist deterministisch.)
- `SCRUM432WiedervorlageFlsTest` (FLS, Negativ+Positiv; AC7/AC8):
  - **AC8 (Negativ):** als User **ohne** PS: `FieldDescribe.getReadable()/Editable()`
    auf `Datum`/`Notiz`/`Von` = **false** (Default-FLS; kein Profil-Edit).
  - **AC7 (Positiv):** PS zugewiesen/aktiv → die drei Felder **readable+editable=true**,
    Formelfeld **readable=true / editable=false**.
- **Playwright E2E** `tests/e2e/SCRUM-432_wiedervorlage.spec.ts` (Muster
  `SCRUM-378_lead-nachfassliste.spec.ts`): gespeicherte Listview öffnen →
  **AC2** 5 Spalten vorhanden; **AC3/AC5** nur eigene + fällige Records sichtbar
  (frontdoor.jsp-Ausschreibung via globalSetup + storageState; `networkidle`/
  login page/sid-Cookie **verboten**). **AC6** ist primär der Apex-Zwei-User-Test
  (deterministisch); E2E ergänzt die POSITIVE Sichtbarkeit.

**AC-Mapping (jede Akzeptanz → genanes Artefakt):**

| AC | Anforderung | Beweiserzeugnis | Status |
|---|---|---|---|
| AC1 | Datum+Notiz speichern & anzeigen | `SCRUM432WiedervorlageTest` + E2E (save) | testbar |
| AC2 | 5 Spalten in der Liste | E2E (Spalten-assert) | testbar |
| AC3 | heute/vergangene ja, ohne Datum nein | `SCRUM432WiedervorlageTest` (4 Fälle) + E2E | testbar |
| AC4 | ältestes Datum oben | **keiner** — `ListView`-Metadata ohne `sort` (ADR-7); UI-Sort | **plattform-limitiert → untested** |
| AC5 | eigene sichtbar | `SCRUM432WiedervorlageTest` runAs(A) + E2E | testbar |
| AC6 | fremde versteckt (und umgekehrt) | `SCRUM432WiedervorlageTest` runAs(A/B) | testbar |
| AC7 | Service-User kann beide setzen | `SCRUM432WiedervorlageFlsTest` (Positiv) + E2E (editable) | testbar |
| AC8 | Nicht-Editor kann nicht ändern | `SCRUM432WiedervorlageFlsTest` (Negativ) | testbar |

---

## ⚠️ Relevante Befunde (Repo-Analyse, Stand `origin/master`=`02ee719`)
1. **Kundenspalte unbestimmt** — `ACCOUNT.NAME` für eine **Case**-Listview ist im
   Repo/Read-only **nicht** verifiziert (nur auf `Opportunity` gewiesen). Erste
   Developer-Aktion: Deploy-Validate, Token aus Ergebnis übernehmen (ADR-6).
2. **Lightning-Placement = Org-Schritt** — Repo trackt nur Classic `Case-Case
   Layout`; Lightning Page im Org (ADR-8 → DevOps/Tester).
3. **Sortierung nicht persistierbar** (ADR-7) → AC4 untestbar, UI-Sort.
4. Keine bestehenden `Wiedervorlage*`-Felder/-Relation auf Case (Collision-Scan OK).
5. House pattern 1:1 vorhanden: `Is_Due__c`/`Nachfassliste` (378), 
   `Is_Close_Date_Overdue__c`/`Ueberfaellige_Chancen` (414), `From_User__c`
   (User-Lookup, 410) — keine Design-vom-blatt.

## Offene Punkte (blocken die Implementierung NICHT)
- [ ] **AC4 Dauer-Sort:** UI-Kolumnen-Sort als Erfüllung annehmen (empfohlen);
  sonst eigenes (späteres) UI/Ticket. → **@po-agent** (info)
- [ ] **„Gesetzt von“ = Nutzer wählt sich selbst** (kein Auto-Pflegen, da Auto-
  matisierung ausgeschlossen). Wenn auto-„ich“ gewünscht → gehört ins spätere
  Erinnerungs-Ticket. → **@po-agent** (info)
- [ ] **Lightning-Page-Placement** (App Builder) im Test-Org setzen + lesen,
  vor Prod erneut. → **@devops-agent** (Deploy-Verify)
- [ ] **PS-Zuweisung + Read-Back** (Targetorg-User + 2. Service-Konto) im
  Developer-Handoff. → **@developer-agent** (Pflicht)
- [ ] **FLS-Default des neuen Lookup-Felds im Ziel-Profil messen** (nie
  extrapolieren — 421 vs 430), Negativ-Probe im FLS-Test. → **@developer-agent**

## ADR-Zusammenfassung (Architektur-Entscheidungen)
1. **Rein deklarativer Build** (4 Custom Fields + 1 Listview + 1 PS), kein
   Apex/Trigger/Flow — PO schließt Automation aus; alles deklarativer Read/Write.
2. **Persönlich via Checkbox-Formel gegen `$User` + Listview-Filter `=1`** —
   geprüfte Standard-Mechanik (Metadata-ListView hat keinen Current-User-Filter),
   1:1 Hausmuster `Is_Due__c`/`Is_Close_Date_Overdue__c`.
3. **Eigener `Wiedervorlage_Von__c`-Lookup**, nicht `OwnerId` — trennt
   „persönliches Memo des Setsenden“ von Case-Zuordnung; Sharing bleibt unangetastet.
4. **FLS via neuem PS `SCRUM432_Wiedervorlage_ServiceTeam` (R/E auf 3 Speicher-,
   R-only auf Formelfeld), kein Profil-Edit.**
5. **Kein Sharing-Eingriff** — persönlichkeit ist ein Listview-Filter, kein
   record-level change.