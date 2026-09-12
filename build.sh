#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./build.sh FILE.nix [OPTIONS]

Build a repository-local Nix image description in a cached Nix container.
No host Nix or Skopeo installation is required.

  --name NAME        Override the image repository name
  --tag TAG          Override the image tag
  --format FORMAT    docker (default) or oci; both are gzip-compressed archives
  --output PATH      Destination (default: dist/<file>.<format>.tar.gz)
  --platform VALUE   linux/amd64 or linux/arm64 (default: Docker platform)
  --load             Load the Docker archive into the local Docker daemon
  -h, --help         Show this help

Existing output files are never overwritten. Build logs go to stderr;
the absolute output path is printed to stdout on success.
EOF
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

require_value() {
  [[ $# -ge 2 && -n $2 && $2 != --* ]] || die "$1 requires a value"
}

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
readonly repo_dir
# shellcheck source=nix/builder.env
source "$repo_dir/nix/builder.env"

input_arg='' image_name='' image_tag='' output_arg='' platform=''
image_format='docker' load_image='false'
input_file='' input_relative=''
output_file='' output_dir='' temporary_output=''

parse_arguments() {
  while (($#)); do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      --name) require_value "$@"; image_name=$2; shift 2 ;;
      --tag) require_value "$@"; image_tag=$2; shift 2 ;;
      --format) require_value "$@"; image_format=$2; shift 2 ;;
      --output) require_value "$@"; output_arg=$2; shift 2 ;;
      --platform) require_value "$@"; platform=$2; shift 2 ;;
      --load) load_image='true'; shift ;;
      -*) die "unknown option: $1" ;;
      *)
        [[ -z $input_arg ]] || die 'only one Nix file may be supplied'
        input_arg=$1
        shift
        ;;
    esac
  done
}

validate_arguments() {
  local requested_platform

  [[ -n $input_arg ]] || { usage >&2; exit 1; }
  [[ $image_format == docker || $image_format == oci ]] ||
    die '--format must be docker or oci'
  [[ $load_image == false || $image_format == docker ]] ||
    die '--load requires --format docker'
  requested_platform=${platform:-${DOCKER_DEFAULT_PLATFORM:-}}
  [[ -z $requested_platform || $requested_platform == linux/amd64 || $requested_platform == linux/arm64 ]] ||
    die '--platform must be linux/amd64 or linux/arm64 (one platform per build)'
  [[ -z $image_tag || $image_tag =~ ^[a-zA-Z0-9_][a-zA-Z0-9_.-]{0,127}$ ]] ||
    die 'invalid image tag'
}

check_dependencies() {
  command -v realpath >/dev/null || die 'realpath is required'
  command -v docker >/dev/null || die 'Docker is required'
}

resolve_input() {
  [[ -f $input_arg ]] || die "Nix file not found: $input_arg"
  input_file=$(realpath -- "$input_arg")
  [[ $input_file == "$repo_dir/"* && $input_file == *.nix ]] ||
    die 'input must be a .nix file inside this repository'

  input_relative=${input_file#"$repo_dir/"}
  case "$input_relative" in
    dist/*|tests/*|.git/*) die 'input is excluded from the build mount' ;;
  esac
  [[ $repo_dir != *','* && $repo_dir != *$'\n'* ]] ||
    die 'repository path cannot contain commas or newlines'
  [[ -f $repo_dir/flake.lock ]] ||
    die 'flake.lock is missing; see README for dependency updates'
}

resolve_output() {
  local basename requested

  requested=$output_arg
  if [[ -z $requested ]]; then
    basename=$(basename -- "$input_file" .nix)
    requested="$repo_dir/dist/$basename.$image_format.tar.gz"
  fi

  [[ $requested != */ ]] || die '--output must name a file'
  output_dir=$(dirname -- "$requested")
  mkdir -p -- "$output_dir"
  output_dir=$(cd -- "$output_dir" && pwd -P)
  output_file="$output_dir/$(basename -- "$requested")"
  [[ ! -e $output_file && ! -L $output_file ]] ||
    die "output already exists: $output_file"
}

cleanup() {
  [[ -z $temporary_output ]] || rm -f -- "$temporary_output"
}

create_temporary_output() {
  temporary_output=$(mktemp "$output_dir/.image-build.XXXXXXXX")
  trap cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
}

build_image() {
  local cache_platform fetcher_volume store_volume
  local -a run_args

  cache_platform=${platform:-${DOCKER_DEFAULT_PLATFORM:-default}}
  cache_platform=${cache_platform//\//-}
  store_volume="nix-container-image-builder-store-$cache_version-$cache_platform"
  fetcher_volume="nix-container-image-builder-fetcher-$cache_version-$cache_platform"

  run_args=(
    run --rm
    --mount "type=volume,src=$store_volume,dst=/nix"
    --mount "type=volume,src=$fetcher_volume,dst=/root/.cache/nix"
    --mount "type=bind,src=$repo_dir,dst=/src,readonly"
  )
  [[ -z $platform ]] || run_args+=(--platform "$platform")
  run_args+=(
    "$nix_image" sh -eu -c '
      result=$(nix-build /src/nix/image.nix --no-out-link \
        --option sandbox false \
        --argstr file "/src/$1" \
        --argstr name "$2" \
        --argstr tag "$3" \
        --argstr format "$4")
      exec cat "$result"
    ' sh "$input_relative" "$image_name" "$image_tag" "$image_format"
  )

  docker "${run_args[@]}" >"$temporary_output"
  [[ -s $temporary_output ]] || die 'builder returned an empty image archive'
  chmod 0644 "$temporary_output"
}

publish_image() {
  # A same-filesystem hard link publishes atomically and rejects existing paths.
  ln -T -- "$temporary_output" "$output_file"
  [[ $load_image == false ]] || docker load --input "$output_file" >&2
  printf '%s\n' "$output_file"
}

main() {
  parse_arguments "$@"
  validate_arguments
  check_dependencies
  resolve_input
  resolve_output
  create_temporary_output
  build_image
  publish_image
}

main "$@"
