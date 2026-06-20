import { LightningElement, api } from 'lwc';

/**
 * SummaryCard - Zeigt Gesamtwert aller genehmigten Laptops
 * Wert wird als property uebergeben
 */
export default class SummaryCard extends LightningElement {
  @api title = 'Gesamtwert genehmigter Laptops';
  @api gesamtwert = 0;
}