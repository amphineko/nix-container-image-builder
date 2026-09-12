#!/usr/bin/env python3
"""Render before-and-after image versions as a Markdown table."""

import sys
from pathlib import Path


def read_versions(path):
    versions = {}
    for line_number, line in enumerate(Path(path).read_text().splitlines(), 1):
        fields = line.split("\t")
        if len(fields) != 2 or not all(fields):
            sys.exit(f"{path}:{line_number}: expected IMAGE<TAB>VERSION")
        name, version = fields
        if name in versions:
            sys.exit(f"{path}:{line_number}: duplicate image {name}")
        versions[name] = version
    return versions


if len(sys.argv) != 3:
    sys.exit("Usage: version-report.py BEFORE.tsv AFTER.tsv")

before = read_versions(sys.argv[1])
after = read_versions(sys.argv[2])
if before.keys() != after.keys():
    sys.exit("image sets differ before and after the update")

print("| Image | Before | After |")
print("| --- | --- | --- |")
for name in sorted(before):
    print(f"| `{name}` | `{before[name]}` | `{after[name]}` |")
