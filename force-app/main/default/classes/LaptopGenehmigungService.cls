/**
 * Service class for Laptop approval process logic
 * Replaces Laptop_Genehmigungsprozess Flow
 */
public without sharing class LaptopGenehmigungService {

    @InvocableMethod(label='Update Laptop Approval Status' description='Sets status based on price')
    public static void updateApprovalStatus(List<Id> laptopIds) {
        List<Laptop__c> laptops = [
            SELECT Id, Preis__c, Status__c
            FROM Laptop__c
            WHERE Id IN :laptopIds
        ];

        List<Laptop__c> toUpdate = new List<Laptop__c>();

        for (Laptop__c laptop : laptops) {
            String newStatus;

            if (laptop.Preis__c != null && laptop.Preis__c > 0 && laptop.Preis__c <= 1500) {
                newStatus = 'Genehmigt';
            } else {
                newStatus = 'Ausstehend';
            }

            if (laptop.Status__c != newStatus) {
                laptop.Status__c = newStatus;
                toUpdate.add(laptop);
            }
        }

        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }

    /**
     * Check if a laptop price requires special justification
     */
    public static Boolean requiresJustification(Decimal price) {
        return price != null && price > 1500;
    }
}