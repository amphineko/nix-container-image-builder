{ system ? builtins.currentSystem }:
let
  lock = builtins.fromJSON (builtins.readFile ../flake.lock);
  source = lock.nodes.nixpkgs.locked;
  nixpkgs = builtins.fetchTarball {
    url = "https://github.com/${source.owner}/${source.repo}/archive/${source.rev}.tar.gz";
    sha256 = source.narHash;
  };
in import nixpkgs { inherit system; }
