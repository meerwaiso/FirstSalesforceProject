import { LightningElement, wire, track } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { getListUi } from 'lightning/uiListApi';

import LAPTOP_OBJECT from '@salesforce/schema/Laptop__c';
import NAME_FIELD from '@salesforce/schema/Laptop__c.Name';
import STATUS_FIELD from '@salesforce/schema/Laptop__c.Status__c';
import PREIS_FIELD from '@salesforce/schema/Laptop__c.Preis__c';
import KUNDE_FIELD from '@salesforce/schema/Laptop__c.Kunde__c';
import MODELL_FIELD from '@salesforce/schema/Laptop__c.Modell__c';
import SERIENNUMMER_FIELD from '@salesforce/schema/Laptop__c.Seriennummer__c';

/**
 * Laptop Dashboard Hauptkomponente
 * Zeigt: Aktive Gerate, Offene Antraege, Gesamtwert aller genehmigten Laptops
 */
export default class LaptopDashboard extends LightningElement {
  @track aktiveLaptops = [];
  @track offeneAntraege = [];
  @track gesamtwert = 0;
  @track filterKunde = '';
  @track filterStatus = '';
  @track filterModell = '';

  // Spalten-Konfiguration fuer aktive Laptops
  aktiveColumns = [
    { label: 'Name', fieldName: 'Name', type: 'text' },
    { label: 'Mitarbeiter', fieldName: 'Kunde__c', type: 'text' },
    { label: 'Modell', fieldName: 'Modell__c', type: 'text' },
    { label: 'Seriennummer', fieldName: 'Seriennummer__c', type: 'text' },
    { label: 'Status', fieldName: 'Status__c', type: 'text' },
  ];

  // Spalten-Konfiguration fuer offene Antraege
  offeneColumns = [
    { label: 'Name', fieldName: 'Name', type: 'text' },
    { label: 'Mitarbeiter', fieldName: 'Kunde__c', type: 'text' },
    { label: 'Modell', fieldName: 'Modell__c', type: 'text' },
    { label: 'Preis (EUR)', fieldName: 'Preis__c', type: 'currency' },
    { label: 'Status', fieldName: 'Status__c', type: 'text' },
  ];

  // Lade aktive Laptops (Status = Zugewiesen oder Auf_Lager)
  @wire(getListUi, {
    objectApiName: LAPTOP_OBJECT,
    listViewApiName: 'All',
    sortBy: 'Name',
    sortOrder: 1,
    pageSize: 50,
  })
  wiredAktiveLaptops({ data, error }) {
    if (data) {
      this.aktiveLaptops = data.records
        .map((r) => getFieldValue(r, 'fields'))
        .filter((f) => {
          const status = getFieldValue(f, STATUS_FIELD);
          return (
            status === 'Zugewiesen' ||
            status === 'Auf_Lager' ||
            status === 'Verfuegbar'
          );
        });
    } else if (error) {
      console.error('Error loading aktive Laptops:', error);
    }
  }

  // Lade offene Antraege (Status = Ausstehend oder Genehmigt)
  @wire(getListUi, {
    objectApiName: LAPTOP_OBJECT,
    listViewApiName: 'All',
    sortBy: 'Name',
    sortOrder: 1,
    pageSize: 50,
  })
  wiredOffeneAntraege({ data, error }) {
    if (data) {
      this.offeneAntraege = data.records
        .map((r) => getFieldValue(r, 'fields'))
        .filter((f) => {
          const status = getFieldValue(f, STATUS_FIELD);
          return status === 'Ausstehend' || status === 'Genehmigt';
        });
    } else if (error) {
      console.error('Error loading offene Antraege:', error);
    }
  }

  // Gesamtwert aller genehmigten Laptops - wird aus den offenen Antraegen berechnet
  get gesamtwertBerechnet() {
    return this.offeneAntraege.reduce((sum, antrag) => {
      const preis = antrag.Preis__c?.value ?? 0;
      return sum + (typeof preis === 'number' ? preis : parseFloat(preis) || 0);
    }, 0);
  }

  // Filter-Handler
  handleFilterChange(event) {
    const { name, value } = event.target;
    if (name === 'kunde') this.filterKunde = value;
    if (name === 'status') this.filterStatus = value;
    if (name === 'modell') this.filterModell = value;

    // Fire custom event to child components
    this.dispatchEvent(
      new CustomEvent('filterchange', {
        detail: {
          kunde: this.filterKunde,
          status: this.filterStatus,
          modell: this.filterModell,
        },
      })
    );
  }

  // Filterte Daten fuer aktive Laptops
  get filteredAktiveLaptops() {
    return this.aktiveLaptops.filter((laptop) => {
      const kunde = laptop.Kunde__c?.value ?? '';
      const status = laptop.Status__c?.value ?? '';
      const modell = laptop.Modell__c?.value ?? '';

      if (this.filterKunde && !kunde.includes(this.filterKunde)) return false;
      if (this.filterStatus && status !== this.filterStatus) return false;
      if (this.filterModell && !modell.includes(this.filterModell)) return false;
      return true;
    });
  }

  // Filterte Daten fuer offene Antraege
  get filteredOffeneAntraege() {
    return this.offeneAntraege.filter((antrag) => {
      const kunde = antrag.Kunde__c?.value ?? '';
      const status = antrag.Status__c?.value ?? '';
      const modell = antrag.Modell__c?.value ?? '';

      if (this.filterKunde && !kunde.includes(this.filterKunde)) return false;
      if (this.filterStatus && status !== this.filterStatus) return false;
      if (this.filterModell && !modell.includes(this.filterModell)) return false;
      return true;
    });
  }
}