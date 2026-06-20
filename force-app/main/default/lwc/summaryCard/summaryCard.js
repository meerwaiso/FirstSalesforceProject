import { LightningElement, api, wire } from 'lwc';
import { getAggregateUi } from 'lightning/uiAggregateApi';
import LAPTOP_OBJECT from '@salesforce/schema/Laptop__c';
import STATUS_FIELD from '@salesforce/schema/Laptop__c.Status__c';
import PREIS_FIELD from '@salesforce/schema/Laptop__c.Preis__c';

/**
 * SummaryCard - Zeigt Gesamtwert aller genehmigten Laptops (SUM(Preis__c))
 * Nutzt wire-Decorator mit SOQL Aggregation
 */
export default class SummaryCard extends LightningElement {
  @api title = 'Gesamtwert genehmigter Laptops';
  gesamtwert = 0;

  @wire(getAggregateUi, {
    objectApiName: LAPTOP_OBJECT,
    groupByAggregates: [],
    aggregateSelects: [
      {
        aggregateSelect: {
          type: 'sum',
          fieldApiName: PREIS_FIELD.fieldApiName,
        },
        alias: 'Gesamtwert',
      },
    ],
    filterCriteria: {
      criteria: [
        {
          fieldApiName: STATUS_FIELD.fieldApiName,
          operator: 'eq',
          value: 'Genehmigt',
        },
      ],
    },
  })
  wiredGesamtwert({ data, error }) {
    if (data) {
      this.gesamtwert = data.records[0]?.Gesamtwert ?? 0;
    } else if (error) {
      console.error('Error loading gesamtwert:', error);
    }
  }
}
