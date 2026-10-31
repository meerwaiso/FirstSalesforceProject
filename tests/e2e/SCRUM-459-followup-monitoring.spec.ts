import { test, expect } from '@playwright/test';
import { execSync } from 'node:child_process';
import path from 'path';

/**
 * [SCRUM-459] E2E: Follow-up Monitoring — the org/UI half of the ACs.
 *
 * Covered here (fixtures via CLI, monitoring values read back in the UI
 * through the list view "Follow_up_Monitoring" and via SOQL):
 *   AC2  overdue count = 1 for due 20./25./28. (today 23.) — relative dates.
 *   AC3  status precedence Overdue / Due Soon (today, +2) / Up to Date (+3).
 *   AC4  last completed interaction = the LATER completion date.
 *   AC5  completing an obligation (CLI save, UI blocked — see gap) recomputes
 *        count/status/last-interaction without touching the Opportunity.
 *   AC6  typing a monitoring value is refused (CLI save; guard message names
 *        the field; stored value unchanged).
 *   AC7  4 outstanding, 2 overdue -> count 2, status Overdue, next = earliest.
 *   AC8  Closed Won clears the six values; a later obligation completion keeps
 *        them cleared; the record leaves the monitoring list.
 *   AC9  attention flag: 75000+overdue -> true; 40000 -> false; 50000 exact -> false.
 *   AC10 the list shows exactly the open opportunities with overdue count >= 1.
 *
 * NOT here — blocked by a deployment gap found while probing (see
 * docs/SCRUM-459-notizen-tester.md and the linked bug ticket):
 *   Followup_Obligation__c has NO record-page FlexiPage: the new-record form
 *   renders only "Obligation Number"/"Owner", the record view renders no
 *   custom fields, and the Opportunity page has no "New Follow-up Obligation"
 *   action (Lookup relationship, no related list). So the rep's UI creation/
 *   completion path (AC1, AC5-UI, AC11-UI) cannot be exercised at all.
 *   The six monitoring fields are NOT on the Opportunity record page either
 *   (no FlexiPage section) — inline edit of them is unreachable, so AC6's UI
 *   half is proven at the guard level (CLI save refused), not by typing.
 *   AC1/AC11/AC12 are covered by the Apex classes (run by the Tester).
 *
 * Locators VERIFIED via probe on 2026-10-31 (this org):
 *   - List view: /lightning/o/Opportunity/list?filterName=Follow_up_Monitoring;
 *     header row ariaSnapshot carries "Select N item(s)"; data rows carry
 *     value BEFORE label ("1 Locked Overdue Follow-ups"), dates locale DD.MM.YYYY.
 *   - Stage inline edit: 'Edit Stage' button + combobox getByLabel('Stage',
 *     {exact:true}).nth(0) + option 'Closed Won' (house, verified SCRUM-445).
 *   - Field labels (meta XML): Follow-up required / Next Followup Date /
 *     Overdue Follow-ups / Last Customer Interaction / Follow-up Status /
 *     Needs manager attention.
 */

const TAG = 'TEST-SCRUM459-E2E-';
const LIST_URL = '/lightning/o/Opportunity/list?filterName=Follow_up_Monitoring';

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
function createOpp(name: string, amount: number): string {
  const out = shell(
    `sf data create record -s Opportunity -o Test-Org --json -v "Name='${name}' AccountId=001WU0000242xNGYAY StageName=Prospecting CloseDate=2027-03-31 Amount=${amount}"`,
  );
  const j = JSON.parse(out.slice(out.indexOf('{'), out.lastIndexOf('}') + 1));
  const id = j?.result?.id;
  if (!id) throw new Error(`Opportunity-Create failed: ${out.slice(0, 300)}`);
  return String(id);
}
function createObligation(oppId: string, dueISO: string | null, completedISO: string | null, action: string): string {
  const due = dueISO ? ` Due_Date__c=${dueISO}` : '';
  const done = completedISO ? ` Status__c=Completed Completed_Date__c=${completedISO}` : ' Status__c=Outstanding';
  const out = shell(
    `sf data create record -s Followup_Obligation__c -o Test-Org --json -v "Opportunity__c=${oppId}${due}${done} Next_Action__c='${action}'"`,
  );
  const j = JSON.parse(out.slice(out.indexOf('{'), out.lastIndexOf('}') + 1));
  const id = j?.result?.id;
  if (!id) throw new Error(`Obligation-Create failed: ${out.slice(0, 300)}`);
  return String(id);
}
const fmt = (d: Date) => `${String(d.getDate()).padStart(2, '0')}.${String(d.getMonth() + 1).padStart(2, '0')}.${d.getFullYear()}`;
const iso = (offset: number) => {
  const d = new Date(Date.UTC(2026, 9, 31)); // org "today" pinned by test start
  const t = new Date();
  t.setDate(t.getDate() + offset);
  return `${t.getFullYear()}-${String(t.getMonth() + 1).padStart(2, '0')}-${String(t.getDate()).padStart(2, '0')}`;
};
const rel = (offset: number) => {
  const t = new Date();
  t.setDate(t.getDate() + offset);
  return fmt(t);
};

const oppIds: string[] = [];
const oblIds: string[] = [];
let oppAC2 = '', oppAC3soon = '', oppAC3today = '', oppAC3later = '', oppAC4 = '', oppAC5 = '';
let oppAC7 = '', oppAC8 = '', oppAC9high = '', oppAC9low = '', oppAC9exact = '';

test.beforeAll(() => {
  const mk = (label: string, amount: number) => {
    const id = createOpp(`${TAG}${label}`, amount);
    oppIds.push(id);
    return id;
  };
  oppAC2 = mk('AC2', 1000);
  for (const o of [-3, 2, 5]) oblIds.push(createObligation(oppAC2, iso(o), null, 'next action'));
  oppAC3soon = mk('AC3-soon', 1000); oblIds.push(createObligation(oppAC3soon, iso(2), null, 'a'));
  oppAC3today = mk('AC3-today', 1000); oblIds.push(createObligation(oppAC3today, iso(0), null, 'a'));
  oppAC3later = mk('AC3-later', 1000); oblIds.push(createObligation(oppAC3later, iso(3), null, 'a'));
  oppAC4 = mk('AC4', 1000);
  oblIds.push(createObligation(oppAC4, iso(-26), iso(-26), 'a'), createObligation(oppAC4, iso(-13), iso(-13), 'b'));
  oblIds.push(createObligation(oppAC4, iso(-1), null, 'still outstanding, keeps the row in the overdue list'));
  oppAC5 = mk('AC5', 1000); oblIds.push(createObligation(oppAC5, iso(-1), null, 'a'));
  oppAC7 = mk('AC7', 1000);
  for (const o of [-5, -2, 4, 9]) oblIds.push(createObligation(oppAC7, iso(o), null, 'a'));
  oppAC8 = mk('AC8', 1000); oblIds.push(createObligation(oppAC8, iso(-1), null, 'a'), createObligation(oppAC8, iso(6), null, 'b'));
  oppAC9high = mk('AC9-high', 75000); oblIds.push(createObligation(oppAC9high, iso(-1), null, 'a'));
  oppAC9low = mk('AC9-low', 40000); oblIds.push(createObligation(oppAC9low, iso(-1), null, 'a'), createObligation(oppAC9low, iso(-2), null, 'b'));
  oppAC9exact = mk('AC9-exact', 50000); oblIds.push(createObligation(oppAC9exact, iso(-1), null, 'a'));
});

test.afterAll(() => {
  for (const id of oblIds) {
    try { shell(`sf data delete record -s Followup_Obligation__c -o Test-Org -i ${id} --json`); } catch {}
  }
  for (const id of oppIds) {
    try { shell(`sf data delete record -s Opportunity -o Test-Org -i ${id} --json`); } catch {}
  }
});

const openOverdueCount = () => {
  const rows = soql(`SELECT Opportunity__c FROM Followup_Obligation__c WHERE Status__c='Outstanding' AND Due_Date__c < ${iso(0)}`);
  const opps = new Set(rows.map((r: any) => r.Opportunity__c));
  const open = [...opps].filter((id) => soql(`SELECT Id FROM Opportunity WHERE Id='${id}' AND IsClosed=false`).length === 1);
  return open.length;
};

async function listRows(page: any) {
  await page.goto(LIST_URL, { waitUntil: 'domcontentloaded', timeout: 60000 });
  await page.locator('div.slds-global-header, one-appnav').first().waitFor({ state: 'visible', timeout: 60000 });
  const rows = page.getByRole('row');
  let rowCount = 0;
  const deadline = Date.now() + 60000;
  while (rowCount <= 1 && Date.now() < deadline) {
    await page.waitForTimeout(5000);
    rowCount = await rows.count();
  }
  expect(rowCount).toBeGreaterThan(1);
  const header = String(await rows.nth(0).ariaSnapshot()).replace(/\s+/g, ' ');
  const stated = Number(header.match(/Select (\d+) item/)?.[1] ?? '0');
  const data: Record<string, string> = {};
  for (let i = 1; i <= rowCount - 1; i++) {
    const snap = String(await rows.nth(i).ariaSnapshot()).replace(/\s+/g, ' ');
    const name = snap.match(new RegExp(`${TAG}[A-Za-z0-9-]+`))?.[0];
    if (name) data[name] = snap;
  }
  return { stated, data, header };
}

test.describe('[SCRUM-459] AC2 — overdue count counts only fully passed dates', () => {
  test('due today-3, today+2, today+5 -> count 1 in the list and at the org', async ({ page }) => {
    const { data } = await listRows(page);
    const row = data[`${TAG}AC2`];
    expect(row).toBeTruthy();
    expect(row).toContain('1 Locked Overdue Follow-ups');
    expect(row).toContain('Overdue Locked Follow-up Status');
    const rec = soql(`SELECT Overdue_Followup_Count__c, Next_Followup_Date__c, Followup_Status__c FROM Opportunity WHERE Id='${oppAC2}'`);
    expect(Number(rec[0].Overdue_Followup_Count__c)).toBe(1);
    expect(String(rec[0].Followup_Status__c)).toBe('Overdue');
    expect(String(rec[0].Next_Followup_Date__c)).toBe(`iso(-3)`);
  });
});

test.describe('[SCRUM-459] AC3 — status precedence Overdue > Due Soon > Up to Date', () => {
  test('due today+2 and today -> Due Soon; due today+3 -> Up to Date', async ({ page }) => {
    const { data } = await listRows(page);
    // Due Soon records have count 0 -> NOT in the overdue list; assert at the org.
    for (const [id, want] of [[oppAC3soon, 'Due Soon'], [oppAC3today, 'Due Soon'], [oppAC3later, 'Up to Date']]) {
      const rec = soql(`SELECT Followup_Status__c, Overdue_Followup_Count__c FROM Opportunity WHERE Id='${id}'`);
      expect(String(rec[0].Followup_Status__c)).toBe(want);
      expect(Number(rec[0].Overdue_Followup_Count__c)).toBe(0);
    }
    // Overdue beats everything: AC2 row in the list already shows Overdue with count 1.
    expect(data[`${TAG}AC2`]).toContain('Overdue Locked Follow-up Status');
  });
});

test.describe('[SCRUM-459] AC4 — last completed interaction is the latest completion', () => {
  test('completed today-26 and today-13 -> Last Customer Interaction = today-13', async ({ page }) => {
    const rec = soql(`SELECT Last_Customer_Interaction__c FROM Opportunity WHERE Id='${oppAC4}'`);
    expect(String(rec[0].Last_Customer_Interaction__c)).toBe(`iso(-13)`);
    // The list column shows the same date (locale DD.MM.YYYY).
    const { data } = await listRows(page);
    const row = data[`${TAG}AC4`];
    expect(row).toBeTruthy();
    expect(row).toContain(`${rel(-13)} Locked Last Customer Interaction`);
  });
});

test.describe('[SCRUM-459] AC5 — completing an obligation recomputes without touching the Opportunity', () => {
  test('complete the overdue obligation (only the obligation is saved)', async ({ page }) => {
    const before = soql(`SELECT Overdue_Followup_Count__c, Followup_Status__c FROM Opportunity WHERE Id='${oppAC5}'`);
    expect(Number(before[0].Overdue_Followup_Count__c)).toBe(1);
    const ob = soql(`SELECT Id FROM Followup_Obligation__c WHERE Opportunity__c='${oppAC5}'`)[0];
    shell(`sf data update record -s Followup_Obligation__c -o Test-Org -i ${ob.Id} --json -v "Status__c=Completed Completed_Date__c=${iso(0)}"`);
    const after = soql(`SELECT Overdue_Followup_Count__c, Followup_Status__c, Last_Customer_Interaction__c, Followup_Required__c FROM Opportunity WHERE Id='${oppAC5}'`);
    expect(Number(after[0].Overdue_Followup_Count__c)).toBe(0);
    expect(String(after[0].Followup_Status__c)).toBe('Up to Date');
    expect(String(after[0].Last_Customer_Interaction__c)).toBe(`iso(0)`);
    expect(after[0].Followup_Required__c).toBe(false);
    // The Opportunity record page cannot show it (Gap B) — the list column would
    // show it once the record is overdue again; org read-back is binding here.
  });
});

test.describe('[SCRUM-459] AC6 — typing a monitoring value is refused', () => {
  test('proposing a wrong overdue count is refused, stored value unchanged', async () => {
    const before = soql(`SELECT Overdue_Followup_Count__c FROM Opportunity WHERE Id='${oppAC9high}'`);
    const stored = Number(before[0].Overdue_Followup_Count__c);
    let refusal = '';
    try {
      refusal = shell(`sf data update record -s Opportunity -o Test-Org -i ${oppAC9high} --json -v "Overdue_Followup_Count__c=${stored + 7}"`);
    } catch (e: any) {
      refusal = String((e as any).stdout || '') + ' ' + String((e as any).message || '');
    }
    expect(refusal).toContain('Overdue_Followup_Count__c');
    const after = soql(`SELECT Overdue_Followup_Count__c FROM Opportunity WHERE Id='${oppAC9high}'`);
    expect(Number(after[0].Overdue_Followup_Count__c)).toBe(stored);
  });
});

test.describe('[SCRUM-459] AC7 — four outstanding, two overdue', () => {
  test('count 2, status Overdue, next = earliest open due date', async ({ page }) => {
    const { data } = await listRows(page);
    const row = data[`${TAG}AC7`];
    expect(row).toBeTruthy();
    expect(row).toContain('2 Locked Overdue Follow-ups');
    expect(row).toContain('Overdue Locked Follow-up Status');
    const rec = soql(`SELECT Overdue_Followup_Count__c, Next_Followup_Date__c FROM Opportunity WHERE Id='${oppAC7}'`);
    expect(Number(rec[0].Overdue_Followup_Count__c)).toBe(2);
    expect(String(rec[0].Next_Followup_Date__c)).toBe(`iso(-5)`);
  });
});

test.describe('[SCRUM-459] AC8 — Closed Won clears the monitoring values', () => {
  test('set Stage Closed Won in the UI, values cleared, later completion keeps them', async ({ page }) => {
    await page.goto(`/lightning/r/Opportunity/${oppAC8}/view`, { waitUntil: 'domcontentloaded', timeout: 60000 });
    await page.locator('div.slds-global-header, one-appnav').first().waitFor({ state: 'visible', timeout: 60000 });
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
    const save = page.getByRole('button', { name: 'Save', exact: true });
    await expect(save).toBeVisible({ timeout: 10000 });
    await save.click();
    await page.waitForTimeout(4000);

    const rec = soql(`SELECT Id, IsClosed, Followup_Required__c, Next_Followup_Date__c, Overdue_Followup_Count__c, Last_Customer_Interaction__c, Followup_Status__c, Needs_Manager_Attention__c FROM Opportunity WHERE Id='${oppAC8}'`);
    expect(rec[0].IsClosed).toBe(true);
    expect(rec[0].Followup_Required__c).toBe(false);
    expect(rec[0].Next_Followup_Date__c).toBeNull();
    expect(Number(rec[0].Overdue_Followup_Count__c)).toBe(0);
    expect(rec[0].Last_Customer_Interaction__c).toBeNull();
    expect(rec[0].Followup_Status__c).toBeNull();
    expect(rec[0].Needs_Manager_Attention__c).toBe(false);

    // A later obligation completion must not change the cleared values.
    const ob = soql(`SELECT Id FROM Followup_Obligation__c WHERE Opportunity__c='${oppAC8}' AND Status__c='Outstanding'`)[0];
    shell(`sf data update record -s Followup_Obligation__c -o Test-Org -i ${ob.Id} --json -v "Status__c=Completed Completed_Date__c=${iso(0)}"`);
    const after = soql(`SELECT Followup_Status__c, Last_Customer_Interaction__c, Overdue_Followup_Count__c FROM Opportunity WHERE Id='${oppAC8}'`);
    expect(after[0].Followup_Status__c).toBeNull();
    expect(after[0].Last_Customer_Interaction__c).toBeNull();
    expect(Number(after[0].Overdue_Followup_Count__c)).toBe(0);
  });
});

test.describe('[SCRUM-459] AC9 — attention flag strictly above 50.000 EUR', () => {
  test('75000 flagged, 40000 not, exactly 50000 not', async ({ page }) => {
    const { data } = await listRows(page);
    expect(data[`${TAG}AC9-high`]).toContain('True Needs manager attention Locked');
    expect(data[`${TAG}AC9-low`]).toContain('False Needs manager attention Locked');
    expect(data[`${TAG}AC9-exact`]).toContain('False Needs manager attention Locked');
    for (const [id, want] of [[oppAC9high, true], [oppAC9low, false], [oppAC9exact, false]] as [string, boolean][]) {
      const rec = soql(`SELECT Needs_Manager_Attention__c FROM Opportunity WHERE Id='${id}'`);
      expect(rec[0].Needs_Manager_Attention__c).toBe(want);
    }
  });
});

test.describe('[SCRUM-459] AC10 — the list shows exactly the open opportunities with overdue >= 1', () => {
  test('list count equals the org count', async ({ page }) => {
    const { stated, data } = await listRows(page);
    const orgCount = openOverdueCount();
    expect(orgCount).toBeGreaterThan(0);
    expect(stated).toBe(orgCount);
    expect(Object.keys(data).length).toBe(orgCount);
  });
});
