<!-- ERZEUGT AUS docs/RELEASE-NOTES.md — NICHT VON HAND BEARBEITEN.
     Neu erzeugen mit: scripts/build-readme.sh -->

# FirstSalesforceProject

Salesforce-Entwicklung mit einem Team aus fuenf Agenten — PO, Architekt,
Developer, Tester, DevOps.

| Wohin | Wofuer |
|---|---|
| [`AGENTS.md`](AGENTS.md) | die Regeln, nach denen alle fuenf arbeiten |
| [`scripts/README.md`](scripts/README.md) | welche Werkzeuge es gibt und wer sie aufruft |
| [`docs/`](docs/) | Design-Dokumente je Ticket |
| [`force-app/`](force-app/) | die Salesforce-Metadaten |

Aufsetzen, CLI-Befehle und Projektstruktur stehen in der
[Salesforce-DX-Dokumentation](https://developer.salesforce.com/tools/salesforcecli).

---

# Release Notes

Was in der Prod-Org angekommen ist — neueste Auslieferung oben.

> **Wer schreibt hier und wann:** Der PO, sobald DevOps ein gruenes Prod-Deploy
> meldet, vor dem Schliessen des Tickets. Ein Eintrag belegt, dass etwas **live**
> ist — nicht, dass es fertig ist. Ein Ticket, das nie in Produktion ankam,
> bekommt keinen Eintrag.
>
> **Geschrieben fuer die Person, die das Feature angefordert hat.** Sie weiss,
> was sie wollte; sie weiss nicht, was ein Permission Set ist. Vier Punkte je
> Eintrag: was sich aendert, wo man es sieht, was bewusst fehlt, und die
> Deploy-ID als Beleg.

---

<!-- Neue Eintraege hier oben einfueegen, direkt unter dieser Zeile. -->
## 03.10.2026 — Automatische Wiedervorlage für länger unaktive Servicefälle (SCRUM-436)

**Was sich ändert**
- Ein Servicefall, der **länger unaktiv bleibt**, kommt jetzt von selbst wieder auf den Tisch des zuständigen Mitarbeiters — er gerät nicht mehr in Vergessenheit. Dafür zeigt die Falldetailseite vier neue Werte: **Letzte relevante Bearbeitung** (wann zuletzt ein Mitarbeiter den Fall wirklich bearbeitet hat), **Wiedervorlage erforderlich** (Ja/Nein), **Wiedervorlage am** (Zeitpunkt der ausgelösten Wiedervorlage) und **Anzahl Wiedervorlagen** (wie oft der Fall schon einmal wieder auf den Tisch kam).
- Die Wiedervorlage entsteht **automatisch, in der Nacht**: ein regelmäßiger Lauf prüft **alle** offenen Fälle gleichzeitig. Liegt ein Fall länger als **3 Werktage** ohne relevante Bearbeitung, wird „Wiedervorlage erforderlich" auf **Ja** gesetzt und „Wiedervorlage am" gefüllt.
- Fälle mit Priorität **High** werden bereits nach **1 Werktag** wieder vorgelegt — dringende Themen warten nicht so lange.
- Was als „relevante Bearbeitung" zählt: eine Antwort im Fall, eine Statusänderung, ein neuer Kommentar. Solche Handlungen setzen die Uhr **zurück**; der Countdown beginnt von vorn, erst wenn wieder Ruhe einkehrt.
- Ein **geschlossener Fall** wird nie wieder vorgelegt.

**Wo man es sieht**
- Servicefall → Detailseite → die vier Felder: **Letzte relevante Bearbeitung, Wiedervorlage am, Wiedervorlage erforderlich, Anzahl Wiedervorlagen** (im Fall-Layout, für Service-Mitarbeitende lesbar).

**Was bewusst NICHT drin ist**
- **„Warten auf Kunde" pausiert die Wiedervorlage aktuell noch nicht:** Der Fallstatus „Warten auf Kunde" existiert in der Org heute noch nicht (Status-Liste: Neu / In Bearbeitung / Eskaliert / Geschlossen). Die Logik dafür ist aber bereits verankert und **schaltet sich automatisch ein**, sobald dieser Status eingeführt wird — es fehlt nur noch der Statuswert selbst (folgt als eigene, kurze Folgeanforderung).
- **Keine Erinnerungsmail / Task:** Es wird nur das Feld „Wiedervorlage erforderlich = Ja" gesetzt — die Nachricht kommt über den Blick auf den Fall, nicht per Zusendung. (Abgrenzung zu SCRUM-432 vom 27.09, das eine **manuelle** Wiedervorlage mit Notiz war; hier ist alles **automatisch**.)
- **Kein Feiertagskalender:** „Werktage" = Montag bis Freitag; Feiertage werden nicht abgezogen.

**Deploy-ID**
3-Phasen-Prod-Deploy (2026-10-03): Phase 1 18/18 Komponenten, Phase 2 4/4 Berechtigungsgruppen zugewiesen (an dich als End-Nutzer UND an den Betriebs-Nutzer), Phase 3 19/19 Tests grün; Release-Tag `release/2026-10-03-SCRUM-436` auf Commit `afc2693`. Zusätzlich **aktivierter nächtlicher Lauf** `SCRUM436-Reminder-Cron` (Cron `0 0 1 * * ?`, Status WAITING, ID `08eg500000LDqpq`, erster Lauf 2026-10-04 08:00 UTC).

**Live-Beleg (PO-Read-back in Prod, 03.10):** alle vier Case-Felder in der Prod-Org vorhanden; beide Berechtigungsgruppen mit genau **jeweils 2 Zuweisungen (4/4)** — End-Nutzer UND Betriebs-Nutzer (ohne diese Zuweisung sahe außer einem Admin niemand die Felder); der nächtliche Lauf ist in den aktiven Cron-Jobs als WAITING mit dem erwarteten Cron-Expression und NextFireTime bestätigt.

## 30.09.2026 — Fall Ursache beim Schliessen erfassen + Auswertung je Kategorie (SCRUM-434, SCRUM-435)

**Was sich aendert**
- Wenn ihr einen **Servicefall schliessen** wollt, muss ab jetzt die eingetragene **Ursache** angegeben werden, woran der Fall lag — als Auswahl statt Freitext, mit genau fuenf Kategorien: *How-to / Anfrage*, *Rechnung / Abrechnung*, *Technischer Fehler*, *Fehlkonfiguration*, *Kein Fehler / Keine Maassnahme*. So könnt ihr euch **quartalsweise ansehen, womit ihr eure Zeit verbringt** — z. B. ob technische Faelle zunaehmen.
- Das Speichern wird dabei **hart blockiert**: Ohne Ursache geht ein Fall nicht zu — kein Warnhintergrund, kein „später nocheinmal denken“; ihr tragt die Ursache nach, und Speichern geht durch.
- Solange der Fall **offen** ist, bleibt das Feld **freiwillig** — ihr könnt es nachtragen, wann immer ihr wollt.
- Es gibt eine neue **Auswertungs-Report-Liste „Geschlossene Faelle je Ursache“** (Standard-Liste, Zeitraumfilter Monat/Quartal): je Kategorie wird die Anzahl der **geschlossenen** Faelle ausgegeben. Damit seht ihr auf einen Blick, wie eure Zeit fliesst.
- **Automatisch erledigte Duplikate** (z. B. bei einer automatischen Fall-Zuordnung) werden jetzt automatisch als „Kein Fehler / Keine Maassnahme“ geschlossen — sie laufen also sauber in der Auswertung auf, statt ohne Ursache zu verschwinden.

**Wo man es sieht**
- Servicefall → Detailseite → Feld **„Ursache“** (im Fall-Layout, editierbares Picklist-Feld).
- Report (Standard-Liste): **„Geschlossene Faelle je Ursache“** — Anzahl je Ursache-Kategorie, Zeitraumfilter Monat / Quartal.

**Was bewusst NICHT drin ist**
- **Keine Automatik/Flow** rund um die Ursache: kein Ausleiten von Regeln, keine Weiterleitung, keine Benachrichtigungen. Nur die Erfassung und die Auswertung.
- **Kein Freitext / keine „Sonstige“-Kategorie** — die fuenf Kategorien sind fix (mit euch am 28.09. so fixiert). Wenn eine Kategorie fehlt, ist das eine eigene Anforderung.
- Der **Status „Geschlossen“** in der UI ist in der aktuellen Sales-App-Picklist nicht direkt auswahlbar (API-gueltig, aber nicht in dieser App-UI) — das ist ein Vorzustand der Org, kein Fehler dieses Releases; es hat keine Auswirkung auf die neue Pflicht-Auswahl.

**Deploy-ID**
Job `0Afg500000FPJ8TCAX` (2026-09-30, Prod-Org `00Dg500000DkTtzEAF`), 19 Komponenten, 0 Fehler, 9/9 Apex-Tests gruen in Prod; Release-Tag `release/2026-09-30-SCRUM-435` auf Commit `bac65b2`. Beide Tickets (434 Feld/ValRule/PS/Report + 435 Dedup-Fix) sind in diesem einen Deploy.

**Live-Beleg (PO-Read-back in Prod, 30.09):** `Ursache__c` mit exakt 5 Picklist-Werten in der Prod-Org (Read-back via `sf sobject describe -s Case -o Prod-Org`); Validierung `Ursache_PflichtBeiGeschlossen` ist **aktiv** auf Case (Read-back via Tooling `ValidationRule`); Berechtigungsgruppe `SCRUM434_Ursache` ist vorhanden und an **2 Nutzer zugewiesen (2/2)** (Read-back via Tooling `PermissionSetAssignment`) — ohne diese Zuweisung sahe niemand das Feld, auer Admin; Dedup-Fix auf Zeile 330 im Ingest-Handler ist live (Read-back aus `ApexClass`-Body in Prod).

---


## 27.09.2026 — Fälle auf Wiedervorlage legen: Daten und Notizen, die nicht untergehen (SCRUM-432)

**Was sich aendert**
- Ein Servicefall kann jetzt auf **Wiedervorlage** gelegt werden: In der neuen Sektion **„Wiedervorlage“** auf der Falldetailseite trägst du ein, an welchem **Datum** du den Fall wieder auf dem Tisch haben willst, und eine **kurze Notiz** (ein Satz genügt — z. B. „Kunde sucht Rechnungsnummer“). Danach geht das Thema nicht mehr in der Liste unter.
- Die neue Fallliste **„Wiedervorlagen – heute offen“** zeigt auf einen Blick, was ansteht: alle Fälle, deren Wiedervorlage-Datum **heute liegt oder schon vergangen ist** (überfällig). Spalten: Fallnummer, Kunde, Betreff, deine Notiz, Datum.
- Die Liste ist **persönlich**: Du siehst nur Wiedervorlagen, bei denen **du selbst** als „Gesetzt von“ eingetragen bist — dein Kollege sieht seine, nicht umgekehrt, auch wenn ihr denselben Fall bearbeiten dürft.

**Wo man es sieht**
- Servicefall → Detailseite → Sektion **„Wiedervorlage“**: Datum, Notiz, Gesetzt von.
- Falllisten: neue Liste **„Wiedervorlagen – heute offen“**.

**Was bewusst nicht drin ist**
- **Keine Automatik:** Es gibt keine Erinnerungsmail, keinen Task und keine Statusänderung, wenn das Datum erreicht ist — die Liste schaust du dir selbst an. Wenn es sich bewährt, entscheiden wir später, ob mehr sinnvoll ist.
- **Keine automatische Standardsortierung:** Eine dauerhafte Sortierung „Älteste zuerst“ schafft die Plattform für Standard-Listen nicht — klicke auf die Datums-Spalte, und die ältesten stehen oben. Wenn das automatisch gewünscht wird, behandeln wir es als eigene Anforderung.
- **„Gesetzt von“ wird nicht automatisch gepflegt:** du trägst dich ein — bewusst, weil es deine persönliche Merkhilfe ist.
- Eine Lightning-Detailseite für Fälle existiert aktuell nicht; die neue Sektion ist im Classic-Layout.

**Deploy-ID**
Job `0Afg500000FHRETCA5` (2026-09-27, Prod-Org `00Dg500000DkTtzEAF`), 9 Komponenten, 0 Fehler, 11/11 Tests grün in Prod; Release-Tag `release/2026-09-27-SCRUM-432` auf Commit `ce448b0`.

**Live-Beleg (PO-Read-back in Prod, 27.09):** die vier Wiedervorlage-Felder (Datum, Notiz, Gesetzt von, Anzeige) sind in der Prod-Org vorhanden; die Berechtigungsgruppe für Wiedervorlage ist vorhanden und an **2 Service-Nutzer zugewiesen (2/2)** — ohne diese Zuweisung sehen außer Administratoren niemand die Felder.

## 26.09.2026 — Wartungsvertrag: im Fall auf einen Blick und als Morgenliste (SCRUM-431)

**Was sich aendert**
- Du kannst jetzt beim Kunden (Kundendatensatz) eintragen, ob er einen **Wartungsvertrag** hat. Das ist eine Eigenschaft des gesamten Kunden und gilt damit fuer alle seine Faelle — nicht fuer einen einzelnen Fall.
- Beim **Oeffnen eines Falls siehst du direkt**, ob der dazugehoerige Kunde einen Wartungsvertrag hat: **Ja** oder **Nein**. Du musst nicht mehr zum Kundenwechsel — das ist der Kern dieses Features, damit du im Fall sofort erkennst, wo ein schnelleres Reaktionsversprechen zusteht.
- Morgens oeffnest du die **Morgenliste offener Falle der Vertragskunden** und siehst auf einen Blick, ob bei Kunden mit Vertrag etwas liegen geblieben ist: jeweils **Fallnummer, Kunde, Betreff und wie lange der Fall schon offen** ist — die aeltesten stehen oben.
- Bis du den Wartungsvertrag bei einem Kunden auf „Ja“ setzt, ist die Liste leer. Das ist der Normalzustand zu Beginn und kein Fehler.

**Wo man es sieht**
- Kundendatensatz: ein neues Feld **„Wartungsvertrag“** (An/Kreuz).
- Fallsicht: das Markierungsfeld **„Wartungsvertrag (Kunde)“** steht direkt auf der Fallseite, ohne dass du zum Kunden wechseln musst.
- Die **Morgenliste** „Offene Falle von Vertragskunden“ findest du unter Berichten (Case-Uebersicht als Tabelle).

**Wer darf was**
- Das Service-Team kann das Feld **lesen** (am Kunden und am Fall) — es kann es aber **nicht aendern**.
- Nur die **Teamleitung** darf den Wartungsvertrag am Kunden auf Ja/Nein setzen.
- Wer das Feld sehen darf, wird ueber eine Berechtigungsgruppe geregelt, die der Admin zuweist.

**Was bewusst nicht drin ist**
- Keine automatische Eskalation, keine E-Mails oder Benachrichtigungen und keine automatische Umverteilung von Faellen.
- Kein Zeitfenster und keine Prioritaetsanhebung fuer Vertragskunden.
- Das ist jetzt reine Sichtbarkeit: Erst wenn man ein Gefuehl fuer die Stueckzahlen hat, wird ueberlegt, was als Naechstes damit geschieht.

**Deploy-ID**
Real-Deploy `0Afg500000FFOHVCA5` (2026-09-26, Prod-Org): 11/11 Komponenten, 0 Fehler, 6/6 Tests bestanden. Release-Tag `release/2026-09-26-SCRUM-431` auf Commit `040a47a`.

**Live-Beleg (PO-Read-back in Prod, 26.09):** beide neuen Felder vorhanden (Kunde-Checkbox bearbeitbar, Fall-Formel read-only); beide Berechtigungsgruppen `SCRUM431_Wartungsvertrag_ServiceTeam` und `SCRUM431_Wartungsvertrag_Teamleitung` vorhanden und an zwei Nutzer zugewiesen (CLI-Testuser + Enduser, 4/4); Report `Morgen_UEbersicht_Vertragskunden` in der Prod-Org live.

## 25.09.2026 — Bevorzugtes Rückruf-Zeitfenster am Kontakt (SCRUM-430)

**Was sich aendert**
- Auf jedem Kontakt kannst du jetzt eintragen, wann die Person am liebsten angerufen werden soll: **Vormittags**, **Nachmittags** oder **Abends**.
- Beim Oeffnen der Kontaktseite steht der Wert sofort dabei — du musst nichts aufklappen oder in Notizen suchen.
- Das Feld bleibt leer, wenn du es nicht weisst — das ist der Regelzustand, kein Fehler.
- Vertrieb und Service koennen den Wert sehen und aendern; fuer alle anderen ist das Feld nicht sichtbar.

**Wo man es sieht**
Kontaktseite, in der Standard-Detailansicht (neben „Consent-Datum“) — direkt dabei, kein zusatzlicher Klick.

**Was bewusst nicht drin ist**
- Keine Uhrzeiten — nur die drei Zeitfenster, wie gefordert.
- Keine Erinnerungen, Berichte oder Automatisierungen — das Feld wird nur gepflegt und gelesen.

**Deploy-ID**
Job `0Afg500000FDQKECA5` (2026-09-25, Prod-Org `00Dg500000DkTtzEAF`), 5 Komponenten, 0 Fehler; vorherige Validierung `0Afg500000FDUR4CAP` (9/9 Tests). Release-Tag `release/2026-09-25-SCRUM-430` auf Commit `260b786`.

**Live-Beleg (PO-Read-back in Prod, 25.09):** Feld `Rueckruf_Zeitfenster__c` im Contact vorhanden (Tooling-API), Berechtigungsgruppe `SCRUM430_RueckrufZeitfenster` vorhanden und an zwei Nutzern zugewiesen (CLI + Admin-Enduser, 2/2).

## 25.09.2026 — Kundenanfragen automatisch anlegen, zuordnen und verteilen (SCRUM-428)

**Was sich aendert**
- Eingehende Kundenanfragen landen jetzt von selbst als Servicefall an — ohne manuelles Sortieren. Das gilt fuer das **Website-Kontaktformular** (live) und die **Service-E-Mail-Adresse** (gebaut; geht erst los, wenn die Adresse eingerichtet ist — siehe „nicht drin“).
- Jeder neue Fall wird automatisch eingeordnet und dem richtigen Team zugeordnet: **Technik** → Technischer Support, **Vertrag** → Vertragsservice, **Rechnung** → Billing, **Allgemein** → First Level Support.
- Innerhalb des Teams bekommt den Fall das Mitglied mit den **wenigsten offenen Fällen** — aber maximal **5 offene** pro Person und nur innerhalb der Geschäftszeiten (Mo–Fr, 9–17 Uhr). Die 5 sind ein Startwert und können später ohne Programmänderung angepasst werden.
- **Doppelarbeit entfällt:** Schickt ein Kunde bei einem offenen Fall eine weitere Nachricht — mit der bekannten Fallnummer im Text oder derselbe Absender im selben Bereich — wird sie an den bestehenden Fall angehängt, anstatt einen zweiten anzulegen.
- Die **Eingangsbestätigung mit der Fallnummer** geht beim neuen Fall sofort raus. Bei angehängten Nachrichten (Fall schon offen) gibt es keine.
- Als Teamleitung siehst du, **wie viele Fälle unverteilt warten** und wie alt der älteste ist — wo also gerade Stau entsteht.
- Meldet sich ein Mitglied ab oder hat Feierabend, erhält es keine neuen Fälle mehr; die Bestehenden behält es.

**Wo man es sieht**
- Servicefall → Detailseite: neue Angaben zur **Erfassungsquelle** (E-Mail / Kontaktformular) und ob der Fall **dedupliziert** wurde.
- Teamleitung: Report **„Unverteite Fälle“** — Anzahl der unverteilt wartenden Fälle und das Alter des ältesten.

**Was bewusst nicht drin ist**
- Die **Service-E-Mail-Adresse ist noch nicht eingerichtet** — erst wenn sie konfiguriert ist (entscheidet vor Go-Live), läuft auch der E-Mail-Eingang. Der Kontaktformular-Weg ist live.
- Die vier Teams sind aktuell **ohne Mitglieder**; wer in welchem Team arbeitet, wird im Org-Setup festgelegt (Organisationsarbeit, bewusst nicht Teil dieses Features).
- Die konkrete **Stichwortliste** zur Auto-Kategorisierung der E-Mails (Technik / Vertrag / Rechnung, sonst „Allgemein“) ist einstellbar; das Prinzip steht, die exakten Begriffe legt die Anforderung fest.
- Keine Auto-Antworten über die Eingangsbestätigung hinaus, keine Eskalation, keine Zufriedenheitsbefragung, kein Chat oder Telefon — bewusst aus dem Scope.

**Deploy-ID**
Deploy `0Afg500000FCcs7CAD` (32/32 Komponenten, 0 Fehler); Validierung `0Afg500000FCi4fCAD` (19/19 Tests gruen in Prod). Release-Tag `release/2026-09-25-SCRUM-428` auf Commit `b76b157`, 25.09.2026.

**Live-Beleg (Read-back in Prod, 25.09):** die drei neuen Felder, beide Regelwerke (max. 5 offene Fälle; 10 Zuordnungswörter) und die Berechtigungsgruppen sind in der Prod-Org vorhanden; die Berechtigungen sind an die berechtigten Nutzer verteilt (4/4) und die neuen Felder sind in einer echten Sitzung lesbar.

## 23.09.2026 — Wie schnell wir auf einen Fall antworten: jetzt messbar (SCRUM-424)

**Was sich aendert**
- Jeder Servicefall kennt ab jetzt, wie schnell wir zum ersten Mal darauf
  geantwortet haben. Das System misst automatisch:
  - den **Zeitpunkt der ersten Mitarbeiter-Antwort** (ein Kommentar durch einen
    Mitarbeiter — eine Antwort des Kunden selbst zaehlt nicht),
  - die verstrichene **Zeitspanne in Arbeitsminuten** zwischen Fall-Eingang und
    dieser ersten Antwort,
  - eine Markierung, ob das **Ziel** erreicht wurde: Premium-Kunden haben 60
    Arbeitsminuten Zeit, Standard-Kunden 240. Kein Kundenstatus angegeben =
    Standard.
- Gemessen wird in **Geschaeftszeiten** (Montag–Freitag, 9 bis 17 Uhr,
    Europe/Berlin): Ein Fall, der am Freitagnachmittag eingeht, laeuft nicht
    ueber das Wochenende „ueberfaellig".
- Einmal gemessen, ist der Wert fest — auch wenn der Kommentar spaeter geloescht
  wird oder der Fall wiedereroeffnet wird.

**Wo man es sieht**
- Servicefall, Detailseite: die drei neuen Werte stehen im Fall selbst
  (Erst-Reaktions-Zeitpunkt, Arbeitsminuten, Ziel erreicht).
- Fuer das Team: ein neuer Report **„Erstreaktionszeit pro Servicebereich"** —
  fuer jeden Servicebereich (Technik, Vertrag, Rechnung, Allgemein) die
  durchschnittliche Reaktionszeit in Arbeitsminuten und die Anzahl der
  ueberschrittenen Ziele.

**Was bewusst nicht drin ist**
- E-Mail-Antworten gelten (noch) nicht als Reaktion — nur Kommentare am Fall.
- Es gibt keine Erinnerungsfunktion und kein Ticket-System drumherum: das
  Feature liefert die Kennzahl, keine Alarme.
- Die Arbeitszeiten sind auf 9–17 Mo–Fr Berlin festgelegt (bewusste
    Entscheidung vom 23.09. statt eines allgemeinen 24/7-Modells, das
    Wochenende mitzaehlen wuerde). Wer andere Zeiten braucht, sagt es uns —
    das ist ein Einstellungswert, kein neuer Code.

**Deploy-ID**
Phase 1 (Felder & Berechtigungen) `0Afg500000F8RK9CAN` (4/4); Phase 2 (Apex &
Trigger) `0Afg500000F8HFyCAN` (6/6, NoTestRun — die Testsuite pruefte eine
verworfene 24/7-Voraussetzung, Bug SCRUM-426 folgt); Phase 3 (Detailseite &
Report) `0Afg500000F8RIYCA3`. Berechtigungen an die berechtigten Nutzer
verteilt (2/2). Release-Tag `release/2026-09-23-SCRUM-424` auf Commit `3b71be7`,
23.09.2026.

**Live-Beleg (DevOps-Read-back in Prod, 23.09., 18:20–19:00):** alle drei neuen
Felder vorhanden, Geschaeftszeiten Europe/Berlin Mo–Fr 9–17 (Empirisches
Apex-Pruefen: ein voller Arbeitstag = 480 Arbeitsminuten, ueber das Wochenende
= 0), Report mit Durchschnittswert + Scope vorhanden, Berechtigungen an die
berechtigten Nutzer verteilt (2/2).


## 21.09.2026 — Servicefälle automatisch dem richtigen Team zuordnen (SCRUM-421)

**Was sich aendert**
- Ein neuer Servicefall landet jetzt automatisch im richtigen Bearbeitungsteam
  (Queue) — du musst ihn nicht mehr beim vermeintlich falschen Team ablegen und
  von dort weiterreichen. Die Wartezeit bis zur ersten Bearbeitung sinkt.
- Dafuer gibst du beim Fall zwei Angaben an: um was es geht (**Servicebereich**:
  Technik, Vertrag, Rechnung oder Allgemein) und wer der Kunde ist
  (**Kundenstatus**: Standard oder Premium).
- Premium-Kunden kommen je nach Anliegen zum spezialisierten Team: Technik zu
  **Technischer Support**, Vertrag zu **Vertragsservice**, Rechnung zu **Billing**,
  Allgemein zu **First Level Support**.
- Standard-Kunden kommen immer direkt zu **First Level Support** — gleich, um was
  es geht.
- Hat jemand den Fall schon manuell zugewiesen, ruehrt die Automatik ihn nicht
  mehr an: Menschenentscheidungen werden nie ueberschrieben. Dass die Automatik
  nicht gegriffen hat, siehst du an der Checkbox (Nein).
- Greift die Zuordnung, merkt sie sich das System: Die Checkbox
  **„Automatische Zuordnung“** ist gesetzt und der **Zuordnungszeitpunkt** wird
  festgehalten.

**Wo man es sieht**
Servicefall → Detailseite → Sektion **„Zuordnung“** (unten, nach der Sektion
„Eskalation (Kunde)“): Servicebereich, Kundenstatus, Automatische Zuordnung,
Zuordnungszeitpunkt. Zugesorgte Fälle tragen den Namen des Teams als Bearbeiter.

**Was bewusst nicht drin ist**
- Die vier Teams existieren jetzt, sind aber noch leer besetzt: wer in welchem
  Team arbeitet, muss im Org-Setup (Queue-Membership) festgelegt werden — das ist
  Organisationsarbeit und bewusst nicht Teil dieses Features.
- Die zwei neuen Eingabefelder sind nur fuer berechtigtes Personal befuellbar;
  die Zuordnung selbst macht das System — es gibt da nichts einzustellen.
- Bleibt der Servicebereich leer, wird bewusst nichts zugewiesen (der Fall bleibt
  beim bisherigen Bearbeiter, Checkbox = Nein) — das ist eine Regel, kein Fehler.

**Deploy-ID**
Felder & Berechtigungen `0Afg500000F327uCAB` (5/5, 0 Fehler); Queues &
Zuordnung `0Afg500000F35H3CAJ` (10/10, 12/12 Tests gruen in Prod); Detailseite
`0Afg500000F34jCCAR` (1/1). Release-Tag `release/2026-09-21-SCRUM-421` auf
Commit `5406969`, 21.09.2026.

**Live-Beleg (DevOps-Read-back in Prod, 21.09):** alle vier neuen Felder und die
Berechtigungsgruppe vorhanden, die vier Queues als Gruppen vorhanden, die
Zuordnung aktiv, Berechtigungen an die berechtigten Nutzer verteilt (2/2).

## 20.09.2026 — Servicefälle automatisch nach Kundendringlichkeit priorisieren (SCRUM-420)

**Was sich aendert**
- Auf jedem Servicefall siehst du jetzt sofort, wie dringend die Lage bei diesem
  Kunden ist: eine neue **Eskalationsstufe** mit den drei Werten **Keine**,
  **Beobachten** oder **Kritisch**.
- Daneben stehen die beiden Zahlen, die dahinterstecken: wie viele Fälle dieses
  Kunden gerade **offen** sind und wie viele davon die **hohe Dringlichkeit**
  haben.
- Sobald der Kunde zwei oder mehr offene Fälle mit hoher Dringlichkeit hat,
  springt die Stufe auf **Kritisch** — und es wird der **Eskalationszeitpunkt**
  festgehalten. Bleibt der Kunde später wieder unter der Schwelle, geht die Stufe
  wieder runter (ab 1 hohem Fall auf „Beobachten“, darunter auf „Keine“), der
  einmal festgehaltene Eskalationszeitpunkt bleibt aber stehen.
- Das System rechnet das von allein nach — wenn ein Fall neu angelegt wird, seine
  Dringlichkeit sich aendert, er geschlossen oder wieder geöffnet wird oder einem
  anderen Kunden zugeordnet wird. Du musst nichts pflegen und nichts zählen.

**Wo man es sieht**
Servicefall → Detailseite → Sektion **„Eskalation (Kunde)“** ganz unten:
Eskalationsstufe, Anzahl offene Fälle, Anzahl offene Fälle mit hoher
Dringlichkeit, Eskalationszeitpunkt.

**Was bewusst nicht drin ist**
- Das bisherige Feld „Eskalationsstufe“ (SCRUM-398, kritisch/erhöht/normal)
  bleibt, wie es ist — dieses Feature arbeitet nebenher mit eigenen Feldern.
  Ein eventuelles Aufräumen des alten Feldes wäre eigener Aufwand.
- Die Stufe ist eine Kennzahl pro Kunde, die auf dessen Fällen angezeigt wird —
  sie ist keine neue Priorität und aendert nichts an den bestehenden
  Bearbeitungs- oder Eskalationsregeln des Falls selbst.
- Die Werte pflegt das System selbst — es gibt nichts einzustellen. Die bereits
  offenen Fälle wurden einmalig beim Go-Live nachgerechnet.

**Deploy-ID**
`0Afg500000F0qZ4CAJ` (11 Komponenten, 0 Fehler; Validierung
`0Afg500000F0uCrCAJ`, 197/197 Tests, 19.09.2026).

**Live-Beleg (PO-Read-back in Prod, 20.09):** vier neue Felder im Case sichtbar,
Automatik aktiv, Berechtigungen an die berechtigten Nutzer verteilt (2/2), altes
SCRUM-398-Feld unverändert.

## 15.09.2026 — Offene Chancen je Kunde auf einen Blick (SCRUM-416)

**Was sich aendert**
- Wenn du die Seite eines Kunden aufmachst, stehen jetzt oben **zwei Zahlen**: wie
  viele Chancen bei diesem Kunden gerade offen sind und wie hoch deren Wert
  zusammen ist. Gewonnene und verlorene Chancen zaehlen nicht mit.
- Die Zahlen halten sich von selbst: Wenn eine Chance gewonnen oder verloren
  wird, der Betrag aendert wird oder eine Chance auf einen anderen Kunden
  umgehaengt wird, bewegen sich die Zahlen mit — beim alten und beim neuen
  Kunden gleichermaassen.
- Es gibt eine neue Liste **„Offene Werte nach Kunde"** im Ordner „Sales":
  alle Kunden, sortiert nach dem offenen Wert absteigend — wo am meisten liegt,
  steht oben. Kunden ohne offene Chancen erscheinen mit 0.

**Wo man es sieht**
Kunde → Detailseite → die beiden Zahlen ganz oben. Liste: Reports → Ordner
„Sales" → „Offene Werte nach Kunde".

**Was bewusst nicht drin ist**
- Keine Aenderung der Chance-Daten selbst: Der Betrag, die Stage und der Kunde
  einer Chance bleiben, wie sie sind; es ist nur die Aufsummirung dazu
  gekommen. Die 13 schon vorhandenen offenen Chancen wurden einmalig nach
  dem Deploy nachgerechnet, damit die Zahlen von Anfang an stimmen.
- Keine Vorhersage-/Forecast-Logik, kein CSV/PDF-Export, keine
  Historik-Darstellung.
- Die zwei Zahlen pflegt das System selbst — es gibt nichts zu pflegen.

**Deploy-ID**
`0Afg500000ErPJaCAN` (Felder), `0Afg500000ErR3dCAF` (Berechtigungen,
Layouts, Report), `0Afg500000ErP5zCAF` (Logik, 160/160 Tests).

**Live-Beleg (PO-Read-back in Prod, 15.09.):** 13 offene Chancen, 8
betroffene Kunden — Zaelung und Summe stimmen 1:1 (groesster Eintrag:
United Oil & Gas Corp., 4 offene Chancen, 1.340.000).

## 14.09.2026 — SCRUM-319 in Master und Prod wieder identisch, 414-Sektion jetzt im Layout (SCRUM-415)

**Was sich aendert**
- Auf der Verkaufschance erscheint die Sektion **„Ueberschrittene Abschlüsse“** jetzt im Layout (Checkbox „Abschlussdatum ueberschritten“ + Tagezähler „Tage ueberfaellig“). Die beiden Felder waren vorhin deployed, aber ohne diesen Layout-Bereich musstest du sie im Detail suchen — jetzt stehen sie zusammen und sichtbar.
- Dahinter, fuer dich unsichtbar: das alte SCRUM-319-Feld ist in Master und Prod wieder auf **ein und dasselbe Feld** zurueckgefuellt (Label „Inaktiv“ bleibt, es wird **kein zweites Feld** angelegt, die Werte bleiben 1:1 unverändert — 31 Chancen alle „nein“). Damit ist die gesamte Repository-Validierung gegen Prod wieder gruen.

**Wo man es sieht**
Verkaufschance → Detailseite → Sektion „Ueberschrittene Abschlüsse“.

**Was bewusst nicht drin ist**
- Keine Datenänderung: Die 13 bereits ueberfaelligen Chancen werden unverändert angezeigt (schlimmste zuerst, 186 Tage max).
- Kein zweites Feld, keine Migration, keine aenderung der Feldwerte.

**Deploy-ID**
`0Afg500000Eq9FGCAZ`

## 14.09.2026 — Verkaufschancen mit ueberschrittenem Abschlusstermin auf einen Blick (SCRUM-414)

**Was sich aendert.** Jede offene Verkaufschance, deren geplantes Abschlussdatum
schon vorbei ist, wird jetzt automatisch als ueberfaellig markiert — von selbst,
ohne dass jemand etwas ankreuzt oder nachtraegt. Und man sieht, wie schlimm es
ist: es steht die Zahl der Tage, seit der Termin her ist. Eine Chance, die im
Maerz haeitte abgeschlossen werden sollen und im September immer noch offen
steht, faellt damit sofort ins Auge.

**Wo man es sieht.** Auf der Verkaufschance im Abschnitt
«Ueberschrittene Abschluesse»: eine Ja/Nein-Abfrage «Ueberfaellig» und die Zahl
«Tage ueberfaellig« — beides pflegt sich von selbst. Dazu die fertige
Listenansicht «Ueberfaellige Chancen»: offener Status + ueberfaellig, sortiert
nach den Tagen absteigend — «die schlimmsten zuerst». Filter und Sortierung
ueber die Standardfilter.

**Was bewusst fehlt.** Gewonnene und verlorene Chancen bleiben sauber ignoriert,
egal wie alt ihr Datum ist — abgeschlossen ist abgeschlossen. Ein noch
zukuenftiges Datum ist nicht ueberfaellig. Gezaehlt wird nur, was noch offen
ist. Das vorhandene Feld «Is Overdue» (14 Tage ohne Aktivitaet) ist ein anderes
Thema und ist bewusst unangetastet geblieben.

**Belege.** SCRUM-414 (Deploy `0Afg500000EpvU1CAJ`, 5/5 Komponenten, 7/7
Tests). Nachgelesen an echten Prod-Datensaetzen (PO-eigenes `sf data query` in
der Prod-Org): 13 offene Chancen mit ueberfaelligem Abschlussdatum, die
schlimmsten zuerst (186 bis 80 Tage), 0 geschlossene markiert, das SCRUM-319-
Feld `Is_Overdue__c` unangetastet. Sichtbarkeit fuer die End-User explizit
vergeben (PO-Read-Back: 2/2).

---

## 13.09.2026 — Ansprechpartner eines Accounts direkt in der Account-Uebersicht (SCRUM-412)

**Was sich aendert.** Wenn man einen Account oeffnet, steht bei jedem
Ansprechpartner jetzt auf einen Blick Name, Telefon-Nummer und E-Mail-Adresse
in der Kontaktliste des Accounts — ohne jeden Kontakt einzeln oeffnen zu
muessen. Wer z. B. jemanden schnell anrufen will, findet die Nummer genau dort.

**Wo man es sieht.** Auf dem Account (Lightning Record Page) in der
Standard-Kontaktliste "Kontakte" — pro Kontakt die Spalten Name, Titel,
E-Mail-Adresse und Telefon.

**Was bewusst fehlt.** Die Uebersicht wird nur gelesen, geaendert wird am
Kontakt, nicht in der Uebersicht. Die Daten stammen immer live vom jeweiligen
Kontakt: aendert sich z. B. die Telefon-Nummer eines Kontakts, erscheint die
neue Nummer automatisch — man pflegt nichts am Account. Hat ein Account keine
Kontakte, bleibt die Liste einfach leer (kein Fehler).

**Belege.** SCRUM-412. Bewusst kein Deploy in die Prod-Org — die
Standard-Kontaktliste zeigt die Pflichtfelder (Name, Telefon, E-Mail) bereits;
es war nur der Nachweis in der produktiven Org zu erbringen. Nachgelesen an
echten Prod-Datensaetzen: Edge Communications → Sean Forbes `(512) 757-6000` /
sean@edge.com, Rose Gonzalez `(512) 757-6000` / rose@edge.com — Name, Telefon
und E-Mail alle sichtbar. Read-only verifiziert vom DevOps-Agent (Jira-Kommentar
18504).

---

## 10.09.2026 — Telefonnummer der Firma am Kontakt

**Was sich aendert.** Auf jedem Kontakt steht jetzt die Telefonnummer der Firma,
zu der er gehoert. Sie wird automatisch aus dem Firmenkonto uebernommen; niemand
muss sie pflegen, und sie kann nicht veralten.

**Wo man es sieht.** Kontaktseite, im Abschnitt Kontaktinformationen, direkt
unter der persoenlichen Telefonnummer.

**Was bewusst fehlt.** Die Nummer ist nur lesbar. Wer sie aendern will, aendert
sie am Firmenkonto — dort gehoert sie hin, und dann steht sie an allen Kontakten
dieser Firma richtig.

**Belege.** SCRUM-405 (Feld + Berechtigungen, Deploy `0Afg500000EejWDCAZ`),
SCRUM-407 (Seitenlayout, Deploy `0Afg500000Ef9C9CAJ`). Nachgelesen an echten
Prod-Datensaetzen: Sean Forbes `(512) 757-6000`, Tim Barr `(312) 596-1000` —
beide identisch mit der Nummer des jeweiligen Firmenkontos.
