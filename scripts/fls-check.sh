#!/usr/bin/env bash
# fls-check.sh — beantwortet "warum sehe ich dieses Feld nicht?" in einem Befehl.
#
#   scripts/fls-check.sh Case Servicebereich__c [Test-Org]
#
# Läuft die kanonische Prüfkette aus Skill 'salesforce-describe-first' §4:
#   1. FieldDefinition        existiert das Feld?
#   2. FieldPermissions       gewährt überhaupt etwas Zugriff?
#   3. PermissionSetAssignment hat der handelnde Benutzer das PS?
set -uo pipefail

OBJ="${1:-}"; FLD="${2:-}"; ORG="${3:-Test-Org}"
if [ -z "$OBJ" ] || [ -z "$FLD" ]; then
  echo "usage: $0 <SObject> <Field__c> [org-alias]" >&2; exit 2
fi

q()  { sf data query -o "$ORG" -q "$1" -r csv 2>/dev/null | grep -v '^Querying' | tail -n +2; }
qt() { sf data query --use-tooling-api -o "$ORG" -q "$1" -r csv 2>/dev/null | grep -v '^Querying' | tail -n +2; }

USER=$(sf org display -o "$ORG" --json 2>/dev/null \
       | python3 -c 'import json,sys;print(json.load(sys.stdin)["result"].get("username",""))' 2>/dev/null)
echo "Org $ORG   Benutzer ${USER:-unbekannt}"
echo "Feld $OBJ.$FLD"
echo

# ---- 1. Existenz -----------------------------------------------------------
EX=$(qt "SELECT QualifiedApiName, DataType FROM FieldDefinition \
         WHERE EntityDefinition.QualifiedApiName='$OBJ' AND QualifiedApiName='$FLD'")
if [ -z "$EX" ]; then
  echo "1. Existenz      NEIN — nicht in dieser Org deployt."
  echo
  echo "URTEIL  Das Feld fehlt wirklich. Deploy prüfen, nicht FLS."
  exit 1
fi
echo "1. Existenz      ja  (${EX#*,})"

# ---- 2. Rechte -------------------------------------------------------------
PERM=$(q "SELECT Parent.IsOwnedByProfile, Parent.Name, Parent.Profile.Name, PermissionsRead, PermissionsEdit \
          FROM FieldPermissions WHERE SobjectType='$OBJ' AND Field='$OBJ.$FLD'")
if [ -z "$PERM" ]; then
  case "$FLD" in
    *__c)
      echo "2. Rechte        KEINE — kein Profil und kein Permission Set gewährt Zugriff."
      echo
      echo "URTEIL  Feld vorhanden, aber für ALLE unsichtbar (auch Sys-Admin)."
      echo "        fieldPermissions-Eintrag in ein Permission Set aufnehmen und deployen."
      exit 1 ;;
    *)
      echo "2. Rechte        keine FieldPermissions-Zeilen — bei Standardfeldern normal:"
      echo "                 Pflicht- und Systemfelder sind nicht FLS-steuerbar."
      echo
      echo "URTEIL  Nicht FLS-beschränkt. Suchst Du hier, suchst Du falsch."
      exit 0 ;;
  esac
fi
NPROF=$(echo "$PERM" | awk -F, '$1=="true"' | grep -c .)
echo "2. Rechte        gewährt durch:"
echo "$PERM" | awk -F, '$1=="false"' | while IFS=, read -r owned name prof r w; do
  printf "                   %-32s %-14s read=%s edit=%s\n" "$name" "Permission Set" "$r" "$w"
done
if [ "$NPROF" -gt 0 ]; then
  if [ "$NPROF" -le 3 ]; then
    echo "$PERM" | awk -F, '$1=="true"' | while IFS=, read -r owned name prof r w; do
      printf "                   %-32s %-14s read=%s edit=%s\n" "$prof" "Profil" "$r" "$w"
    done
  else
    printf "                   %s Profile (Profil-FLS, keine PS-Zuweisung nötig)\n" "$NPROF"
  fi
fi

# ---- 3. Zuweisung ----------------------------------------------------------
PS_NAMES=$(echo "$PERM" | awk -F, '$1=="false"{print $2}')
if [ -z "$PS_NAMES" ]; then
  echo "3. Zuweisung     entfällt — Zugriff kommt vom Profil, nicht von einem PS."
  echo
  echo "URTEIL  Sichtbar. Sieht Dein Code das Feld trotzdem nicht, ist es nicht FLS."
  exit 0
fi

echo "3. Zuweisung"
UNASSIGNED=0; SELF=0
for PS in $PS_NAMES; do
  A=$(q "SELECT Assignee.Username FROM PermissionSetAssignment WHERE PermissionSet.Name='$PS'")
  N=$(echo "$A" | grep -c . )
  if [ "$N" -eq 0 ]; then
    printf "                   %-32s NIEMAND zugewiesen\n" "$PS"; UNASSIGNED=1
  else
    printf "                   %-32s %s Benutzer\n" "$PS" "$N"
    echo "$A" | sed 's/^/                     · /'
    echo "$A" | grep -qxF "$USER" && SELF=1
  fi
done

echo
if [ "$UNASSIGNED" = "1" ] && [ "$SELF" = "0" ]; then
  echo "URTEIL  DIE FLS-WAND. Feld und Permission Set existieren, das PS ist"
  echo "        niemandem zugewiesen. SOQL und Apex melden deshalb 'No such"
  echo "        column' auf ein vorhandenes Feld. Das ist KEIN Deploy-Problem"
  echo "        und KEIN Schema-Cache."
  echo "        sf org assign permset -n <PS> -b $USER -o $ORG"
  exit 1
elif [ "$SELF" = "0" ]; then
  echo "URTEIL  DIE FLS-WAND für Dich. Das PS ist zugewiesen, aber nicht an"
  echo "        $USER — den Benutzer, unter dem CLI und Tests laufen."
  echo "        sf org assign permset -n <PS> -b $USER -o $ORG"
  exit 1
fi
echo "URTEIL  Sichtbar für $USER. Sieht Dein Code das Feld trotzdem nicht,"
echo "        ist es nicht FLS — weiter in salesforce-deploy-diagnostics."
exit 0
