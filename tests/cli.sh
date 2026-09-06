#!/usr/bin/env bash
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "$repo"

reject() {
  if ./build.sh "$@" >/dev/null 2>&1; then
    printf 'unexpected success: %s\n' "$*" >&2
    exit 1
  fi
}

bash -n build.sh
./build.sh --help >/dev/null
reject
reject --unknown
reject images/chrony.nix --tag
reject images/chrony.nix --format invalid
reject images/chrony.nix --format oci --load
reject images/chrony.nix --platform linux/amd64,linux/arm64
DOCKER_DEFAULT_PLATFORM=linux/riscv64 reject images/chrony.nix
reject images/chrony.nix --tag 'bad tag'
reject images/chrony.nix images/chrony.nix
reject /etc/passwd
reject images/does-not-exist.nix
reject tests/../README.md
printf 'CLI validation passed\n'
