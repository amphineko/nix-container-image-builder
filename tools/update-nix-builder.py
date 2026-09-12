#!/usr/bin/env python3
"""Update the pinned Nix builder to the newest stable same-major release."""

import json
import re
import sys
from pathlib import Path
from urllib.request import urlopen


REPOSITORY = "nixos/nix"
API_URL = f"https://hub.docker.com/v2/repositories/{REPOSITORY}/tags?page_size=100"
REFERENCE_PATTERN = re.compile(
    r"^readonly nix_image='nixos/nix:(\d+\.\d+\.\d+)@(sha256:[0-9a-f]{64})'$",
    re.MULTILINE,
)
CACHE_PATTERN = re.compile(r"^readonly cache_version='v(\d+)'$", re.MULTILINE)
VERSION_PATTERN = re.compile(r"\d+\.\d+\.\d+")


def stable_tags():
    url = API_URL
    pages = 0
    while url and pages < 10:
        with urlopen(url, timeout=30) as response:
            payload = json.load(response)
        for tag in payload["results"]:
            if VERSION_PATTERN.fullmatch(tag["name"]):
                yield tag
        url = payload.get("next")
        pages += 1


def main():
    config_path = Path(__file__).resolve().parents[1] / "nix" / "builder.env"
    config = config_path.read_text()
    reference_match = REFERENCE_PATTERN.search(config)
    cache_match = CACHE_PATTERN.search(config)
    if reference_match is None or cache_match is None:
        sys.exit("nix/builder.env has an unexpected format")

    current_version = reference_match.group(1)
    current_major = int(current_version.split(".", 1)[0])
    candidates = [
        tag
        for tag in stable_tags()
        if int(tag["name"].split(".", 1)[0]) == current_major
        and {image["architecture"] for image in tag["images"] if image["os"] == "linux"}
        >= {"amd64", "arm64"}
    ]
    if not candidates:
        sys.exit(f"no stable multi-platform Nix {current_major}.x tags found")

    latest = max(candidates, key=lambda tag: tuple(map(int, tag["name"].split("."))))
    digest = latest["digest"]
    if not re.fullmatch(r"sha256:[0-9a-f]{64}", digest):
        sys.exit(f"unexpected digest for Nix {latest['name']}: {digest}")

    old_reference = f"{REPOSITORY}:{current_version}@{reference_match.group(2)}"
    new_reference = f"{REPOSITORY}:{latest['name']}@{digest}"
    if old_reference != new_reference:
        config = REFERENCE_PATTERN.sub(f"readonly nix_image='{new_reference}'", config, count=1)
        next_cache = int(cache_match.group(1)) + 1
        config = CACHE_PATTERN.sub(f"readonly cache_version='v{next_cache}'", config, count=1)
        config_path.write_text(config)

    print(f"{old_reference} -> {new_reference}")


if __name__ == "__main__":
    main()
