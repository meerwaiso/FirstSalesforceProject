import { LightningElement, api } from 'lwc';
import { getRecord } from 'lightning/uiRecordApi';
import USER_NAME_FIELD from 'lightning/schema/User.Name';
import previewTransfer from '@salesforce/apex/CustomerTransferController.preview';
import launchTransfer from '@salesforce/apex/CustomerTransferController.launch';
import availableUsers from '@salesforce/apex/CustomerTransferController.availableUsers';

/**
 * [SCRUM-410] Betreuungs-Übergabe als Quick Action auf dem User-Record.
 *
 * Flow: „Gibt ab" = der offene User-Record (vorausgefüllt, read-only),
 * „Übernimmt" wählbar aus den aktiven Nutzern → „Vorschau" zeigt die vier
 * Counts (AC1, read-only) → „Übergeben" startet den atomaren Queueable-Job (AC2).
 *
 * Kein networkidle/DOM-Timer — der Zustandswechsel kommt rein aus den Apex-Kontroll-
 * rufen; die Tester-UI-Prüfung (Playwright) wartet auf die Ergebnis-Texte.
 */
export default class Betreuungsuebergabe extends LightningElement {
    /** Id des User-Records, dessen Seiten die Quick Action geöffnet hat. */
    @api recordId;

    fromUser = '';
    fromUserName = 'aktueller Nutzer';
    toOptions = [];
    toUserId = '';
    preview = null;
    previewLoading = false;
    launching = false;
    error = '';
    done = '';

    async connectedCallback() {
        this.fromUser = this.recordId || '';
        if (!this.fromUser) {
            this.error =
                'Kein User-Record im Kontext — die Aktion muss auf dem Record einer Person geöffnet werden.';
            return;
        }
        try {
            const rec = await getRecord({
                recordIds: this.fromUser,
                fields: [USER_NAME_FIELD]
            });
            this.fromUserName = rec.fields[USER_NAME_FIELD.fieldApiName].value;
            this.toOptions = await availableUsers({ excludeUserId: this.fromUser });
        } catch (e) {
            this.error = this.errorMessage(e);
        }
    }

    get formVisible() {
        return !this.done;
    }

    get canPreview() {
        return Boolean(this.fromUser && this.toUserId && !this.preview);
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
                fromUserId: this.fromUser,
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
                fromUserId: this.fromUser,
                toUserId: this.toUserId
            });
            this.done =
                'Übergabe abgestoßen. Der Lauf ist atomar; die Lauf-Nr., wer wann wie viele ' +
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
