# scripts/ — was hier liegt, und wer es aufruft

Hier liegen zwei verschiedene Dinge, und sie zu verwechseln kostet Zeit:
**Werkzeuge**, die man bei jedem Ticket wieder braucht, und **Einmal-Belege**,
die zu einem einzigen Ticket gehören. Diese Datei sagt, was was ist.

Bestandsaufnahme vom 21.09.2026.

## Werkzeuge — dauerhaft, bei jedem Ticket brauchbar

| Aufruf | Beantwortet | Wer ruft es |
|---|---|---|
| `scripts/fls-check.sh <Objekt> <Feld>` | „Warum sehe ich dieses Feld nicht?" — Existenz, Gewährung, Zuweisung in einem Befehl | Agent, von Hand |
| `scripts/apex-probe.sh "<apex>"` | „Gibt es diese Apex-Klasse/Signatur, und was liefert sie?" in ~5 s | Agent, von Hand |
| `npm run probe` (`scripts/probe-locators.js`) | echte Locators aus der laufenden Seite, statt sie zu raten | Agent, von Hand |
| `scripts/fls-gate.py --base <ref> --org <org>` | blockiert Felder ohne wirksame FLS | **CI**, `org`-Job |

Hintergrund zu den ersten beiden: Skill `salesforce-describe-first`, §4 und §10.

**Nur `fls-gate.py` läuft automatisch.** Alle anderen wirken ausschliesslich,
wenn jemand sie aufruft — deshalb stehen sie in `AGENTS.md`, das immer im
Kontext liegt, und nicht nur hier.

## Einmal-Belege — an ein Ticket gebunden, nicht wiederverwendbar

| Datei | Ticket | Was sie belegt |
|---|---|---|
| `ac4_live_check.py` | SCRUM-367 | AC4: Rebuild läuft, während parallel Fälle bearbeitet werden — keine langen Locks. Hartkodierter Projektpfad, nicht portabel. |
| `apex/scr386_backfill_email_norm.apex` | SCRUM-386 | einmaliger Backfill der E-Mail-Normalisierung |
| `soql/scr386_verify_backfill.soql` | SCRUM-386 | Read-back zum Backfill |
| `apex/hello.apex`, `soql/account.soql` | — | Beispiel-Schnipsel |

Diese Dateien werden **von niemandem aufgerufen** und sollen es auch nicht. Sie
sind Nachweis, dass eine Prüfung einmal stattgefunden hat. Wer ein ähnliches
Problem hat, liest sie als Vorlage — er führt sie nicht aus.

## Wenn Du hier etwas ablegst

Werkzeug oder Beleg? Ein Werkzeug bekommt einen Eintrag in der oberen Tabelle
**und** eine Zeile in `AGENTS.md`, sonst findet es niemand — genau das ist
`npm run probe` passiert: vorhanden seit August, in keinem SOUL und keinem Skill
genannt, und in der Zwischenzeit wurden 48 Sondierskripte von Hand gebaut.

Ein Beleg bekommt einen Eintrag in der unteren Tabelle mit seinem Ticket. Ohne
Ticket-Bezug ist er in einem halben Jahr nicht mehr einzuordnen.
