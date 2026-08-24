import { test, expect, type Locator, type Page } from '@playwright/test';
import { openRecordDetails, expectFieldVisible, startInlineEdit, saveInlineEdit } from './record-page';

/**
 * [SCRUM-353] FeldFinoIlsede__c (Text 255) auf Contact — UI-Tests.
 *
 * Akzeptanzkriterien (Jira SCRUM-353):
 *   AC1: Feld wird auf dem Contact-Layout angezeigt (Details-Tab)
 *   AC2: max. 255 Zeichen werden gespeichert und angezeigt
 *   AC3: mehr als 255 Zeichen werden abgelehnt
 *   (AC4 — FLS-Negativ: User OHNE das Permission Set SCRUM353_FeldFinoIlsede
 *    sieht das Feld nicht — ist KEIN UI-Szenario der Test-Org: beide lizenzierten
 *    User sind System-Administrators, die Custom-Field-FLS erben selbst ohne PS
 *    (verifiziert SCRUM-329). Bewiesen stattdessen via System.runAs() mit
 *    Standard-User in SCRUM353FeldFinoIlsedeFlsTest.cls — siehe Jira-Report.)
 *
 * Regression:
 *   AC-Reg: Detailed_Comment__c + Additional_Comment__c bleiben in derselben
 *    Notes-Sektion sichtbar (Layout wurde um FeldFinoIlsede__c erweitert).
 *
 * Test-User devops-agent@cline.test trägt PS SCRUM353_FeldFinoIlsede
 * (verifiziert via SOQL) → positives Szenario gegen echte FLS.
 *
 * Record 003WU00001VrdqTYAR (Rose Gonzalez): FeldFinoIlsede__c = null;
 * Detailed_Comment__c / Additional_Comment__c haben Restwerte früherer
 * Tickets (2026-08-24 verifiziert via SOQL Read-back).
 */
const CONTACT_PATH = '/lightning/r/Contact/003WU00001VrdqTYAR/view';
const FIELD_LABEL = 'FeldFinoIlsede';

/** Deterministic 255-char value, SOQL-readable after the run. */
const FULL_VALUE = 'SCRUM353-AC1-' + 'a'.repeat(255 - 'SCRUM353-AC1-'.length);
const SHORT_VALUE = 'SCRUM353-EDGE-42';

/**
 * Type a value into a field's edit input (full form is open).
 *
 * Clear first, then type character by character: a clean field means the
 * length read back equals the text sent, and over-length input exposes the
 * maxlength cap for real (a pre-filled field would just block appending,
 * which reads like a broken test when it is not).
 */
async function typeInto(input: Locator, text: string) {
  await input.scrollIntoViewIfNeeded();
  await input.fill('');
  await input.pressSequentially(text, { delay: 0 });
}

/**
 * Assert the saved value renders in the record Details tab (read mode).
 *
 * Scoping matters: the record page shows the value once, but a substring
 * search over the whole page can resolve to a different field's value that
 * sits earlier in the DOM (e.g. Phone renders tel:-links above the layout —
 * observed: a value typed into Phone shadowed the intended assertion).
 */
async function expectFieldSaved(page: Page, fieldLabel: string, value: string) {
  const inDetails = page
    .getByRole('tabpanel', { name: 'Details', exact: true })
    .getByRole('listitem')
    .filter({ hasText: fieldLabel })
    .first()
    .getByText(value, { exact: true });
  await expect(
    inDetails,
    `saved value "${value.slice(0, 40)}…" not visible next to "${fieldLabel}" on the Details tab`
  ).toBeVisible({ timeout: 20000 });
}

test.describe('[SCRUM-353] FeldFinoIlsede field on Contact', () => {
  test('AC1: field is visible on the Contact layout (Details tab, Notes section)', async ({ page }) => {
    await openRecordDetails(page, CONTACT_PATH);
    await expectFieldVisible(page, FIELD_LABEL);
  });

  test('AC2: authorized user enters and saves max 255 chars — value persists', async ({ page }) => {
    expect(FULL_VALUE.length).toBe(255);

    await openRecordDetails(page, CONTACT_PATH);
    await expectFieldVisible(page, FIELD_LABEL);

    const input = await startInlineEdit(page, FIELD_LABEL);
    await typeInto(input, FULL_VALUE);
    await saveInlineEdit(page);

    // Saved value must render in read mode …
    await expectFieldSaved(page, FIELD_LABEL, FULL_VALUE);

    // … and survive a full page reload (persistence, not just DOM state).
    await page.reload({ waitUntil: 'domcontentloaded' });
    await openDetailsTabClick(page);
    await expectFieldSaved(page, FIELD_LABEL, FULL_VALUE);
  });

  test('AC3: input with MORE than 255 characters is rejected', async ({ page }) => {
    const over = 'b'.repeat(280);

    await openRecordDetails(page, CONTACT_PATH);
    await expectFieldVisible(page, FIELD_LABEL);

    const input = await startInlineEdit(page, FIELD_LABEL);

    // 1) The input itself declares the cap (Text(255) → maxlength=255).
    await expect(input).toHaveAttribute('maxlength', '255');

    // 2) A typed 280-char value is truncated to exactly 255 — the 25 extra
    //    characters never enter the field, i.e. the system rejects them.
    await typeInto(input, over);
    expect(await input.inputValue()).toBe('b'.repeat(255));
    const len = (await input.inputValue()).length;
    expect(len).toBeLessThanOrEqual(255);

    // abandon the edit — no save (the persisted value stays untouched)
    await page.keyboard.press('Escape');
  });

  test('AC-Reg: regression — Detailed_Comment__c and Additional_Comment__c remain in the same Notes section', async ({ page }) => {
    await openRecordDetails(page, CONTACT_PATH);

    // All three fields of the Notes section must be visible together:
    // the two pre-existing fields (SCRUM-319/344) + the new one (SCRUM-353).
    await expectFieldVisible(page, 'Additional Comment');
    await expectFieldVisible(page, 'Detailed Comment');
    await expectFieldVisible(page, FIELD_LABEL);
  });

  test('edge: short value round-trips exactly', async ({ page }) => {
    await openRecordDetails(page, CONTACT_PATH);
    await expectFieldVisible(page, FIELD_LABEL);

    const input = await startInlineEdit(page, FIELD_LABEL);
    await typeInto(input, SHORT_VALUE);
    await saveInlineEdit(page);

    await expectFieldSaved(page, FIELD_LABEL, SHORT_VALUE);
  });
});

/**
 * Re-open the Details tab after a reload — a Contact always opens on the
 * Related tab, and record-page.ts already documents why text-scanning before
 * the tab click reports false negatives.
 */
async function openDetailsTabClick(page: Page) {
  const details = page.getByRole('tab', { name: 'Details' });
  await expect(details, 'Details tab missing after reload').toBeVisible({ timeout: 30000 });
  await details.click();
  await page.waitForTimeout(2500);
}
