import { test, expect, type Page, type Frame } from '@playwright/test';
import { execSync } from 'node:child_process';

/**
 * [SCRUM-428] AC12 — Teamleitungs-Sicht: Report "Unverteite_Faelle"
 * (Id 00OWU00000QXsyj2AD, deploy dd4886e).
 *
 * AC12 verbatim:
 *   "Given die Teamleitung, When sie die Übersicht öffnet, Then sie sieht die
 *    Anzahl unverteilter (unassigned) Fälle und das Alter des ältesten
 *    unverteilt wartenden Falls."
 *
 * The team-leadership opens the report "Unverteite_Faelle" (scope organisation,
 * filter: OPEN + Owner in 4 support queues). It lists every open queue-owned
 * case, sorted by Date/Time Opened oldest-first. Salesforce then shows:
 *   - "Total Records" = the count of unassigned (queue-owned, open) cases  → AC "Anzahl"
 *   - the first row = the oldest open queue case (oldest-first) + its Age column → AC "Alter des ältesten"
 *
 * This is a REAL session read (the deliverable is run, not queried): the report
 * count is asserted against a live SOQL ground-truth query of open queue-owned
 * cases, and the first rendered row must be the SOQL-oldest case. No number is
 * hardcoded — the SOQL is run at test time, so the test stays valid as cases
 * are assigned/closed.
 *
 * DOM facts (2026-09-25 live probed, Test-Org): the report renders a real
 * <table> in the lightningReportApp cross-doc frame. Column order of each row:
 *   [rowNum, CaseNumber, Subject, CaseOwner, Date/Time Opened, Age]
 * so the Case Number is <td> index 1 (index 0 is the # column).
 */

const REPORT_ID = '00OWU00000QXsyj2AD';
const QUEUES = ['Technischer Support', 'Vertragsservice', 'Billing', 'First Level Support'];

/* ------------------------- sf-CLI helpers (sf-JSON, house) ------------------ */

function shellJson(out: string): any {
  const clean = out.replace(/\uFEFF/g, '').replace(/\u001b\[[0-9;]*[A-Za-z]/g, '');
  const start = clean.indexOf('{');
  const end = clean.lastIndexOf('}');
  if (start < 0 || end < start) throw new Error(`Kein JSON in sf-Antwort: ${out.slice(0, 200)}`);
  return JSON.parse(clean.slice(start, end + 1));
}

function rawOut(command: string): string {
  return execSync(command, {
    encoding: 'utf-8',
    timeout: 90000,
    stdio: ['pipe', 'pipe', 'pipe'],
    maxBuffer: 16 * 1024 * 1024,
    env: { ...process.env, FORCE_COLOR: '0', NO_COLOR: '1' },
  });
}

/** SOQL read-back → records[] (empty array if none). */
function soql(q: string): any[] {
  const doc = shellJson(rawOut(`sf data query -q "${q}" --target-org Test-Org --json`));
  return (doc.result && doc.result.records) || [];
}

/** Live ground truth: open queue-owned cases, oldest (CreatedDate) first. */
function unassignedGroundTruth(): { count: number; oldestCaseNumber: string } {
  const inList = QUEUES.map((q) => `'${q.replace(/'/g, "''")}'`).join(',');
  const recs = soql(
    `SELECT CaseNumber FROM Case WHERE IsClosed=false AND OwnerId IN ` +
      `(SELECT Id FROM Group WHERE Name IN (${inList})) ORDER BY CreatedDate ASC LIMIT 200`
  );
  return {
    count: recs.length,
    oldestCaseNumber: recs.length > 0 ? String(recs[0].CaseNumber) : '',
  };
}

/* --------------------------- Report frame helpers -------------------------- */

async function openReportFrame(page: Page): Promise<Frame> {
  await page.goto(`/lightning/r/Report/${REPORT_ID}/view`, {
    waitUntil: 'domcontentloaded',
    timeout: 60000,
  });
  let frame: Frame | undefined;
  const deadline = Date.now() + 60000;
  for (;;) {
    frame = page.frames().find((fr) => fr.url().includes('lightningReportApp'));
    if (frame) break;
    if (Date.now() > deadline) throw new Error('Report-Frame (lightningReportApp) nicht aufgetaucht');
    await page.waitForTimeout(500);
  }
  await frame.waitForLoadState('domcontentloaded').catch(() => {});
  // Wait for the results grid to render (not a fixed sleep).
  await frame.locator('table tbody tr').first().waitFor({ timeout: 45000 });
  return frame!;
}

/** Read every rendered row as trimmed td cells. */
async function reportDataRows(frame: Frame): Promise<string[][]> {
  const rows = frame.locator('table tbody tr');
  const n = await rows.count();
  const out: string[][] = [];
  for (let i = 0; i < n; i++) {
    const cells = await rows.nth(i).locator('td').allTextContents().catch(() => []);
    const t = cells.map((c) => c.trim());
    if (t.length > 0 && t.join('').length > 0) out.push(t);
  }
  return out;
}

/** The "Total Records" number Salesforce shows in the report frame. */
async function reportTotalRecords(frame: Frame): Promise<number> {
  const text: string = await frame.locator('body').innerText().catch(() => '');
  const m = text.match(/Total Records\s*(\d+)/);
  if (!m) throw new Error(`"Total Records N" nicht im Report-Frame gefunden:\n${text.slice(0, 600)}`);
  return parseInt(m[1], 10);
}

/* ============================ The acceptance test ========================== */

test.describe('[SCRUM-428] AC12 — Teamleitungs-Sicht Report', () => {
  test('AC12: Report zählt offene Queue-Cases und zeigt den ältesten zuerst', async ({ page }) => {
    const truth = unassignedGroundTruth();
    const truthCase = truth.count > 0 ? truth.oldestCaseNumber : 'n/a';
    console.log(`[AC12] SOQL ground truth: ${truth.count} offene Queue-Cases, ältester=${truthCase}`);

    const frame = await openReportFrame(page);

    const uiTotal = await reportTotalRecords(frame);
    const rows = await reportDataRows(frame);
    // Actual row cell layout (verified live, 2026-09-25, 5 <td>s per row):
    //   [CaseNumber, Subject, CaseOwner, DateTimeOpened, Age]
    // The "#" row-number column is not a <td> in the data table rows.
    const firstRowCase = rows.length > 0 ? rows[0][0] : '';

    console.log(`[AC12] Report: Total Records=${uiTotal}, Rows=${rows.length}, erste Zeile Case=${firstRowCase}`);

    // AC "Anzahl unverteilter Fälle": the report's Total Records must equal
    // the live count of open queue-owned cases (the thing "unassigned" means here).
    expect(
      uiTotal,
      `Report "Total Records"=${uiTotal} ≠ SOQL ${truth.count} offene Queue-Cases — die Teamleitung sieht die falsche Anzahl.`
    ).toBe(truth.count);

    // The rendered grid row count agrees with the reported total (no hidden rows).
    expect(
      rows.length,
      `Rendered rows=${rows.length} ≠ Total Records ${uiTotal}`
    ).toBe(truth.count);

    // AC "Alter des ältesten …": oldest-first ⇒ the first row is the SOQL-oldest
    // case, and its Age column is the age of that oldest case.
    if (truth.count > 0) {
      expect(
        firstRowCase,
        `Erste Report-Zeile Case=${firstRowCase} ≠ SOQL-ältester ${truth.oldestCaseNumber} — Sortierung oldest-first verletzt.`
      ).toBe(truth.oldestCaseNumber);
      // Age column (index 4, 5th cell) present and non-empty for the oldest row.
      expect(
        rows[0].length >= 5 && rows[0][4].length > 0,
        `Alter (Age) der ersten Zeile leer: ${JSON.stringify(rows[0])}`
      ).toBe(true);
    }

    test.info().annotations.push({
      type: 'observed',
      description: `AC12: Report Total Records=${uiTotal}, Rows=${rows.length}, ältester=${firstRowCase}; SOQL ${truth.count}/${truthCase}`,
    });
  });
});
