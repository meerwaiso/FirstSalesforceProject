import { test, expect, type Page, type Frame } from '@playwright/test';
import { execSync } from 'node:child_process';
import { openRecordDetails, openRecordPage } from './record-page';

/**
 * [SCRUM-416] Offene Chancen je Kunde auf einen Blick — E2E-Verifikation (UI +
 * live Org-Read-back). Jedes AK bekommt ein eigenes, deterministisches Fixture
 * (eigener Account, bekanntes Chancen-Setup), damit die Coverage-Zahlen pro
 * Konto vor/nach 1:1 per SOQL abgleichbar sind (PO-Vorgabe: konkrete Zahlen).
 *
 * Alle Chance-Änderungen laufen über die sf-CLI (create/update record) — der
 * Opportunity-Trigger + OpenOpportunityRollupHandler rechnen die Account-Felder
 * dabei live nach (Produktionsweg), kein manueller DML-Bypass. Referenz für die
 * UI-Values ist der SOQL-Read-back aus der Org, nicht eine hartgecodete Zahl.
 *
 * DOM-Fakten (2026-09-15 live geprobt, Test-Org):
 *   - Record-Page öffnet auf "Related"; die Felder stehen unter dem Details-Tab
 *     → house-Helper openRecordDetails() (bounded-retry Details-Klick).
 *   - Feld-Blocks: div.slds-form-element, Wert in .test-id__field-value.
 *   - "Offene Chancen" (Number) rendert als Ziffern; "Wert offener Chancen"
 *     (Currency) rendert in Org-Locale (de-Format, z.B. "3.500,00 €").
 *   - Report "Offene_Werte_nach_Kunde" (00OWU00000QOzTB2A1) rendert in einer
 *     Cross-Doc-Frame (lightningReportApp) als echtes <table> mit <th>/<td>;
 *     Standardsortierung absteigend nach "Wert offener Chancen" (org-weit,
 *     ~384 Zeilen, Paginierung).
 */

const REPORT_ID = '00OWU00000QOzTB2A1';
const COUNT_LABEL = 'Offene Chancen';
const VALUE_LABEL = 'Wert offener Chancen';
const ANNUAL_REVENUE_LABEL = 'Annual Revenue';

// Unique-per-run suffix: re-runs create fresh fixtures and never collide with
// TEST-SCRUM-416-* records left from an earlier round (leftovers are cleaned
// between rounds; this protects mid-round re-runs from double-counting).
const RUN = `-${new Date().toISOString().replace(/[-:TZ.]/g, '').slice(0, 12)}Z`;

// Win/Won stage values in this org (verified via SOQL GROUP BY earlier).
const STAGE_OPEN = 'Prospecting';
const STAGE_WON = 'Closed Won';
const STAGE_LOST = 'Closed Lost';

/* ------------------------- sf-CLI helpers (sf-JSON) ------------------------ */

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
  });
}

/** SOQL read-back → records[] (empty array if none). */
function soql(q: string): any[] {
  const doc = shellJson(rawOut(`sf data query -q "${q}" --target-org Test-Org --json`));
  return (doc.result && doc.result.records) || [];
}

function accountRollup(accountId: string): { count: number; value: number } {
  const recs = soql(
    `SELECT Open_Opportunity_Count__c, Open_Opportunity_Value__c FROM Account WHERE Id='${accountId}'`
  );
  if (recs.length !== 1) throw new Error(`Account ${accountId} liefert ${recs.length} Records, erwartet 1`);
  return {
    count: Number(recs[0].Open_Opportunity_Count__c ?? 0),
    value: Number(recs[0].Open_Opportunity_Value__c ?? 0),
  };
}

function createAccount(name: string): string {
  const doc = shellJson(rawOut(`sf data create record -s Account -v "Name='${name}'" --target-org Test-Org --json`));
  const id = String(doc.id ?? doc.result?.id ?? '');
  if (!id) throw new Error(`Account ${name}: keine Id zurück (` + JSON.stringify(doc).slice(0, 200) + ')');
  return id;
}

function createOpp(accountId: string, name: string, amount: number | null, stageName: string): string {
  const amt = amount == null ? '' : ` Amount=${amount}`;
  // CLOSED LOST requires a loss reason (validation rule LossReason_PflichtBeiClosedLost,
  // BEFORE-context — must be passed at create time).
  const lossReason = stageName.toLowerCase().includes('lost') ? " Loss_Reason__c='Sonstiges'" : '';
  const doc = shellJson(
    rawOut(
      `sf data create record -s Opportunity -v "Name='${name}' AccountId=${accountId}${amt} StageName='${stageName}'${lossReason} CloseDate=2026-12-31" --target-org Test-Org --json`
    )
  );
  const id = String(doc.id ?? doc.result?.id ?? '');
  if (!id) throw new Error(`Opp ${name} (${stageName}): keine Id zurück (` + JSON.stringify(doc).slice(0, 200) + ')');
  return id;
}

/** Change only the Stage (wins/losses). */
function setStage(oppId: string, stageName: string): void {
  rawOut(`sf data update record -s Opportunity -i ${oppId} -v "StageName='${stageName}'" --target-org Test-Org --json`);
}

/** Change only the Amount. */
function setAmount(oppId: string, amount: number): void {
  rawOut(`sf data update record -s Opportunity -i ${oppId} -v "Amount=${amount}" --target-org Test-Org --json`);
}

/** Reassign to another Account. */
function reassign(oppId: string, newAccountId: string): void {
  rawOut(`sf data update record -s Opportunity -i ${oppId} -v "AccountId=${newAccountId}" --target-org Test-Org --json`);
}

/* --------------------------- UI value parsing ----------------------------- */

/** Locale-tolerant parse of a rendered number/currency to a number.
 * Handles de- ("3.500,00 €") and en- ("3,500.00") forms both. */
function parseNum(s: string): number {
  let t = s.replace(/[€$¥£\s]/g, '');
  const lastDot = t.lastIndexOf('.');
  const lastComma = t.lastIndexOf(',');
  if (lastDot >= 0 && lastComma >= 0) {
    // both present: last one is the decimal separator, the other is thousands
    if (lastDot > lastComma) {
      t = t.replace(/,/g, ''); // comma = thousands
    } else {
      t = t.replace(/\./g, '').replace(',', '.'); // dot = thousands, comma = decimal
    }
  } else if (lastComma >= 0) {
    // currency in de-locale: comma is the DECIMAL separator ("600,00")
    t = t.replace(/,/g, '.');
  } else {
    // no comma: any dots are thousands separators (de-locale integers)
    t = t.replace(/\./g, '');
  }
  const n = parseFloat(t);
  if (!isFinite(n)) throw new Error(`Konnte "${s}" nicht als Zahl parsen`);
  return n;
}

function approx(a: number, b: number, eps = 0.01): boolean {
  return Math.abs(a - b) <= eps;
}

/* -------- Record-page field helpers (house pattern, open shadow roots) ----- */

async function fieldElement(page: Page, label: string) {
  const forms = page.locator('div.slds-form-element');
  const n = await forms.count();
  for (let i = 0; i < n; i++) {
    const t = await forms.nth(i).innerText().catch(() => '');
    if (t.includes(label)) return forms.nth(i);
  }
  throw new Error(`Kein slds-form-element mit Label "${label}" — Feld fehlt auf der Seite`);
}

async function fieldY(page: Page, label: string): Promise<number> {
  const el = await fieldElement(page, label);
  const bb = await el.boundingBox();
  if (!bb) throw new Error(`Kein boundingBox für "${label}"`);
  return bb.y;
}

/** Read the rendered value of a field label; parse to number. */
async function readFieldValueNum(page: Page, label: string): Promise<number> {
  const el = await fieldElement(page, label);
  await el.locator('.test-id__field-value').first().waitFor({ state: 'attached', timeout: 15000 });
  const raw = (await el.locator('.test-id__field-value').first().innerText()).trim();
  if (!raw) throw new Error(`Feld "${label}" rendert ohne Wert`);
  return parseNum(raw);
}

/* ----------------------- Report frame helpers ----------------------------- */

async function openReportFrame(page: Page): Promise<Frame> {
  await openRecordPage(page, `/lightning/r/Report/${REPORT_ID}/view`);
  let frame: Frame | undefined;
  const deadline = Date.now() + 60000;
  for (;;) {
    frame = page.frames().find((fr) => fr.url().includes('lightningReportApp'));
    if (frame) break;
    if (Date.now() > deadline) throw new Error('Report-Frame (lightningReportApp) nicht aufgetaucht');
    await page.waitForTimeout(500);
  }
  await frame.waitForLoadState('domcontentloaded').catch(() => {});
  await frame.locator('table td').first().waitFor({ timeout: 45000 });
  return frame!;
}

async function reportRows(frame: Frame) {
  const rows = frame.locator('table tbody tr');
  const n = await rows.count();
  const out: { name: string; cells: string[] }[] = [];
  for (let i = 0; i < n; i++) {
    const tds = rows.nth(i);
    const cells = await tds.locator('td').allTextContents().catch(() => []);
    if (cells.length >= 3 && cells[0].trim()) out.push({ name: cells[0].trim(), cells: cells.map((c) => c.trim()) });
  }
  return out;
}

/* ============================ The acceptance tests ========================= */

test.describe('[SCRUM-416] Offene Chancen je Kunde', () => {
  test('AK1: Kundenseite zeigt Anzahl=3 und Summe=600 (won/lost exkludiert)', async ({ page }) => {
    const name = `TEST-SCRUM-416-AK1${RUN}`;
    const acc = createAccount(name);
    createOpp(acc, `${name}-open-100`, 100, STAGE_OPEN);
    createOpp(acc, `${name}-open-200`, 200, STAGE_OPEN);
    createOpp(acc, `${name}-open-300`, 300, STAGE_OPEN);
    const won = createOpp(acc, `${name}-won-500`, 500, STAGE_WON);
    const lost1 = createOpp(acc, `${name}-lost-700`, 700, STAGE_LOST);
    const lost2 = createOpp(acc, `${name}-lost-800`, 800, STAGE_LOST);
    expect(won).toBeTruthy(); expect(lost1).toBeTruthy(); expect(lost2).toBeTruthy();

    // Org-Read-back vs UI — the two must agree and both exclude won/lost.
    const org = accountRollup(acc);
    await openRecordDetails(page, `/lightning/r/Account/${acc}/view`);
    const uiCount = await readFieldValueNum(page, COUNT_LABEL);
    const uiValue = await readFieldValueNum(page, VALUE_LABEL);

    expect(org.count, `Org Count ${org.count} ≠ 3 (won/lost müssen exkludiert sein), Org Value ${org.value} ≠ 600`).toBe(3);
    expect(approx(org.value, 600), `Org Value ${org.value} ≠ 600`).toBe(true);
    expect(uiCount, `UI Count ${uiCount} ≠ 3 (SOQL sagt ${org.count})`).toBe(3);
    expect(approx(uiValue, 600), `UI Value ${uiValue} ≠ 600 (SOQL sagt ${org.value})`).toBe(true);
    test.info().annotations.push({ type: 'observed', description: `AK1 ${name}: UI ${uiCount}/${uiValue}, SOQL ${org.count}/${org.value}` });
  });

  test('AK2: Gewinn einer offenen Chance nimmt sie aus Anzahl UND Summe', async ({ page }) => {
    const name = `TEST-SCRUM-416-AK2${RUN}`;
    const acc = createAccount(name);
    const o100 = createOpp(acc, `${name}-open-100`, 100, STAGE_OPEN);
    const o200 = createOpp(acc, `${name}-open-200`, 200, STAGE_OPEN);
    const o300 = createOpp(acc, `${name}-open-300`, 300, STAGE_OPEN);
    createOpp(acc, `${name}-won-500`, 500, STAGE_WON);

    const before = accountRollup(acc);
    expect(before.count).toBe(3); expect(approx(before.value, 600)).toBe(true);

    // one previously-open opp becomes won → drops out of Count AND Sum
    setStage(o300, STAGE_WON);
    const after = accountRollup(acc);
    expect(after.count, `AK2 Count nach Gewinn: ${after.count} ≠ 2`).toBe(2);
    expect(approx(after.value, 300), `AK2 Value nach Gewinn: ${after.value} ≠ 300 (100+200)`).toBe(true);

    await openRecordDetails(page, `/lightning/r/Account/${acc}/view`);
    const uiCount = await readFieldValueNum(page, COUNT_LABEL);
    const uiValue = await readFieldValueNum(page, VALUE_LABEL);
    expect(uiCount, `AK2 UI Count ${uiCount} ≠ 2`).toBe(2);
    expect(approx(uiValue, 300), `AK2 UI Value ${uiValue} ≠ 300`).toBe(true);
    test.info().annotations.push({ type: 'observed', description: `AK2 ${name}: vor ${before.count}/${before.value} → nach ${after.count}/${after.value} (SOQL); UI ${uiCount}/${uiValue}` });
  });

  test('AK3: Betragänderung verschiebt die Summe um (Y − X)', async ({ page }) => {
    const name = `TEST-SCRUM-416-AK3${RUN}`;
    const acc = createAccount(name);
    const o100 = createOpp(acc, `${name}-open-100`, 100, STAGE_OPEN);
    createOpp(acc, `${name}-open-200`, 200, STAGE_OPEN);

    const before = accountRollup(acc);
    expect(before.count).toBe(2); expect(approx(before.value, 300)).toBe(true);

    // 100 → 400 ⇒ +300
    setAmount(o100, 400);
    const after = accountRollup(acc);
    expect(after.count, 'AK3 Count bleibt 2').toBe(2);
    expect(approx(after.value, 600), `AK3 Value nach 100→400: ${after.value} ≠ 600`).toBe(true);
    expect(approx(after.value - before.value, 300), `AK3 Delta ${after.value - before.value} ≠ +300`).toBe(true);

    await openRecordDetails(page, `/lightning/r/Account/${acc}/view`);
    const uiCount = await readFieldValueNum(page, COUNT_LABEL);
    const uiValue = await readFieldValueNum(page, VALUE_LABEL);
    expect(uiCount, 'AK3 UI Count bleibt 2').toBe(2);
    expect(approx(uiValue, 600), `AK3 UI Value ${uiValue} ≠ 600`).toBe(true);
    test.info().annotations.push({ type: 'observed', description: `AK3 ${name}: vor ${before.count}/${before.value} → nach ${after.count}/${after.value} (Δ +300, SOQL); UI ${uiCount}/${uiValue}` });
  });

  test('AK4: Umhängen — Alter Kunde sinkt, Neuer steigt (beide korrekt)', async ({ page }) => {
    const nameA = `TEST-SCRUM-416-AK4-A${RUN}`;
    const nameB = `TEST-SCRUM-416-AK4-B${RUN}`;
    const accA = createAccount(nameA);
    const accB = createAccount(nameB);

    const keep = createOpp(accA, `${nameA}-open-100`, 100, STAGE_OPEN);
    const move = createOpp(accA, `${nameA}-open-200move`, 200, STAGE_OPEN);
    expect(keep).toBeTruthy(); expect(move).toBeTruthy();

    const beforeA = accountRollup(accA); // 2 / 300
    const beforeB = accountRollup(accB); // 0 / 0
    expect(beforeA.count).toBe(2); expect(approx(beforeA.value, 300)).toBe(true);
    expect(beforeB.count).toBe(0); expect(approx(beforeB.value, 0)).toBe(true);

    reassign(move, accB); // 200 leaves A, joins B

    const afterA = accountRollup(accA); // 1 / 100
    const afterB = accountRollup(accB); // 1 / 200
    expect(afterA.count, `AK4 A Count ${afterA.count} ≠ 1 (SOQL)`).toBe(1);
    expect(approx(afterA.value, 100), `AK4 A Value ${afterA.value} ≠ 100 (SOQL)`).toBe(true);
    expect(afterB.count, `AK4 B Count ${afterB.count} ≠ 1 (SOQL)`).toBe(1);
    expect(approx(afterB.value, 200), `AK4 B Value ${afterB.value} ≠ 200 (SOQL)`).toBe(true);
    // PO-Vorgabe: ALTE Seite sinkt UND NEUE steigt — beide Konten verifiziert
    expect(afterA.value < beforeA.value, 'AK4: Alter Kunde muss sinken').toBe(true);
    expect(afterB.value > beforeB.value, 'AK4: Neuer Kunde muss steigen').toBe(true);

    // BOTH in the UI (PO: ein Read-back reicht nicht)
    await openRecordDetails(page, `/lightning/r/Account/${accA}/view`);
    const uiA = await readFieldValueNum(page, COUNT_LABEL);
    const uiAv = await readFieldValueNum(page, VALUE_LABEL);
    expect(uiA, `AK4 UI A Count ${uiA} ≠ 1`).toBe(1);
    expect(approx(uiAv, 100), `AK4 UI A Value ${uiAv} ≠ 100`).toBe(true);
    await openRecordDetails(page, `/lightning/r/Account/${accB}/view`);
    const uiB = await readFieldValueNum(page, COUNT_LABEL);
    const uiBv = await readFieldValueNum(page, VALUE_LABEL);
    expect(uiB, `AK4 UI B Count ${uiB} ≠ 1`).toBe(1);
    expect(approx(uiBv, 200), `AK4 UI B Value ${uiBv} ≠ 200`).toBe(true);

    test.info().annotations.push({ type: 'observed', description: `AK4 A: ${beforeA.count}/${beforeA.value}→${afterA.count}/${afterA.value} (SOQL), UI ${uiA}/${uiAv}; B: ${beforeB.count}/${beforeB.value}→${afterB.count}/${afterB.value} (SOQL), UI ${uiB}/${uiBv}` });
  });

  test('AK5: Report sortiert Kunden absteigend nach offenem Wert (Hoch zuerst)', async ({ page }) => {
    // three fixture accounts with the clearly-top values of the org
    const hi = `TEST-SCRUM-416-AK5-HI${RUN}`;
    const mid = `TEST-SCRUM-416-AK5-MID${RUN}`;
    const low = `TEST-SCRUM-416-AK5-LOW${RUN}`;
    createOpp(createAccount(hi), `${hi}-open`, 99999, STAGE_OPEN);
    createOpp(createAccount(mid), `${mid}-open`, 88888, STAGE_OPEN);
    createOpp(createAccount(low), `${low}-open`, 77777, STAGE_OPEN);

    const frame = await openReportFrame(page);
    const rows = await reportRows(frame);
    const idx = (nm: string) => rows.findIndex((r) => r.name === nm);
    const iHi = idx(hi), iMid = idx(mid), iLow = idx(low);

    // all three must be present in the visible first page
    expect(iHi, `AK5 "${hi}" fehlt in Report-Page 1`).toBeGreaterThanOrEqual(0);
    expect(iMid, `AK5 "${mid}" fehlt in Report-Page 1`).toBeGreaterThanOrEqual(0);
    expect(iLow, `AK5 "${low}" fehlt in Report-Page 1`).toBeGreaterThanOrEqual(0);

    // strictly descending ⇒ 99999 first, then 88888, then 77777
    expect(iHi < iMid, `AK5: ${hi}(99999) muss vor ${mid}(88888) stehen, Indexe ${iHi},${iMid}`).toBe(true);
    expect(iMid < iLow, `AK5: ${mid}(88888) muss vor ${low}(77777) stehen, Indexe ${iMid},${iLow}`).toBe(true);

    // row cells carry the right count/value per fixture (locale-tolerant)
    const rowFor = (i: number) => rows[i];
    expect(approx(parseNum(rowFor(iHi).cells[2]), 99999), `AK5 ${hi} Value in UI-Row ${rowFor(iHi).cells}`).toBe(true);
    expect(approx(parseNum(rowFor(iMid).cells[2]), 88888), `AK5 ${mid} Value in UI-Row ${rowFor(iMid).cells}`).toBe(true);
    expect(approx(parseNum(rowFor(iLow).cells[2]), 77777), `AK5 ${low} Value in UI-Row ${rowFor(iLow).cells}`).toBe(true);

    // default sort indicator (informational in the annotation)
    const header = await frame.locator('table').first().locator('th').allTextContents().catch(() => []);
    const sortHdr = header.find((h) => /sort(ed|ierung|iert)|descending|absteigend|largest/i.test(h));
    test.info().annotations.push({ type: 'observed', description: `AK5 Reihenfolge UI: ${hi}#${iHi} < ${mid}#${iMid} < ${low}#${iLow}; Sort-Spalte-Header: ${sortHdr ? JSON.stringify(sortHdr).slice(0, 80) : 'n/a'}` });
  });

  test('AK6: Beide Zahlen oben auf der Seite (erste Section, klar sichtbar)', async ({ page }) => {
    const name = `TEST-SCRUM-416-AK6${RUN}`;
    const acc = createAccount(name);
    createOpp(acc, `${name}-open-100`, 100, STAGE_OPEN);

    await openRecordDetails(page, `/lightning/r/Account/${acc}/view`);
    const elCount = await fieldElement(page, COUNT_LABEL);
    const elValue = await fieldElement(page, VALUE_LABEL);
    await expect(elCount).toBeVisible();
    await expect(elValue).toBeVisible();

    // "deutlich sichtbar, nicht erst tief im Layout": beide in der ersten
    // Section, direkt nach Annual Revenue (Design-Intent). Assert: Annual
    // Revenue sitzt (wenn vorhanden) über beiden Feldern, und beide liegen in
    // einem oberen y-Bereich der Rendered-Page.
    const yCount = await fieldY(page, COUNT_LABEL);
    const yValue = await fieldY(page, VALUE_LABEL);
    const areVisible = await page.getByText(ANNUAL_REVENUE_LABEL, { exact: false }).first().isVisible().catch(() => false);
    if (areVisible) {
      const yARE = await fieldY(page, ANNUAL_REVENUE_LABEL);
      expect(yCount > yARE, `AK6: Offene Chancen (y=${yCount}) muss nach Annual Revenue (y=${yARE}) in der 1. Section stehen`).toBe(true);
      expect(yValue > yARE, `AK6: Wert offener Chancen (y=${yValue}) muss nach Annual Revenue (y=${yARE}) in der 1. Section stehen`).toBe(true);
    }
    // not deep in the layout: upper region of the rendered page
    expect(yCount < 1400, `AK6: Offene Chancen y=${yCount} zu tief (erwartet oberer Bereich)`).toBe(true);
    expect(yValue < 1400, `AK6: Wert offener Chancen y=${yValue} zu tief (erwartet oberer Bereich)`).toBe(true);
    const areY = areVisible ? Math.round(await fieldY(page, ANNUAL_REVENUE_LABEL)) : 'n/a';
    test.info().annotations.push({ type: 'observed', description: `AK6 ${name}: Offene Chancen y=${Math.round(yCount)}, Wert offener Chancen y=${Math.round(yValue)}, Annual Revenue y=${areY} — beide sichtbar, erste Section` });
  });
});
