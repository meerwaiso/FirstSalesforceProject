import { LightningElement, api } from 'lwc';
import submitForm from '@salesforce/apex/SCRUM428ContactFormController.submitForm';

const BEREICHE = [
    { label: 'Bitte wählen —', value: '' },
    { label: 'Technik', value: 'Technik' },
    { label: 'Vertrag', value: 'Vertrag' },
    { label: 'Rechnung', value: 'Rechnung' },
    { label: 'Allgemein', value: 'Allgemein' }
];

export default class Scr428ContactForm extends LightningElement {
    name = '';
    email = '';
    bereich = '';
    nachricht = '';
    submitting = false;
    bereiche = BEREICHE;
    statusVariant = '';
    statusMessage = '';

    @api init() {
        // no-op, für Lightning-Record-Page-Kompatibilität
    }

    handleName(e) { this.name = e.target.value; }
    handleEmail(e) { this.email = e.target.value; }
    handleBereich(e) { this.bereich = e.target.value; }
    handleNachricht(e) { this.nachricht = e.target.value; }

    get beschreibungHint() {
        const len = this.nachricht ? this.nachricht.length : 0;
        return len < 10
            ? `Noch ${10 - len} Zeichen bis zur Mindestlänge (10).`
            : '';
    }

    get statusClass() {
        if (this.statusVariant === 'success') {
            return 'slds-m-top_small slds-text-color_success';
        }
        if (this.statusVariant === 'error') {
            return 'slds-m-top_small slds-text-color_error';
        }
        return 'slds-m-top_small';
    }

    async handleSubmit(e) {
        e.preventDefault();
        if (this.submitting) { return; }
        const missing = !this.name.trim() || !this.email.trim() || !this.nachricht.trim();
        if (missing) {
            this.setStatus('error', 'Bitte alle Pflichtfelder (*) ausfüllen.');
            return;
        }
        if (this.nachricht.trim().length < 10) {
            this.setStatus('error', 'Die Nachricht muss mindestens 10 Zeichen haben.');
            return;
        }
        this.submitting = true;
        this.statusVariant = '';
        this.statusMessage = 'Wird übermittelt …';
        try {
            const caseNumber = await submitForm({
                name: this.name,
                email: this.email,
                bereich: this.bereich || null,
                nachricht: this.nachricht
            });
            this.setStatus('success', 'Ihre Anfrage wurde erfasst. Fallnummer: ' + caseNumber);
            this.resetForm();
        } catch (error) {
            const message = error && error.body && error.body.message
                ? error.body.message : 'Bitte versuchen Sie es später erneut.';
            this.setStatus('error', message);
        } finally {
            this.submitting = false;
        }
    }

    setStatus(variant, message) {
        this.statusVariant = variant;
        this.statusMessage = message;
    }

    resetForm() {
        this.name = '';
        this.email = '';
        this.bereich = '';
        this.nachricht = '';
    }
}
