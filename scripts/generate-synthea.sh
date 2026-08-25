#!/usr/bin/env bash
# Regenerate dataset. Run once

set -euo pipefail

POPULATION="${1:-18}"
STATE="${2:-Massachusetts}"
OUT="$(cd "$(dirname "$0")/.." && pwd)/data/synthea"
WORK="$(mktemp -d)"

# Run Synthea in a container (for avoid jdk install)
command -v docker >/dev/null || { echo "Synthea requires docker to run"; exit 1; }

echo "Downloading synthea-with-dependencies.jar"
curl -sSL -o "$WORK/synthea.jar" https://github.com/synthetichealth/synthea/releases/download/master-branch-latest/synthea-with-dependencies.jar

echo "Generating $POPULATION patients ($STATE) in NDJSON"
docker run --rm --user "$(id -u):$(id -g)" -v "$WORK:/work" -w /work eclipse-temurin:17-jre \
  java -jar synthea.jar -p "$POPULATION" -a 25-75 \
    --generate.only_alive_patients true --exporter.years_of_history 3 \
    --exporter.baseDirectory /work/out --exporter.fhir.export true --exporter.fhir.bulk_data true --exporter.hospital.fhir.export false --exporter.practitioner.fhir.export false "$STATE"

mkdir -p "$OUT"
rm -f "$OUT"/*.ndjson

# Keep only the resource types exposes
for type in Patient Condition Observation MedicationRequest AllergyIntolerance Encounter Immunization Procedure; do
  src="$WORK/out/fhir/$type.ndjson"
  [ -f "$src" ] && cp "$src" "$OUT/$type.ndjson" && echo "  $type: $(wc -l < "$src") resources"
done

[ -n "$(ls -A "$OUT"/*.ndjson 2>/dev/null)" ] || { echo "No NDJSON produced, check $WORK/out"; exit 1; }

# Synthea points at Practitioner/Location/Organization with conditional references, which the IRIS FHIR server rejects on create.
# Without this - Encounter, MedicationRequest, Immunization and Procedure all fail to load..
echo "Fix conditional references"
python3 "$(dirname "$0")/strip-conditional-refs.py" "$OUT"

rm -rf "$WORK"
echo
echo "Written to $OUT"
du -sh "$OUT"
echo "Dont forget commit these files"