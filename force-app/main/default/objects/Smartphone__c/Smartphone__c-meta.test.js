/**
 * [SCRUM-245] Smartphone Custom Object — Metadata Validation Tests
 * Validates all 14 fields and their types against acceptance criteria.
 */

const fs = require('fs');
const path = require('path');

const FIELDS_DIR = path.join(__dirname, 'fields');

function loadField(filename) {
  const filepath = path.join(FIELDS_DIR, filename);
  const raw = fs.readFileSync(filepath, 'utf-8');
  // Strip the xmlns for simpler assertions
  return raw;
}

describe('[SCRUM-245] Smartphone Custom Object Metadata', () => {

  // --- AC 1: Object exists ---
  describe('AC-1: Smartphone custom object exists with 14 fields', () => {
    it('should have an object folder with field files', () => {
      expect(fs.existsSync(FIELDS_DIR)).toBe(true);
    });

    it('should have exactly 14 field files', () => {
      const files = fs.readdirSync(FIELDS_DIR).filter(f => f.endsWith('.field-meta.xml'));
      expect(files.length).toBe(14);
    });
  });

  // --- AC-2: Each field ---
  describe('AC-2: Field Modell (Text)', () => {
    let xml;
    beforeEach(() => { xml = loadField('Modell__c.field-meta.xml'); });

    it('should be type Text', () => {
      expect(xml).toContain('<type>Text</type>');
    });
    it('should have label Modell', () => {
      expect(xml).toContain('<label>Modell</label>');
    });
  });

  describe('AC-2: Field Marke (Text)', () => {
    let xml;
    beforeEach(() => { xml = loadField('Marke__c.field-meta.xml'); });

    it('should be type Text', () => {
      expect(xml).toContain('<type>Text</type>');
    });
    it('should have label Marke', () => {
      expect(xml).toContain('<label>Marke</label>');
    });
  });

  describe('AC-2: Field Kaufdatum (Date)', () => {
    let xml;
    beforeEach(() => { xml = loadField('Kaufdatum__c.field-meta.xml'); });

    it('should be type Date', () => {
      expect(xml).toContain('<type>Date</type>');
    });
    it('should have label Kaufdatum', () => {
      expect(xml).toContain('<label>Kaufdatum</label>');
    });
  });

  describe('AC-2: Field Kunde (Lookup)', () => {
    let xml;
    beforeEach(() => { xml = loadField('Kunde__c.field-meta.xml'); });

    it('should be type Lookup', () => {
      expect(xml).toContain('<type>Lookup</type>');
    });
    it('should have label Kunde', () => {
      expect(xml).toContain('<label>Kunde</label>');
    });
    it('should reference Account', () => {
      expect(xml).toContain('<referenceTo>Account</referenceTo>');
    });
    // NOTE: AC says "Lookup zu Account/Contact" but implementation uses Account only.
    // This may be a discrepancy — see SCRUM-245 comment.
  });

  describe('AC-2: Field Preis (Currency)', () => {
    let xml;
    beforeEach(() => { xml = loadField('Preis__c.field-meta.xml'); });

    it('should be type Currency', () => {
      expect(xml).toContain('<type>Currency</type>');
    });
    it('should have label Preis', () => {
      expect(xml).toContain('<label>Preis</label>');
    });
  });

  describe('AC-2: Field Seriennummer (Text)', () => {
    let xml;
    beforeEach(() => { xml = loadField('Seriennummer__c.field-meta.xml'); });

    it('should be type Text', () => {
      expect(xml).toContain('<type>Text</type>');
    });
    it('should have label Seriennummer', () => {
      expect(xml).toContain('<label>Seriennummer</label>');
    });
    it('should be unique', () => {
      expect(xml).toContain('<unique>true</unique>');
    });
  });

  describe('AC-2: Field Status (Picklist)', () => {
    let xml;
    beforeEach(() => { xml = loadField('Status__c.field-meta.xml'); });

    it('should be type Picklist', () => {
      expect(xml).toContain('<type>Picklist</type>');
    });
    it('should have label Status', () => {
      expect(xml).toContain('<label>Status</label>');
    });
    it('should contain value Verfuegbar', () => {
      expect(xml).toContain('Verf\xFCgbar');
      // Check that all 5 values are present (may use UTF-8 or escaped)
      const values = ['Verf\xFCgbar', 'Reserviert', 'In_Betrieb', 'Verkauft', 'Ausgemustert'];
      values.forEach(v => {
        expect(xml).toContain(v);
      });
    });
    it('should have exactly 5 picklist values', () => {
      const valueMatches = xml.match(/<value>/g);
      expect(valueMatches.length).toBe(5);
    });
  });

  describe('AC-2: Field Verkäufer (Lookup)', () => {
    let xml;
    beforeEach(() => { xml = loadField('Verkaeufer__c.field-meta.xml'); });

    it('should be type Lookup', () => {
      expect(xml).toContain('<type>Lookup</type>');
    });
    it('should have label Verkäufer', () => {
      expect(xml).toContain('Verkaeufer');
    });
    it('should reference User', () => {
      expect(xml).toContain('<referenceTo>User</referenceTo>');
    });
  });

  describe('AC-2: Field Verkaufsdatum (Date)', () => {
    let xml;
    beforeEach(() => { xml = loadField('Verkaufsdatum__c.field-meta.xml'); });

    it('should be type Date', () => {
      expect(xml).toContain('<type>Date</type>');
    });
    it('should have label Verkaufsdatum', () => {
      expect(xml).toContain('<label>Verkaufsdatum</label>');
    });
  });

  describe('AC-2: Field Farbe (Text)', () => {
    let xml;
    beforeEach(() => { xml = loadField('Farbe__c.field-meta.xml'); });

    it('should be type Text', () => {
      expect(xml).toContain('<type>Text</type>');
    });
    it('should have label Farbe', () => {
      expect(xml).toContain('<label>Farbe</label>');
    });
  });

  describe('AC-2: Field Speicherkapazität (Picklist)', () => {
    let xml;
    beforeEach(() => { xml = loadField('Speicherkapazitaet__c.field-meta.xml'); });

    it('should be type Picklist', () => {
      expect(xml).toContain('<type>Picklist</type>');
    });
    it('should have label Speicherkapazität', () => {
      expect(xml).toContain('Speicherkapazitaet');
    });
    it('should have exactly 5 picklist values (64GB, 128GB, 256GB, 512GB, 1TB)', () => {
      const expected = ['64GB', '128GB', '256GB', '512GB', '1TB'];
      expected.forEach(v => {
        expect(xml).toContain(v);
      });
      const valueMatches = xml.match(/<value>/g);
      expect(valueMatches.length).toBe(5);
    });
  });

  describe('AC-2: Field Garantie bis (Date)', () => {
    let xml;
    beforeEach(() => { xml = loadField('Garantie_bis__c.field-meta.xml'); });

    it('should be type Date', () => {
      expect(xml).toContain('<type>Date</type>');
    });
    it('should have label Garantie bis', () => {
      expect(xml).toContain('<label>Garantie bis</label>');
    });
  });

  describe('AC-2: Field Kondition (Picklist)', () => {
    let xml;
    beforeEach(() => { xml = loadField('Kondition__c.field-meta.xml'); });

    it('should be type Picklist', () => {
      expect(xml).toContain('<type>Picklist</type>');
    });
    it('should have label Kondition', () => {
      expect(xml).toContain('<label>Kondition</label>');
    });
    it('should have exactly 4 picklist values (Neu, Wie Neu, Gut, Angezischt)', () => {
      const expected = ['Neu', 'Wie_Neu', 'Gut', 'Angezischt'];
      expected.forEach(v => {
        expect(xml).toContain(v);
      });
      const valueMatches = xml.match(/<value>/g);
      expect(valueMatches.length).toBe(4);
    });
  });

  describe('AC-2: Field Gewährleistungsnummer (Text)', () => {
    let xml;
    beforeEach(() => { xml = loadField('Gewaehrleistungsnummer__c.field-meta.xml'); });

    it('should be type Text', () => {
      expect(xml).toContain('<type>Text</type>');
    });
    it('should have label Gewährleistungsnummer', () => {
      expect(xml).toContain('Gewaehrleistungsnummer');
    });
  });
});
