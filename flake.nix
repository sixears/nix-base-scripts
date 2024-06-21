{
  description = "base-scripts setup for nix";

  inputs = {
    nixpkgs.url     = github:NixOS/nixpkgs/938aa157; # nixos-24.05 2024-06-20
    flake-utils.url = github:numtide/flake-utils/c0e246b9;
    hpkgs1          = {
      url    = github:sixears/hpkgs1/r0.0.24.0;
#      inputs = { nixpkgs.follows = "nixpkgs"; };
    };
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

        hix         = hpkgs.hix;
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

            prompt     = let
                           src = import ./src/prompt.nix
                                        { inherit pkgs bash-header; };
                         in
                           pkgs.writers.writeBashBin "prompt" src;

            inherit hix;

            path-edit = (mkHBin "path-edit" ./src/path-edit.hs {
              libs = p: with p; with hlib.hpkgs;
                [ directory path QuickCheck split tasty tasty-hunit
                  tasty-quickcheck ];
            }).pkg;
            paths     = import ./src/paths.nix { inherit pkgs path-edit; };
          });
        });
}
