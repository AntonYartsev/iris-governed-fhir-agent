#!/usr/bin/env python3
"""
Drop conditional references from Synthea NDJSON.
Usage: strip-conditional-refs.py DIR
"""

import json
import pathlib
import sys


def clean(node):
    changed = 0
    if isinstance(node, dict):
        ref = node.get("reference")
        if isinstance(ref, str) and "?" in ref:
            del node["reference"]
            changed += 1
        for value in node.values():
            changed += clean(value)
    elif isinstance(node, list):
        for item in node:
            changed += clean(item)
    return changed


def clean_file(path):
    out, changed = [], 0
    for line in path.read_text().splitlines():
        if not line.strip():
            continue
        resource = json.loads(line)
        changed += clean(resource)
        out.append(json.dumps(resource))
    path.write_text("\n".join(out) + "\n")
    return changed


def self_check():
    doc = {
        "resourceType": "Procedure",
        "subject": {"reference": "Patient/abc"},
        "location": {
            "reference": "Location?identifier=https://x|1",
            "display": "Clinic",
        },
        "performer": [{"actor": {"reference": "Practitioner?identifier=y|2"}}],
    }
    assert clean(doc) == 2, "both conditional references are removed"
    assert doc["subject"]["reference"] == "Patient/abc", "literal reference kept"
    assert "reference" not in doc["location"], "conditional reference dropped"
    assert doc["location"]["display"] == "Clinic", "sibling fields survive"
    assert "reference" not in doc["performer"][0]["actor"], "nested list handled"
    assert clean(doc) == 0, "second pass is a no-op"


if __name__ == "__main__":
    self_check()
    directory = pathlib.Path(sys.argv[1])
    for ndjson in sorted(directory.glob("*.ndjson")):
        n = clean_file(ndjson)
        print(f"  {ndjson.name}: {n} references removed")
