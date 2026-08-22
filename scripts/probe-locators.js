#!/usr/bin/env node
/**
 * Locator probe for Salesforce Lightning.
 *
 * Lightning's accessible names, roles and DOM differ per org, locale, release
 * and component. Guessing a locator and finding out 30 seconds later in a test
 * report is the single biggest time sink in this suite. Ask the page instead.
 *
 * Usage:
 *   node scripts/probe-locators.js <path> [filter]
 *
 *   node scripts/probe-locators.js /lightning/page/home
 *   node scripts/probe-locators.js /lightning/page/home search
 *   node scripts/probe-locators.js "/lightning/r/Opportunity/006.../view" feld
 *
 * Prints every visible interactive element with a ready-to-paste Playwright
 * locator. Requires a valid auth/storage-state.json — run any test once (or
 * `npm run test:e2e:smoke`) to create it.
 */

const { chromium } = require('@playwright/test');
const { execSync } = require('child_process');
const fs = require('fs');

const AUTH = 'auth/storage-state.json';

function lightningUrl() {
  if (process.env.SALESFORCE_URL) {
    return process.env.SALESFORCE_URL.replace('.my.salesforce.com', '.lightning.force.com');
  }
  const raw = execSync('sf org display --json', {
    encoding: 'utf-8',
    stdio: ['pipe', 'pipe', 'pipe'],
  });
  const instanceUrl = JSON.parse(raw.replace(/\x1b\[[0-9;]*[a-zA-Z]/g, '')).result.instanceUrl;
  return instanceUrl.replace('.my.salesforce.com', '.lightning.force.com');
}

/** Suggest the most robust Playwright locator for an element. */
function suggest({ tag, role, name, placeholder, text }) {
  if (placeholder) return `getByPlaceholder(/${escape(placeholder)}/i)`;
  if (name && role) return `getByRole('${role}', { name: '${name}' })`;
  if (name) return `getByLabel('${name}')`;
  if (text) return `getByText(/${escape(text)}/i)`;
  return `locator('${tag}')  // no accessible name — consider a test id`;
}

const escape = (s) => s.slice(0, 40).replace(/[.*+?^${}()|[\]\\/]/g, '\\$&');

(async () => {
  const path = process.argv[2] || '/lightning/page/home';
  const filter = (process.argv[3] || '').toLowerCase();

  if (!fs.existsSync(AUTH)) {
    console.error(`No ${AUTH}. Run "npm run test:e2e:smoke" once to create it.`);
    process.exit(1);
  }

  const base = lightningUrl();
  const browser = await chromium.launch();
  const context = await browser.newContext({ storageState: AUTH });
  const page = await context.newPage();

  console.log(`\n  page: ${base}${path}`);
  await page.goto(base + path, { waitUntil: 'domcontentloaded', timeout: 60000 });
  await page.waitForSelector('.slds-global-header', { state: 'visible', timeout: 60000 });
  await page.waitForTimeout(4000); // let Lightning finish its async rendering

  const els = await page.locator('button, a[role], input, textarea, select, [role="tab"], [role="option"], [role="combobox"]').all();

  const rows = [];
  for (const el of els) {
    if (!(await el.isVisible().catch(() => false))) continue;
    const info = await el.evaluate((n) => ({
      tag: n.tagName.toLowerCase(),
      role: n.getAttribute('role') || '',
      aria: n.getAttribute('aria-label') || '',
      placeholder: n.getAttribute('placeholder') || '',
      title: n.getAttribute('title') || '',
      // assistive-text spans are how Lightning names most icon buttons
      assistive: n.querySelector('.slds-assistive-text')?.textContent?.trim() || '',
      text: (n.textContent || '').trim().slice(0, 40),
    }));

    const name = info.aria || info.assistive || info.title;
    const role = info.role || (info.tag === 'button' ? 'button' : '');
    const blob = `${name} ${info.placeholder} ${info.text}`.toLowerCase();
    if (filter && !blob.includes(filter)) continue;

    rows.push({ ...info, name, role });
  }

  if (!rows.length) {
    console.log(filter ? `\n  no visible element matching "${filter}"\n` : '\n  nothing found\n');
  } else {
    console.log(`  ${rows.length} visible interactive element(s)${filter ? ` matching "${filter}"` : ''}:\n`);
    for (const r of rows) {
      const label = r.name || r.placeholder || r.text || '(unnamed)';
      console.log(`  ${label}`);
      console.log(`      <${r.tag}> role=${r.role || '-'}  ->  page.${suggest(r)}`);
    }
    console.log('');
  }

  await browser.close();
})();
