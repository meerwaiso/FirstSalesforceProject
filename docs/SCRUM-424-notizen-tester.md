# SCRUM-424 Tester-Notizen (Beleg + offenen Items)

Erstellt: 2026-09-23. Branch: feature/SCRUM-424-first-response @ b2eecab (Remote-Head).
Worktree: ~/Desktop/SoftwareProjects/Salesforce/scr424-wt; Shared-Checkout (418) NICHT angefasst.
Test-Org: devops-agent@cline.test, host resourceful-bear-6f1u4j-dev-ed.

## Org-Stand (Test-Org) - read-backs
- AC11/S1: SELECT TimeZoneSidKey FROM BusinessHours WHERE IsDefault = Europe/Berlin. S1 ERLEDIGT.
- S2 (echte Tageswerte): NICHT gesetzt. Default-BH = 24/7 (alle Day-Start/End NULL).
  --> PROBE (SCRUM424_TesterBhProbe, BusinessHours.diff live-gelesen, 4 Szenarien):
      D: Fri 18:00 -> Mon 09:00 (Europe/Berlin) = 3960 Min = 100% Kalender, 0 Nacht-/Wochenende-Abschlag.
      C: Saturday 10->11 = 60 Min = Wochenende NICHT frei gerechnet.
      --> Default-BW reagiert kalender-gleich. AC7-Arbeitszeit-Semantik ist bauartbedingt
          unerfuellbar BEI OFFENEM S2 (Designer-ADR-5: S2 blockiert AC7-Semantik, nicht den Build).
      --> WICHTIG: User-Aussage "Mo-Fr 9-17" passt NICHT zum org-messbaren Zustand (Default-WW).
          Entweder S2 in der Test-Org fehlen, oder es gibt eine zweite WW, die nicht Default ist.
          MUESSIG KLAEREN (PO/DevOps) - aber NICHT blocker-fuer-Developer.
- Handler (CaseCommentFirstResponse.cls) ruft korrekt `BusinessHours WHERE IsDefault=true LIMIT 1` auf.
  D.h. Handler + WW-Config matcht. Bug ist rein S2-org-missing, NICHT im Code.
- PS SCRUM424_FirstResponse_Read: deployed, 2 User (devops-agent + Meerwais) zugeordnet. Stufe 3 OK.
- FLS (via USER_MODE Apex-Test, 14/14 PASS): kein Read ohne PS, Read mit PS, kein Write fuer beide.
- Trigger CaseCommentFirstResponseTrigger deployed + active. NPE-Fix (CreatedDate) im Code.
- Report id 00OWU00000QW1bV2AT:
    scope = user (KRITISCH: My Cases, nicht everything - SCRUM-390-Lektion)
    format=Summary, reportType=CaseList.
    groupingsDown: Case.Servicebereich__c Asc.
    columns: CASE_NUMBER, SUBJECT, Case.First_Response_Working_Mins__c, Case.First_Response_Target_Missed__c.
    filter: First_Response_Time__c notEqual "".
    description: "Average via S4" - d.h. S4 (Aggregation) ist NICHT gesetzt.
    --> AC9: Anzahl gerissene Ziele = Subtotal der Checkbox-Spalte = count(true) -> DECKT "Anzahl".
           Durchschnitt (Average) fehlt, da S4 fehlt. -> Average = Org-Setup S4, NICHT Dev-Bug.
           BUT scope=user ist ein METADATA-DEFECT: Service-Manager soll "ueber Servicebereiche hinweg
           vergleichen koennen" (User Story!). User-Scope zeigt nur eigene Cases. -> DEFECT, Dev fix.
- Layout: Sektion "Erste Reaktion" (mit Leerzeichen; Design-Doc sagt "Erstreaktion", ein Wort).
  Doku-Discrepancy; Felder sind vorhanden.

## Apex-Testlauf 707WU00001K7EyV: 14/14 PASS, 100%
- SCRUM424FirstResponseTest: ac1_premium_inTarget, ac2_standard_missed, ac3_blank_standard,
  ac4_customer_comment_ignored, ac5_write_on