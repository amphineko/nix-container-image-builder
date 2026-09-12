#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
readonly repo_dir
# shellcheck source=../nix/builder.env
source "$repo_dir/nix/builder.env"

uid=$(id -u)
gid=$(id -g)

docker run --rm \
  --mount "type=volume,src=nix-container-image-builder-store-$cache_version-default,dst=/nix" \
  --mount "type=volume,src=nix-container-image-builder-fetcher-$cache_version-default,dst=/root/.cache/nix" \
  --mount "type=bind,src=$repo_dir,dst=/src" \
  --workdir /src \
  "$nix_image" sh -eu -c '
    nix --extra-experimental-features "nix-command flakes" flake update nixpkgs
    chown "$1:$2" flake.lock
  ' sh "$uid" "$gid"
