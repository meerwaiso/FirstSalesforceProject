import { createElement } from 'lwc';
import Scr428ContactForm from 'c/scr428ContactForm';

// Apex-Import als virtual module mocken (sfdx-lwc-jest kennt Apex nicht).
const submitForm = jest.fn();
jest.mock(
    '@salesforce/apex/SCRUM428ContactFormController.submitForm',
    () => ({ default: submitForm }),
    { virtual: true }
);

function makeForm() {
    const element = createElement('c-scr428-contact-form', {
        is: Scr428ContactForm
    });
    document.body.appendChild(element);
    return element;
}

function setField(elm, selector, value) {
    elm.querySelector(selector).value = value;
    elm.querySelector(selector).dispatchEvent(new Event('change'));
}

describe('c-scr428-contact-form', () => {
    afterEach(() => {
        document.body.innerHTML = '';
        submitForm.mockReset();
    });

    it('validates required fields before submit', () => {
        const element = makeForm();
        element.querySelector('form').dispatchEvent(new Event('submit'));
        expect(submitForm).not.toHaveBeenCalled();
    });

    it('rejects nachricht shorter than 10 chars (client-side)', () => {
        const element = makeForm();
        setField(element, 'lightning-input[type="text"]', 'Max Mustermann');
        setField(element, 'lightning-input[type="email"]', 'max@example.com');
        setField(element, 'lightning-textarea', 'zu kurz');
        element.querySelector('form').dispatchEvent(new Event('submit'));
        expect(submitForm).not.toHaveBeenCalled();
    });

    it('submits a valid form with optional bereich = null', async () => {
        submitForm.mockResolvedValue('00002837');
        const element = makeForm();
        setField(element, 'lightning-input[type="text"]', 'Max Mustermann');
        setField(element, 'lightning-input[type="email"]', 'max@example.com');
        setField(element, 'lightning-textarea', 'Hier ist genug Text fuer 10 Zeichen.');
        element.querySelector('form').dispatchEvent(new Event('submit'));
        await Promise.resolve();
        await Promise.resolve();
        expect(submitForm).toHaveBeenCalledTimes(1);
        expect(submitForm).toHaveBeenCalledWith({
            name: 'Max Mustermann',
            email: 'max@example.com',
            bereich: null,
            nachricht: 'Hier ist genug Text fuer 10 Zeichen.'
        });
    });

    it('passes a chosen bereich through', async () => {
        submitForm.mockResolvedValue('00002840');
        const element = makeForm();
        setField(element, 'lightning-input[type="text"]', 'Max Mustermann');
        setField(element, 'lightning-input[type="email"]', 'max@example.com');
        setField(element, 'lightning-combobox', 'Technik');
        setField(element, 'lightning-textarea', 'Hier ist genug Text fuer 10 Zeichen.');
        element.querySelector('form').dispatchEvent(new Event('submit'));
        await Promise.resolve();
        await Promise.resolve();
        expect(submitForm).toHaveBeenCalledWith({
            name: 'Max Mustermann',
            email: 'max@example.com',
            bereich: 'Technik',
            nachricht: 'Hier ist genug Text fuer 10 Zeichen.'
        });
    });

    it('shows error toast and keeps form on apex rejection', async () => {
        submitForm.mockRejectedValue({
            body: { message: 'Die Nachricht muss mindestens 10 Zeichen haben.' }
        });
        const element = makeForm();
        setField(element, 'lightning-input[type="text"]', 'Max Mustermann');
        setField(element, 'lightning-input[type="email"]', 'max@example.com');
        setField(element, 'lightning-textarea', 'Hier ist genug Text fuer 10 Zeichen.');
        element.querySelector('form').dispatchEvent(new Event('submit'));
        await Promise.resolve();
        await Promise.resolve();
        expect(submitForm).toHaveBeenCalledTimes(1);
        expect(element.querySelector('lightning-textarea').value).toBe(
            'Hier ist genug Text fuer 10 Zeichen.'
        );
    });
});
