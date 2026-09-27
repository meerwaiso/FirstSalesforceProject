# SCRUM-432 — Notizen (Developer)

## Auftrag
Persönliche Wiedervorlage auf Case: 2 Storage-Felder (Datum, Notiz)
+ Mechanismus (Lookup `Wiedervorlage_Von__c`, Formel `Wiedervorlage_Heute_Offen__c`)
+ Listview „Wiedervorlagen – heute offen" + Layout-Sektion + PS
`SCRUM432_Wiedervorlage_ServiceTeam`. Rein deklarativ, kein Apex/Trigger/Flow.
Autoritative Build-Spec: `docs/SCRUM-432-design.md` (Commit 030910e).

## Felder (API-Name exakt, keine Umlaute außer Label)
| API-Name | Label | Typ | Pflicht |
|---|---|---|---|
| Wiedervorlage_Datum__c | Wiedervorlage Datum | Date | optional |
| Wiedervorlage_Notiz__c | Wiedervorlage Notiz | Text 255 | optional |
| Wiedervorlage_Von__c | Gesetzt von | Lookup→User (SetNull) | optional |
| Wiedervorlage_Heute_Offen__c | Wiedervorlage heute offen | Formel→Checkbox | read-only |

Formel (ADR-2):
```
AND(
  Wiedervorlage_Von__r.Id = $User.Id,
  NOT(ISBLANK(Wiedervorlage_Datum__c)),
  Wiedervorlage_Datum__c <= TODAY()
)
```
Nicht im Layout — nur in der Liste.

## KERN-Offenpunkt: Kundenspalte (AC2, FALLENRISIKO)
- `ACCOUNT.NAME` ist im Repo nur auf Opportunity (Hochwertige_Chancen) verifiziert.
- Case-Listview mit Owner zeigt `CORE.USERS.ALIAS`, nicht Account-Name.
- ACCOUNT.NAME für Case NICHT verifiziert. Erste Aktion: dry-run der Listview.
- Kandidaten: ACCOUNT.NAME (Report-Schema), sonst aus Validator-Fehler ablesen.

## Deploy-Sequenz (ADR-9)
1. phase1-fields: die 4 CustomField
2. phase2-referencing: PS + ListView + Layout (Case-Case Layout)
3. apextests: SCRUM432WiedervorlageTest, SCRUM432WiedervorlageFlsTest (RunSpecifiedTests)
4. PS zuweisen an Targetorg-User + 2. Service-Konto, PermissionSetAssignment +
   1 Feld durch reale Session lesen (Read-Back).

## Befunde (hier eintragen)
- Phase-1-Deploy OK: 4 CustomFields in Test-Org (job 0AfWU00000bkWxF0AU).
  Manifest brauchte `Case.`-Prefix bei CustomField (bare Members -> "No source-backed components", House-Pattern scr382/421/428/430).
- Default-FLS nach Deploy: 0 Zeilen FieldPermissions auf alle 4 Felder (Baseline "kein Zugriff" ohne PS -> AC8-Negativ testbar, Grant kommt aus dem PS).
- **Kernfrage ADR-6 BEANTWORTET: `ACCOUNT.NAME` ist gültige Case-Listview-Spalte**
  (Phase-2-Validate status 0). Zusätzlich via `/analytics/report-types/CaseList`
  detailColumnInfo: ACCOUNT.NAME -> Account.Name (7 Col total; Spalten hängen unter
  reportExtendedMetadata.detailColumnInfo, NICHT reportColumns!).
- PS-Description limit 255 (Deploy-Fehler "data value too large") — kurz halten.
- Phase-2-Manifest: ListView-Member mit `Case.`-Prefix (scr403 `Contact.Letztes_Anliegen`);
  ohne Prefix: "named in package.xml, but not found in zipped directory".
- Phase-2-Validate status 0 (ListView + Layout + PS).

