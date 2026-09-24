/**
 * [SCRUM-428] Kontaktformular-Controller (ADR-2 Punkt 2, AC2).
 *
 * @AuraEnabled submitForm(name, email, bereich, nachricht):
 *   - Contact per E-Mail matchen, sonst anlegen (LastName=name)
 *   - Case-Insert mit Erfassungsquelle__c='Kontaktformular'
 *
 * Der after-insert-Trigger (SCRUM428CaseIngestTrigger) übernimmt
 * Dedup (AC4/5), Zuteilung (AC6–AC10) und Bestätigung (AC11).
 * Origin bleibt null (kein Email -> keine Keyword-Kategorisierung,
 * Servicebereich kommt vom Formular).
 *
 * with sharing: nutzt den Session-User (LWC-Kontext), nicht without sharing.
 *
 * @author developer-agent
 * @date 2026-09-24
 */
public with sharing class SCRUM428ContactFormController {

    /**
     * Speichert eine Anfrage aus dem Kontaktformular.
     *
     * @param name      Name des Absenders (Pflicht) — Contact.LastName, sonst neu
     * @param email     E-Mail-Adresse (Pflicht) — Contact-Matching per Email
     * @param bereich   Servicebereich ('Technik'|'Vertrag'|'Rechnung'|'Allgemein'|null)
     * @param nachricht Beschreibung / Anliegen (Pflicht, >= 10 Zeichen)
     * @return CaseNumber des neu angelegten Cases
     */
    @AuraEnabled(cacheable=false)
    public static String submitForm(String name, String email,
                                    String bereich, String nachricht) {
        if (name == null || name.trim().isEmpty()) {
            throw new AuraHandledException('Name ist erforderlich.');
        }
        if (email == null || email.trim().isEmpty()) {
            throw new AuraHandledException('E-Mail-Adresse ist erforderlich.');
        }
        if (nachricht == null || nachricht.trim().isEmpty()) {
            throw new AuraHandledException('Nachricht ist erforderlich.');
        }
        if (nachricht.trim().length() < 10) {
            throw new AuraHandledException('Die Nachricht muss mindestens 10 Zeichen haben.');
        }

        // Contact per E-Mail matchen (exakt, trimmed), sonst anlegen.
        List<Contact> existing = [
            SELECT Id FROM Contact WHERE Email = :email.trim() LIMIT 1
        ];
        Id contactId;
        if (!existing.isEmpty()) {
            contactId = existing[0].Id;
        } else {
            Contact c = new Contact(LastName = name.trim(), Email = email.trim());
            insert c;
            contactId = c.Id;
        }

        // Case anlegen. Status bleibt default (nicht hartkodiert).
        Case kase = new Case(
            Subject = 'Kontaktformular: ' + name.trim(),
            Description = nachricht.trim(),
            ContactId = contactId,
            Servicebereich__c = bereich,
            Erfassungsquelle__c = 'Kontaktformular'
        );
        insert kase;   // feuert SCRUM428CaseIngestTrigger (after insert)

        return [SELECT CaseNumber FROM Case WHERE Id = :kase.Id LIMIT 1].CaseNumber;
    }
}
