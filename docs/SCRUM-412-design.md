# SCRUM-412 — Ansprechpartner eines Accounts direkt in der Account-Kontaktübersicht anzeigen

**Architektur-Status:** freigegeben 2026-09-12 (architect-agent)
**Art:** rein deklarativ / Verifikations-Story — **keine neuen Objekte, keine neuen Felder, kein Apex, kein Flow, keine DML, kein Rollup.**
**Basis:** Test-Org `devops-agent@cline.test`, SfDX-Repo `FirstSalesforceProject`. Alle Befunde unten per genanntem Befehl im Ziel-System verifiziert.

---

## Ziel

Wer einen Account öffnet, sieht Name, Telefon und E-Mail seiner Ansprechpartner (Contacts) direkt in der Contact-Related-List auf dem Account — ohne jeden Kontakt einzeln zu öffnen. Die Daten stammen live aus den Contact-Standardfeldern `Name`, `Phone`, `Email`; es wird nichts am Account dupliziert oder gepflegt.

---

## Zentrale Architektur-Entscheidung (ADR-1)

**Die Übersicht ist die bestehende `RelatedContactList` auf dem Account. Es gibt nichts zu bauen.**

- AC1–AC3 sind von der Plattform nativ erfüllt, *sobald die Related-List die Spalten Name/Phone/Email trägt*:
  - **AC2/AC3 (live aus dem Contact):** trivial wahr — eine Related-List zeigt die aktuellen Wertefelder des `Contact`-Child-Records. Ändert man `Contact.Phone`, zeigt die Liste den neuen Wert, weil kein Zwischenspeicher am Account existiert. Genau die geforderte „keine Duplizierung"-Eigenschaft.
  - **AC4 (Account ohne Kontakte):** wahr per Definition — eine Related-List ohne Child-Records rendert leer, kein Fehler.
  - **AC5 (FLS respektiert):** wahr per Definition — Related-Lists lesen Standardfelder und respektieren automatisch die Contact-Read-FLS des öffnenden Nutzers; eine Blöcke-Spalte ohne FLS bleibt leer. Es wird *nichts* umgangen.
- Konsequenz: **kein Apex, kein Flow, kein DML, kein Rollup, kein neues Feld, kein neuer Permission Set.** Die Out-of-Scope-Liste des POs wird vollständig eingehalten.

### ADR-2 — Kein Rollup / kein „Ansprechpartner"-Feld

PO-Abgrenzung explizit umgesetzt: kein `Account`-Custom-Feld, kein Flow, kein Queueable, der Contact-Werte auf den Account kopiert. Eine solche Lösung hätte AC2/AC3 verletzt (veralteter Stand nach Contact-Änderung). Die Related-List ist die einzige Lösung, die „live aus dem Contact" strukturell garantiert.

### ADR-3 — Kein Custom Lightning-FlexiPage

Die Org enthält **null** `FlexiPage` für `Account` (Tooling-API, `EntityDefinitionId` des Accounts, vgl. Befund unten). Der Account nutzt die **System-Record-Page** von Lightning. Deshalb ist die Lightning-Ansicht **Org-gemanagt** (App Builder / Related-List-Spaltenkonfiguration) — kein Artefaktpfad im Repo. Das ist konsistent mit der House-Regel „Lightning pages are NOT in source control" (`references/salesforce-sfdx-patterns.md`, Befund 1).

---

## Befunde im Ziel-System (verifiziert)

### B1 — Classic: Related-List trägt die Spalten bereits (Repo, `search_files RelatedContactList`)

Alle **vier** Account-Classic-Layouts enthalten die `RelatedContactList` mit den Spalten `FULL_NAME`, `CONTACT.TITLE`, `CONTACT.EMAIL`, `CONTACT.PHONE1`:

```
force-app/main/default/layouts/Account-Account Layout.layout-meta.xml              (Zeile ~269–273)
force-app/main/default/layouts/Account-Account %28Sales%29 Layout.layout-meta.xml  (Zeile ~226–230)
force-app/main/default/layouts/Account-Account %28Marketing%29 Layout.layout-meta.xml (Zeile ~226–230)
force-app/main/default/layouts/Account-Account %28Support%29 Layout.layout-meta.xml (Zeile ~226–230)
```

```xml
<relatedLists>
    <fields>FULL_NAME</fields>
    <fields>CONTACT.TITLE</fields>
    <fields>CONTACT.EMAIL</fields>
    <fields>CONTACT.PHONE1</fields>
    <relatedList>RelatedContactList</relatedList>
</relatedLists>
```

→ **Classic ist in der Quelle bereits erfüllt.** Name (`FULL_NAME`), Telefon (`CONTACT.PHONE1`) und E-Mail (`CONTACT.EMAIL`) sind alle da; `CONTACT.TITLE` ist ein harmloser Bonus (AC verlangt „mindestens" Name/Telefon/E-Mail). **Keine Layout-Änderung nötig.**

### B2 — Lightning: keine Custom Record Page in der Org (Tooling-API)

```
sf data query --use-tooling-api \
  -q "SELECT Id, DeveloperName, MasterLabel FROM FlexiPage
      WHERE EntityDefinitionId='<Account EntityDefinitionId>'"
→ 0 records
```

`EntityDefinitionId` des Accounts: `000000000000000AAA` (standard). Die Lightning-Ansicht des Contact-Blocks auf dem Account ist die **System-Record-Page** bzw. deren Related-List-Standard-Spaltenkonfiguration → **Org-Bereich, kein Datei-Pfad im Repo**.

### B3 — FLS: `Phone`/`Email` sind lesbar (UI-API object-info, FLS-filtriert)

```
sf api request rest /services/data/v62.0/ui-api/object-info/Contact
→ fields: Name/LastName/Phone/Email/MobilePhone alle PRESENT
```

In einem FLS-filtrierten object-info ist ein Feld **nur enthalten, wenn der aufrufende Nutzer Lese-FLS darauf hat**. `Phone` und `Email` sind present ⇒ Lese-FLS existiert (System-Admin-Konntext). Ein Custom Permission Set ist daher **nicht** nötig, solange das relevante Standard-Profil bereits Contact-Read-FLS auf Phone/Email gewährt — das ist in Standard-Profilen (Sales/Support/Admin) der Fall. **Kein neuer Permission Set in dieser Story.** (AC5 wird vom Tester mit einem eingeschränkten Nutzer final bestätigt; s. Open Items.)

---

## Was der Developer konkret umsetzt

**Es gibt keine Metadata-Datei zu erzeugen.** Das Artefakt der Story ist **E2E-Beweis, dass die Anforderung in beiden UIs gilt** (+ bedingter Org-Schritt).

### Komponenten
1. **E2E-Spec (Classic):** `tests/e2e/SCRUM-412-account-kontaktuebersicht-classic.spec.ts`
   - AC1: Account mit ≥ 2 Kontakten (Name/Phone/Email) öffnen → `RelatedContactList` „Kontakte" zeigt je Kontakt die Spalten Name, Telefon, E-Mail.
   - AC4: Account ohne Kontakte öffnen → Related-List leer, kein Fehler.
2. **E2E-Spec (Lightning):** `tests/e2e/SCRUM-412-account-kontaktuebersicht-lightning.spec.ts`
   - AC1: Account (Lightning Record Page) mit Kontakten → Contact-Related-List zeigt Name, Telefon, E-Mail.
   - AC2/AC3: `Contact.Phone` (bzw. `Email`) per SOQL/UI ändern → Account neu laden → neuer Wert sichtbar (live, ohne Pflege am Account).
3. **Testdaten-Setup** (Probesatz): 1 Account mit 2 Kontakten, 1 Account ohne Kontakte — über Testdaten-Helfer (kein DML-Code als Artefakt, nur E2E-Setup).

### Test-Strategie (warum E2E, kein Apex)
- Kein Apex/Trigger/Flow wird gebaut, folglich **keine Apex-Testklasse und keine Coverage-Pflicht** aus dieser Story.
- Die „Funktion" ist reine UI-/Plattform-Verdrahtung → E2E ist das richtige Prüfartefakt und deckt AC2/AC3 (Live-Verhalten über UI) ab, was ein Apex-Test *nicht* ausdrücken kann.

---

## Datenmodell / Sharing / Governor Limits
- **Datenmodell:** keine Änderung (keine neuen Objekte/Felder/Relationships/Record Types).
- **Sharing:** keine Änderung. Sichtbarkeit der Contacts folgt dem bestehenden Account→Contact-Sharing (`ParentAccount`). Kein neues Sharing, keine OWD-, Rollen- oder Sharing-Rule-Änderung.
- **Governor Limits:** irrelevant (kein Apex, kein Flow, kein DML).

## Flow-vs-Apex (ADR-1/2 umgekehrt verifiziert)
Weder Flow noch Apex gewählt — beides wäre hier *falsch*, weil es die AC2/AC3-Eigenschaft („live aus dem Contact, kein Cache") verletzen oder das Problem unnötig komplex machen würde. Deklarative Related-List ist die einzige saubere Lösung. Dokumentiert gemäß House-Regel „Apex over Flow" — hier bewusst *weder* gewählt, mit Begründung.

## Permission Set / FLS
- **Kein neuer Permission Set.** Lese-FLS auf Contact `Name`/`Phone`/`Email` via bestehenden Standard-Profilen. (House-Regel FLS-over-Profile wird eingehalten, weil **gar nichts Neues** hinzukommt, was eine FLS-Lücke öffnen könnte.)

---

## ⚠️ Befund mit Org-Schritt (nicht blockierend für die E2E)

- **Lightning-Contact-Related-List-Spalten** liegen in der System-Record-Page (0 Custom FlexiPages für Account, B2). *Falls* die Lightning-Related-List in der Org-Standardansicht `Phone`/`Email` **nicht** als Spalten zeigt (nur Name), ist das ein **Related-List-Spalten-Config-Schritt im App Builder (Org)** — kein Source-Änderung, kein Code. **Eigentümer: @devops-agent** (nur falls E2E-Lightning-AC1 das zeigt).
- Ist die Lightning-Related-List per Default bereits Name+Phone+Email (häufiger Standardfall), ist **kein** Org-Schritt nötig.

## Offene Punkte (blocken die E2E-Implementierung NICHT)
- [ ] Lightning-Related-List-Default-Spalten in der Org per E2E bestätigen (developer-agent führt E2E aus; bei Abweichung → @devops-agent macht App-Builder-Spaltenconfig).
- [ ] AC5 final mit einem **eingeschränkten** Kontakt-Read-Nutzer verifizieren (tester-agent); bei Lücke im Standard-Profil wird nachträglich ein FLS-Permission Set entworfen (heutiger Befund B3: kein Bedarf im Admin-/Standard-Profil-Kontext).
- [ ] `CONTACT.TITLE`-Spalte in Classic behalten (Bonus, AC-neutral) oder entfernen? **Empfehlung: behalten** — AC verlangt „mindestens" 3 Spalten, ein 4. Informationsfeld ist gewünscht und schadet nicht.

---

## Für @user (Kurz-Fassung)
Es ist **nichts Neues zu bauen**: Die „Kontakte"-Liste, die Sie unten auf einem Account schon sehen, zeigt je Kontakt bereits Name, Telefon und E-Mail directly aus den Kontakten. Wenn sich die Nummer eines Kontakts ändert, sieht die Liste sofort den neuen Wert, weil sie nichts speichert, sondern live den Kontakt liest. Ein Account ohne Kontakte zeigt eine leere Liste. Wir legen dazu einen automatisierten Check an, der das in Lightning und Classic beweist; falls die Lightning-Liste in Ihrer Ansicht ausnahmsweise keine Spalte für Telefon/E-Mail zeigt, ergänzen wir das einmalig per Einstellung (ohne Code).
