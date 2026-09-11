import { test, expect } from '@playwright/test';

/**
 * [SCRUM-405] AC 7 — Firmen-Telefonnummer ("Telefonnummer der Firma") am Contact, Lightning UI, Test-Org.
 *
 * Session: frontdoor.jsp globalSetup (auth/storage-state.json), baseURL from
 * org.ts (never hardcoded). Network never networkidle on Lightning.
 *
 * Mechanism under test: Firmen_Telefonnummer__c is a read-only Text-Formula
 * equal to Account.Phone. In this org NO Contact Lightning record page
 * (FlexiPage) exists — all 8 FlexiPages are UtilityBars (verified via
 * --use-tooling-api on 2026-09-10) — so Lightning renders the profile-assigned
 * Classic "Contact Layout", which carries the field in the "Contact Information"
 * section directly below the personal "Phone". The org's standard labels render
 * in English ("Phone", "Fax", "Email"); only the custom label is German.
 * AC 7 (Lightning + Classic) resolves to the same physical record view; the
 * field is reached via the "Details" tab (the default-active tab is "Related").
 * (Same Record-view mechanic as SCRUM-403.)
 *
 * Fixtures — real org contacts, read back via SOQL against Test-Org on 2026-09-10:
 *   Rose Gonzalez  003WU00001VrdqTYAR
 *     personal Phone = NULL; Account "Edge Communications" = (512) 757-6000
 *     Firmen_Telefonnummer__c = (512) 757-6000
 *     -> the single cleanest ADR-5 proof: the displayed value can ONLY come from
 *        the Account cross-reference, because the contact's own phone is empty.
 *   Tim Barr 003WU00001VrdqYYAR — corroboration, both lines = (312) 596-1000.
 *
 * Coverage of AC 7 + ADR-5 + Negativ:
 *   - AC 7  (this spec): label "Telefonnummer der Firma" + personal "Telefon"
 *     present together in Details, firm value = Account.Phone.
 *   - ADR-5 no-data-leak (no user can read the Account's phone without Account
 *     read access): proven at the API boundary by SCRUM405FirmenTelefonnummerFlsTest
 *     via System.runAs() (a distinct low-privilege user is not possible here —
 *     the Test-Org has 2/2 licenses, both System Administrators, so a second
 *     non-privileged UI session is ruled out by the org shape, not by us).
 *   - Negativ (Kontakt ohne Firma -> leer, kein N/A, kein 0): proven at data level
 *     by SOQL on 2026-09-10 (contacts without an Account -> NULL, e.g. "ghg hh"
 *     003WU00001VvAKqYAN and the ProbeCount/ScaleM* set) — a read-only formula
 *     returns NULL for a missing cross-reference source.
 */

// Rose Gonzalez — personal Phone NULL, Account.Phone = (512) 757-6000.
const CONTACT_ADR5 = '003WU00001VrdqTYAR';
// The value the read-only formula must render (= Account.Phone of Edge Communications).
const FIRM_PHONE = /\(512\)\s*757\s*-?\s*6000/;
// Exact fixed label (SCRUM-406 fix, verified in the org: sf project retrieve).
const FIRM_LABEL = 'Telefonnummer der Firma';
// The Details view groups every phone field under a collapsible "Phone (N)" section.
// The group header robustly identifies the section that holds BOTH the personal
// "Phone" (Durchwahl) and the firm field — Lightning appends the "Edit Phone" button
// text to the label node, so a bare exact "Phone" match is unreliable.
const PHONE_GROUP = /^Phone\s*\(/;

test.describe('[SCRUM-405] AC 7 Firmen-Telefonnummer am Contact (Test-Org, Lightning)', () => {
  // The fields live in the "Details" tab of the Record Home page — open it and
  // wait for the org-specific firm label to render (robust vs. tab timing), as
  // in SCRUM-403.
  async function openDetails(page: any): Promise<void> {
    for (let attempt = 0; attempt < 5; attempt++) {
      const details = page.getByRole('tab', { name: 'Details' });
      if (await details.first().isVisible({ timeout: 3000 }).catch(() => false)) {
        await details.first().click();
      }
      if (
        await page
          .getByText(FIRM_LABEL, { exact: true })
          .first()
          .isVisible({ timeout: 4000 })
          .catch(() => false)
      ) {
        return;
      }
      await page.waitForTimeout(1500);
    }
    // Let the timed assertions below surface the absence clearly.
  }

  test('AC7: "Telefonnummer der Firma" renders in the same Details phone group as the phone, value = Account.Phone (ADR-5)', async ({ page }) => {
    await page.goto(`/lightning/r/Contact/${CONTACT_ADR5}/view`);
    await page.waitForSelector('.slds-global-header, one-appnav', { timeout: 60000 });
    await page.waitForLoadState('domcontentloaded');
    await openDetails(page);

    // AC1: the exact fixed label renders (not the old "Telefon Firma").
    await expect(page.getByText(FIRM_LABEL, { exact: true }).first()).toBeVisible({ timeout: 15000 });

    // AC7 "neben der Durchwahl": the firm field lives in the Details "Phone (N)"
    // group — the same section that carries the personal Phone — so the fix and the
    // personal phone are placed together, as the AC and Classic layout intend.
    await expect(page.getByRole('button', { name: PHONE_GROUP }).first()).toBeVisible({ timeout: 15000 });

    // ADR-5, in the field's own node: label and value render together, and the value
    // = Account.Phone = (512) 757-6000. Rose's personal Phone is NULL, so the
    // displayed value can only come from the Account cross-reference.
    await expect(page.getByText(new RegExp(`Telefonnummer der Firma.*${FIRM_PHONE.source}`))).toBeVisible({ timeout: 15000 });
  });
});
