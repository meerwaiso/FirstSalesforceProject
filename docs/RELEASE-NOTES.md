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
