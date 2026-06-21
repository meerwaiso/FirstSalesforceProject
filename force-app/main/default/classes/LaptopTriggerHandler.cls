/**
 * Handler for Laptop trigger - replaces Flow-based logic
 */
public without sharing class LaptopTriggerHandler {

    /**
     * Handle before insert - apply approval status based on price
     */
    public static void handleBeforeInsert(List<Laptop__c> laptops) {
        for (Laptop__c laptop : laptops) {
            if (laptop.Preis__c != null && laptop.Preis__c <= 1500) {
                laptop.Status__c = 'Genehmigt';
            } else if (laptop.Preis__c != null && laptop.Preis__c > 1500) {
                laptop.Status__c = 'Ausstehend';
            }
        }
    }

    /**
     * Handle after insert - no inventory check on insert.
     * Inventory check only runs on update when status changes to Genehmigt.
     * This prevents overriding the approval status set by before insert.
     */
    public static void handleAfterInsert(List<Laptop__c> laptops) {
        // No action on insert - inventory check is triggered by after update
        // when status explicitly changes to Genehmigt
    }

    /**
     * Handle after update - check inventory when status changes to Genehmigt
     */
    public static void handleAfterUpdate(List<Laptop__c> laptops, Map<Id, Laptop__c> oldMap) {
        List<Id> laptopIds = new List<Id>();
        for (Laptop__c laptop : laptops) {
            Laptop__c old = oldMap.get(laptop.Id);
            // Check inventory when status changes to Genehmigt
            if (old != null && old.Status__c != 'Genehmigt' && laptop.Status__c == 'Genehmigt') {
                laptopIds.add(laptop.Id);
            }
        }

        if (!laptopIds.isEmpty()) {
            LaptopLagerbestandService.checkInventory(laptopIds);
        }
    }
}