/**
 * Service class for Laptop inventory check logic
 * Replaces Laptop_Lagerbestandspruefung Flow
 */
public without sharing class LaptopLagerbestandService {

    @InvocableMethod(label='Check Laptop Inventory' description='Checks inventory and updates status')
    public static void checkInventory(List<Id> laptopIds) {
        List<Laptop__c> laptops = [
            SELECT Id, Modell__c, Status__c
            FROM Laptop__c
            WHERE Id IN :laptopIds
        ];

        Map<String, List<Id>> modelToIds = new Map<String, List<Id>>();

        for (Laptop__c laptop : laptops) {
            if (laptop.Modell__c != null) {
                if (!modelToIds.containsKey(laptop.Modell__c)) {
                    modelToIds.put(laptop.Modell__c, new List<Id>());
                }
                modelToIds.get(laptop.Modell__c).add(laptop.Id);
            }
        }

        // Query inventory laptops by model - exclude the request laptops themselves
        // (only laptops with Status 'Auf_Lager' count as inventory)
        Map<String, List<Laptop__c>> inventoryByModel = new Map<String, List<Laptop__c>>();
        if (!modelToIds.isEmpty()) {
            List<Laptop__c> inventoryLaptops = [
                SELECT Id, Modell__c, Status__c
                FROM Laptop__c
                WHERE Modell__c IN :modelToIds.keySet()
                  AND Status__c = 'Auf_Lager'
                  AND Id NOT IN :laptopIds
            ];

            for (Laptop__c invLaptop : inventoryLaptops) {
                if (!inventoryByModel.containsKey(invLaptop.Modell__c)) {
                    inventoryByModel.put(invLaptop.Modell__c, new List<Laptop__c>());
                }
                inventoryByModel.get(invLaptop.Modell__c).add(invLaptop);
            }
        }

        List<Laptop__c> toUpdate = new List<Laptop__c>();
        List<Laptop__c> inventoryToUpdate = new List<Laptop__c>();

        for (Laptop__c laptop : laptops) {
            List<Laptop__c> availableInventory = inventoryByModel.get(laptop.Modell__c);

            if (availableInventory != null && !availableInventory.isEmpty()) {
                // Inventory available - set to Zugewiesen
                laptop.Status__c = 'Zugewiesen';
                toUpdate.add(laptop);

                // Mark one inventory laptop as assigned
                Laptop__c invLaptop = availableInventory.remove(0);
                invLaptop.Status__c = 'Zugewiesen';
                inventoryToUpdate.add(invLaptop);
            } else {
                // No inventory - set to Nachbestellung
                laptop.Status__c = 'Nachbestellung';
                toUpdate.add(laptop);
            }
        }

        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }

        if (!inventoryToUpdate.isEmpty()) {
            update inventoryToUpdate;
        }
    }
}