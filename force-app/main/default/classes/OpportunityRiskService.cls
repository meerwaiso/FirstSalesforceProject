/**
 * [SCRUM-449] OpportunityRiskService — the ONLY place the risk rules live.
 *
 * Six fields on Opportunity (4 business + 2 support):
 *   Risk_Level__c            Low / Medium / High, leer = nothing applies
 *   Risk_Reason__c           one German clause per applying condition
 *   Inactive_Days__c         FORMULA field — never written here
 *   Last_Risk_Evaluation__c  stamped on every recompute
 *   Last_User_Change__c      anchor: last change made by a USER
 *   Highest_Stage_Reached__c high-water mark for the setback condition (C4)
 *
 * Rule contract (docs/SCRUM-449-design.md §5):
 *   open   = IsClosed = false — NOT "Status": that field does not exist on
 *            Opportunity (verified INVALID_FIELD); house Single Source of Truth
 *            ADR-3 of SCRUM-416.
 *   C1 inactivity          anchor older than 14 days
 *   C2 unrealistic close   CloseDate within the next 7 days AND early stage
 *   C3 close date passed   CloseDate before today, still open        -> High
 *   C4 stage setback       highest reached - current; >1 -> High, =1 -> warning
 *   High = C3 or setback >1 | Medium = >= 2 warnings | Low = exactly 1
 *
 * Stage order is read from the org at runtime: Opportunity.StageName.getDescribe()
 * .picklistValues returns the picklist in CONFIGURED order (verified with
 * scripts/apex-probe.sh on Test-Org: 10 entries, Prospecting .. Closed Lost).
 * A later picklist change therefore cannot silently mis-rank the stages.
 * "Early stage" = first half of that picklist (10 values -> positions 1-5).
 *
 * Bulkification: evaluate() is pure Apex over records already in hand (0 SOQL);
 * recomputeAll() = 1 selective SOQL + chunked DML. No SOQL in any record loop.
 *
 * without sharing: the scheduler path must see every record organisation-wide
 * (AC10/AC12), independent of the running user's sharing.
 *
 * @author developer-agent
 * @date 2026-10-14
 */
public without sharing class OpportunityRiskService {

    @testVisible private static final Integer INACTIVE_DAYS_THRESHOLD = 14;
    @testVisible private static final Integer CLOSE_DATE_WINDOW_DAYS = 7;
    @testVisible private static final Integer REASON_MAX_LENGTH = 255;
    @testVisible private static final Integer DML_CHUNK_SIZE = 2000;

    // True while recomputeAll() runs its batch DML. The trigger handler reads it
    // and does NOT treat the scheduler's own writes as a user change — PO rule:
    // "changes written by the risk mechanism itself never count as an update
    //  and never reset the inactivity counter".
    // This flag alone is NOT sufficient: OTHER mechanisms (SCRUM-319
    // OpportunityOverdueService, SCRUM-445 DiscountApprovalHandler, ...) also
    // `update` Opportunities without the user touching anything. Those fire this
    // trigger with the flag false. The real gate is userEditedRecord() below.
    @testVisible public static Boolean systemWriteInProgress = false;

    // ---- Is this update a USER change? ---------------------------------------
    // Review SCRUM-449 (Architect, Blocking 1): moving the anchor on every
    // before-update let the SCRUM-319 nightly job reset the inactivity counter on
    // all 66 Is_Overdue__c records. The anchor moves only when a field the user
    // can edit actually changed value.
    // The list is generated from `sf sobject describe -s Opportunity` (2026-10-14)
    // minus: formula/readOnly/autoImplemented/compound fields, the five risk
    // fields, and every field another Apex mechanism writes without a user
    // (Is_Overdue__c, Discount_Approval__c, Approval_Decided_* /
    //  Approval_Requested_On__c / Approved_Discount_Value__c, Loss_Reason__c,
    //  Rueckruf_am__c). Apex has no generic sObject field access here
    // (getField/setField/getDescribe on sObject all reject — probe-verified),
    // so the comparison is explicit and typed.
    public static Boolean userEditedRecord(Opportunity now, Opportunity was) {
        if (now.AccountId != was.AccountId) return true;
        if (now.Name != was.Name) return true;
        if (now.Description != was.Description) return true;
        if (now.StageName != was.StageName) return true;
        if (now.Amount != was.Amount) return true;
        if (now.Probability != was.Probability) return true;
        if (now.ExpectedRevenue != was.ExpectedRevenue) return true;
        if (now.TotalOpportunityQuantity != was.TotalOpportunityQuantity) return true;
        if (now.CloseDate != was.CloseDate) return true;
        if (now.Type != was.Type) return true;
        if (now.NextStep != was.NextStep) return true;
        if (now.LeadSource != was.LeadSource) return true;
        if (now.ForecastCategoryName != was.ForecastCategoryName) return true;
        if (now.CampaignId != was.CampaignId) return true;
        if (now.Pricebook2Id != was.Pricebook2Id) return true;
        if (now.OwnerId != was.OwnerId) return true;
        if (now.PushCount != was.PushCount) return true;
        if (now.FiscalQuarter != was.FiscalQuarter) return true;
        if (now.FiscalYear != was.FiscalYear) return true;
        if (now.Fiscal != was.Fiscal) return true;
        if (now.ContactId != was.ContactId) return true;
        if (now.DeliveryInstallationStatus__c != was.DeliveryInstallationStatus__c) return true;
        if (now.TrackingNumber__c != was.TrackingNumber__c) return true;
        if (now.OrderNumber__c != was.OrderNumber__c) return true;
        if (now.CurrentGenerators__c != was.CurrentGenerators__c) return true;
        if (now.MainCompetitors__c != was.MainCompetitors__c) return true;
        if (now.TestFeld__c != was.TestFeld__c) return true;
        if (now.MeinNeuesFeld__c != was.MeinNeuesFeld__c) return true;
        if (now.Rueckruf_desired__c != was.Rueckruf_desired__c) return true;
        if (now.Discount_in_Pct__c != was.Discount_in_Pct__c) return true;
        if (now.Rejection_Reason__c != was.Rejection_Reason__c) return true;
        return false;
    }

    // ---- Stage order, read from the org --------------------------------------
    @testVisible private static Map<String, Integer> stagePosCache;
    @testVisible private static List<String> stageByPosCache; // 1-based: index 0 unused

    public static Map<String, Integer> stageOrder() {
        if (stagePosCache == null) {
            Map<String, Integer> m = new Map<String, Integer>();
            List<String> byPos = new List<String>{null}; // index 0 unused
            for (PicklistEntry e : Opportunity.StageName.getDescribe().picklistValues) {
                m.put(e.value, byPos.size()); // 1-based position, configured order
                byPos.add(e.value);
            }
            stagePosCache = m;
            stageByPosCache = byPos;
        }
        return stagePosCache;
    }

    public static Integer stagePos(String stage) {
        if (stage == null) {
            return null;
        }
        return stageOrder().get(stage);
    }

    public static String stageValueAt(Integer pos) {
        if (pos == null || pos < 1 || pos >= stageByPosCache.size()) {
            return null;
        }
        return stageByPosCache[pos];
    }

    /** "Early stage" = first half of the configured picklist. */
    public static Integer earlyStageCutoff() {
        return stageOrder().size() / 2; // 10 values -> 5
    }

    /**
     * Whole elapsed days between two DateTimes, rounded half-up — the same
     * value the formula field Inactive_Days__c shows for (NOW() - anchor) at
     * scale 0. Computed with daysBetween on the date parts plus the exact
     * seconds-of-day difference (Apex has no numeric Datetime value; Time
     * arithmetic rejects Integer/Long, so the clock parts are parsed from the
     * formatted string — verified with scripts/apex-probe.sh).
     *
     * @param from earlier anchor
     * @param to  later timestamp (now)
     */
    public static Integer roundedElapsedDays(DateTime earlier, DateTime later) {
        if (earlier == null || later == null) {
            return 0;
        }
        Integer whole = earlier.date().daysBetween(later.date()); // calendar steps
        Integer fromSec = secondsOfDay(earlier);
        Integer toSec = secondsOfDay(later);
        Integer delta = toSec - fromSec; // day-fraction difference in seconds
        if (delta < 0) {
            whole -= 1;
            delta += 86400;
        }
        Decimal elapsed = (Decimal)whole + (Decimal)delta / 86400.0;
        return (Integer)Math.round(elapsed);
    }

    private static Integer secondsOfDay(DateTime d) {
        return 3600 * Integer.valueOf(d.format('HH'))
             + 60 * Integer.valueOf(d.format('mm'))
             + Integer.valueOf(d.format('ss'));
    }

    // ---- The rule engine over records already in hand ------------------------
    public static List<Opportunity> evaluate(List<Opportunity> records) {
        List<Opportunity> dirty = new List<Opportunity>();
        for (Opportunity o : records) {
            if (applyRules(o)) {
                dirty.add(o);
            }
        }
        return dirty;
    }

    /**
     * Applies the rule contract to one record.
     * @return true when at least one field changed (record must be saved).
     */
    public static Boolean applyRules(Opportunity o) {
        Boolean changed = false;

        // 1. High-water mark first: the setback must be measured against the
        //    highest stage INCLUDING this record's current stage.
        Integer curPos = stagePos(o.StageName);
        Integer highPos = stagePos(o.Highest_Stage_Reached__c);
        Integer newHighPos = highPos;
        if (curPos != null) {
            newHighPos = (newHighPos != null && newHighPos > curPos) ? newHighPos : curPos;
        }
        if (newHighPos != null && (highPos == null || newHighPos > highPos)) {
            o.Highest_Stage_Reached__c = stageValueAt(newHighPos);
            changed = true;
        }

        // 2. The anchor: seeded once, never moved by the system's own writes
        //    (the caller guards that), only by real user transactions.
        if (o.Last_User_Change__c == null) {
            o.Last_User_Change__c = (o.LastModifiedDate != null)
                                        ? o.LastModifiedDate
                                        : System.now();
            changed = true;
        }

        // 3. Level + reason
        String level = null;
        String reason = null;

        if (o.IsClosed) {
            // AC7: Closed Won / Closed Lost are no active risk -> cleared.
            level = null;
            reason = null;
        } else {
            DateTime now = System.now();
            Date today = Date.today();
            DateTime anchor = o.Last_User_Change__c;

            // C1 and the DISPLAYED number must never disagree: Inactive_Days__c
            // is a formula the org computes as (NOW() - anchor) rounded at scale
            // 0. The same rounding is done here — whole calendar steps between
            // the date parts, minus one when the day-fraction has not passed,
            // then half-up. All DateTime arithmetic, no Date.today(): the org
            // runs in America/Los_Angeles and Date.today() is user-timezone
            // while Datetime.date() is GMT (house timezone lesson).
            Integer shownDays = 0;
            if (anchor != null) {
                shownDays = roundedElapsedDays(anchor, now);
            }
            Boolean c1 = (shownDays > INACTIVE_DAYS_THRESHOLD);

            Date closeD = o.CloseDate;
            // Date has no before()/after() in Apex — comparison operators (house).
            Boolean c3 = (closeD != null && closeD < today);
            Boolean c2 = (closeD != null
                          && closeD >= today
                          && closeD <= today.addDays(CLOSE_DATE_WINDOW_DAYS)
                          && curPos != null
                          && curPos <= earlyStageCutoff());

            Integer setback = (newHighPos != null && curPos != null) ? (newHighPos - curPos) : 0;
            Boolean c4Warning = (setback == 1);   // AC4: exactly one = warning only
            Boolean c4High = (setback > 1);

            Integer warnings = (c1 ? 1 : 0) + (c2 ? 1 : 0) + (c4Warning ? 1 : 0);

            if (c3 || c4High) {
                level = 'High';
            } else if (warnings >= 2) {
                level = 'Medium';
            } else if (warnings == 1) {
                level = 'Low';
            }

            List<String> clauses = new List<String>();
            if (c1) {
                clauses.add('Inaktivity: ' + shownDays + ' days without user change');
            }
            if (c2) {
                clauses.add('Unrealistic close date: CloseDate '
                    + String.valueOf(closeD)
                    + ' within the next ' + CLOSE_DATE_WINDOW_DAYS
                    + ' days while still in an early stage (' + o.StageName + ')');
            }
            if (c3) {
                clauses.add('Close date already passed (CloseDate ' + String.valueOf(closeD) + ')');
            }
            if (setback >= 1) {
                clauses.add('Stage setback: ' + setback
                    + ' positions below the highest stage reached ('
                    + stageValueAt(newHighPos) + ')');
            }
            if (!clauses.isEmpty()) {
                reason = String.join(clauses, ';');
                if (reason != null && reason.length() > REASON_MAX_LENGTH) {
                    reason = reason.substring(0, REASON_MAX_LENGTH);
                }
            }
        }

        if (o.Risk_Level__c != level) {
            o.Risk_Level__c = level;
            changed = true;
        }
        if (o.Risk_Reason__c != reason) {
            o.Risk_Reason__c = reason;
            changed = true;
        }

        // 4. Stamp the evaluation on every record we touched.
        if (changed) {
            o.Last_Risk_Evaluation__c = System.now();
        }
        return changed;
    }

    // ---- Nightly / full-scan path -------------------------------------------
    /**
     * Recomputes every Opportunity that could carry risk: all open records plus
     * any closed record that still shows a level or a reason (AC7 recovery).
     * Chunked DML so Prod growth cannot hit the 50k record limit.
     * @return number of records saved
     */
    public static Integer recomputeAll() {
        systemWriteInProgress = true;
        Integer saved = 0;
        try {
            List<Opportunity> batch = [
                SELECT Id, Name, AccountId, StageName, CloseDate, IsClosed,
                       LastModifiedDate, Risk_Level__c, Risk_Reason__c,
                       Last_Risk_Evaluation__c, Last_User_Change__c,
                       Highest_Stage_Reached__c
                FROM Opportunity
                WHERE IsClosed = false
                   OR Risk_Level__c != null
                   OR Risk_Reason__c != null
            ];
            List<Opportunity> dirty = evaluate(batch);
            // House chunking (AccountSatisfactionRebuilder): List.subList is not
            // Apex — buffer + flush at DML_CHUNK_SIZE.
            List<Opportunity> buffer = new List<Opportunity>();
            for (Opportunity o : dirty) {
                buffer.add(o);
                if (buffer.size() >= DML_CHUNK_SIZE) {
                    update buffer;
                    saved += buffer.size();
                    buffer = new List<Opportunity>();
                }
            }
            if (!buffer.isEmpty()) {
                update buffer;
                saved += buffer.size();
            }
        } finally {
            systemWriteInProgress = false;
        }
        return saved;
    }
}
