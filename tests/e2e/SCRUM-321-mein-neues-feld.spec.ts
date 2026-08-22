import { test, expect, type Page } from '@playwright/test';
import { execSync } from 'child_process';

/**
 * [SCRUM-321] MeinNeuesFeld auf Opportunity-Objekt
 *
 * Lightning Experience inline-editing pattern:
 * - Detail view: fields shown as label + value + "Edit <Field>" button
 * - NO data-fieldname attribute — use text-based locators
 * - Inline editing: click "Edit <Field>", fill, click "Save"
 * - "Details" tab must be selected (default is "Activity")
 *
 * Migrated from tests/playwright/. Authentication now comes from the shared
 * globalSetup + storageState, so no per-test frontdoor fixture is needed.
 */

const FIELD_LABEL = 'MeinNeuesFeld';

/** Resolve a target Opportunity instead of hardcoding a record id. */
function resolveOpportunityId(): string {
  if (process.env.SCRUM321_OPPORTUNITY_ID) return process.env.SCRUM321_OPPORTUNITY_ID;

  const raw = execSync('sf data query --query "SELECT Id FROM Opportunity LIMIT 1" --json', {
    encoding: 'utf-8',
    stdio: ['pipe', 'pipe', 'pipe'],
  });
  const records = JSON.parse(raw.replace(/\x1b\[[0-9;]*[a-zA-Z]/g, '')).result.records;
  if (!records?.length) {
    throw new Error('[SCRUM-321] No Opportunity found in the org to run against.');
  }
  return records[0].Id;
}

test.describe('[SCRUM-321] MeinNeuesFeld E2E Tests', () => {
  let viewUrl: string;

  test.beforeAll(() => {
    viewUrl = `/lightning/r/Opportunity/${resolveOpportunityId()}/view`;
  });

  async function openStablePage(page: Page, path: string) {
    await page.goto(path, { waitUntil: 'domcontentloaded', timeout: 60000 });
    // Wait for a structural landmark — networkidle never settles on Lightning
    await page.waitForSelector('.slds-global-header', { state: 'visible', timeout: 60000 });
    await page.waitForTimeout(2500);
  }

  async function clickDetailsTab(page: Page) {
    const detailsTab = page.getByRole('tab', { name: 'Details' });
    if (await detailsTab.isVisible()) {
      await detailsTab.click();
      await page.waitForTimeout(2500);
    }
  }

  /** Open the inline editor for the field and return the active input. */
  async function startInlineEdit(page: Page) {
    const editBtn = page.getByRole('button', { name: `Edit ${FIELD_LABEL}` });
    await expect(editBtn).toBeVisible();
    await editBtn.click();
    await page.waitForTimeout(500);

    const input = page.locator('input[type="text"]').filter({ visible: true }).first();
    await expect(input).toBeVisible({ timeout: 15000 });
    return input;
  }

  async function save(page: Page) {
    const saveBtn = page.getByRole('button', { name: 'Save' });
    if (await saveBtn.isVisible({ timeout: 5000 }).catch(() => false)) {
      await saveBtn.click();
      return;
    }
    const saveAndNew = page.getByRole('button', { name: 'Save & New' });
    await expect(saveAndNew).toBeVisible({ timeout: 5000 });
    await saveAndNew.click();
  }

  test('AC-1: Feld "MeinNeuesFeld" ist auf der Detailseite sichtbar', async ({ page }) => {
    await openStablePage(page, viewUrl);
    await clickDetailsTab(page);

    await expect(page.getByText(FIELD_LABEL).first()).toBeVisible();
  });

  test('AC-2: Speichern wird verhindert, wenn das Pflichtfeld leer ist', async ({ page }) => {
    await openStablePage(page, viewUrl);
    await clickDetailsTab(page);

    const input = await startInlineEdit(page);
    await input.click();
    await input.fill('');
    await save(page);

    const error = page.getByText(/MeinNeuesFeld.*Pflicht|Required|Complete this field/i);
    await expect(error.first()).toBeVisible({ timeout: 15000 });
  });

  test('AC-3: Ein gültiger Wert wird erfolgreich gespeichert', async ({ page }) => {
    const testValue = `VALID_${Date.now()}`;

    await openStablePage(page, viewUrl);
    await clickDetailsTab(page);

    const input = await startInlineEdit(page);
    await input.click();
    await input.fill(testValue);
    await save(page);
    await page.waitForTimeout(3000);

    // Assert the value persisted across a reload
    await openStablePage(page, viewUrl);
    await clickDetailsTab(page);
    await expect(page.getByText(testValue).first()).toBeVisible({ timeout: 15000 });
  });

  test('AC-4: Feld ist editierbar (CRUD Positive) — Wert wird persistent', async ({ page }) => {
    const testValue = `EDIT_TEST_${Date.now()}`;

    await openStablePage(page, viewUrl);
    await clickDetailsTab(page);

    const input = await startInlineEdit(page);
    await expect(input).toBeEnabled();
    await input.click();
    await input.fill(testValue);
    await save(page);

    await openStablePage(page, viewUrl);
    await clickDetailsTab(page);
    await expect(page.getByText(testValue).first()).toBeVisible({ timeout: 15000 });
  });
});
