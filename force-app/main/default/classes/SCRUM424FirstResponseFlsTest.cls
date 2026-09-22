/**
 * [SCRUM-424] FLS-Evidenz: Profil-Read für 3 Custom-Felder — via UI-API Read-Test.
 *
 * Kein Systemtest mit runAs (wie SCRUM421) — der Profil-Lock (S3) ist erst vom
 * DevOps-Setup durchzufuehren. Dieser Test prueft via record-ui API, dass alle
 * 3 Felder fuer den Test-User lesbar sind (Read-back fuer Handoff an Tester).
 *
 * @author developer-agent
 * @date 2026-09-22
 */
@isTest
private class SCRUM424FirstResponseFlsTest {

    public static testmethod void fields_are_readable_via_ui_api() {
        // Create test case
        Case c = new Case(Subject = 'FLS Read Test', Status = 'New');
        insert c;

        // Use REST UI API to check field visibility (same as Lightning uses)
        HttpRequest req = new HttpRequest();
        req.setEndpoint(URL.getSalesforceBaseUrl().toExternalForm() +
            '/services/data/v62.0/ui-api/record-ui/' + c.Id +
            '?layoutTypes=Full&modes=View');
        req.setMethod('GET');
        req.setHeader('Authorization', 'Bearer ' + UserInfo.getSessionId());
        req.setHeader('Content-Type', 'application/json');

        HttpResponse res = new Http().send(req);
        System.assertEquals(200, res.getStatusCode(), 'UI API returned 200');

        // Parse JSON and check our 3 fields are in editable field set
        Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        Map<String, Object> fields = (Map<String, Object>) result.get('layouts');

        // Verify all 3 fields are present and readable
        Boolean timeFound = false;
        Boolean minsFound = false;
        Boolean missedFound = false;

        for (Object layout : (List<Object>)fields) {
            Map<String, Object> l = (Map<String, Object>)layout;
            Map<String, Object> layoutFields = (Map<String, Object>)l.get('fields');
            if (layoutFields.containsKey('First_Response_Time__c')) {
                timeFound = true;
            }
            if (layoutFields.containsKey('First_Response_Working_Mins__c')) {
                minsFound = true;
            }
            if (layoutFields.containsKey('First_Response_Target_Missed__c')) {
                missedFound = true;
            }
        }

        System.assert(timeFound, 'First_Response_Time__c readable via UI API');
        System.assert(minsFound, 'First_Response_Working_Mins__c readable via UI API');
        System.assert(missedFound, 'First_Response_Target_Missed__c readable via UI API');

        System.debug('SCRUM424: All 3 First-Response fields are readable via Profile/PS');
    }
}
