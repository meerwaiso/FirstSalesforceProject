const fs = require('fs');
const path = require('path');

const FIELDS_DIR = path.join(__dirname, '..', 'fields');
const VALRULES_DIR = path.join(__dirname, '..', 'validationRules');
const LAYOUTS_DIR = path.join(__dirname, '..', '..', '..', 'layouts');
const PERMSET_DIR = path.join(__dirname, '..', '..', '..', 'permissionsets');

function loadField(filename) {
  return fs.readFileSync(path.join(FIELDS_DIR, filename), 'utf-8');
}

function loadValidationRule(filename) {
  return fs.readFileSync(path.join(VALRULES_DIR, filename), 'utf-8');
}

function loadLayout(filename) {
  return fs.readFileSync(path.join(LAYOUTS_DIR, filename), 'utf-8');
}

function loadPermissionSet(filename) {
  return fs.readFileSync(path.join(PERMSET_DIR, filename), 'utf-8');
}

describe('[SCRUM-321] MeinNeuesFeld auf Opportunity-Objekt', () => {

  // AC-1: Feld sichtbar, Typ Text, max 255 Zeichen
  describe('AC-1: MeinNeuesFeld ist sichtbar und vom Typ Text (Max. 255 Zeichen)', () => {
    let fieldXml;
    let layoutXml;

    beforeEach(() => {
      fieldXml = loadField('MeinNeuesFeld__c.field-meta.xml');
      layoutXml = loadLayout('Opportunity-Opportunity Layout.layout-meta.xml');
    });

    it('should be of type Text', () => {
      expect(fieldXml).toContain('<type>Text</type>');
    });

    it('should have max length of 255 characters', () => {
      expect(fieldXml).toContain('<length>255</length>');
    });

    it('should be present on the Opportunity page layout', () => {
      expect(layoutXml).toContain('<field>MeinNeuesFeld__c</field>');
    });
  });

  // AC-2: Pflichtfeld-Validierung
  describe('AC-2: Pflichtfeld — Speichern verhindert wenn Feld leer', () => {
    let valRuleXml;

    beforeEach(() => {
      valRuleXml = loadValidationRule('MeinNeuesFeld_Pflichtfeld.validationRule-meta.xml');
    });

    it('Validation rule should be active', () => {
      expect(valRuleXml).toContain('<active>true</active>');
    });

    it('Validation rule should check for blank field', () => {
      expect(valRuleXml).toContain('ISBLANK(MeinNeuesFeld__c)');
    });

    it('Validation rule should display error message', () => {
      expect(valRuleXml).toContain('<errorMessage>MeinNeuesFeld ist ein Pflichtfeld. Bitte geben Sie einen Wert ein.</errorMessage>');
    });
  });

  // AC-3: Wert bis 255 Zeichen speichern
  describe('AC-3: Wert bis 255 Zeichen wird gespeichert', () => {
    let fieldXml;

    beforeEach(() => {
      fieldXml = loadField('MeinNeuesFeld__c.field-meta.xml');
    });

    it('should allow up to 255 characters', () => {
      expect(fieldXml).toContain('<length>255</length>');
    });
  });

  // AC-4: CRUD/FLS — alle mit Opportunity-Zugriff können lesen, schreiben, aktualisieren
  describe('AC-4: CRUD/FLS — Feld ist lesbar und beschreibbar', () => {
    let fieldXml;
    let permSetXml;
    let layoutXml;

    beforeEach(() => {
      fieldXml = loadField('MeinNeuesFeld__c.field-meta.xml');
      permSetXml = loadPermissionSet('SCRUM321_MeinNeuesFeld.permissionset-meta.xml');
      layoutXml = loadLayout('Opportunity-Opportunity Layout.layout-meta.xml');
    });

    it('Permission Set should grant Read access (implicit by field existence)', () => {
      expect(permSetXml).toContain('<field>Opportunity.MeinNeuesFeld__c</field>');
    });

    it('Permission Set should grant Edit access', () => {
      expect(permSetXml).toContain('<editable>true</editable>');
    });

    it('Field should be visible on page layout with Required behavior (create/update possible)', () => {
      // The layout block for MeinNeuesFeld__c should have Required behavior
      // (which implies the field is both editable and mandatory on the form)
      const match = /<behavior>Required<\/behavior>\s*<field>MeinNeuesFeld__c<\/field>/s.test(layoutXml);
      expect(match).toBe(true);
    });
  });

  // Edge Cases
  describe('Edge Cases', () => {
    let fieldXml;

    beforeEach(() => {
      fieldXml = loadField('MeinNeuesFeld__c.field-meta.xml');
    });

    it('should reject values over 255 characters (length enforced by platform)', () => {
      // Salesforce platform enforces the length limit automatically
      // The metadata correctly defines the limit
      expect(fieldXml).toContain('<length>255</length>');
    });
  });

});
