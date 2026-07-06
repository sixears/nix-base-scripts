{
  description = "base-scripts setup for nix";

  inputs = {
    nixpkgs.url     = github:NixOS/nixpkgs/667d5cf1; # nixos-26.05 2026-06-26
    flake-utils.url = github:numtide/flake-utils/c0e246b9;
    myPkgs          = {
      url    = github:sixears/nix-pkgs/r0.0.16.0;
#      url    = path:/home/martyn/nix/pkgs/;
      inputs = { nixpkgs.follows = "nixpkgs"; };
    };
    hpkgs1          = {
      url    = github:sixears/hpkgs1/r0.0.55.0;
#      inputs = { nixpkgs.follows = "nixpkgs"; };
    };
    bashHeader      = {
      url    = github:sixears/bash-header/r0.0.7.0;
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

        termfake   = let src = pkgs.lib.strings.fileContents ./src/termfake.py;
                     in  pkgs.writers.writePython3Bin "termfake" {} src;
      in
        {
          packages = flake-utils.lib.flattenTree (with pkgs; rec {

            # general utilities ------------------------------------------------

            replace       = import ./src/replace.nix  { inherit pkgs; };

            # nix utilities ----------------------------------------------------

            nix-dist-version-bump  =
              import ./src/nix-dist-version-bump.nix { inherit pkgs; };

            nix-upgrade =
              import ./src/nix-upgrade.nix { inherit pkgs replace bash-header
                                                     nix-dist-version-bump; };

            nix-clone-revision =
              let
                src = import ./src/nix-clone-revision.nix
                             { inherit pkgs bash-header; };
              in
                pkgs.writers.writeBashBin "nix-clone-revision" src;

##            prompt = let
##                       src = import ./src/prompt.nix
##                                    { inherit pkgs bash-header; };
##                     in
##                       pkgs.writers.writeBashBin "prompt" src;

            inherit hix;
            inherit (my-pkgs) paths path-edit;

            flasher = let src = import ./src/flasher.nix
                                       { inherit pkgs termfake; };
                      in  pkgs.writers.writeBashBin "flasher" src;

            echot   = let src = import ./src/echot.nix
                                       { inherit pkgs bash-header; };
                      in  pkgs.writers.writeBashBin "echot" src;

            bash-preexec = import ./src/bash-preexec.nix { inherit pkgs; };
          });
        });
}
