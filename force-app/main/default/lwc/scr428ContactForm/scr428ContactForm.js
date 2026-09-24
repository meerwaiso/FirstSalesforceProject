import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/showToastEvent';
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

    async handleSubmit(e) {
        e.preventDefault();
        const missing = !this.name.trim() || !this.email.trim() || !this.nachricht.trim();
        if (missing) {
            this.showToast('Fehler', 'Bitte alle Pflichtfelder (*) ausfüllen.', 'error');
            return;
        }
        if (this.nachricht.trim().length < 10) {
            this.showToast('Fehler', 'Die Nachricht muss mindestens 10 Zeichen haben.', 'error');
            return;
        }
        this.submitting = true;
        try {
            const caseNumber = await submitForm({
                name: this.name,
                email: this.email,
                bereich: this.bereich || null,
                nachricht: this.nachricht
            });
            this.showToast('Erfolg', 'Ihre Anfrage wurde erfasst. Fallnummer: ' + caseNumber, 'success');
            this.resetForm();
        } catch (error) {
            const message = error && error.body && error.body.message
                ? error.body.message : 'Bitte versuchen Sie es später erneut.';
            this.showToast('Fehler', message, 'error');
        } finally {
            this.submitting = false;
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    resetForm() {
        this.name = '';
        this.email = '';
        this.bereich = '';
        this.nachricht = '';
    }
}
