public with sharing class DevOpsFieldCheck341 {
    public static String run() {
        List<String> lines = new List<String>();
        Map<String, Schema.SObjectField> fields = Schema.SObjectType.Case.fields.getMap();

        // count custom fields
        Integer customCount = 0;
        for (String k : fields.keySet()) {
            if (k.endsWith('__c')) {
                customCount++;
            }
        }
        lines.add('TOTAL_CUSTOM_FIELDS_ON_CASE=' + customCount);

        // any field containing 'rueck'
        for (String k : fields.keySet()) {
            if (k.toLowerCase().contains('rueck')) {
                lines.add('DESCRIBE_FIELD=' + k);
            }
        }

        // direct lookups
        List<String> candidates = new List<String>{
            'RueckrufGewuenscht__c', 'RueckrufTermin__c',
            'RueckrufGewuenscht', 'RueckrufTermin',
            'Rueckruf_Gewuenscht__c', 'Rueckruf_Termin__c',
            'Rueckrufgewuenscht__c', 'Rueckruftermin__c'
        };
        for (Integer i = 0; i < candidates.size(); i++) {
            Schema.SObjectField f = fields.get(candidates[i]);
            if (f != null) {
                lines.add('LOOKUP_OK=' + candidates[i] + ' type=' + f.getDescribe().getType());
            } else {
                lines.add('LOOKUP_MISS=' + candidates[i]);
            }
        }
        return String.join(lines, '\n');
    }
}
