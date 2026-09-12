{
  file,
  system ? builtins.currentSystem,
  pkgs ? import ./pkgs.nix { inherit system; },
}:
let
  description = import (builtins.toPath file) { inherit pkgs; };
in {
  inherit (description) name tag;
}
