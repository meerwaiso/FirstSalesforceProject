/**
 * [SCRUM-428] Eingangsbestätigung (ADR-4, AC11).
 *
 * Messaging.SingleEmailMessage mit festem Plain-Text im Code — kein
 * EmailTemplate-Metadata, keine PII über den Empfänger hinaus.
 * Dup-Cases (Dedupliziert__c = true) werden NIE bestätigt (Filter in sendAll).
 *
 * buildMessage ist SOQL-frei und rein (CaseNumber kommt vom Caller) ->
 * unit-testbar. sendAll prüft das e-Mail-Limit vor dem Senden (Bulk-Schutz)
 * und sendet nur, wenn noch Limit übrig ist.
 *
 * @author developer-agent
 * @date 2026-09-24
 */
public without sharing class SCRUM428CaseConfirmation {

    /**
     * Baut die Bestätigung für einen Case (rein, keine DML/SOQL).
     *
     * @param caseNumber   Case-Nummer (kommt vom Caller, der Case kennt)
     * @param recipient    E-MailAdresse (Contact.Email sonst SuppliedEmail)
     * @param recipientName Anrede (Contact.Name sonst SuppliedName sonst 'Kunde')
     * @return SingleEmailMessage oder null, falls keine Empfängeradresse
     */
    public static Messaging.SingleEmailMessage buildMessage(
            String caseNumber, String recipient, String recipientName) {
        if (recipient == null || recipient.trim().length() == 0) {
            return null;
        }
        if (caseNumber == null || caseNumber.trim().length() == 0) {
            return null;
        }
        String name = (recipientName != null && recipientName.trim().length() > 0)
                ? recipientName.trim() : 'Kunde';

        Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
        message.setToAddresses(new List<String>{ recipient.trim() });
        message.setSubject('Ihre Anfrage wurde erfasst — Fall ' + caseNumber);
        message.setPlainTextBody(templateBody(name, caseNumber));
        return message;
    }

    /** Fixer Plain-Text aus ADR-4 (konfigurierbar über ADR-Text, keine PII). */
    public static String templateBody(String name, String caseNumber) {
        return 'Guten Tag ' + name + ',\n\n'
            + 'Ihre Anfrage ist bei uns eingegangen und wurde unter der\n'
            + 'Fallnummer ' + caseNumber + ' erfasst.\n\n'
            + 'Wir melden uns schnellstmöglich bei Ihnen.\n\n'
            + 'Mit freundlichen Grüßen\n'
            + 'Ihr Service-Team';
    }

    /**
     * Sendet die Bestätigungen für alle nicht-Dup-Cases, die eine Empfänger-
     * adresse haben. Dup-Cases (Dedupliziert__c = true) werden übersprungen.
     * Prüft vor dem Senden das e-Mail-Limit (Bulk-Schutz): wenn nicht genug
     * Rest ist, sendet nur so viele, wie möglich — der Rest wartet (kein
     * Hard-Fail: der Fall liegt weiterhin in der Queue).
     *
     * @param cases Cases, deren Empfänger-Adresse vorliegt (Contact/Supplied*)
     * @return Anzahl tatsächlich erfolgreich versandte Mails
     */
    public static Integer sendAll(List<Case> cases) {
        if (cases == null || cases.isEmpty()) {
            return 0;
        }
        List<Messaging.SingleEmailMessage> toSend = new List<Messaging.SingleEmailMessage>();
        for (Case c : cases) {
            if (c.Dedupliziert__c == true) {
                continue; // Dup -> KEINE Bestätigung
            }
            String recipient = (c.Contact != null && c.Contact.Email != null)
                    ? c.Contact.Email : c.SuppliedEmail;
            String recipientName = (c.Contact != null && c.Contact.Name != null)
                    ? c.Contact.Name : c.SuppliedName;
            Messaging.SingleEmailMessage m = buildMessage(c.CaseNumber, recipient, recipientName);
            if (m != null) {
                toSend.add(m);
            }
        }
        if (toSend.isEmpty()) {
            return 0;
        }
        // Bulk-Schutz: nicht mehr Mails senden, als noch im Limit liegen.
        Integer emailRest = Limits.getLimitEmailInvocations() - Limits.getEmailInvocations();
        if (emailRest <= 0) {
            return 0;
        }
        // sublist() meiden: Unterliste manuell aufbauen (keine API-Annahme).
        List<Messaging.SingleEmailMessage> capped = new List<Messaging.SingleEmailMessage>();
        Integer upper = toSend.size();
        if (emailRest < upper) {
            upper = emailRest;
        }
        for (Integer i = 0; i < upper; i++) {
            capped.add(toSend.get(i));
        }
        Messaging.SendEmailResult[] res = Messaging.sendEmail(capped);
        Integer ok = 0;
        for (Messaging.SendEmailResult r : res) {
            if (r != null && r.isSuccess()) {
                ok++;
            }
        }
        return ok;
    }
}
