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
