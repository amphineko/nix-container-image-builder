#!/usr/bin/env python3
"""Print the single tag for an expected repository in a Docker archive."""

import json
import re
import sys
import tarfile


if len(sys.argv) != 3:
    sys.exit("Usage: docker-image-tag.py DOCKER.tar.gz REPOSITORY")

archive_path, expected_repository = sys.argv[1:]

with tarfile.open(archive_path, "r:gz") as archive:
    member = archive.extractfile("manifest.json")
    if member is None:
        sys.exit("manifest.json is missing from Docker archive")
    manifests = json.load(member)

if len(manifests) != 1:
    sys.exit(f"expected one image manifest, found {len(manifests)}")

references = manifests[0].get("RepoTags", [])
if len(references) != 1:
    sys.exit(f"expected one image reference, found {len(references)}")

repository, separator, tag = references[0].rpartition(":")
if not separator or repository != expected_repository:
    sys.exit(f"unexpected image reference: {references[0]}")
if not re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}", tag):
    sys.exit(f"invalid image tag: {tag}")

print(tag)
