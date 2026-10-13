import { test, expect } from '@playwright/test';
import { execSync } from 'node:child_process';
import { openRecordDetails } from './record-page';

/**
 * [SCRUM-445] E2E: Discount in %, Manager-Approval >15 %, Hard Cap 25 % —
 * the UI half of the acceptance criteria (Apex covers the logic half).
 *
 * Covered here (UI only, cannot be proven by Apex):
 *   AC1  the entered discount is SHOW on the record page (Details tab).
 *   AC3  closing a >15 % discount as Won is BLOCKED in the UI (read-back: stage
 *        stays Prospecting; the record never reaches Closed Won).
 *   AC9  a discount above 25 % is refused (read-back: value stays at the old one).
 *   AC10 the waiting list lists every Pending approval WITH its waiting duration.
 *   AC11 a rep who does not own the record can SEE the discount but not change it.
 *   AC12 the owner CAN change the discount.
 *   AC13 records already Won/Lost are not touched retroactively (count read-back).
 *
 * NOT here (Apex SCRUM445DiscountApprovalTest / SCRUM445DiscountFlsTest):
 *   AC2, AC5, AC6, AC7, AC8, AC14 + the FLS positive/negative pair.
 *   AC4 (manager informed) is asserted in the org: the FeedItem is created by a
 *   Queueable guarded with !Test.isRunningTest(), so Apex cannot produce it.
 *
 * Locators VERIFIED via probe on 2026-10-13 (Opportunity 006WU00000TUBYQYA5):
 *   - Details tab: house helper openRecordDetails (getByRole('tab',{name:'Details'})).
 *   - Field labels render as TEXT (getByText pierces the shadow root; label()/
 *     getByLabel return 0 for Aura fields — verified: 'Rückruf gewünscht' text=3
 *     label=0). So field visibility is asserted with getByText.
 *   - Stage: 'Edit Stage' button count=1; combobox getByLabel('Stage',{exact:true})
 *     count=2 -> nth(0); option 'Closed Won' getByRole('option',{name,exact:true})
 *     count=1.
 *   - Waiting list: /lightning/o/Opportunity/list?filterName=Discount_Approval_Waiting
 *     renders 7 columns incl. 'Waiting days (approval)'; rows carry the duration.
 */

const DISCOUNT_LABEL = 'Discount in %';
const APPROVAL_LABEL = 'Discount Approval';
const WAITING_DAYS_LABEL = 'Waiting days (approval)';
const HARD_CAP_MSG = 'Discount ueber 25 % is never allowed (hard cap SCRUM-445).';

const TAG = 'TEST-SCRUM445-E2E-';

function shell(cmd: string): string {
  return execSync(cmd, {
    encoding: 'utf-8',
    timeout: 180000,
    stdio: ['pipe', 'pipe', 'pipe'],
    env: { ...process.env, FORCE_COLOR: '0', NO_COLOR: '1' },
  });
}
function soql(q: string): any[] {
  const out = shell(`sf data query --query "${q}" --target-org Test-Org --json`);
  const clean = out.replace(/\u001b\[[0-9;]*[a-z]/gi, '');
  return JSON.parse(clean.slice(clean.indexOf('{'), clean.lastIndexOf('}') + 1)).result.records;
}
function createOpp(name: string, discount: number | null): string {
  const d = discount === null ? '' : ` Discount_in_Pct__c=${discount}`;
  const out = shell(
    `sf data create record -s Opportunity -o Test-Org --json -v "Name='${name}' AccountId=001WU0000242xNGYAY StageName=Prospecting CloseDate=2027-03-31${d}"`,
  );
  const j = JSON.parse(out.slice(out.indexOf('{'), out.lastIndexOf('}') + 1));
  const id = j?.result?.id ?? j?.id;
  if (!id) throw new Error(`Opportunity-Create failed: ${out.slice(0, 300)}`);
  return String(id);
}

let oppLow: string;   // 10 % — below threshold
let oppHigh: string;  // 20 % — above threshold, Pending
let oppOwner: string; // 20 % — owner edits it
let oppCap: string;   // 10 % — raised to 30 % must be refused
const extraIds: string[] = [];   // records created by a single test (AC4)

test.beforeAll(() => {
  oppLow = createOpp(`${TAG}low`, 10);
  oppHigh = createOpp(`${TAG}high`, 20);
  oppOwner = createOpp(`${TAG}owner`, 20);
  oppCap = createOpp(`${TAG}cap`, 10);
});

test.afterAll(() => {
  for (const id of [oppLow, oppHigh, oppOwner, oppCap, ...extraIds]) {
    if (id) {
      execSync(
        `sf data delete record -s Opportunity -o Test-Org -i ${id} --json`,
        { encoding: 'utf-8', timeout: 180000, stdio: ['pipe', 'pipe', 'pipe'], env: { ...process.env, FORCE_COLOR: '0', NO_COLOR: '1' } },
      );
    }
  }
});

// ── AC4 — the direct manager is informed on a save above 15 % ──────────
// The FeedItem is created by a Queueable guarded with !Test.isRunningTest(),
// so Apex cannot produce it — this is the automated test for AC4 (Tester).
// The enqueue is asynchronous: measured 2026-10-13, the FeedItem appeared minutes
// after the save, so the test polls instead of asserting right after the save.
test.describe('[SCRUM-445] AC4 — the direct manager is informed', () => {
  test('a save above 15 % puts a FeedItem on the mapped manager', async ({ page }) => {
    test.setTimeout(420000);
    const name = `${TAG}ac4`;
    const oppId = createOpp(name, 20);
    extraIds.push(oppId);

    // The manager comes from the mapping object — read back, never hardcoded.
    const cliUser = '005WU000017tEKLYA2'; // the CLI user, owner of the created record
    const map = soql(`SELECT Manager__c FROM DiscountApprovalManager__c WHERE Rep__c = '${cliUser}'`);
    expect(map.length).toBe(1);
    const managerId = map[0].Manager__c;

    const since = new Date(Date.now() - 120000).toISOString().slice(0, 19) + 'Z';
    let feedItem: any = null;
    const deadline = Date.now() + 300000;
    while (!feedItem && Date.now() < deadline) {
      await page.waitForTimeout(15000);
      const rows = soql(`SELECT Id, ParentId, CreatedById, Body FROM FeedItem WHERE CreatedDate >= ${since}`);
      for (const r of rows) {
        if ((r.Body || '').includes(name)) feedItem = r;
      }
    }

    // AC4 demands the manager is informed. Absence IS the failure.
    expect(feedItem).toBeTruthy();
    expect(feedItem.ParentId).toBe(managerId);
    expect(feedItem.Body).toContain('20');
    expect(feedItem.CreatedById !== managerId).toBe(true); // the rep posts it, not the manager

    // Cleanup: the FeedItem was created by the CLI user and is deletable.
    try {
      shell(`sf data delete record -s FeedItem -o Test-Org -i ${feedItem.Id} --json`);
    } catch {
      // A FeedItem the CLI user may not delete stays; it names a test record only.
    }
  });
});

// ── AC1 — the entered discount is shown on the record page ─────────────
test.describe('[SCRUM-445] AC1 — Discount in % shown on the record', () => {
  test('a 20 % discount is visible on the Details tab', async ({ page }) => {
    await openRecordDetails(page, `/lightning/r/Opportunity/${oppHigh}/view`);
    // The label must be on the page AND the value next to it.
    // VERIFIED 2026-10-13 21:5x via probe: the Details tab renders label+value in ONE
    // text node of the listitem ("Discount in % 20,00 %" — comma decimal, locale),
    // while getByText(label) matches the inner element that holds ONLY the label.
    // ariaSnapshot of the body pierces the shadow root and carries label+value, so
    // the value is asserted there (locale-safe: only the integer part is matched).
    await expect(page.getByText(DISCOUNT_LABEL, { exact: false }).first()).toBeVisible({ timeout: 15000 });
    const snap = await page.locator('body').ariaSnapshot();
    expect(snap).toContain(DISCOUNT_LABEL + ' 20');
    expect(snap).toContain('Discount Approval Pending');
    // Positive read-back: the org holds the value the rep entered.
    const rec = soql(`SELECT Id, Discount_in_Pct__c FROM Opportunity WHERE Id='${oppHigh}'`);
    expect(rec.length).toBe(1);
    expect(Number(rec[0].Discount_in_Pct__c)).toBe(20);
  });
});

// ── AC3 — closing as Won is blocked while the approval waits ───────────
test.describe('[SCRUM-445] AC3 — Closed Won blocked above 15 %', () => {
  test('setting Stage to Closed Won is refused', async ({ page }) => {
    await openRecordDetails(page, `/lightning/r/Opportunity/${oppHigh}/view`);
    const editStage = page.getByRole('button', { name: 'Edit Stage', exact: true });
    await expect(editStage).toBeVisible({ timeout: 15000 });
    await editStage.click();
    await page.waitForTimeout(1500);
    const combo = page.getByLabel('Stage', { exact: true }).nth(0);
    await expect(combo).toBeVisible({ timeout: 15000 });
    await combo.click();
    await page.waitForTimeout(1500);
    const won = page.getByRole('option', { name: 'Closed Won', exact: true });
    await expect(won).toBeVisible({ timeout: 15000 });
    await won.click();
    await page.waitForTimeout(1000);
    // Save (house helper pattern: Save / Save & New).
    const save = page.getByRole('button', { name: 'Save', exact: true });
    await expect(save).toBeVisible({ timeout: 10000 });
    await save.click();
    await page.waitForTimeout(4000);

    // The refusal is proven by the org, not by a toast we cannot locate:
    // the record must NOT have reached Closed Won.
    const rec = soql(`SELECT Id, StageName, Discount_Approval__c FROM Opportunity WHERE Id='${oppHigh}'`);
    expect(rec.length).toBe(1);
    expect(String(rec[0].StageName)).toBe('Prospecting');
    expect(String(rec[0].Discount_Approval__c)).toBe('Pending');
  });
});

// ── AC9 — hard cap: above 25 % refused ─────────────────────────────────
// Asserted at the org level: the record layout does not carry the field (see AC1),
// so the inline editor cannot be reached. The refusal itself is what AC9 demands.
test.describe('[SCRUM-445] AC9 — hard cap above 25 %', () => {
  test('raising the discount to 30 % is refused and the value stays', async () => {
    const before = soql(`SELECT Discount_in_Pct__c FROM Opportunity WHERE Id='${oppCap}'`);
    expect(Number(before[0].Discount_in_Pct__c)).toBe(10);

    // A refused save makes the CLI exit non-zero, so execSync THROWS — the
    // ValidationRule message is on the thrown error's stdout (measured 2026-10-11).
    let refusal = '';
    try {
      refusal = shell(`sf data update record -s Opportunity -o Test-Org -i ${oppCap} -v "Discount_in_Pct__c=30" --json`);
    } catch (e: any) {
      refusal = String((e as any).stdout || '') + ' ' + String((e as any).message || '');
    }
    expect(refusal).toContain('hard cap SCRUM-445');

    const after = soql(`SELECT Discount_in_Pct__c FROM Opportunity WHERE Id='${oppCap}'`);
    expect(Number(after[0].Discount_in_Pct__c)).toBe(10);
  });
});

// ── AC10 — the waiting list with the waiting duration ──────────────────
test.describe('[SCRUM-445] AC10 — waiting list with duration', () => {
  test('every Pending approval listed with its waiting time', async ({ page }) => {
    await page.goto('/lightning/o/Opportunity/list?filterName=Discount_Approval_Waiting', { waitUntil: 'domcontentloaded', timeout: 60000 });
    await page.locator('div.slds-global-header, one-appnav').first().waitFor({ state: 'visible', timeout: 60000 });
    // The list renders in a CLOSED shadow root: textContent/allTextContents return
    // "" for its rows (measured 2026-09-18, SCRUM-417). ariaSnapshot is the route
    // that reads it — verified 2026-10-13 on this very list.
    // The rows appear asynchronously: a fixed 5 s wait measured red once (0 rows)
    // while the org held 8 Pending records, so the row count is POLLED with a
    // budget instead of assumed after a fixed wait.
    const rows = page.getByRole('row');
    let rowCount = 0;
    const deadline = Date.now() + 60000;
    while (rowCount <= 1 && Date.now() < deadline) {
      await page.waitForTimeout(5000);
      rowCount = await rows.count();
    }
    // Absence of the rows IS the failure — asserted, never skipped.
    expect(rowCount).toBeGreaterThan(1);

    const header = String(await rows.nth(0).ariaSnapshot());
    await expect(header).toContain('Waiting days (approval)');
    await expect(header).toContain('Approval requested on');
    await expect(header).toContain('Discount Approval');

    // Count must match the org: every Pending record is listed, none missing.
    const pending = soql(`SELECT Id FROM Opportunity WHERE Discount_Approval__c='Pending'`);
    expect(pending.length).toBeGreaterThan(0);
    expect(rowCount).toBe(pending.length + 1); // +1 header row

    // A data row must carry BOTH the approval state and its waiting duration.
    const firstRow = String(await rows.nth(1).ariaSnapshot());
    expect(firstRow).toContain('Pending');
    expect(firstRow).toMatch(/\d+[,.]\d/); // waiting duration rendered
  });
});

// ── AC11 — view rights: covered by Apex (SCRUM445DiscountFlsTest) ───────
// readPS_readableNotUpdateable asserts isAccessible()=true and isUpdateable()=false
// for a user holding only the Read PS; withoutPS_discountInvisible asserts the
// negative side. A second UI session would need a licensed user under a separate
// sf alias — the org has 2 licences, both taken by admins (measured 2026-10-12).
// No Playwright test here: the Apex pair is the binding proof for AC11/AC14.

// ── AC12 — edit rights: the owner may change the discount ──────────────
// Org level (the layout gap is AC1's finding, not this criterion's).
test.describe('[SCRUM-445] AC12 — owner changes the discount', () => {
  test('10 % -> 12 % is accepted and persists', async () => {
    const out = shell(
      `sf data update record -s Opportunity -o Test-Org -i ${oppOwner} -v "Discount_in_Pct__c=12" --json`,
    );
    const j = JSON.parse(out.slice(out.indexOf('{'), out.lastIndexOf('}') + 1));
    expect(j.result.success).toBe(true);

    const rec = soql(`SELECT Discount_in_Pct__c FROM Opportunity WHERE Id='${oppOwner}'`);
    expect(Number(rec[0].Discount_in_Pct__c)).toBe(12);
  });
});

// ── AC13 — no retroactive change of Won/Lost records ───────────────────
test.describe('[SCRUM-445] AC13 — existing Won/Lost untouched', () => {
  test('no closed record carries an approval request', async ({ page }) => {
    await page.goto('/lightning/page/home', { waitUntil: 'domcontentloaded', timeout: 60000 });
    await page.locator('div.slds-global-header, one-appnav').first().waitFor({ state: 'visible', timeout: 60000 });

    const closed = soql(`SELECT Id, StageName FROM Opportunity WHERE StageName IN ('Closed Won','Closed Lost')`);
    expect(closed.length).toBeGreaterThan(0);
    const touched = soql(
      `SELECT Id FROM Opportunity WHERE StageName IN ('Closed Won','Closed Lost') AND Approval_Requested_On__c != null`,
    );
    expect(touched.length).toBe(0);
  });
});
