{ pkgs, ... }: pkgs.writers.writeBashBin "nix-dist-version-bump" ''

# -u: Treat unset variables and parameters other than the special parameters "@"
#     and "*" as an error when performing parameter expansion.  If expansion is
#     attempted on an unset variable or parameter, the shell prints an error
#     message, and, if not interactive, exits with a non-zero status.

# -o pipefail: If set, the return value of a pipeline is the value of the last
#              (rightmost) command to exit with a non-zero status, or zero if
#              all commands in the pipeline exit successfully.  This option is
#              disabled by default.

builtin set -u -o pipefail

# nullglob: If set, bash allows patterns which match no files to expand to a
#           null string, rather than themselves.
# dotglob:  If set, bash includes filenames beginning with a . in the results of
#           pathname expansion.
builtin shopt -s nullglob
builtin shopt -s dotglob

ls=${pkgs.coreutils}/bin/ls
sort=${pkgs.coreutils}/bin/sort
tail=${pkgs.coreutils}/bin/tail

dists=~/rc/nixpkgs/dists

for argv in "$@"; do
  if [ "x/" != "x${argv:0:1}" ] && [ ! -e "$argv" ] && \
       [ -e "$dists/$argv" ]; then
    argv="$( $ls -1 "$dists/$argv/"*.nix | $sort --version-sort \
                                         | $tail --lines 1 )"
  fi

  if [[ "$argv" =~ ^(.*)/([0-9.]+)(-([0-9]+))?.nix$ ]]; then
    p=$(("''${BASH_REMATCH[4]:-0}"+1))
    builtin echo "$argv ''${BASH_REMATCH[1]}/''${BASH_REMATCH[2]}-$p.nix"
  else
    builtin echo "no match: '$argv'" >&2
    builtin exit 2
  fi
done
''

# Local Variables:
# mode: sh
# End:
