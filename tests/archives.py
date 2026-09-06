#!/usr/bin/env python3
"""Validate Docker/OCI archives built from the same description and arguments."""
import gzip
import hashlib
import json
import sys
import tarfile
from datetime import datetime


def digest(data):
    return "sha256:" + hashlib.sha256(data).hexdigest()


def read(archive, name):
    # Read archive members in place; never extract paths into the filesystem.
    member = archive.extractfile(name)
    assert member is not None, name
    return member.read()


def blob(archive, descriptor):
    algorithm, value = descriptor["digest"].split(":", 1)
    assert algorithm == "sha256"
    data = read(archive, f"./blobs/{algorithm}/{value}")
    assert len(data) == descriptor["size"]
    assert digest(data) == descriptor["digest"]
    return data


if len(sys.argv) != 3:
    sys.exit("Usage: python3 tests/archives.py DOCKER.tar.gz OCI.tar.gz")

with tarfile.open(sys.argv[1], "r:gz") as docker:
    manifests = json.loads(read(docker, "manifest.json"))
    assert len(manifests) == 1
    manifest = manifests[0]
    docker_config = json.loads(read(docker, manifest["Config"]))
    assert len(manifest["Layers"]) == len(docker_config["rootfs"]["diff_ids"])
    for layer, diff_id in zip(manifest["Layers"], docker_config["rootfs"]["diff_ids"]):
        assert digest(read(docker, layer)) == diff_id

with tarfile.open(sys.argv[2], "r:gz") as oci:
    assert json.loads(read(oci, "./oci-layout"))["imageLayoutVersion"] == "1.0.0"
    index = json.loads(read(oci, "./index.json"))
    assert len(index["manifests"]) == 1
    descriptor = index["manifests"][0]
    assert descriptor["mediaType"] == "application/vnd.oci.image.manifest.v1+json"
    manifest = json.loads(blob(oci, descriptor))
    oci_config = json.loads(blob(oci, manifest["config"]))
    assert oci_config["config"] == docker_config["config"]
    assert oci_config["rootfs"] == docker_config["rootfs"]
    assert oci_config["architecture"] == docker_config["architecture"]
    assert oci_config["os"] == docker_config["os"] == "linux"
    # Skopeo normalizes the UTC suffix from +00:00 to Z.
    assert datetime.fromisoformat(oci_config["created"].replace("Z", "+00:00")) == \
        datetime.fromisoformat(docker_config["created"].replace("Z", "+00:00"))
    assert len(manifest["layers"]) == len(oci_config["rootfs"]["diff_ids"])
    for layer, diff_id in zip(manifest["layers"], oci_config["rootfs"]["diff_ids"]):
        assert layer["mediaType"] == "application/vnd.oci.image.layer.v1.tar+gzip"
        assert digest(gzip.decompress(blob(oci, layer))) == diff_id

print("Docker/OCI metadata, blob hashes, and all filesystem layer digests match")
