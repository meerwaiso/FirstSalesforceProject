import { LightningElement, api } from 'lwc';
import previewTransfer from '@salesforce/apex/CustomerTransferController.preview';
import launchTransfer from '@salesforce/apex/CustomerTransferController.launch';
import availableUsers from '@salesforce/apex/CustomerTransferController.availableUsers';
import userName from '@salesforce/apex/CustomerTransferController.userName';

/**
 * [SCRUM-410] Betreuungs-Übergabe als Quick Action auf dem User-Record.
 *
 * Flow: „Gibt ab" = der offene User-Record (vorausgefüllt, read-only),
 * „Übernimmt" wählbar aus den aktiven Nutzern → „Vorschau" zeigt die vier
 * Counts (AC1, read-only) → „Übergeben" startet den atomaren Queueable-Job (AC2).
 *
 * Der Zustand kommt rein aus den Apex-Aufrufen — kein networkidle/DOM-Timer.
 */
export default class Betreuungsuebergabe extends LightningElement {
    /** Id des User-Records, auf dem die Quick Action geöffnet wurde. */
    @api recordId;

    fromUserName = '';
    toOptions = [];
    toUserId = '';
    preview = null;
    previewLoading = false;
    launching = false;
    error = '';
    done = '';

    /**
     * Name des User-Records, auf dem die Quick Action geöffnet wurde —
     * per Apex-Methode (kein lightning/schema-Import, der scheitert im
     * Compile des Bundles).
     */
    async connectedCallback() {
        if (!this.recordId) {
            this.error =
                'Kein User-Record im Kontext — die Aktion muss auf dem Record einer Person geöffnet werden.';
            return;
        }
        try {
            const name = await userName({ userId: this.recordId });
            this.fromUserName = name || '';
            this.toOptions = await availableUsers({ excludeUserId: this.recordId });
        } catch (e) {
            this.error = this.errorMessage(e);
        }
    }

    get formVisible() {
        return !this.done;
    }

    get canPreview() {
        return Boolean(this.recordId && this.toUserId && !this.preview);
    }

    handleToChange(e) {
        this.toUserId = e.target.value;
        this.preview = null;
        this.error = '';
    }

    async handlePreview() {
        this.previewLoading = true;
        this.error = '';
        try {
            this.preview = await previewTransfer({
                fromUserId: this.recordId,
                toUserId: this.toUserId
            });
        } catch (e) {
            this.error = this.errorMessage(e);
        }
        this.previewLoading = false;
    }

    async handleLaunch() {
        this.launching = true;
        this.error = '';
        try {
            await launchTransfer({
                fromUserId: this.recordId,
                toUserId: this.toUserId
            });
            this.done =
                'Übergabe abgestoßen. Der Lauf ist atomar; wer wann wie viele ' +
                'Kunden/Fälle/Chancen übergeben hat, steht im Objekt „Betreuungs-Übergabe".';
            this.preview = null;
        } catch (e) {
            this.error = this.errorMessage(e);
        }
        this.launching = false;
    }

    errorMessage(e) {
        return (e && e.body && e.body.message) || String(e);
    }
}
