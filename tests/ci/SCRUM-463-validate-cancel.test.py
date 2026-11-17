#!/usr/bin/env python3
# SCRUM-463 Tester: die Lifecycle eines deploy-Validation, tested against a real org.
# Run from the repo root:  tests/ci/SCRUM-463-validate-cancel.test.py
# Exit 0 only when every assertion held; every scenario prints its own evidence.
#
#   AC1  a run that is cancelled while its validation is still live cancels that
#        validation in the org (both cancel paths: the SIGTERM trap AND the
#        `if: cancelled()` step reading the id file)
#   AC3  a validation that finishes normally still produces its verdict and the
#        shape the gate parser reads — cancelling must not swallow a real verdict
#   AC4  a cancelled validation states "no verdict" and never writes a verdict
#        file, so the parser cannot read green
#   neg  a FINISHED operation must not be cancelled and its verdict file must
#        survive untouched
#
# Test-Org only, check-only validations (--source-dir points at a one-component
# fixture, so a run costs seconds, not the full force-app).
#
# Measured traps (see docs/SCRUM-463-notizen-tester.md):
#  - a killed process's PIPE can lose its tail — the killed scenarios write their
#    output to a FILE, which cannot;
#  - stale id files from a previous run must be removed before each scenario, or
#    a scenario reads the previous run's job id instead of its own.
import json, os, re, subprocess, time, hashlib, sys

ROOT = os.getcwd()
SCRIPT = os.path.join(ROOT, "scripts", "ci-prod-validate.sh")
FIXTURE = os.path.join(ROOT, "tests", "fixtures", "scr463-validate")
ORG = "Test-Org"
RESULTS = os.path.join(ROOT, "test-results")
results = []


def check(label, ok, evidence):
    results.append((label, bool(ok), evidence))
    print(("PASS " if ok else "FAIL ") + label + " :: " + evidence)


def jsonish(text):
    i = text.find("{")
    if i < 0:
        return {}
    try:
        return json.loads(text[i:])
    except Exception:
        # The CLI appends a Warning line to stderr AFTER the JSON — the payload is
        # the outermost object, so cut at the last closing brace.
        j = text.rfind("}")
        try:
            return json.loads(text[i:j + 1])
        except Exception:
            return {}


def sf_report(job):
    """Read one deploy operation back through the Tooling API."""
    p = subprocess.run(["sf", "project", "deploy", "report", "-o", ORG, "-i", job, "--json"],
                       capture_output=True, text=True, timeout=180)
    return jsonish(p.stdout + p.stderr).get("result", {})


def report_done(job, tries=12):
    """A cancellation finishes in the org seconds after the call — poll until done."""
    rep = {}
    for _ in range(tries):
        rep = sf_report(job)
        if rep.get("done") is True:
            return rep
        time.sleep(5)
    return rep


def sha(path):
    return hashlib.sha256(open(path, "rb").read()).hexdigest() if os.path.exists(path) else "MISSING"


def validate_args(out, idfile, tests=None):
    """The CI call site uses RunLocalTests (the whole local suite, 492 tests measured in
    Test-Org). Scenario A narrows to the fixture's own class so its verdict can be read
    as Success without unrelated org failures in the way."""
    a = [SCRIPT, "--org", ORG, "--source-dir", FIXTURE,
         "--wait", "20", "--out", out, "--id-file", idfile]
    a += (["--test-level", "RunSpecifiedTests", "--tests", tests] if tests
          else ["--test-level", "RunLocalTests"])
    return a


def read_id(idfile):
    return open(idfile).read().strip() if os.path.exists(idfile) else ""


def start_and_kill(args, idfile, caplog, kill="term"):
    """Run the gate script, wait until it published its job id, then kill it.
    Returns (rc, job, captured output). Output goes to a FILE: a killed process's
    pipe can lose the tail, a file cannot. Stale id/verdict/cap files are removed
    first, so a scenario can never read a previous run's job id."""
    for stale in (idfile, caplog):
        if os.path.exists(stale):
            os.remove(stale)
    with open(caplog, "w") as lf:
        p = subprocess.Popen(args, stdout=lf, stderr=subprocess.STDOUT)
        t0 = time.time()
        job = ""
        while time.time() - t0 < 60:
            job = read_id(idfile)
            if job:
                break
            time.sleep(2)
        (p.terminate() if kill == "term" else p.kill())
        rc = p.wait()
    return rc, job, open(caplog).read()


def run_cancel(idfile):
    """The `if: cancelled()` step: cancel exactly the id in the file."""
    p = subprocess.run([SCRIPT, "--org", ORG, "--cancel", "--id-file", idfile],
                       capture_output=True, text=True, timeout=300)
    return p.returncode, p.stdout + p.stderr


os.makedirs(RESULTS, exist_ok=True)

# ---------- AC3: a validation that finishes normally keeps its verdict ----------
outA = os.path.join(RESULTS, "scr463-verdict-A.json")
idA = os.path.join(RESULTS, ".ci-validate-job-id-A")
for stale in (outA, idA):
    if os.path.exists(stale):
        os.remove(stale)
pA = subprocess.run(validate_args(outA, idA, tests="SCRUM463ProbeTest"),
                    capture_output=True, text=True, timeout=1500)
jobA = read_id(idA)
dA = jsonish(open(outA).read()) if os.path.exists(outA) else {}
rA = dA.get("result", {})
cfA = (rA.get("details") or {}).get("componentFailures")
check("AC3 exit code 0 (a finished validation is green)",
      pA.returncode == 0,
      "rc=%s status=%s job=%s" % (pA.returncode, rA.get("status"), jobA))
check("AC3 verdict file written and readable JSON",
      os.path.getsize(outA) > 0 if os.path.exists(outA) else False,
      "file=%s bytes=%s" % (outA, os.path.getsize(outA) if os.path.exists(outA) else 0))
check("AC3 shape the gate parser reads (result + details.componentFailures + message)",
      "result" in dA and isinstance(cfA, list) and "message" in dA,
      "componentFailures=%s message=%r" % (cfA, dA.get("message")))
check("AC3 the finished verdict reads Success (the real verdict, not a cancel)",
      str(rA.get("status", "")).lower() == "success",
      "status=%s testsTotal=%s testErrors=%s" % (rA.get("status"), rA.get("numberTestsTotal"), rA.get("numberTestErrors")))
check("AC3 the finished operation was NOT cancelled",
      "cancel" not in str(rA.get("status", "none")).lower(),
      "status=%s done=%s" % (rA.get("status"), rA.get("done")))
shaA = sha(outA)

# ---------- AC1a: the SIGTERM trap path ----------
outB = os.path.join(RESULTS, "scr463-verdict-B.json")
idB = os.path.join(RESULTS, ".ci-validate-job-id-B")
capB = os.path.join(RESULTS, "scr463-cap-B.out")
if os.path.exists(outB):
    os.remove(outB)
rcB, jobB, outBtxt = start_and_kill(validate_args(outB, idB), idB, capB, kill="term")
repB = report_done(jobB) if jobB else {}
check("AC1a trap path: the live operation was cancelled in the org",
      str(repB.get("status", "")).lower().startswith("cancel") and repB.get("done") is True,
      "job=%s status=%s done=%s deployed=%s checkOnly=%s" % (
          jobB, repB.get("status"), repB.get("done"), repB.get("numberComponentsDeployed"), repB.get("checkOnly")))
check("AC1a the script says no verdict and exits red",
      rcB == 1 and "no verdict" in outBtxt,
      "rc=%s line=%s" % (rcB, [l for l in outBtxt.splitlines() if "no verdict" in l][:1]))
check("AC1a no verdict file was written (the parser cannot read green)",
      not os.path.exists(outB),
      "out=%s exists=%s" % (outB, os.path.exists(outB)))

# ---------- AC1b: the `if: cancelled()` step reads the id file (SIGKILL: no trap) ----------
outC = os.path.join(RESULTS, "scr463-verdict-C.json")
idC = os.path.join(RESULTS, ".ci-validate-job-id-C")
capC = os.path.join(RESULTS, "scr463-cap-C.out")
if os.path.exists(outC):
    os.remove(outC)
rcC, jobC, capCtxt = start_and_kill(validate_args(outC, idC), idC, capC, kill="kill")
live = sf_report(jobC) if jobC else {}
check("AC1b the operation stayed live after SIGKILL (no trap could run)",
      bool(live) and live.get("done") is not True,
      "job=%s rc=%s done=%s status=%s" % (jobC, rcC, live.get("done"), live.get("status")))
rcD, txtC = run_cancel(idC)
repC = report_done(jobC) if jobC else {}
check("AC1b id-file path: the live operation was cancelled in the org",
      str(repC.get("status", "")).lower().startswith("cancel") and repC.get("done") is True,
      "job=%s status=%s done=%s deployed=%s canceledBy=%s" % (
          jobC, repC.get("status"), repC.get("done"), repC.get("numberComponentsDeployed"), repC.get("canceledByName")))
check("AC1b the cancel step names the operation it cancelled, not the most recent one",
      jobC in txtC and "most recent" not in txtC,
      "job=%s in output; rc=%s" % (jobC, rcD))
check("AC4 the cancelled run states plainly that there is no verdict",
      "no verdict" in txtC,
      "line=%s" % [l for l in txtC.splitlines() if "no verdict" in l][:1])
check("AC4 the cancelled run wrote no verdict file",
      not os.path.exists(outC),
      "out=%s exists=%s" % (outC, os.path.exists(outC)))

# ---------- negative case: a finished operation must not be cancelled ----------
idD = os.path.join(RESULTS, ".ci-validate-job-id-D")
if jobA:
    open(idD, "w").write(jobA + "\n")
    before = sha(outA)
    rcE, txtD = run_cancel(idD)
    after = sha(outA)
    check("negative: a finished operation is refused, not cancelled",
          "already finished" in txtD and "CannotCancelDeployError" not in txtD,
          "job=%s rc=%s line=%s" % (jobA, rcE, [l for l in txtD.splitlines() if "finished" in l][:1]))
    check("negative: the real verdict file survived untouched",
          before == after and before != "MISSING",
          "sha256 before=%s after=%s" % (before[:16], after[:16]))
    check("negative: the cancel step wrote no verdict of its own",
          not any("no verdict" in l for l in txtD.splitlines()),
          "no --out given; file absent")
else:
    check("negative: a finished operation is refused, not cancelled", False, "scenario A produced no job id")

print("\n--- SCRUM-463 coverage ---")
for label, ok, ev in results:
    print("%-72s %s" % (label, "PASS" if ok else "FAIL"))
print("AC2 (never more than one live validation per PR) NOT COVERED — it needs six pushes and the"
      " workflow wiring in .github/workflows/, which the user applies; no test of mine can reach it.")
failed = [r for r in results if not r[1]]
sys.exit(1 if failed else 0)
