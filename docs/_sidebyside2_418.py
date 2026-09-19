#!/usr/bin/env python3
"""SCRUM-418 SAUBERER ABGLEICH — 1 Skript, frische Cases, 3 Wege.
Erstellt 3 frische Cases (jeden Closed), reopening via (A) CLI 'sf data
update record', (B) reinem REST-PATCH — und liest den Zaehler aus der Org.
UI-Weg ist separat gemessen (Playwright, =1). Erwartet bei Defekt: A=2, B=2.
Alle Calls mit FORCE_COLOR=0 NO_COLOR=1; große CLI-Ausgaben hier inline (klein).
"""
import json, re, subprocess, urllib.request, base64

ORG = "devops-agent@cline.test"

def sf(args, t=120):
    r = subprocess.run(["bash","-c","FORCE_COLOR=0 NO_COLOR=1 sf "+args],
                       capture_output=True, text=True, timeout=t)
    out=r.stdout
    out=re.sub(r"\x1b\[[0-9;]*[a-zA-Z]","",out)
    i=out.find("{")
    if i<0:
        raise RuntimeError("no JSON for: sf "+args+"\n"+out[:400]+"\n"+r.stderr[:400])
    return json.JSONDecoder().raw_decode(out[i:])[0]

def q(soql):
    d=sf(f'data query -o {ORG} --query "{soql}" --json')
    return d["result"]["records"]

def get_token():
    inst=sf(f'org display -o {ORG} --json')["result"]["instanceUrl"]
    # show-access-token hat einen interaktiven Prompt -> 'yes |' davor
    r=subprocess.run(["bash","-c",f"yes | FORCE_COLOR=0 NO_COLOR=1 sf org auth show-access-token -o {ORG} --json"],
                     capture_output=True, text=True, timeout=60)
    out=re.sub(r"\x1b\[[0-9;]*[a-zA-Z]","",r.stdout)
    i=out.find("{")
    tok=json.JSONDecoder().raw_decode(out[i:])[0]["result"]["accessToken"]
    return tok, inst

def make_case(subject):
    d=sf(f"data create record -o {ORG} -s Case -v 'Subject={subject} Origin=Phone' --json")
    return d["result"]["id"]

def close(id):
    sf(f"data update record -o {ORG} -s Case -i {id} -v 'Status=Closed' --json")

def countsof(id):
    r=q(f"SELECT Reactivation_Count__c FROM Case WHERE Id='{id}'")
    return r[0]["Reactivation_Count__c"] if r else None

def statusof(id):
    r=q(f"SELECT Id, Status FROM Case WHERE Id='{id}'")
    return r[0].get("Status") if r else None

def rest_reopen(tok, inst, id):
    # reinen REST-PATCH an eine einzelne Felder (Status) senden
    base=inst.rstrip("/")
    body=json.dumps({"Status":"New"}).encode()
    req=urllib.request.Request(base+"/services/data/v61.0/sobjects/Case/"+id,
                               data=body, method="PATCH")
    req.add_header("Authorization","Bearer "+tok)
    req.add_header("Content-Type","application/json")
    with urllib.request.urlopen(req, timeout=60) as resp:
        return resp.status

tok, inst = get_token()
print("org:", inst[:50])

results={}
# A: CLI
sa=make_case("SCRUM418_SIDE_A")
close(sa)
print("A created+closed:", sa, "count0=", countsof(sa), "status=", statusof(sa))
sf(f"data update record -o {ORG} -s Case -i {sa} -v 'Status=New' --json")
print("A after CLI reopen: status=", statusof(sa), "count=", countsof(sa))
results["A_cli"]=countsof(sa)

# B: REST
sb=make_case("SCRUM418_SIDE_B")
close(sb)
print("B created+closed:", sb, "count0=", countsof(sb), "status=", statusof(sb))
code=rest_reopen(tok, inst, sb)
print("B rest patch http", code, "-> after: status=", statusof(sb), "count=", countsof(sb))
results["B_rest"]=countsof(sb)

# C: CLI nochmal (Reproduktionssicherheit)
sc=make_case("SCRUM418_SIDE_C")
close(sc)
sf(f"data update record -o {ORG} -s Case -i {sc} -v 'Status=New' --json")
print("C after CLI reopen: status=", statusof(sc), "count=", countsof(sc))
results["C_cli2"]=countsof(sc)

print("\nSUMMARY:", json.dumps(results))
print("UI (Playwright, separat gemessen): 1")
