#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
readonly repo_dir
# shellcheck source=../nix/builder.env
source "$repo_dir/nix/builder.env"

command -v docker >/dev/null || { printf 'error: Docker is required\n' >&2; exit 1; }
command -v jq >/dev/null || { printf 'error: jq is required\n' >&2; exit 1; }

for file in "$repo_dir"/images/*.nix; do
  relative=${file#"$repo_dir/"}
  metadata=$(docker run --rm \
    --mount "type=volume,src=nix-container-image-builder-store-$cache_version-default,dst=/nix" \
    --mount "type=volume,src=nix-container-image-builder-fetcher-$cache_version-default,dst=/root/.cache/nix" \
    --mount "type=bind,src=$repo_dir,dst=/src,readonly" \
    "$nix_image" sh -eu -c '
      exec nix-instantiate --eval --strict --json /src/nix/metadata.nix \
        --argstr file "/src/$1"
    ' sh "$relative")
  printf '%s\t%s\n' \
    "$(printf '%s' "$metadata" | jq -er .name)" \
    "$(printf '%s' "$metadata" | jq -er .tag)"
done
