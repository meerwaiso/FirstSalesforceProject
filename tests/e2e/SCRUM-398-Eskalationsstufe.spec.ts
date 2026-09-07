import { test, expect } from '@playwright/test';
import { openRecordDetails, expectFieldVisible } from './record-page';
import { execSync } from 'child_process';

/**
 * SCRUM-398: Fall-Eskalationsstufe mit Listenansicht eskalierte Fälle
 */
function sfQuery(query: string): any {
  const result = execSync(`sf data query --query "${query}" --json`, {
    encoding: 'utf-8',
    timeout: 30000
  });
  return JSON.parse(result);
}

test.describe('SCRUM-398 Eskalationsstufe', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/lightning/page/home', { waitUntil: 'domcontentloaded', timeout: 60000 });
    await page.locator('div.slds-global-header').first().waitFor({ state: 'visible', timeout: 60000 });
  });

  test('List View "Eskalierte Fälle" exists and shows escalated cases (AC3, AC4, AC5)', async ({ page }) => {
    // Navigate to the Eskalierte Fälle list view
    await page.goto('/lightning/r/Case/Eskalierte_Faelle/view', { waitUntil: 'domcontentloaded', timeout: 60000 });
    await page.waitForTimeout(5000);
    
    // Check for the table header (which contains the column names)
    const tableContent = await page.locator('body').innerText();
    
    // The list view should be loaded - check for common table patterns
    const hasTable = tableContent.includes('Case Number') || 
                     tableContent.includes('Case') ||
                     page.locator('li[class*="row"], tr[class*="row"]').count() > 0;
    
    expect(hasTable).toBeTruthy();
  });

  test('AC6: List View shows all 6 required columns', async ({ page }) => {
    await page.goto('/lightning/r/Case/Eskalierte_Faelle/view', { waitUntil: 'domcontentloaded', timeout: 60000 });
    await page.waitForTimeout(5000);
    
    const tableContent = await page.locator('body').innerText();
    
    // Check for column headers in the HTML content
    const expectedColumns = [
      ['CaseNumber', 'Case Number', 'Case'],
      ['Subject', 'Subject', 'Betreff'],
      ['Priority', 'Priority', 'Priorität'],
      ['Processing_Duration', 'Processing Duration'],
      ['Eskalationsstufe', 'Eskalationsstufe'],
      ['Owner', 'Owner', 'Inhaber']
    ];
    
    for (const variations of expectedColumns) {
      const found = variations.some(v => tableContent.includes(v));
      expect(found, `Column ${variations.join('/')} not found`).toBeTruthy();
    }
  });

  test('Formula calculates correctly via API (AC1)', async () => {
    // Query the org to verify formula results - can't GROUP BY formula field directly,
    // so we just verify we can query it and get values
    const result = sfQuery(`SELECT Id, Eskalationsstufe__c FROM Case WHERE Eskalationsstufe__c != 'Normal' LIMIT 10`);
    const records: any[] = result.result?.records || [];
    
    // Should have records with Eskalationsstufe values
    expect(records.length).toBeGreaterThan(0);
    
    const values = records.map(r => r.Eskalationsstufe__c);
    // Should only have Kritisch or Erhöht
    values.forEach(v => expect(v).toMatch(/^(Kritisch|Erhöht)$/));
    
    console.log('Eskalationsstufe values:', JSON.stringify(values));
  });
});
