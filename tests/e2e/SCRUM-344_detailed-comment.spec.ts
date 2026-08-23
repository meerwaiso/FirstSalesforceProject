import { test, expect, type Locator, type Page } from '@playwright/test';
import { openRecordDetails, expectFieldVisible, startInlineEdit, saveInlineEdit } from './record-page';

/**
 * [SCRUM-344] Detailed_Comment__c (Text 255) auf Contact — UI-Tests.
 *
 * Akzeptanzkriterien (Jira SCRUM-344):
 *   AC1: autorisierter Benutzer kann Text bis 255 Zeichen eingeben und speichern
 *   AC3: Eingabe wird ab 255 Zeichen begrenzt
 *   (AC2 — Feld unsichtbar ohne Permission Set — ist kein UI-Szenario der
 *    Test-Org: beide User sind System-Administrators und erben FLS auf Custom
 *    Fields trotz fehlendem PS. Bewiesen stattdessen via System.runAs() mit
 *    Standard-User in SCRUM344DetailedCommentFlsTest.cls — siehe Jira.)
 *
 * Test-User devops-agent@cline.test trägt PS SCRUM344_DetailedComment
 * (verifiziert, PR #32) → positives Szenario gegen echte FLS.
 *
 * Record 003WU00001VrdqTYAR: verifiziert am 2026-08-23 (Details-Tab rendert
 * "Additional Comment" + "Detailed Comment" nebeneinander).
 */
const CONTACT_PATH = '/lightning/r/Contact/003WU00001VrdqTYAR/view';
const FIELD_LABEL = 'Detailed Comment';

/** Deterministic 255-char value, SOQL-readable after the run. */
const FULL_VALUE = 'SCRUM344-AC1-' + 'a'.repeat(255 - 'SCRUM344-AC1-'.length);
const SHORT_VALUE = 'SCRUM344-EDGE-42';

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

test.describe('[SCRUM-344] Detailed Comment field on Contact', () => {
  test('TC1: field is visible on the Details tab', async ({ page }) => {
    await openRecordDetails(page, CONTACT_PATH);
    await expectFieldVisible(page, FIELD_LABEL);
  });

  test('TC2 (AC1): authorized user enters and saves 255 chars', async ({ page }) => {
    expect(FULL_VALUE.length).toBe(255);

    await openRecordDetails(page, CONTACT_PATH);
    await expectFieldVisible(page, FIELD_LABEL);

    const input = await startInlineEdit(page, FIELD_LABEL);
    await typeInto(input, FULL_VALUE);
    await saveInlineEdit(page);

    await expectFieldSaved(page, FIELD_LABEL, FULL_VALUE);
  });

  test('TC3 (AC3): input accepts no more than 255 characters', async ({ page }) => {
    const over = 'b'.repeat(280);

    await openRecordDetails(page, CONTACT_PATH);
    await expectFieldVisible(page, FIELD_LABEL);

    const input = await startInlineEdit(page, FIELD_LABEL);

    // 1) The input itself declares the cap (Text(255) → maxlength=255).
    await expect(input).toHaveAttribute('maxlength', '255');

    // 2) A typed 280-char value is truncated to exactly 255.
    await typeInto(input, over);
    expect(await input.inputValue()).toBe('b'.repeat(255));
    const len = (await input.inputValue()).length;
    expect(len).toBeLessThanOrEqual(255);

    // abandon the edit — no save
    await page.keyboard.press('Escape');
  });

  test('TC4 (edge): short value round-trips exactly', async ({ page }) => {
    await openRecordDetails(page, CONTACT_PATH);
    await expectFieldVisible(page, FIELD_LABEL);

    const input = await startInlineEdit(page, FIELD_LABEL);
    await typeInto(input, SHORT_VALUE);
    await saveInlineEdit(page);

    await expectFieldSaved(page, FIELD_LABEL, SHORT_VALUE);
  });
});
