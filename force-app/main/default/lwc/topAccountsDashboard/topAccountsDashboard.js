import { LightningElement, wire, track } from 'lwc';
import { getListUi } from 'lightning/uiListApi';

import ACCOUNT_OBJECT from '@salesforce/schema/Account';

/**
 * Top Accounts Dashboard Komponente
 * Zeigt die Top 3 Accounts nach AnnualRevenue (absteigend).
 * Bei Gleichstand wird alphabetisch nach Account-Name sortiert (A-Z).
 * Read-Only Ansicht — keine Bearbeitungsmoeglichkeiten.
 */
export default class TopAccountsDashboard extends LightningElement {
  @track accounts = [];
  @track error = null;
  @track isLoading = true;

  // Spalten-Konfiguration
  columns = [
    { label: 'Rank', fieldName: 'rank', type: 'text', fixedWidth: '50px' },
    { label: 'Account Name', fieldName: 'accountName', type: 'text' },
    {
      label: 'Annual Revenue',
      fieldName: 'annualRevenue',
      type: 'currency',
      typeAttributes: {
        currencyCode: 'EUR',
        locale: 'de-DE',
      },
    },
  ];

  // Lade Accounts via getListUi
  @wire(getListUi, {
    objectApiName: ACCOUNT_OBJECT,
    listViewApiName: 'AllAccounts',
    sortBy: 'AnnualRevenue',
    sortOrder: -1,
    pageSize: 50,
  })
  wiredAccounts({ data, error }) {
    this.isLoading = false;
    if (data) {
      this.processAccounts(data.records);
    } else if (error) {
      this.error = error;
      console.error('Error loading accounts:', error);
    }
  }

  /**
   * Verarbeitet die geladenen Accounts:
   * - Filtert Accounts mit AnnualRevenue > 0
   * - Sortiert nach AnnualRevenue DESC, dann Name ASC bei Gleichstand
   * - Begrenzt auf Top 3
   * - Fuegt Rank-Nummer hinzu
   */
  processAccounts(records) {
    const accountsWithRevenue = records
      .map((record) => {
        const fields = record.fields;
        const name = fields.Name?.value ?? '';
        const annualRevenue = fields.AnnualRevenue?.value ?? 0;
        return { name, annualRevenue };
      })
      .filter((a) => a.annualRevenue > 0);

    // Sortierung: AnnualRevenue DESC, bei Gleichstand Name ASC
    accountsWithRevenue.sort((a, b) => {
      if (b.annualRevenue !== a.annualRevenue) {
        return b.annualRevenue - a.annualRevenue;
      }
      // Gleichstand: alphabetisch nach Name (A-Z)
      return a.name.localeCompare(b.name);
    });

    // Begrenzen auf Top 3 und Rank hinzufuegen
    this.accounts = accountsWithRevenue.slice(0, 3).map((a, index) => ({
      rank: index + 1,
      accountName: a.name,
      annualRevenue: a.annualRevenue,
    }));
  }

  // Leerer Zustand: keine Accounts mit Umsatz
  get isEmpty() {
    return this.accounts.length === 0;
  }

  // Leerzustands-Nachricht
  get emptyStateMessage() {
    return 'Keine Accounts mit Umsatz gefunden';
  }
}