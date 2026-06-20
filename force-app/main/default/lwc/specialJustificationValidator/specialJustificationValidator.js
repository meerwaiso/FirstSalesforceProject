import { LightningElement, api } from 'lwc';
import KAUFDATUM_FIELD from '@salesforce/schema/Laptop__c.Kaufdatum__c';
import SONDERBEGRUENDUNG_FIELD from '@salesforce/schema/Laptop__c.Sonderbegruendung__c';

/**
 * Lightning Validation Rule (client-seitig) für Sonderbegruendung__c
 * Prueft, ob Sonderbegruendung ausgefuellt ist, wenn Kaufdatum jünger als 3 Jahre
 */
export default class SpecialJustificationValidator extends LightningElement {
  @api recordTypeId;
  @api objectApiName = 'Laptop__c';

  // Feld-Referenzen
  kaufdatumField = KAUFDATUM_FIELD;
  sonderbegruendungField = SONDERBEGRUENDUNG_FIELD;

  /**
   * Validates on save - Lightning Validation Rule entry point
   */
  @api
  validate() {
    const errors = [];

    // Only validate on create (new records)
    const mode = this.template.querySelector('lightning-record-edit-form')
      ?.mode ?? 'edit';

    // Get field values from the form
    const kaufdatum = this.getFieldValue(KAUFDATUM_FIELD.fieldApiName);
    const sonderbegruendung = this.getFieldValue(
      SONDERBEGRUENDUNG_FIELD.fieldApiName
    );

    // Check if Kaufdatum is within the last 3 years (1095 days)
    if (kaufdatum && !sonderbegruendung) {
      const kaufdatumDate = new Date(kaufdatum);
      const threeYearsAgo = new Date();
      threeYearsAgo.setDate(threeYearsAgo.getDate() - 1095);

      if (kaufdatumDate > threeYearsAgo) {
        errors.push({
          fieldPath: SONDERBEGRUENDUNG_FIELD.fieldApiName,
          message:
            'Ihr aktuelles Gerät ist weniger als 3 Jahre alt. Bitte geben Sie eine Sonderbegründung an.',
        });
      }
    }

    return { errors };
  }

  /**
   * Helper method to get field value from the form
   */
  getFieldValue(fieldApiName) {
    const fieldEl = this.template.querySelector(
      `[data-field-name="${fieldApiName}"]`
    );
    return fieldEl ? fieldEl.value : null;
  }
}