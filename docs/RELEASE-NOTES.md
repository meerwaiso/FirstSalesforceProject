# Release Notes

Neueste Einträge oben. Ein Eintrag je Produktivauslieferung — ein Eintrag belegt, dass etwas **live** ist, nicht dass es fertig ist.

## 2026-09-13 — Ansprechpartner eines Accounts direkt in der Account-Übersicht (SCRUM-412)

**Was sich für dich ändert:** Wenn du einen Account öffnest, siehst du jetzt bei jedem Ansprechpartner direkt **Name, Telefonnummer und E-Mail-Adresse** in der Kontaktliste des Accounts — ohne jeden Kontakt einzeln öffnen zu müssen. Willst du jemanden schnell anrufen, findest du die Nummer an der Stelle.

**Wo du es siehst:** Auf dem Account (Lightning-Record-Page) in der Standard-Liste „Kontakte“ — pro Kontakt die Spalten Name, Titel, E-Mail und Telefon.

**Wichtig zu wissen:**

- Die Daten kommen **immer direkt vom jeweiligen Kontakt**. Ändert sich z. B. eine Telefonnummer beim Kontakt, erscheint der neue Wert sofort in der Übersicht. Du pflegst nichts zusätzlich am Account.
- Hat ein Account keine Kontakte, bleibt die Liste einfach leer (kein Fehler).
- Es wurde **nichts in der Produktion umgebaut oder neu deployed** — die vorhandene Kontaktliste zeigt die Pflichtfelder an; es fehlte nur der Nachweis, dass das in der produktiven Org so steht, und der ist jetzt erbracht.

**Live nachgewiesen in der produktiven Org:** Auf dem Account „Edge Communications“ sind pro Kontakt Name, Telefon und E-Mail sichtbar (z. B. Sean Forbes / (512) 757-6000 / sean@edge.com; Rose Gonzalez / (512) 757-6000 / rose@edge.com). Read-only verifiziert vom DevOps-Agent (Jira-Kommentar 18504).

**Noch bewusst nicht drin:** kein Bearbeiten der Kontaktdaten direkt aus der Account-Übersicht (Änderung bleibt am Kontakt) und kein Filtern/Sortieren der Ansprechpartner — kann später eine eigene Story werden.
