{ pkgs, path-edit }: pkgs.writers.writeBashBin "paths" ''

set -eu -o pipefail
PATH=/dev/null

: ''${USER:=$($id --user --name)}

path_edit=${path-edit}/bin/path-edit

paths=( ~
        ~/.nix-profile ~/.nix-profiles/*
        /etc/profiles/per-user/$USER
        /run/wrappers /run/current-system/sw /usr
      )
# PATH=/bin

case $# in
  0) $path_edit -C prepend "''${paths[@]}" ;;
  *) eval $( $path_edit -C prepend "''${paths[@]}" )
     exec "$@" ;;
esac

# Local Variables:
# mode: sh
# End:
''
