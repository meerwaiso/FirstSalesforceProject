# SCRUM-386 — Lead-Dubletten-Markierung per E-Mail · Authoritative Build-Spec

> **This file is the source of truth** für exakte API-Namen, XML, Apex und
> Pfade. Die Jira-Kommentare zu SCRUM-386 werden vom Jira-Markdown-Konverter
> beschädigt (doppelte Unterstriche → Bold, XML-Endtags werden weggefressen —
> auf diesem Projekt wiederholt verifiziert, SCRUM-375/378/381). Die Dateien
> werden aus DIESEM Doc gebaut; API-Namen nicht aus Jira-Kommentaren kopieren.
> In-Repo-Referenzdateien (deployen aktuell, Shapes davon kopieren) stehen
> unter „Dateien“.

## Goal
Lead gegen Lead per E-Mail case-insensitiv auf Dubletten prüfen: zwei neue
Felder auf Lead (Kennzeichen + „Doppelt zu“) werden bei Insert und bei
E-Mail-Änderung automatisch gesetzt, bei eindeutiger E-Mail geleert —
bulk-fähig (200 Records, Dubletten auch innerhalb desselben Batch),
konvertierte Leads vollständig ausgeschlossen.

## Branch
`feature/SCRUM-386-lead-duplicate` frisch von `master` abziehen.
Geteilter Tree: `.cline-roles/` und `scr378-report-final.zip` liegen untracked
— weder commiten noch löschen, nur explizit eigene Pfade stageen.
Niemals `git add .` / `-A`.

## ADR

### ADR-1: Apex Trigger (before insert + before update) — kein Flow, keine ValRule, kein Built-in Duplicate Management
Markierung + dynamischer Referenzwert (Name des ältesten Leads) + Auto-Clear
erfordern Apex. Flow: Hausregel Apex-over-Flow bei Verzweigungslogik
(Schema-Drift/apiVersion, dokumentiert). ValRule: kann keine Felder setzen
und würde blocken (Anforderung ist nur Markierung). Plattform-Duplikatregeln
(Duplicate Management) setzen keine Felder → taugen nicht. Ein neuer
Trigger-File auf Lead (vorher KEIN Lead-Trigger im Repo) im Haus-Muster „ein
Trigger pro Objekt“ (SCRUM-381/384).

### ADR-2: Case-insensitive Matching → technisches Feld Email_Norm__c
SOQL kennt kein `LOWER()`; `Email IN :list` ist **case-sensitive**. Eine
case-insensitive Abfrage über das Rohefeld `Lead.Email` ist in SOQL nicht
möglich (LSI/PII-Match auf Standardfeldern wird bewusst NICHT angenommen —
Edition-abhängig, hier nicht verifizierbar). Lösung: drittes, technisches
Feld
`Lead.Email_Norm__c` = Text(255), gefüllt vom selben Trigger mit
`lower(trim(Email))` bei jedem Insert/Update; Abfrageraum ist damit
case-insensitiv exakt.
Folge (Pflicht): **One-off-Backfill** aller bereits existierenden,
nicht-konvertierten Leads nach Phase-2-Deploy, sonst referenzieren neue
Leads ältere Dubletten nur, wenn deren Case zufällig matcht. → Org-Schritt
@devops-agent (Script + Verifikation in „Dateien“), vorab NICHT blockierend,
vor finaler Tester-Verifikation in der Org aber **erforderlich**.
Zweite Folge: `Email_Norm__c` gehört ins Permission Set (readable), weil
SOQL FLS respektiert — ein Aktor ohne FLS auf dem Feld würde den Trigger-Query
crashen (No-such-column). Das PS wird an die Autoassign-Gruppe vergeben →
alle Lead-User haben das Feld lesbar.

### ADR-3: AC5 Bulk-200 + Dubletten innerhalb desselben Imports — Ein-Pass-Lösung (der zentrale Entscheid)
Ein before-insert SOQL sieht **nur den commitierten Zustand**: Schwestern
der eigenen DML-Anweisung sind zur Trigger-Zeit nicht abfragbar. Eine
naive Pre-Insert-Abfrage findet intra-Batch-Dubletten also nie — das
bestätigt die PO-Feststellung. Lösung ist **keine Zweiphasen-Sequenzierung**
(kein after-insert-DML, kein Queueable, keine zweite Trigger-Invocation),
sondern *ein* deterministischer Pass über `Trigger.new` (Liste ist pro Batch
stabil) aus genau zwei Maps:

1. **dbMap** — 1 SOQL: ältester nicht-konvertierter Lead pro Normal-Email
   (Sortierung `CreatedDate ASC, Id ASC`, in Apex pro Norm-Key das erste
   Element behalten).
2. **batchFirst** — Map, die beim Durchlauf pro Norm-Key den *ersten*
   Kandidaten des Laufes hält.

Referenz pro Kandidat = `dbMap[norm]` (existiert DB- Lead, ist er immer
älter) sonst `batchFirst[norm]` sonst eindeutig → nicht markiert/geleert.

Determinismus: Intra-Batch teilen sich alle Kandidaten desselben Imports die
gleiche commitierte `CreatedDate`; `Id` ist in der before-Phase
**noch nicht zugewiesen** → die PO-Semantik (CreatedDate, dann kleinste Id)
ist intra-Batch nicht wörtlich semantisch;
Tie-Breaker ist die **Listen-Position in Trigger.new** (deterministisch pro
Batch, in der Reihenfolge des Import-Batches). Das ist das Intra-Batch-Äquivalent
der PO-Semantik und wird im Test fixiert.

**Kein second Trigger-Set nötig**: ein einziger Trigger-File mit
before insert + before update deckt alle Fälle; die Sequenzierungsfrage
löst sich auf, weil intra-Batch-Auflösung ausschließlich aus `Trigger.new`
kommt und inter-Batch-Auflösung aus 1 SOQL.

### ADR-4: Auto-Clear (AC3b) nur bei effektiver E-Mail-Änderung
Reevaluation erfolgt nur, wenn der Normalwert sich ändert
(`norm(old) != norm(new)`, inklusive null→wert und wert→null). Reine
Case-Änderung desselben Normalwerts und andere Edits rühren die Markierung
nicht an. Bekannte Limitation (bewusst out of scope, PO: „nur Markierung“):
wird der referenzierte Lead gelöscht, bleibt die Markierung stehen, bis die
eigene E-Mail next geändert wird.

### ADR-5: without sharing
Die Markierung muss unabhängig vom Profil des anlegenden Bearbeiter greifen
(PO: jeder Vertriebsmitarbeiter). Sichtbarkeit der Felder steuert FLS (PS),
nicht Sharing. Präzedenz: `OpportunityLockedAccountGuard` (SCRUM-384,
`without sharing` mit gleicher Begründung). Sharing-Modell: **keine Änderung**
(PO-Festlegung; Felder liegen auf Lead).

### ADR-6: Konvertierte Leads vollständig ausgenommen
Sowohl als Markierungsobjekt (`if (lead.IsConverted) continue;` in beide
Phasen) als auch als Referenz (Query filtert `IsConverted = false`).

### ADR-7: FLS → ein Permission Set, editables upper-bound
`SCRUM386_LeadDuplicate` mit `readable=true` **und** `editable=true` auf
allen drei Feldern, `hasActivationRequired=false`, Profile unverändert.
PO-Tabelle „Read-only“ bleibt damit implementierbar: Feld-FLS ist
Obergrenze, kein Boost — ein User ohne Object-Edit auf Lead nutzt
`editable=true` nie praktisch (Precendenz SCRUM-384 ADR-4, Pattern
`SCRUM359_NewsletterConsent`/`SCRUM353_FeldFinoIlsede`).

### ADR-8: 2-Phase-Deploy, neue Trigger-Datei (keine Erweiterung)
Phase 1 = die drei Fields (gelangen zuerst: Layout/PS/Trigger referenzieren
darauf); Phase 2 = Trigger, Klasse, Tests, PS, Layout, Manifeste.
House-Muster SCRUM-381/382/384. Auf Lead existiert **kein** Trigger →
neue Datei `LeadDuplicateGuard.trigger`, kein Merge mit bestehendem
Trigger.

## Datenmodell
- 3 neue CustomFields auf Lead:
  - `Likely_Duplicate__c` — Checkbox, label „Möglicher Doppeleintrag“,
    defaultValue false
  - `Duplicate_Of__c` — Text(255), label „Doppelt zu“, required false
  - `Email_Norm__c` — Text(255), label „Email (normalisiert)“, required false
    (technisch, **nicht** ins Layout)
- 1 neuer Trigger `LeadDuplicateGuard` (before insert, before update)
- 1 neue Klasse `LeadDuplicateGuard`
- 1 neues PS `SCRUM386_LeadDuplicate`
- 1 Layout-Change (Lead-Lead Layout, neues Section „Dublettenprüfung“)
- 2 Manifeste Phase 1/2
- 1 Backfill-Script + 1 Verifikations-SOQL
- Sharing: keine Änderung. ValRules: keine.

## Dateien — exakte Pfade

In-Repo-Referenzdateien ( Shapes kopieren):
- `force-app/main/default/objects/Lead/fields/Interesting__c.field-meta.xml` (Checkbox-Shape)
- `force-app/main/default/objects/Contact/fields/Additional_Comment__c.field-meta.xml` (Text-255-Shape)
- `force-app/main/default/triggers/AccountLockGuard.trigger` + `.trigger-meta.xml` (Trigger-Shape, meta apiVersion 62.0)
- `force-app/main/default/classes/AccountLockClearHandler.cls-meta.xml` (Klassen-meta apiVersion 63.0)
- `force-app/main/default/permissionsets/SCRUM384_AccountBlocking.permissionset-meta.xml` (PS-Shape)
- `force-app/main/default/classes/SCRUM359NewsletterConsentFlsTest.cls` (FLS-Test-Pattern)
- `docs/SCRUM-384-design.md` (doc-Hausform)

### Phase-1-Fields
1. `force-app/main/default/objects/Lead/fields/Likely_Duplicate__c.field-meta.xml`
   — Shape `Interesting__c`; `type` Checkbox, `defaultValue` false,
   label „Möglicher Doppeleintrag“, Beschreibung/inlineHelp je nach PO-Label.
2. `force-app/main/default/objects/Lead/fields/Duplicate_Of__c.field-meta.xml`
   — Shape `Additional_Comment__c`; `length` 255, `required` false,
   label „Doppelt zu“.
3. `force-app/main/default/objects/Lead/fields/Email_Norm__c.field-meta.xml`
   — Shape `Additional_Comment__c`; `length` 255, label „Email (normalisiert)“.

### Trigger & Klasse
4. `force-app/main/default/triggers/LeadDuplicateGuard.trigger`
```apex
/**
 * Lead-Trigger (SCRUM-386): Dubletten-Markierung per E-Mail.
 * before insert: neue Leads gegen DB + Batch pruefen (AC2, AC5).
 * before update: nur bei veraenderter Email neu bewerten (AC3, AC3b, AC4).
 * Konvertierte Leads: nie markiert, nie Referenz (ADR-6).
 */
trigger LeadDuplicateGuard on Lead (before insert, before update) {
    if (Trigger.isInsert) {
        LeadDuplicateGuard.handleBeforeInsert(Trigger.new);
    }
    if (Trigger.isUpdate) {
        LeadDuplicateGuard.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
    }
}
```
5. `force-app/main/default/triggers/LeadDuplicateGuard.trigger-meta.xml` — apiVersion 62.0, Active.
6. `force-app/main/default/classes/LeadDuplicateGuard.cls` — `public without sharing class LeadDuplicateGuard`.

Handler-Algorithmus (exakte Semantik; Developer implementiert 1:1):

```
private static Map<String, Lead> resolve(List<Lead> candidates, Set<Id> excludeIds) {
    // 1) Kandidaten filtern: Email nicht blank, nicht konvertiert
    //    (bei Update nur, wenn norm(old) != norm(new), ADR-4)
    // 2) Einmalige SOQL (1 pro Trigger-Invocation, nie im Loop):
    //    SELECT Id, Name, CreatedDate, Email_Norm__c
    //    FROM Lead
    //    WHERE IsConverted = false AND Email_Norm__c IN :normSet
    //    ORDER BY CreatedDate ASC, Id ASC
    //    → dbMap: pro normEmail das ERSTE Element (alterste, TIE-Breaker Id)
    //      excludeIds herausfiltern (Update-Pfad: eigener Id)
    // 3) Einzelner Pass über die Kandidaten in LISTE-ORDNUNG (Trigger.new-Reihenfolge):
    //      norm = lower(trim(lead.Email))
    //      norm empty → skip (AC4)
    //      ref = dbMap.get(norm) ?? batchFirst.get(norm)
    //      ref != null:
    //          lead.Likely_Duplicate__c = true
    //          lead.Duplicate_Of__c = ref.Name (falls > 255 Zeichen: shorten)
    //      sonst: (Insert) nichts setzen; (Update) beide Felder = null (AC3b)
    //      if (ref == null) batchFirst.put(norm, lead)   // erste Begegnung wird Referenz
    //      → 0 DML, 0 SOQL im LOOP, O(batch) Speicher
}
```
- Kein `hasFired`-Flag nötig (keine DML im Handler, keine Reentrancy).
- `Email_Norm__c` selbst wird im Handler mitgeführt:
  `lead.Email_Norm__c = Email == null ? null : Email.trim().toLowerCase()`
  für JEDEN geänderten Lead (Insert + Update), damit der Backfilled-Zustand
  bei späteren Edits erhalten bleibt.
- Name-Fallback: `ref.Name` ist auf Lead immer gesetzt (Standard-Namensfeld);
  Fallback auf `ref.Email_Norm__c` bei blankem Name (defensiv, im Test fixieren).

7. `force-app/main/default/classes/LeadDuplicateGuard.cls-meta.xml` — apiVersion 63.0.

### Tests
8. `force-app/main/default/classes/SCRUM386LeadDuplicateTest.cls` + meta (apiVersion 63.0):
   - AC2: existing „Max@Beispiel.de“, insert „max@beispiel.pde“ → markiert, `Duplicate_Of__c` = Name des Ältesten; Case in beide Directions.
   - AC3: Update auf existente E-Mail → markiert.
   - AC3b: Update auf eindeutige E-Mail → beide Felder null; auch auf null E-Mail.
   - AC4: Insert + Update ohne E-Mail → nie markiert.
   - Älteste-Semantik: 3 Leads gleiche E-Mail → Referenz = älteste CreatedDate; TIE-Breaker kleinste Id.
   - ADR-6: einzige Dublette ist konvertierter Lead → NICHT markiert;
     konvertierter Lead in Update → nicht markiert; konvertierter Lead nie
     als Referenz.
   - AC5 (Scale-Pattern SCRUM-367): **200 neue Leads in EINER `insert`-Anweisung**,
     enthält (a) Dubletten gegen bereits bestehende Leads und (b) mehrere
     AUS DEMSELBEN Batch → alle korrekt markiert, intra-Batch-Referenz = erste
     Liste-Position; assert, dass keine Dublette ungeprüft bleibt.
   - Governors: 200er-Batch ohne governor-limit Fehler.
9. `force-app/main/default/classes/SCRUM386LeadDuplicateFlsTest.cls` + meta —
   Pattern `SCRUM359NewsletterConsentFlsTest` 1:1: Temp-User „Standard User“
   Profil, Preconditions Object-Read, NEGATIV ohne PS (alle 3 Felder nicht
   lesbar/schreibbar), PS toew, POSITIV lesbar. (System Admins erben FLS
   — deshalb Standard User, nicht SysAdmin, verifiziert SCRUM-329.)

### PS
10. `force-app/main/default/permissionsets/SCRUM386_LeadDuplicate.permissionset-meta.xml`
— Shape `SCRUM384_AccountBlocking`; 3 `fieldPermissions`
(`Lead.Likely_Duplicate__c`, `Lead.Duplicate_Of__c`, `Lead.Email_Norm__c`),
jeweils `readable=true`, `editable=true`; label `SCRUM386_LeadDuplicate`;
`hasActivationRequired=false`; Beschreibung: SCRUM-386, FLS upper-bound,
Profile unverändert, `Email_Norm__c` lesbar für alle Lead-User (Trigger-Query
braucht FLS — ADR-2).

### Layout
11. `force-app/main/default/layouts/Lead-Lead Layout.layout-meta.xml`
— NEUES `layoutSection` (customLabel true, label „Dublettenprüfung“,
OneColumn) zwischen der „Nachfassung“-Section und „System Information“
INSERT (Punkt: nach Closing-Tag des "Nachfassung"-layoutSection, vor
`<layoutSections>` mit label „System Information“). Beide Felder als
`<behavior>Readonly</behavior>` (PO: systemgesetzt, Read-only).
`Email_Norm__c` kommt NICHT ins Layout.

### Manifeste
12. `manifest/scr386-phase1-fields.xml` — CustomField:
`Lead.Likely_Duplicate__c`, `Lead.Duplicate_Of__c`, `Lead.Email_Norm__c`; version 67.0.
13. `manifest/scr386-phase2-referencing.xml` — ApexTrigger `LeadDuplicateGuard`;
ApexClass `LeadDuplicateGuard`, `SCRUM386LeadDuplicateTest`,
`SCRUM386LeadDuplicateFlsTest`; PermissionSet `SCRUM386_LeadDuplicate`;
Layout `Lead-Lead Layout`; version 67.0.

### Backfill (Org-Schritt, @devops-agent, NACH Phase-2-Deploy)
14. `scripts/apex/scr386_backfill_email_norm.apex` (einmalig via `sf apex run`):
```
for (Lead l : [SELECT Email, Email_Norm__c FROM Lead WHERE IsConverted = false]) {
    l.Email_Norm__c = (l.Email == null) ? null : l.Email.trim().toLowerCase();
}
List<Lead> toUpdate = new List<Lead>();
Set<String> existing = new Set<String>();
for (Lead l : [SELECT Email, Email_Norm__c FROM Lead WHERE IsConverted = false]) { existing.add(l == null ? null : l.Email_Norm__c); }
// (einfache Version: alle nicht konvertierten Leads mit Email neu berechnen, update)
Database.update(toUpdate, true);
```
(Genauer Code vom Developer/Devops; Semantik: alle `IsConverted=false`-Leads,
`Email_Norm__c` = lower(trim(Email)), null bei leerer Email.)
15. `scripts/soql/scr386_verify_backfill.soql`:
`SELECT COUNT() FROM Lead WHERE IsConverted = false AND Email != null AND (Email_Norm__c = null OR Email_Norm__c != null AND LENGTH(Email_Norm__c) != LENGTH(TRIM(Email)))`
→ Erwartung 0 (Verifikation per Read-back, nicht per Deploy-Exit-Code).

## Governor Limits
- 1 SOQL pro Trigger-Invocation (IN-Clause, max 200 Norm-Keys bei AC5), 0
  DML, 0 SOQL im Loop, Speicher O(batch). 200er-Batch: kein Limit-Risiko.
- Kandidatenmenge der DB-Query ist durch die Anzahl Leads mit identischer
  Normal-Email begrenzt; bei Akzeptanz-Semantik (Lead gegen Lead, 1 E-Mail)
  klein. Kein LIMIT gesetzt (w
ürde älteste-Auswahl brechen).

## Deploy
1. Phase-1-Fields deployen (Manifest 12), Read-back: 3 FieldDefinitions
`sf data query` (FieldDefinition), alle present.
2. Phase 2 deployen (Manifest 13), Apex-Tests grün (RunLocalTests).
3. Backfill (14) + Verifikation (15) — Org-Schritt @devops-agent.
4. PS an Autoassign-Gruppe vergeben (Org-Schritt @devops-agent, Pattern
   SCRUM-384 ADR-4) — alle Lead-User müssen `Email_Norm__c` lesbar haben,
   sonst crasht der Trigger-Query (ADR-2).

## Technische Akzeptanzkriteria (ergänzend zu PO-Gherkin)
- AK-T1: 1 SOQL-Query pro Trigger-Invocation (Test mit `Limits.getQueries()`-Assert im 200er-Batch).
- AK-T2: Trigger feuert korrekt bei API-, UI- und Bulk-Pfad (insert via Apex in Test = Bulk-Pfad).
- AK-T3: FLS-NEGATIV ohne PS (alle 3 Felder unsichtbar), POSITIV mit PS.
- AK-T4: Konvertierung eines Leads (IsConverted=true) → Markierung wird nicht (mehr) erneuert.

## ⚠️ Befund (Repo-Analyse)
- Repo pflegt nur das Classic-Layout `Lead-Lead Layout`; Lightning-Recordpages
  leben in der Org. AC1 („ich sehe das Kennzeichen …“) gilt: Classic =
  Layout-Eintrag (Repo), Lightning = FLS + App-Builder-Platzierung =
  Org-Schritt @devops-agent (blockt NICHT, Pattern SCRUM-381/382).
- `Email_Norm__c` erzeugt eine Abhängigkeit: PS muss an alle Lead-User
  (Autoassign-Gruppe) vergeben sein, sonst schlägt der Trigger-Select fehl
  (FLS in SOQL). Siehe Deploy-Schritt 4.

## Offene Punkte (blocken die Implementierung NICHT)
- [ ] Lightning-Platzierung der neuen Section → @devops-agent (Org, nach Deploy)
- [ ] PS-Assignment an Autoassign-Gruppe + Backfill → @devops-agent (Org, nach Deploy, vor finaler Tester-Verifikation)
- [ ] Bestätigung PO: intra-Batch „ältester“ = Trigger.new-Listenposition (ADR-3, deterministisch; Id ist in before-Phase nicht verfügbar) → Nicht-Blocker, im Test fixiert

## Definition of Done
- Alle 15 Dateien vorhanden, exakte Pfade oben
- Phase 1/2 Manifests deployen ohne Fehler (devops)
- Apex-Tests (funktional + FLS) grün
- Gherkin AC2/AC3/AC3b/AC4/AC5 deckt der Testklassen-Satz vollständig
- Layout-File: „Dublettenprüfung“-Section zwischen „Nachfassung“ und
  „System Information“, beide Felder Readonly
- Nur eigene Pfade stageen (`.cline-roles/`, `scr378-report-final.zip` unan
       gefasst lassen)
