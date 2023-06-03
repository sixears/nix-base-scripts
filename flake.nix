{
  description = "base-scripts setup for nix";

  inputs = {
    nixpkgs.url     = github:nixos/nixpkgs/dcf6d202; # 2023-04-17
#    nixpkgs.url     = github:nixos/nixpkgs/be44bf67; # nixos-22.05 2022-10-15
    flake-utils.url = github:numtide/flake-utils/c0e246b9;
    hpkgs1.url      = github:sixears/hpkgs1/r0.0.9.0;
    bashHeader      = {
      url    = github:sixears/bash-header/5206b087;
      inputs = { nixpkgs.follows = "nixpkgs"; };
    };
  };

  outputs = { self, nixpkgs, flake-utils, hpkgs1, bashHeader }:
    flake-utils.lib.eachSystem [ "x86_64-linux" ] (system:
      let
        pkgs        = nixpkgs.legacyPackages.${system};
        hpkgs       = hpkgs1.packages.${system};
        hlib        = hpkgs1.lib.${system};
        mkHBin      = hlib.mkHBin;
        bash-header = bashHeader.packages.${system}.bash-header;
      in
        {
          packages = flake-utils.lib.flattenTree (with pkgs; rec {
            # general utilities ------------------------------------------------

            replace       = import ./src/replace.nix  { inherit pkgs; };

            # nix utilities ----------------------------------------------------

            nix-dist-version-bump  =
              import ./src/nix-dist-version-bump.nix { inherit pkgs; };

            nix-upgrade            =
              import ./src/nix-upgrade.nix { inherit pkgs replace bash-header
                                                     nix-dist-version-bump; };

            nix-clone-revision     =
              let
                src = import ./src/nix-clone-revision.nix
                             { inherit pkgs bash-header; };
              in
                pkgs.writers.writeBashBin "nix-clone-revision" src;

            profile-members =
              (mkHBin "profile-members" ./src/profile-members.hs {
                libs = p: with p; [ stdmain ];
              }).pkg;

            nyx       = import ./src/nyx.nix
                               { inherit pkgs bash-header profile-members; };

            path-edit              =
              import ./src/path-edit { inherit pkgs; };
          });
        });
}
