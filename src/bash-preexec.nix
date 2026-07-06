# copied and edited from /local/nixpkgs/nixpkgs/pkgs/by-name/ba/bash-preexec
# to allow an update from 2022
{ pkgs }:

let stdenvNoCC      = pkgs.stdenvNoCC;
    lib             = pkgs.lib;
    fetchFromGitHub = pkgs.fetchFromGitHub;
    bats            = pkgs.bats;
in

let
  version = "2025-05-28";
  rev    = "e8e9024d4d101a69016169e46f5d75df3fdb7e32";
  sha256 = "sha256-OiMDwZpw+VajrdFM/ar1G8d6jensA/Xxyy3m9Fh+q5E=";
in
stdenvNoCC.mkDerivation {
  pname = "bash-preexec";
  inherit version;

  src = fetchFromGitHub {
    owner = "rcaloras";
    repo = "bash-preexec";
    inherit rev sha256;
  };

  nativeCheckInputs = [ bats ];

  dontConfigure = true;
  doCheck = true;
  dontBuild = true;

  patchPhase = ''
    # Needed since the tests expect that HISTCONTROL is set.
    sed -i '/setup()/a HISTCONTROL=""' test/bash-preexec.bats

    # Skip tests failing with Bats 1.5.0.
    # See https://github.com/rcaloras/bash-preexec/issues/121
    sed -i '/^@test.*IFS/,/^}/d' test/bash-preexec.bats
  '';

  checkPhase = ''
    bats test
  '';

  installPhase = ''
    install -Dm755 $src/bash-preexec.sh $out/share/bash/bash-preexec.sh
  '';

  meta = with lib; {
    description = "preexec and precmd functions for Bash just like Zsh";
    license = licenses.mit;
    homepage = "https://github.com/rcaloras/bash-preexec";
    maintainers = [
      maintainers.hawkw
      maintainers.rycee
    ];
    platforms = platforms.unix;
  };
}
