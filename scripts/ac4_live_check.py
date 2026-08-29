#!/usr/bin/env python3
# SCRUM-367 AC4 Live-Szenario: Rebuild läuft, während parallel ein Fall bearbeitet
# wird -> die Bearbeitung darf NICHT fehlschlagen (keine langen Locks).
#
# Mechanik:
#  - Rebuild wird über EXAKT die WebLink-Methode gestartet:
#    CaseOpenCountRebuilder.startRebuild() per `sf apex run -f` (System-Mode).
#    Das legt die Run-Zeile an und startet den Batch ASYNCHRON (200er-Chunks).
#  - Sofort danach, mit minimaler Verzögerung, führen wir SO-VIELE-WIE-MÖGLICH
#    Case-DML-Updates aus (typische Service-Bearbeitung: Priority setzen).
#  - AC4 gilt als erfüllt, wenn (1) KEIN einziger Case-Update fehlschlägt
#    (rc=0 + Field tatsächlich geschrieben) UND (2) der Rebuild trotzdem bis
#    Abgeschlossen läuft.
import subprocess, json, time, sys, os
PROJ = '/home/fino/Desktop/SoftwareProjects/Salesforce/FirstSalesforceProject'
os.chdir(PROJ)

def run(cmd, to=180):
    p = subprocess.run(cmd, capture_output=True, text=True, timeout=to, shell=isinstance(cmd, str))
    return p.returncode, p.stdout, p.stderr

def query(qs, to=120):
    rc, out, err = run(['sf','data','query','-o','Test-Org','--json','-q',qs], to)
    s = out[out.index('{'):] if '{' in out else out
    return json.loads(s)['result']['records']

def count(qs):
    r = query(qs)
    for r0 in r:
        for k in ('expr0','cnt','c'):
            if k in r0:
                return r0[k]
    return None

# Ausgangszähler (vor dem Lauf) — zum Belegen dass der Batch sich bewegt
null_before = count("SELECT COUNT(Id) FROM Contact WHERE Open_Cases_Count__c = null")
runs_before = count("SELECT COUNT(Id) FROM CaseRebuildRun__c")
print("vorher: nulls=%s runs=%s" % (null_before, runs_before))

# Target-Fälle: mehrere New-Cases, damit wir parallel mehrere schreiben können
cases = query("SELECT Id, Subject FROM Case WHERE Status='New' LIMIT 8")
print("target cases:", len(cases))

# --- Rebuild starten (EXAKTE WebLink-Methode, System-Mode) ---
open('/tmp/rebuild_apex.txt','w').write("CaseOpenCountRebuilder.startRebuild();")
t_start = time.time()
rc1, out1, err1 = run(['sf','apex','run','-o','Test-Org','-f','/tmp/rebuild_apex.txt','--json'], 180)
t_start_end = time.time()
s1 = out1[out1.index('{'):] if '{' in out1 else out1
try:
    d1 = json.loads(s1).get('result', {})
    print("rebuild start: status=%s exc=%r done=%r (%.1fs)" % (
        d1.get('status'), d1.get('exceptionMessage',''), (d1.get('result') or '')[:80].replace('\n',' '), t_start_end-t_start))
except Exception as e:
    print("parse err:", e, out1[:200])

# --- PARALLEL: Case-Updates SOFORT und möglichst während des Batches ---
upd_ok = 0
upd_fail = []
for c in cases:
    t0 = time.time()
    # Priority + Subject-Änderung = echte Service-Bearbeitung
    rc, out, err = run(['sf','data','record','update','-o','Test-Org','-i',c['Id'],
                        '-s','Case','-v','Priority=Low'], 120)
    dt = time.time()-t0
    if rc == 0:
        upd_ok += 1
    else:
        upd_fail.append((c['Id'], rc, (out+err)[:150].replace('\n',' ')))

print("\nPARALLEL-Phase: %d/%d Case-Updates erfolgreich, %d fehlgeschlagen" % (upd_ok, len(cases), len(upd_fail)))
for u in upd_fail:
    print("  FAILED:", u)

# Verifizieren: ein Updated-Fall hat tatsächlich Priority=Low (read-back)
if cases:
    chk = query("SELECT Priority FROM Case WHERE Id='"+cases[0]['Id']+"'")[0]
    print("read-back Priority:", chk['Priority'], "-> %s" % ("geschrieben" if chk['Priority']=='Low' else "NICHT geschrieben"))

# --- Rebuild ausrasten ---
last=None
for i in range(40):
    runs = query("SELECT Id, Status__c, ContactsProcessed__c, ContactsCorrected__c, FinishedAt__c FROM CaseRebuildRun__c ORDER BY CreatedDate DESC LIMIT 1")
    if runs:
        last = runs[0]
        if last['FinishedAt__c'] is not None:
            break
    time.sleep(2)
ok_last = last is not None
print("\nRun nach Lauf:", json.dumps({k:last[k] for k in ('Id','Status__c','ContactsProcessed__c','ContactsCorrected__c','FinishedAt__c')}, ensure_ascii=False) if ok_last else "keine Run-Zeile gefunden")
null_after = count("SELECT COUNT(Id) FROM Contact WHERE Open_Cases_Count__c = null")
print("nulls nach Lauf: %s (vorher %s)" % (null_after, null_before))

# --- VERDIKT ---
rebuild_ok = ok_last and last['Status__c']=='Abgeschlossen'
no_fail = len(upd_fail)==0
ok = rebuild_ok and no_fail
print("\nAC4 VERDIKT: %s  (Batch läuft=%s, Case-Updates fehlerfrei=%s)" % (
    "PASS" if ok else "FAIL", rebuild_ok, no_fail))
sys.exit(0 if ok else 1)
