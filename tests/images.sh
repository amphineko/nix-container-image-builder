#!/usr/bin/env bash
set -euo pipefail

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
temporary=$(mktemp -d)
cleanup() { rm -rf -- "$temporary"; }
trap cleanup EXIT

for file in "$repo"/images/*.nix; do
  image=$(basename -- "$file" .nix)
  runtime_test="$repo/tests/$image.sh"
  [[ -x $runtime_test ]] || { printf 'missing runtime test: %s\n' "$runtime_test" >&2; exit 1; }

  "$repo/build.sh" "$file" --name "local/$image" \
    --output "$temporary/$image.docker.tar.gz" --load
  version=$(python3 "$repo/tools/docker-image-tag.py" \
    "$temporary/$image.docker.tar.gz" "local/$image")
  bash "$runtime_test" "local/$image:$version"
  "$repo/build.sh" "$file" --name "local/$image" --format oci \
    --output "$temporary/$image.oci.tar.gz"
  python3 "$repo/tests/archives.py" \
    "$temporary/$image.docker.tar.gz" "$temporary/$image.oci.tar.gz"
done
