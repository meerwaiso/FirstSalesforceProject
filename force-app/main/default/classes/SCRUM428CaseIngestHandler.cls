/**
 * [SCRUM-428] Phase A Ingest-Handler (ADR-3 Schritte 1–6).
 *
 * Läuft im after-insert-Trigger auf Case. Bulk, ~2 SOQL + 2 DML je Batch:
 *   Schritt 1  Erfassungsquelle (AC1/2): Origin='Email' -> 'E-Mail'
 *   Schritt 2  Kategorisierung (AC3): Origin='Email' + Servicebereich null
 *             -> Keyword-Match (MDT) in Subject+Description, case-insensitive,
 *             Priority Technik > Rechnung > Vertrag, Fallback 'Allgemein'
 *   Schritt 3  AC4: Case-Nummer im Text -> bestehenden Fall anhängen
 *   Schritt 4  AC5: gleiche ContactId + gleicher Bereich, offen -> anhängen
 *   Schritt 5  Rekursions-/Interaktions-Schutz (dokumentiert, kein Code nötig)
 *   Schritt 6  SCRUM428AssignmentQueueable einreihen (Phase B, Schritte 7–8)
 *
 * Anhängen (AC4/5): Dup-Case wird GESCHLOSSEN (Status='Closed', Subject-Präfix
 *   '[Dedupliziert: {Ziel-CaseNumber}] '), Dedupliziert__c=true, CaseComment auf
 *   den Ziel-Case (Body = Text der Nachricht). PO-Default (Design §8).
 *
 * Rekursions-/Interaktions-Schutz (ADR-3 Schritt 5):
 *   - 428-Trigger ist after-insert ONLY -> eigenes update feuert ihn NICHT erneut.
 *   - 421-Trigger feuert auf update; sein Änderungs-Filter reagiert nur auf
 *     Servicebereich-Wechsel. Schritt 2 ändert Servicebereich__c -> 421 routiert
 *     jetzt auf die korrekte Queue (GEWOLLT, ohne 421 zu ändern).
 *   - Dup-Schließung ändert nur Status/Subject/Dedupliziert__c -> 421 macht continue.
 *   - Phase B (Queueable) setzt OwnerId Queue->User -> 421 filtert (kein SB) -> keine Überschreibung.
 *
 * without sharing (Automation-Kontext — Haus-Pattern SCRUM-420/398/421).
 *
 * @author developer-agent
 * @date 2026-09-24
 */
public without sharing class SCRUM428CaseIngestHandler {

    /** AC4: 8-stellige Standard-Case-Nummer (3 Präfix-Stellen + 4–7 Ziffern, Design §2.1). */
    private static final Pattern CASE_NUMBER_RE = Pattern.compile('\\b000\\d{4,7}\\b');

    /** AC3 Priority-Reihenfolge (Developer legt Startliste fest, Design ADR-3 §9). */
    private static final List<String> CATEGORIZE_ORDER = new List<String>{
        'Technik', 'Rechnung', 'Vertrag'
    };

    /**
     * Entry Point aus dem Trigger. newCases = Trigger.new (vor der Insert).
     */
    public static void process(List<Case> newCases) {
        if (newCases == null || newCases.isEmpty()) {
            return;
        }

        // Schritt 1+2: Erfassungsquelle + Kategorisierung (mutiert sObjects, kein DML).
        applySourceAndCategory(newCases);

        // Schritt 3+4: Dedup-Zielfindung (liest die Org, 2 SOQL).
        Map<Id, Id> dupTargetByNewCase = findDupTargets(newCases);

        // Dup-Abschluss auf den sObjects anwenden + CaseComments sammeln.
        List<CaseComment> newComments = applyDup(newCases, dupTargetByNewCase);

        // 1 DML: alle mutierten Cases (Quelle/Kategorie/Dup) in einem update.
        update newCases;

        // 1 DML: CaseComments auf die Ziel-Cases.
        if (!newComments.isEmpty()) {
            insert newComments;
        }

        // Schritt 6: Phase B einreihen (Zuteilung + Bestätigung), inkl. Dup-Cases
        // (die Confirmation überspringt Dup intern).
        List<Id> caseIds = new List<Id>();
        for (Case c : newCases) {
            caseIds.add(c.Id);
        }
        System.enqueueJob(new SCRUM428AssignmentQueueable(caseIds));
    }

    /**
     * Schritt 1 (AC1/2) + Schritt 2 (AC3). Mutiert die sObject-Felder direkt —
     * persistiert erst im gemeinsamen update. Keine SOQL.
     */
    private static void applySourceAndCategory(List<Case> newCases) {
        Map<String, List<String>> keywordsByBerech = loadBerechKeywords();
        for (Case c : newCases) {
            // Schritt 1: E-Mail -> Erfassungsquelle 'E-Mail'. Formular-Case trägt
            // schon 'Kontaktformular' vom Controller — nicht überschreiben.
            if (c.Origin == 'Email' && c.Erfassungsquelle__c == null) {
                c.Erfassungsquelle__c = 'E-Mail';
            }
            // Schritt 2: nur E-Mail + noch kein Bereich gesetzt.
            if (c.Origin == 'Email' && c.Servicebereich__c == null) {
                c.Servicebereich__c = categorize(c, keywordsByBerech);
            }
        }
    }

    /**
     * Schritt 2 (AC3): Keyword-Match, Priority Technik > Rechnung > Vertrag.
     * Kein Treffer -> 'Allgemein'.
     */
    private static String categorize(Case c, Map<String, List<String>> keywordsByBerech) {
        String haystack = buildHaystack(c);
        for (String bereich : CATEGORIZE_ORDER) {
            List<String> keywords = keywordsByBerech.get(bereich);
            if (keywords == null) {
                continue;
            }
            for (String kw : keywords) {
                if (kw != null && !kw.isEmpty() && haystack.contains(kw.toLowerCase())) {
                    return bereich;
                }
            }
        }
        return 'Allgemein';
    }

    // ---------------------------------------------------------------------
    // Schritt 3 (AC4) + Schritt 4 (AC5): Dedup-Zielfindung
    // ---------------------------------------------------------------------

    /**
     * Für jeden neuen Case das Dup-Ziel (bestehende offene Case-Id) bestimmen.
     * Kandidaten = offene Org-Cases + neue Cases desselben Batches (nach dem
     * insert existieren sie; Trigger läuft after insert). Ziel pro Key =
     * kleinste Id (deterministisch), niemals der Case selbst.
     * AC4 (Case-Nummer im Text) hat Vorrang vor AC5 (ContactId + gleicher
     * Bereich, offen).
     *
     * @return Map neue-Case-Id -> Ziel-Case-Id (nur Treffer)
     */
    private static Map<Id, Id> findDupTargets(List<Case> newCases) {
        Map<Id, Id> result = new Map<Id, Id>();
        if (newCases.isEmpty()) {
            return result;
        }

        // --- Kandidaten-Pool: kleinste offene Id pro Schlüssel, inkl. Batch ---
        // AC4: CaseNumber -> Ziel-Id (offene Org-Cases + neue Batch-Cases).
        Map<String, Id> targetByCaseNumber = new Map<String, Id>();
        for (Case c : newCases) {
            if (c.CaseNumber != null) {
                addIfSmaller(targetByCaseNumber, c.CaseNumber, c.Id);
            }
        }
        Set<String> numberCandidates = new Set<String>();
        for (Case c : newCases) {
            String num = extractCaseNumber(c);
            if (num != null) {
                numberCandidates.add(num);
            }
        }
        if (!numberCandidates.isEmpty()) {
            for (Case existing : [
                SELECT Id, CaseNumber
                FROM Case
                WHERE Status != 'Closed' AND CaseNumber IN :numberCandidates
            ]) {
                addIfSmaller(targetByCaseNumber, existing.CaseNumber, existing.Id);
            }
        }
        // AC5: ContactId + ':' + Bereich -> Ziel-Id (offene Org-Cases + Batch).
        Map<String, Id> targetByContactBerech = new Map<String, Id>();
        Set<Id> contactIds = new Set<Id>();
        for (Case c : newCases) {
            if (c.ContactId != null && c.Servicebereich__c != null) {
                addIfSmaller(targetByContactBerech, c.ContactId + ':' + c.Servicebereich__c, c.Id);
            }
            if (c.ContactId != null) {
                contactIds.add(c.ContactId);
            }
        }
        if (!contactIds.isEmpty()) {
            for (Case existing : [
                SELECT Id, ContactId, Servicebereich__c
                FROM Case
                WHERE Status != 'Closed' AND ContactId IN :contactIds
            ]) {
                if (existing.ContactId == null || existing.Servicebereich__c == null) {
                    continue;
                }
                addIfSmaller(targetByContactBerech,
                    existing.ContactId + ':' + existing.Servicebereich__c, existing.Id);
            }
        }

        // --- Zuordnung ---
        Map<Id, String> extractedByCase = new Map<Id, String>();
        for (Case c : newCases) {
            String num = extractCaseNumber(c);
            if (num != null) {
                extractedByCase.put(c.Id, num);
            }
        }
        for (Case c : newCases) {
            Id ac4 = null;
            String num = extractedByCase.get(c.Id);
            if (num != null && targetByCaseNumber.containsKey(num)) {
                ac4 = targetByCaseNumber.get(num);
            }
            Id ac5 = null;
            if (c.ContactId != null && c.Servicebereich__c != null) {
                ac5 = targetByContactBerech.get(c.ContactId + ':' + c.Servicebereich__c);
            }
            Id target = ac4 != null ? ac4 : ac5; // AC4 hat Vorrang
            if (target != null && target != c.Id) {
                result.put(c.Id, target);
            }
        }
        return result;
    }

    /** Setzt key->id, wenn der neue Id kleiner ist (deterministisch kleinste Id). */
    private static Boolean addIfSmaller(Map<String, Id> map, String key, Id id) {
        Id cur = map.get(key);
        if (cur == null || id < cur) {
            map.put(key, id);
            return true;
        }
        return false;
    }

    /**
     * Wendet den Dup-Abschluss an (Status/Subject/Dedupliziert) und baut die
     * CaseComments für die Ziel-Cases. Mutiert nur die übergebenen sObjects.
     * 1 SOQL für die Ziel-CaseNumbers.
     */
    private static List<CaseComment> applyDup(List<Case> newCases, Map<Id, Id> dupTargetByNewCase) {
        List<CaseComment> comments = new List<CaseComment>();
        if (dupTargetByNewCase.isEmpty()) {
            return comments;
        }
        Set<Id> targetIds = new Set<Id>();
        for (Id t : dupTargetByNewCase.values()) {
            targetIds.add(t);
        }
        Map<Id, String> numberByTarget = new Map<Id, String>();
        for (Case t : [SELECT Id, CaseNumber FROM Case WHERE Id IN :targetIds]) {
            numberByTarget.put(t.Id, t.CaseNumber);
        }
        for (Case c : newCases) {
            Id targetId = dupTargetByNewCase.get(c.Id);
            if (targetId == null) {
                continue;
            }
            c.Status = 'Closed';
            c.Subject = '[Dedupliziert: ' + numberByTarget.get(targetId) + '] ' + c.Subject;
            c.Dedupliziert__c = true;
            comments.add(new CaseComment(
                ParentId = targetId,
                CommentBody = buildHaystack(c)
            ));
        }
        return comments;
    }

    // ---------------------------------------------------------------------
    // Helfer
    // ---------------------------------------------------------------------

    /** Keyword-Regeln aus MDT, gruppiert nach Bereich (1× SOQL, 0 SOQL je Case). */
    private static Map<String, List<String>> loadBerechKeywords() {
        Map<String, List<String>> byBerech = new Map<String, List<String>>();
        for (SCRUM428_KategorierRegel__mdt md : [
            SELECT Bereich__c, Keyword__c
            FROM SCRUM428_KategorierRegel__mdt
        ]) {
            if (md.Bereich__c == null || md.Keyword__c == null) {
                continue;
            }
            if (!byBerech.containsKey(md.Bereich__c)) {
                byBerech.put(md.Bereich__c, new List<String>());
            }
            byBerech.get(md.Bereich__c).add(md.Keyword__c);
        }
        return byBerech;
    }

    /** Subject + Description, case-insensitive (lowercase). */
    private static String buildHaystack(Case c) {
        return ((c.Subject == null ? '' : c.Subject)
            + ' '
            + (c.Description == null ? '' : c.Description)).toLowerCase();
    }

    /** Erste im Text gefundene Case-Nummer (AC4) oder null. */
    private static String extractCaseNumber(Case c) {
        String haystack = c.Subject == null ? ''
            : (c.Subject + ' ' + (c.Description == null ? '' : c.Description));
        Matcher m = CASE_NUMBER_RE.matcher(haystack);
        if (m.find()) {
            return m.group();
        }
        return null;
    }
}
