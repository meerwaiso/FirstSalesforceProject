<?xml version="1.0" encoding="UTF-8"?>
<!-- SCRUM-404: globale Zeile. Prioritaet leer = gilt für alle Prioritäten (Fallback).
     Teamlead__c ist aktuell LEER (open item §9: Name/Account-ID der Teamleitung hängen — @user/PO).
     Deterministisch: kein Teamlead -> der Überfälligkeits-Alert wird NICHT enqueuet (ADR-6, §8.5).
     Sobald der Teamlead-User gesetzt ist (MDT-Edit in Setup, OHNE Deploy), wird der Alert aktiv. -->
<CustomMetadata xmlns="http://soap.sforce.com/2006/04/metadata" entity="Sla_Konfiguration__mdt" label="global" protected="false">
    <values>
        <field>Alert_Kanal__c</field>
        <value>
            <stringValue>Beides</stringValue>
        </value>
    </values>
</CustomMetadata>
