{
  file,
  system ? builtins.currentSystem,
  pkgs ? import ./pkgs.nix { inherit system; },
  name ? "",
  tag ? "",
  format ? "docker",
}:
let
  # Destructuring rejects unknown top-level fields instead of ignoring typos.
  makeImage = {
    name,
    tag,
    contents ? [],
    config ? {},
    extraCommands ? "",
    fakeRootCommands ? "",
    maxLayers ? 100,
  }: pkgs.dockerTools.buildLayeredImage {
    inherit name tag extraCommands fakeRootCommands maxLayers;
    created = "1970-01-01T00:00:01Z";
    contents = pkgs.buildEnv {
      name = "image-root";
      paths = contents;
      pathsToLink = [ "/" ];
    };
    config = {
      User = "65532:65532";
      WorkingDir = "/";
      Env = [ "PATH=/bin:/sbin" ];
    } // config;
  };
  description = import (builtins.toPath file) { inherit pkgs; };
  resolved = description
    // pkgs.lib.optionalAttrs (name != "") { inherit name; }
    // pkgs.lib.optionalAttrs (tag != "") { inherit tag; };
  dockerImage = makeImage resolved;
in
assert pkgs.lib.assertMsg (builtins.elem format [ "docker" "oci" ])
  "format must be docker or oci";
if format == "docker" then dockerImage else
pkgs.runCommand "oci-image.tar.gz" {
  nativeBuildInputs = [ pkgs.skopeo pkgs.gnutar pkgs.gzip ];
} ''
  # No daemon or registry credentials are needed for a local conversion.
  skopeo --insecure-policy copy --format oci \
    docker-archive:${dockerImage} \
    oci:layout:${pkgs.lib.escapeShellArg resolved.tag}
  # Normalize the outer archive too; Nix fixes the inner image timestamp.
  tar --sort=name --mtime=@1 --owner=0 --group=0 --numeric-owner \
    -C layout -cf - . | gzip -n > "$out"
''
