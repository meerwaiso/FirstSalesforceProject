import { LightningElement, api } from 'lwc';

/**
 * FilterBar - Child-Komponente fuer Laptop-Dashboard
 * Filter fuer: Mitarbeiter (Kunde__c), Status (Status__c), Modell (Modell__c)
 * Feuert onChange-Event an Parent mit Filter-Werten
 */
export default class FilterBar extends LightningElement {
  @api filterKunde = '';
  @api filterStatus = '';
  @api filterModell = '';

  kundeOptions = [
    { label: 'Alle', value: '' },
    { label: 'Max Mustermann', value: 'Max Mustermann' },
    { label: 'Anna Schmidt', value: 'Anna Schmidt' },
    { label: 'Thomas Mueller', value: 'Thomas Mueller' },
  ];

  statusOptions = [
    { label: 'Alle', value: '' },
    { label: 'Ausstehend', value: 'Ausstehend' },
    { label: 'Genehmigt', value: 'Genehmigt' },
    { label: 'Abgelehnt', value: 'Abgelehnt' },
    { label: 'Auf_Lager', value: 'Auf_Lager' },
    { label: 'Zugewiesen', value: 'Zugewiesen' },
    { label: 'Nachbestellung', value: 'Nachbestellung' },
  ];

  modellOptions = [
    { label: 'Alle', value: '' },
    { label: 'ThinkPad X1', value: 'ThinkPad X1' },
    { label: 'Latitude 5520', value: 'Latitude 5520' },
    { label: 'EliteBook 840', value: 'EliteBook 840' },
    { label: 'Surface Laptop', value: 'Surface Laptop' },
  ];

  handleFilterChange(event) {
    const { name, value } = event.target;
    if (name === 'kunde') this.filterKunde = value;
    if (name === 'status') this.filterStatus = value;
    if (name === 'modell') this.filterModell = value;

    this.dispatchEvent(
      new CustomEvent('change', {
        detail: {
          kunde: this.filterKunde,
          status: this.filterStatus,
          modell: this.filterModell,
        },
      })
    );
  }
}
