{
  description = "base-scripts setup for nix";

  inputs = {
    nixpkgs.url     = github:NixOS/nixpkgs/d9d87c51; # nixos-24.11 2024-12-11
    flake-utils.url = github:numtide/flake-utils/c0e246b9;
    myPkgs          = {
      url    = github:sixears/nix-pkgs/r0.0.13.0;
#      url    = path:/home/martyn/nix/pkgs/;
      inputs = { nixpkgs.follows = "nixpkgs"; };
    };
    hpkgs1          = {
      url    = github:sixears/hpkgs1/r0.0.41.0;
#      inputs = { nixpkgs.follows = "nixpkgs"; };
    };
    bashHeader      = {
      url    = github:sixears/bash-header/r0.0.3.0;
      inputs = { nixpkgs.follows = "nixpkgs"; };
    };
  };

  outputs = { self, nixpkgs, flake-utils, hpkgs1, bashHeader, myPkgs }:
    flake-utils.lib.eachSystem [ "x86_64-linux" ] (system:
      let
        pkgs        = nixpkgs.legacyPackages.${system};
        my-pkgs     = myPkgs.packages.${system};
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
            inherit (my-pkgs) paths path-edit;
          });
        });
}
