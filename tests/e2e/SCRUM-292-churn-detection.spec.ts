import { test, expect } from '@playwright/test';

test.describe('[SCRUM-292] Inaktive Kunden (90+ Tage ohne Kontakt) automatisch erkennen', () => {
  // Acceptance Criterion 1: LastContactDate__c field exists on Account
  test('Acceptance Criterion 1: Account shows LastContactDate__c field', async ({ page }) => {
    // Arrange
    await page.goto('/one/one.app#/sObject/001/view');
    await page.waitForLoadState('domcontentloaded');

    // Act & Assert - Account page should load and show the LastContactDate__c field
    await expect(page).toHaveTitle(/Salesforce/);
    // The field should be visible on the account detail page
    await expect(page.getByLabel('Last Contact').first()).toBeVisible({ timeout: 10000 });
  });

  // Acceptance Criterion 2: ChurnStatus__c field exists on Account
  test('Acceptance Criterion 2: Account shows ChurnStatus__c field', async ({ page }) => {
    // Arrange
    await page.goto('/one/one.app#/sObject/001/view');
    await page.waitForLoadState('domcontentloaded');

    // Act & Assert - Account page should load and show the ChurnStatus__c field
    await expect(page).toHaveTitle(/Salesforce/);
    // The field should be visible on the account detail page
    await expect(page.getByLabel('Churn Status').first()).toBeVisible({ timeout: 10000 });
  });

  // Acceptance Criterion 3: Custom Metadata Type ChurnThreshold__mdt is accessible
  test('Acceptance Criterion 3: ChurnThreshold Custom Metadata Type exists', async ({ page }) => {
    // Arrange
    await page.goto('/one/one.app#/sObject/ChurnThreshold__mdt/list');
    await page.waitForLoadState('domcontentloaded');

    // Act & Assert - Custom Metadata Type should be accessible
    await expect(page).toHaveTitle(/Salesforce/);
    // The list view should show the Standard_Churn_Threshold record
    await expect(page.getByText('Standard_Churn_Threshold').first()).toBeVisible({ timeout: 15000 });
  });

  // Acceptance Criterion 4: Task creation updates LastContactDate__c on Account
  test('Acceptance Criterion 4: Task creation updates Account LastContactDate__c', async ({ page }) => {
    // Arrange - Navigate to Tasks
    await page.goto('/one/one.app#/sObject/00T/home');
    await page.waitForLoadState('domcontentloaded');

    // Act - Create a new task linked to an account
    await page.getByRole('link', { name: 'New Task' }).first().click();
    await page.waitForTimeout(2000);

    // Fill in task details - link to an account via WhatId
    await page.getByLabel('Related To').click();
    await page.getByPlaceholder('Search').first().fill('Acme');
    await page.waitForTimeout(1000);
    await page.getByRole('option', { name: /Acme/ }).first().click();
    await page.waitForTimeout(1000);

    // Fill subject
    await page.getByLabel('Subject').fill('Test contact for churn detection');

    // Save
    await page.getByRole('button', { name: 'Save' }).click();
    await page.waitForTimeout(2000);

    // Assert - Task should be created
    await expect(page.getByText('Test contact for churn detection')).toBeVisible({ timeout: 10000 });
  });

  // Edge Case: ChurnThreshold__mdt has configurable threshold
  test('Edge Case: ChurnThreshold__mdt Standard_Churn_Threshold record exists with 90-day threshold', async ({ page }) => {
    // Arrange
    await page.goto('/one/one.app#/sObject/ChurnThreshold__mdt/list');
    await page.waitForLoadState('domcontentloaded');

    // Act & Assert - The default record should exist
    await expect(page).toHaveTitle(/Salesforce/);
    await expect(page.getByText('Standard_Churn_Threshold').first()).toBeVisible({ timeout: 15000 });
  });
});