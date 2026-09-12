# Nix Container Image Builder

Build Docker or OCI images from Nix descriptions in a cached Nix container.

## Usage

The host needs Bash, GNU coreutils, and Docker; Nix and Skopeo run inside the pinned builder image.

```sh
./build.sh images/<image>.nix
```

Options:

```text
--name NAME        Override the image name
--tag TAG          Override the image tag
--format FORMAT    docker (default) or oci
--output PATH      Set the archive path
--platform VALUE   linux/amd64 or linux/arm64
--load             Load a Docker archive into the local daemon
```

Run `./build.sh --help` for details. By default, output is written to `dist/<image>.<format>.tar.gz`. Existing files are never overwritten. A build produces one platform; cross-platform builds require Docker support for the requested platform, typically through a native worker or QEMU.

## Image descriptions

Each trusted `.nix` file receives the locked `pkgs` set and returns an attribute set:

```nix
{ pkgs }:
let
  primary = pkgs.somePackage;
in {
  name = "example";
  tag = primary.version;
  contents = [ primary /* other derivations */ ];
  config = {
    Entrypoint = [ "/path/to/program" ];
    Cmd = [ /* arguments */ ];
  };
}
```

Supported fields:

| Field | Description |
| --- | --- |
| `name` | Required image name |
| `tag` | Required image tag; normally the primary package version |
| `contents` | Derivations merged into the image root |
| `config` | OCI image configuration |
| `extraCommands` | Commands that populate the final layer |
| `fakeRootCommands` | Fakeroot commands for ownership and permissions |
| `maxLayers` | Maximum layer count; defaults to 100 |

Unknown fields fail evaluation. Default configuration values are `User = "65532:65532"`, `WorkingDir = "/"`, and `Env = [ "PATH=/bin:/sbin" ]`. A supplied `config` replaces defaults by field, so an `Env` override must include its own `PATH` when required.

Input files must be inside this repository. They can reference other repository files because the tree is mounted read-only at `/src`. Nix descriptions are executable build code and should be reviewed before use.

## Reproducibility

`nix/image.nix` uses `dockerTools.buildLayeredImage` to collect runtime closures. `flake.lock` pins nixpkgs, and the Nix builder image is pinned by digest. OCI output is converted inside the container with Skopeo. Image timestamps and OCI archive metadata are normalized.

The image archive is streamed from the container into a temporary host file and published atomically. `--load` then loads a Docker archive into the daemon. Builds do not require a privileged container or a Docker socket inside the builder.

## Cache

Docker volumes persist the Nix store, its database, and fetcher metadata across builds. Cache names include a schema version and platform selection so incompatible Nix runtimes cannot share a store. The first build seeds `/nix` from the builder image; subsequent builds reuse downloaded and built paths.

The cache is managed with standard `docker volume` commands. When changing the pinned Nix image, increment `cache_version` in `nix/builder.env` to create a fresh store.

Update nixpkgs with a local Nix installation:

```sh
nix --extra-experimental-features 'nix-command flakes' flake update nixpkgs
```

Review the lock-file change and rebuild the affected images.

## Automation

GitHub Actions builds and tests every image matrix entry on pull requests. Updates to `master` repeat those checks and publish the image description's version tag together with `sha-<commit>` and `latest` aliases to `ghcr.io/<owner>/<repository>/<image>` using the repository's `GITHUB_TOKEN`.

A weekly workflow checks the pinned Nix builder and nixpkgs separately. It validates every image before opening or refreshing dependency pull requests, and can also be run manually from the Actions tab.
