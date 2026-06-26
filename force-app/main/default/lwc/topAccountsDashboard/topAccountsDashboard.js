import { LightningElement, wire, track } from 'lwc';
import getTopAccounts from '@salesforce/apex/TopAccountsService.getTopAccounts';

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

  // Lade Accounts via Apex — zuverlässig, unabhaengig von List View Konfiguration
  @wire(getTopAccounts)
  wiredAccounts({ data, error }) {
    this.isLoading = false;
    if (data) {
      this.accounts = data;
    } else if (error) {
      this.error = error;
      console.error('Error loading accounts:', error);
    }
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
