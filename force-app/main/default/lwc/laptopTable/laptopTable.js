import { LightningElement, api } from 'lwc';

/**
 * LaptopTable - Wiederverwendbare Tabellen-Komponente
 * Empfängt Daten und Spaltenkonfiguration via @api
 * Nutzt lightning-datatable mit Sortierung und Pagination
 */
export default class LaptopTable extends LightningElement {
  @api title = 'Laptops';
  @api data = [];
  @api columns = [];
  @api keyField = 'Id';

  // Pagination
  currentPage = 1;
  pageSize = 10;

  get paginatedData() {
    const start = (this.currentPage - 1) * this.pageSize;
    const end = start + this.pageSize;
    return this.data.slice(start, end);
  }

  get totalPages() {
    return Math.ceil(this.data.length / this.pageSize);
  }

  get hasPrevious() {
    return this.currentPage > 1;
  }

  get hasNext() {
    return this.currentPage < this.totalPages;
  }

  handlePrevious() {
    if (this.hasPrevious) {
      this.currentPage--;
    }
  }

  handleNext() {
    if (this.hasNext) {
      this.currentPage++;
    }
  }

  handleSort(event) {
    const { fieldName, sortBy } = event.detail;
    const sorted = [...this.data].sort((a, b) => {
      const aVal = a[fieldName] || '';
      const bVal = b[fieldName] || '';
      return sortBy === 'asc'
        ? aVal.localeCompare(bVal)
        : bVal.localeCompare(aVal);
    });
    this.data = sorted;
  }
}
