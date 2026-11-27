/**
 * [SCRUM-483] Sales-Austritt-Uebergabey: Target-Resolution and Audit-Spur.
 *
 * ADR-1 (Apex, not Flow) / ADR-4: the handover writes Account, Opportunity and
 * the new trail object ONLY. It never writes a User field - therefore the
 * deactivation of a person cannot fail because of this feature, and the rest of
 * AC11 is only about making a failed move visible.
 *
 * Target resolution (PO comment 23891 is authoritative):
 *   R-1  DiscountApprovalManager__c.Manager__c where Rep__c = owner  -> rule Manager
 *   R-2  User.ManagerId, only if that user is IsActive             -> rule Manager
 *   R-3  SalesHandoverFallback__c[0].Fallback_User__c              -> rule Fallback
 * R-1/R-2 are rejected when the manager is himself part of the deactivated set of
 * this run ("if that manager is themselves deactivated in the same run, the
 * records go to the fallback person"). The Test-Org mapping is circular (Meerwais
 * -> devops-agent and back, 2 rows measured 2026-11-27), so for AC7 BOTH persons
 * receive the fallback person and the row says Target_Rule__c=Fallback.
 *
 * Sales membership (PO comment 23891): a user is "of sales" iff he appears as
 * Rep__c in that mapping. Ownership as the rule would hand over the 1 Account of
 * Automated Process and break AC10's negative case.
 *
 * D-1 (open decision for review): AC10 and AC12 both describe a deactivated
 * owner without a mapping row - AC10 wants NOTHING recorded, AC12 wants a visible
 * row. Discriminator: the org's system users (Alias read from Test-Org 2026-11-27:
 * autoproc, integ, sec, autocln, Chatter, platint) are never sales people and
 * produce no row; any other owner without a mapping row is an entry mistake and
 * is logged as Blocked (AC12).
 *
 * Governor: ONE bulk read per object type per run, cached statically. Measured
 * Test-Org volume: 8 Users, 268 Accounts, 89 open Opportunities, 2 mapping rows,
 * 0 fallback rows, 0 trail rows.
 *
 * Tests: SalesDepartureHandoverTest (behaviour), SalesDepartureHandoverFlsTest (FLS).
 *
 * @author developer-agent
 * @date 2026-11-27
 */
public without sharing class SalesDepartureHandoverService {

    // --- Picklist constants (SalesDepartureHandover__c) ----------------------
    public static final String RULE_MANAGER = 'Manager';
    public static final String RULE_FALLBACK = 'Fallback';
    public static final String RULE_NONE = 'None';
    public static final String EV_INACTIVE = 'IsActive_false';
    public static final String EV_DELETED = 'Owner_record_deleted';
    public static final String ST_DONE = 'Done';
    public static String ST_BLOCKED = 'Blocked';
    public static String ST_FAILED = 'Failed';
    // Picklist value of the Target_Rule field on a Blocked row — the deployed value
    // set is Manager / Fallback / None (measured in the field file); an unknown value is
    // refused by the save, which would hide the alarm row itself.
    public static String ST_TARGET_NONE = 'None';

    // --- System users are never sales people (D-1) ---------------------------
    private static final Set<String> SYSTEM_USER_ALIASES = new Set<String>{
        'autoproc', 'integ', 'sec', 'autocln', 'Chatter', 'platint'
    };

    // --- Run caches (chunk-independent, one bulk read each) ------------------
    private static Boolean cachesLoaded = false;
    private static Map<Id, User> usersById;
    private static Map<Id, Id> mappedManager;
    private static Set<Id> salesRepIds;
    private static Set<Id> deactivatedThisRun;
    private static Set<String> loggedKeys;
    private static Id fallbackUserId;

    // --- Result of the last resolveTarget (rule + info, see below) -----------
    private static String lastRule = null;
    private static String lastInfo = null;

    public static void resetRunCaches() {
        cachesLoaded = false;
        usersById = new Map<Id, User>();
        mappedManager = new Map<Id, Id>();
        salesRepIds = new Set<Id>();
        deactivatedThisRun = new Set<Id>();
        loggedKeys = new Set<String>();
        fallbackUserId = null;
        lastRule = null;
        lastInfo = null;
    }

    /**
     * Reads the org state for one run: 4 bulk queries (User, mapping, fallback,
     * existing trail rows). The owner scans live in findDeactivatedOwners (2 more).
     * @param deactivatedIds the whole set deactivated in this run (AC7 rule)
     */
    public static void loadRunCaches() {
        resetRunCaches();
        for (User u : [SELECT Id, Name, Alias, IsActive, ManagerId FROM User]) {
            usersById.put(u.Id, u);
            if (!u.IsActive) {
                deactivatedThisRun.add(u.Id);
            }
        }
        for (DiscountApprovalManager__c row :
                [SELECT Id, Rep__c, Manager__c FROM DiscountApprovalManager__c]) {
            if (row.Rep__c != null) {
                salesRepIds.add(row.Rep__c);
                if (row.Manager__c != null) {
                    mappedManager.put(row.Rep__c, row.Manager__c);
                }
            }
        }
        for (SalesHandoverFallback__c row :
                [SELECT Id, Fallback_User__c FROM SalesHandoverFallback__c]) {
            if (row.Fallback_User__c != null) {
                fallbackUserId = row.Fallback_User__c;
            }
        }
        for (SalesDepartureHandover__c row :
                [SELECT Id, From_User__c, Deactivation_Evidence__c
                 FROM SalesDepartureHandover__c]) {
            if (row.From_User__c != null) {
                loggedKeys.add(logKey(row.From_User__c, row.Deactivation_Evidence__c));
            }
        }
        cachesLoaded = true;
    }

    private static void ensureLoaded() {
        if (!cachesLoaded) {
            loadRunCaches();
        }
    }

    /** A mapping row makes a user a sales person (R-1, AC10/AC12). */
    public static Boolean isSalesUser(Id userId) {
        ensureLoaded();
        return salesRepIds.contains(userId);
    }

    /** The org's own system users are never sales (D-1). */
    public static Boolean isSystemUser(Id userId) {
        ensureLoaded();
        User u = usersById.get(userId);
        if (u == null) {
            return false; // a deleted owner record is no system placeholder
        }
        return SYSTEM_USER_ALIASES.contains(u.Alias);
    }

    /**
     * Owner Ids that still hold records but are no longer usable: deactivated
     * (IsActive=false) or deleted (no User record any more). 2 bulk queries,
     * no aggregate, no query in a loop.
     * @return Map ownerId -> Deactivation_Evidence__c value
     */
    public static Map<Id, String> findDeactivatedOwners() {
        ensureLoaded();
        Set<Id> owners = new Set<Id>();
        for (Account a : [SELECT Id, OwnerId FROM Account]) {
            if (a.OwnerId != null) {
                owners.add(a.OwnerId);
            }
        }
        for (Opportunity o :
                [SELECT Id, OwnerId FROM Opportunity WHERE IsClosed = false]) {
            if (o.OwnerId != null) {
                owners.add(o.OwnerId);
            }
        }
        Map<Id, String> found = new Map<Id, String>();
        for (Id ownerId : owners) {
            User u = usersById.get(ownerId);
            if (u == null) {
                found.put(ownerId, EV_DELETED);
            } else if (!u.IsActive) {
                found.put(ownerId, EV_INACTIVE);
            }
        }
        return found;
    }

    /** A trail row already exists for this person + evidence (idempotency, AC7). */
    public static Boolean alreadyLogged(Id fromUserId, String evidence) {
        ensureLoaded();
        return loggedKeys.contains(logKey(fromUserId, evidence));
    }

    /**
     * Target resolution for one deactivated owner (R-1 -> R-2 -> R-3).
     * Evaluated once per person against the whole deactivated set of the run,
     * never per record.
     * @return the receiving user, null when nothing may move (AC4 / AC12)
     */
    public static Id resolveTarget(Id ownerId) {
        ensureLoaded();
        if (isSystemUser(ownerId)) {
            lastRule = RULE_NONE;
            lastInfo = 'System-User (Automated Process) - not a sales person, '
                + 'no handover.';
            return null;
        }
        if (!salesRepIds.contains(ownerId)) {
            lastRule = RULE_NONE;
            lastInfo = 'No Sales-Manager-Mapping row for this user (entry mistake)'
                + ' - nothing moved.';
            return null;
        }
        Id candidate = mappedManager.get(ownerId);
        if (candidate == ownerId) {
            candidate = null; // a person never hands his own records over
        }
        if (candidate != null && isUsableTarget(candidate)) {
            lastRule = RULE_MANAGER;
            lastInfo = null;
            return candidate;
        }
        User owner = usersById.get(ownerId);
        if (owner != null && owner.ManagerId != ownerId && owner.ManagerId != null
            && isUsableTarget(owner.ManagerId)) {
            lastRule = RULE_MANAGER;
            lastInfo = null;
            return owner.ManagerId;
        }
        if (fallbackUserId != ownerId && fallbackUserId != null
            && isUsableTarget(fallbackUserId)) {
            lastRule = RULE_FALLBACK;
            lastInfo = null;
            return fallbackUserId;
        }
        lastRule = RULE_NONE;
        lastInfo = 'Neither a manager nor a fallback person is available - nothing moved.';
        return null;
    }

    /** Which rule gave the last resolution: Manager / Fallback / None. */
    public static String targetRule() {
        return lastRule;
    }

    /** German explanation of a blocked resolution (AC4 / AC12 visibility). */
    public static String blockInfo() {
        return lastInfo;
    }

    /** A target must exist, be active and must not be deactivated in this run. */
    private static Boolean isUsableTarget(Id candidateId) {
        if (candidateId == null || deactivatedThisRun.contains(candidateId)) {
            return false;
        }
        User u = usersById.get(candidateId);
        return u != null && u.IsActive;
    }

    /**
     * One trail row per person x run. Blocked runs (AC4, AC12, pre-flight AC11)
     * are logged so sales management can open the tab - the alarm is not hidden
     * in a system log (ADR-4).
     * @return the Id of the new row
     */
    public static Id logRow(Id fromUserId, Id toUserId, String rule, String evidence,
                            String status, String info, String errorDetail) {
        SalesDepartureHandover__c row = new SalesDepartureHandover__c();
        row.From_User__c = fromUserId;
        if (toUserId != null) {
            row.To_User__c = toUserId;
        }
        row.Target_Rule__c = rule;
        row.Deactivation_Evidence__c = evidence;
        row.Status__c = status;
        row.Handed_Over_At__c = System.now();
        row.Info__c = trim255(info);
        row.Error_Detail__c = trim255(errorDetail);
        insert row;
        loggedKeys.add(logKey(fromUserId, evidence));
        return row.Id;
    }

    /** German message into a Text(255): never overflow the field. */
    public static String trim255(String s) {
        if (s == null) {
            return null;
        }
        return (s.length() <= 255) ? s : s.substring(0, 255);
    }

    private static String logKey(Id userId, String evidence) {
        String u = (userId == null) ? '' : String.valueOf(userId);
        String e = (evidence == null) ? '' : evidence;
        return u + '|' + e;
    }
}
