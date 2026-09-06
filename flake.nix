{
  description = "Containerized Nix builder for Docker and OCI images";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
    in {
      packages = nixpkgs.lib.genAttrs systems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          chrony = import ./nix/image.nix {
            inherit pkgs system;
            file = "${self}/images/chrony.nix";
          };
        in {
          inherit chrony;
          default = chrony;
        });
    };
}
