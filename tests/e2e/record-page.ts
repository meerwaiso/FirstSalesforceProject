import { expect, type Page } from '@playwright/test';

/**
 * Helpers for Lightning record pages.
 *
 * A record page does NOT open on the Details tab — on this org a Contact opens
 * with `Related | Details | Activity | Chatter` and Related active. Custom
 * fields live under Details, so they are absent from the page text until that
 * tab is clicked. Reading `document.body.innerText` straight after load
 * therefore reports every custom field as missing, which reads like a broken
 * deployment and is not one.
 *
 * Verified 2026-08-23 against Contact 003WU00001VrdqTYAR.
 */

/** Navigate to a record page and wait for the Lightning shell to render. */
export async function openRecordPage(page: Page, path: string) {
  await page.goto(path, { waitUntil: 'domcontentloaded', timeout: 60000 });
  // networkidle never fires on Lightning — wait for a structural landmark
  await page
    .locator('div.slds-global-header, one-appnav')
    .first()
    .waitFor({ state: 'visible', timeout: 60000 });
  await page.waitForTimeout(2500);
}

/** Switch to the Details tab, where the layout's fields are rendered. */
export async function openDetailsTab(page: Page) {
  const details = page.getByRole('tab', { name: 'Details' });
  if (await details.isVisible().catch(() => false)) {
    await details.click();
    await page.waitForTimeout(2500);
  }
}

/** Open a record and land on its Details tab in one step. */
export async function openRecordDetails(page: Page, path: string) {
  await openRecordPage(page, path);
  await openDetailsTab(page);
}

/**
 * Assert a field label is visible on the Details tab.
 *
 * Use this rather than scanning page text: it fails with a useful message and
 * it cannot pass by accident on a tab that never opened.
 */
export async function expectFieldVisible(page: Page, label: string) {
  await expect(
    page.getByText(label, { exact: false }).first(),
    `field "${label}" not visible on the Details tab — check the layout with ` +
      `\`sf project retrieve start --metadata "Layout:<Object>-<Layout Name>"\` ` +
      `before concluding it was not deployed`
  ).toBeVisible({ timeout: 15000 });
}

/**
 * Open the inline editor for a field and return THAT field's input.
 *
 * Clicking "Edit <Field>" puts the entire Details section into edit mode, not
 * just the one field: 26 inputs become visible on a standard Contact. Taking
 * the first visible input therefore binds to whatever sits at the top of the
 * section — on Contact that is Phone, and the test value silently lands there
 * while the intended field stays empty. Scope by the field's own label.
 *
 * Verified 2026-08-23 on Contact 003WU00001VrdqTYAR: with the section in edit
 * mode, `getByLabel('Detailed Comment')` matches exactly 1 of 26 inputs.
 */
export async function startInlineEdit(page: Page, fieldLabel: string) {
  const editBtn = page.getByRole('button', { name: `Edit ${fieldLabel}` });
  await expect(editBtn).toBeVisible({ timeout: 15000 });
  await editBtn.click();
  await page.waitForTimeout(500);

  const input = page.getByLabel(fieldLabel, { exact: true });
  await expect(
    input,
    `no single input labelled "${fieldLabel}" — the whole section is in edit ` +
      `mode, so never take the first visible input; scope by label or by ` +
      `[name="<ApiName>__c"]`
  ).toHaveCount(1);
  await expect(input).toBeVisible({ timeout: 15000 });
  return input;
}

/** Save an inline edit. Lightning shows either "Save" or "Save & New". */
export async function saveInlineEdit(page: Page) {
  const save = page.getByRole('button', { name: 'Save' });
  if (await save.isVisible({ timeout: 5000 }).catch(() => false)) {
    await save.click();
    return;
  }
  const saveAndNew = page.getByRole('button', { name: 'Save & New' });
  await expect(saveAndNew).toBeVisible({ timeout: 5000 });
  await saveAndNew.click();
}
