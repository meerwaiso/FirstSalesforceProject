# Security Audit — Prod-Org (read-only)

**Ticket:** SCRUM-427
**Datum:** 2026-09-23
**Org:** Prod-Org (`00Dg500000DkTtzEAF`, `orgfarm-0effda4ab9-dev-ed.develop.my.salesforce.com`)
**Login (Audit-Executor):** `devops-agent@cline.de` (Alias `Prod-Org`)
**Ablauf:** **ausschließlich read-only** — nur `sf data query` (SELECT), `sf sobject describe`, `sf org display` und `sf project retrieve start` (Metadata lesen). Keine DML, kein Modify, kein Deploy, keine Änderung an Daten, Metadaten, Einstellungen, Benutzern oder Berechtigungen.

---

## 1. Zusammenfassung (für die Betreiberperson, ohne Jargon)

Die Org ist **klein, intern und relativ dicht** — das ist gut. Es gibt nur 9 angemeldete Nutzer, von denen 4 volle Admin-Rechte haben. Es gibt **keine externen oder Gästekonten** (alle Community-/Portal-Lizenzen sind komplett ungenutzt) und **keine aktiven Sharing-Regeln**, die Daten über Team-Grenzen hinweg freigeben würden. Das Code-Umfang (76 Apex-Klassen, 10 Trigger) ist überschaubar und enthält **keine** typischen Injections-Schwachstellen.

**Wo es trotzdem Aufmerksamkeit braucht — die zwei wichtigsten Punkte:**

1. **Zweistufen-Überprüfung (MFA/2FA) ist org-weit NICHT verpflichtend.** Keines der 44 Nutzerprofile erzwingt MFA forciert das Einloggen. Das heißt: Wenn jemand das Passwort eines dieser Nutzer hat, muss er nicht einmal ein zweites Gerät zeigen. Für 4 Volladmins ist das ein reales Risiko.
2. **Vier Nutzer haben volle Admin-Rechte**, und einer davon (ein Integration-/Agent-Konto) hat sie über ein Profil, das sie nicht unbedingt braucht. Volladmin sollte man auf das Minimum halten.

Alles andere (Passwortrichtlinie, keine IP-Restriktionen, kein Code-Risiko) steht im Detail unten.

> **Hinweis:** Der Salesforce Health-Check-Score selbst ist nicht per read-only-CLI oder Metadata abrufbar — er steht nur in der Setup-Oberfläche (Setup → „Health Check"). Er ist daher in diesem Report bewusst **nicht** erfunden, sondern als „manuell in Setup prüfen" gekennzeichnet.

---

## 2. Dringendste Probleme (nach Dringlichkeit)

| # | Dringlichkeit | Bereich | Befund | Risiko |
|---|---------------|---------|--------|--------|
| 1 | **Hoch** | Benutzerrechte / MFA | Keines der 44 Profile erzwingt Zweistufen-Überprüfung (`PermissionsForceTwoFactor` = `false` überall). Org-weit gibt es keinen 2FA-Zwang. | Ohne 2FA reicht ein gestohlenes/geratetes Passwort zum Vollzugriff. Bei den 4 Volladmin-Nutzern ist das Schadenspotenzial maximal (ganze Org). |
| 2 | **Hoch** | Benutzerrechte | 4 von 9 Nutzern haben volle Admin-Rechte (`ModifyAllData`/`ViewAllData`): 2× via Profil *System Administrator*, 1× via Profil *System Administrator*, 1× via Profil *Analytics Cloud Integration User* (hier nur `ViewAllData`). | Jedes Admin-Konto ist ein Einfallstor. Integration-/Agent-Konten mit `ViewAllData` können alle Kundendaten lesen. |
| 3 | **Mittel** | Code | `CustomerTransferController` (LWC-Backend) ist `without sharing` und stellt 4 `@AuraEnabled`-Methoden bereit **ohne** Permission-/`hasAccess`-Gate; `launch()` startet einen DML-Job. | Jeder Nutzer mit Sicht auf die Quick-Action `betreuungsuebergabe` kann die Aktion auslösen; die Vorschau-Logik sieht zudem über Sharing-Grenzen. Bewusst so gebaut (SCRUM-365-Präzedenz), aber es fehlt ein explizites Berechtigungs-CHECK im Endpunkt. |
| 4 | **Mittel** | Einstellungen | Es gibt **keine** Login-Zeitfenster (`UserListView` = 0) und keine IP-Beschränkung (`LoginIp` = 4 Einträge = bekannte IP-Adressen, keine LoginRange-Restriktion). | Ein kompromittiertes Passwort kann zu jeder Uhrzeit und aus jedem Netzwerk verwendet werden. |
| 5 | **Niedrig** | Einstellungen | Passwortrichtlinie ist eher locker: Mindestlänge 8, Komplexitätsstufe 1/4, 90 Tage Ablauf, 3 Historie, 10 Versuchsgrenze, 15 Min Sperre. | Erleichtert Brute-Force/Passwort-Recycling gegenüber strengerer Richtlinien (12+ Zeichen, Stufe 3+). |
| 6 | **Niedrig** | Code | 26 der 76 Apex-Klassen sind ohne `with sharing` (Trigger-Handler, Rebuilder, Batch-Klassen). | Meist beabsichtigt (Rollup/Rebuilder müssen Bestand sehen), aber ohne `with sharing` gilt die Sharing-Logik nicht automatisch — bei nachgerückten Funktionen leicht vergessen. Kein aktiver Befund, aber ein Muster zu beobachten. |
| 7 | **Niedrig** | Datenschutz / OWD | Die Default-Teilungsstufe (OWD) ist **nicht** per read-only-CLI verifizierbar (steht weder in Profile-Metadaten noch in abrufbaren SharingRules; 230 SharingRules-Dateien, **0** mit Regeln). | Nicht verifizierbar, **nicht** „problemlos" — muss manuell in Setup bestätigt werden (siehe Abschnitt 3). |

> „Kein Befund ist ein Befund": Bereiche ohne Fund sind in Abschnitt 3 entsprechend als „kein Befund" abgedeckt.

---

## 3. Was konkret zu tun ist — Schritt für Schritt je Befund

### Befund #1 — Zweistufen-Überprüfung (MFA) org-weit verpflichtend machen *(Hoch)*
1. In Prod-Org: **Setup → Security → „Two-Factor Authentication"**.
2. Dort **„Enforce Two-Factor Authentication for all users"** aktivieren (oder auf die Rolle/Profile einschränken, die es brauchen — mind. alle Admins).
3. Alternativ/ergänzend: **Setup → „Multi-Factor Authentication Policies"** → Richtlinie mit „MFA required for login" wählen und den Profilen/Permission Sets zuordnen.
4. Nach dem Change: 1–2 Wochen Übergangsfrist geben, in der Nutzer ihre MFA-Methoden einrichten dürfen, bevor der Zwang greift.
5. **Kontrollieren:** Ein nicht-MFA-fähiges Passwort sollte beim Anmelden mit 2FA-Zwang an der Schwelle scheitern.

### Befund #2 — Volladmin-Nutzer reduzieren *(Hoch)*
1. Prüfen, welche der 4 Admin-Nutzer die Rechte **tatsächlich** für den Alltag brauchen.
2. Das *Analytics Cloud Integration User*-Profil: dort `ViewAllData` prüfen — wenn die Integration nur ihre eigenen Tabellen braucht, `ViewAllData` entfernen und stattdessen gezielte Object-Rechte geben.
3. Integration-/Agent-Konten (z. B. `epic.b2c…@orgfarm…`, `integration@…`) möglichst auf **dedizierte Permission Sets** umstellen statt auf „System Administrator".
4. Nach jedem Schritt die verbleibenden `ModifyAllData`/`ViewAllData`-Nutzer neu zählen und dokumentieren; Ziel: nur die Personen, die morgen wirklich Admin sein müssen.

### Befund #3 — `CustomerTransferController`-Endpunkt absichern *(Mittel)*
1. In jedem `@AuraEnabled`-Endpunkt einen expliziten Permission-Check ergänzen, z. B. vor `launch()`:
   - `Security.HasPermission` gegen ein dediziertes Custom Permission, **oder**
   - `System.HasPermission('PermissionSetName')`.
2. Den `without sharing`-Zweck (Vorschau über Sharing-Grenzen) mit einem Kommentar begründen und sicherstellen, dass die Endpunktdaten danach nur an Nutzer rausgeben, die das Feature ausführen dürfen.
3. **Kontrollieren:** Nutzer ohne die Berechtigung sehen keine Möglichkeit, `launch` auszulösen (kein Toast-/Job-Start).

### Befund #4 — Login-Zeitfenster / IP-Restriktion *(Mittel)*
1. Falls das Team nicht rund um die Uhr arbeitet: **Setup → Security → „Login Hours"** → Zeitfenster pro Rolle/Profil einrichten.
2. Falls feste Ausgangs-IPs (Headquarter, Büro) existieren: **Setup → Security → „Network Access"** → erlaubte IP-Bereiche anlegen.
3. Für reine Integrationen: **Setup → „Remote Site Settings"** + ggf. **IP-Restriction auf das API-Konto** engziehen.

### Befund #5 — Passwortrichtlinie anziehen *(Niedrig)*
1. **Setup → Security → „Password Policies"**.
2. Mindestlänge auf **12** erhöhen, Komplexität auf **Stufe 3** (Groß-/Kleinbuchstaben + Zahl + Sonderzeichen), Historie auf **5** anheben.
3. Ablauf (90 Tage) kann bleiben; die Sperre (10/15 Min) ist ok.

### Befund #6 — `with sharing`-Muster beobachten *(Niedrig)*
1. Keine Sofortmaßnahme nötig.
2. In Code-Reviews als Checkliste einpflegen: „Neue Klasse, die DML/SOQL auf Kundendaten macht → braucht `with sharing`, außer mit dokumentiertem Grund".
3. Bestandsklassen bei nächster Änderung mit `with sharing` nachziehen, wo es fachlich passt.

### Befund #7 — OWD manuell bestätigen *(Niedrig, aber wichtig einzuordnen)*
1. **Setup → Security → „Sharing Settings"** → für die geschäftskritischen Objekte (Account, Contact, Case, Lead, Opportunity) die Default-Teilstufe ablesen.
2. Ziel: Standard = **„Private"** (außer für den Admin/Manager-Hierarchie).
3. Falls ein Objekt auf „Read" steht, prüfen, ob das gewollt ist — sonst auf „Private" stellen.
4. Ergebnis hier in ein Folgeticket aufnehmen, falls etwas nicht „Private" ist.

---

## 4. Prüfbereiche im Detail („kein Befund" ist ein Befund)

### 4.1 Allgemeine Einstellungen
- **Passwortrichtlinie** (read-only abgerufen): min. Länge 8, Komplexität 1, Ablauf 90 Tage, Historie 3, max. 10 Versuche, Sperre 15 min, Passwort-Frage aktiv. → **Befund #5.**
- **MFA-Zwang:** 0/44 Profile erzwingen `ForceTwoFactor`. → **Befund #1.**
- **Health-Check-Score:** nicht per read-only CLI/Metadaten abrufbar — **manuell in Setup → Health Check prüfen** (siehe Hinweis oben).
- **Login-/IP-Restriktionen:** `LoginIp` = 4 (bekannte IP-Adressen, keine LoginRange-Restriktion), `UserListView` = 0 (keine Login-Zeitfenster), `LoginHistory` = 406. → **Befund #4.**

### 4.2 Benutzerrechte
- **Gesamtnutzer:** 9.
- **Volladmin (`ModifyAllData`/`ViewAllData`):** 4 Nutzer (2× System Administrator, 1× System Administrator, 1× Analytics Cloud Integration User/`ViewAllData`). → **Befund #2.**
- **Permission Sets, die Admin-Rechte gewähren:** 3 (`PermissionsModifyAllData` oder `PermissionsViewAllData` = true).
- **Inaktive Nutzer mit kritischen Rechten:** 0. → **kein Befund.**
- **Profile Gesamt:** 44 (viele Standard/Inaktive).

### 4.3 Datenfreigabe & Datenschutz
- **OWD:** nicht per read-only verifizierbar; 230 SharingRules-Metadaten-Dateien, **0 davon mit aktiven Regeln** (keine expliziten Freigaben). → **Befund #7** (manuell bestätigen).
- **Externe Gäste / Experience Cloud:** 19 externe/Geschäfts-Lizenzen existieren, **alle mit 0 genutzten Lizenzen** (kein aktiver Gast, kein aktiver Portal-User). Eine Experience existiert (`sfdcEnablement_EnablementWorkspace` — interne Enablement-Site, nicht öffentlich). → **kein Befund** für aktive externe Zugänge.
- **PII / Field-Level-Security:** verschlüsselte/PII-Felder sind an die OWD/FLS-Analyse gebunden; mit Befund #7 (OWD) abzudecken. Dediziertes PII-Masking wurde nicht als separater Befund gefunden.

### 4.4 Code & Anpassungen
- **Apex:** 76 Klassen in der Org, 10 Trigger. Repo-Analyse (Autor des Reports, eigener Code-Durchlauf):
  - **SOQL-Injection:** keine dynamische String-Konkatenation in SOQL/DMQL gefunden (alle Queries sind statische Literale oder parametrisiert, z. B. `WHERE Id IN :ids`). → **kein Befund.**
  - **Callouts / `@RestResource`:** keine gefunden. → **kein Befund.**
  - **`with sharing`:** 3 Klassen `with sharing`, 26 ohne (s. Befund #6).
  - **Unschutzte Endpunkte:** `CustomerTransferController` (4× `@AuraEnabled`, ohne Permission-Check, `without sharing`). → **Befund #3.**

---

## 5. Bestätigung — read-only-Ablauf

Der Audit hat **ausschließlich read-only** stattgefunden. Durchgeführte Operationen:
- `sf data query` (nur `SELECT` / `Count`),
- `sf sobject describe` (Schema lesen),
- `sf org display` (Org-Info),
- `sf project retrieve start` (Metadaten **lesen** nach lokal).

Es wurden **keine** Änderungen an Daten, Einstellungen, Metadaten, Benutzern oder Berechtigungen in der Prod-Org vorgenommen. Keiner der abgewiesenen/verworfenen Read-Versuche war ein Write-Versuch.
