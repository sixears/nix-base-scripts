{ pkgs ? import <nixpkgs> {} }:

let
  libraries = with pkgs.haskellPackages; [ path QuickCheck split tasty
                                           tasty-hunit tasty-quickcheck ];
  src       = import ./path-edit.nix {};
in
  pkgs.writers.writeHaskellBin "path-edit" { inherit libraries; } src
