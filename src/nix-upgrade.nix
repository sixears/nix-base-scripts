{ pkgs, bash-header, nix-dist-version-bump, replace }: pkgs.writers.writeBashBin "nix-upgrade" ''

set -u -o pipefail -o noclobber;
shopt -s nullglob
shopt -s nullglob
shopt -s dotglob

source ${bash-header}

Cmd[nix-dist-version-bump]=${nix-dist-version-bump}/bin/nix-dist-version-bump
Cmd[replace]=${replace}/bin/replace

# List of pkgs to consider upgrading.  By default, look at all packages
# (signified by an empty list).
declare -a UpgradePkgs=()

# ------------------------------------------------------------------------------

# Find the old version of $1, write it to a var named $2
old_pkg_version() {
  local pkg="$1" varname="$2"

  local oldv_plus_nix oldv_plus oldv
  oldv_plus_nix="$(gocmdnodryrun 10 ls -1 "$DISTS/$pkg"/*.nix    \
                        | gocmdnodryrun 11 sort --version-sort   \
                        | gocmdnodryrun 12 tail --lines 2        \
                        | gocmdnodryrun 13 head --lines 1        )"
  check_ 'ls | sort | tail | head'

  oldv_plus="$(gocmdnodryrun 14 basename "$oldv_plus_nix" .nix)"
  check_ basename
  oldv="''${oldv_plus%-*}"
  printf -v "$varname" %s "''${oldv//./-}"
}

# --------------------------------------

# Find the old version of $1, write it to a var named $2
new_pkg_version() {
  local pkg="$1" varname="$2"

  local newv_nix newv
  newv_nix="$(gocmdnodryrun 15 ls -1 "$DISTS/$pkg"/*.nix \
                | gocmdnodryrun 16 sort --version-sort   \
                | gocmdnodryrun 17 tail --lines 1        )"
  newv="$(gocmdnodryrun 18 basename "$newv_nix" .nix)"; check_ basename
  printf -v "$varname" %s "''${newv//./-}"
}

# --------------------------------------

main() {
  local pkg old_v new_v

  if [[ -z ''${1:-} ]]; then
    pkg="$(gocmdnodryrun 24 basename "$(pwd)")"
  elif [[ $1 =~ ^[a-z][a-z0-9-]+[a-z0-9]$ ]]; then
    pkg="$1"
  else
    dieusage "arg#1 should be a package name"
  fi

  if [[ -n ''${2:-} ]]; then
    old_v="$2"
  else
    old_pkg_version "$pkg" old_v
  fi

  if [[ $old_v =~ ^([0-9]+)[-.]([0-9]+)[-.]([0-9]+)[-.]([0-9]+)$ ]]; then
    old_v="''${BASH_REMATCH[1]}-''${BASH_REMATCH[2]}"
    old_v+="-''${BASH_REMATCH[3]}-''${BASH_REMATCH[4]}"
  else
    dieusage "old_version should be a package version (got '$old_v')"
  fi

  if [[ -z ''${3:-} ]]; then
    new_pkg_version "$pkg" new_v
  else
    new_v="$3"
  fi

  if [[ $new_v =~ ^([0-9]+)[-.]([0-9]+)[-.]([0-9]+)[-.]([0-9]+)$ ]]; then
    new_v="''${BASH_REMATCH[1]}-''${BASH_REMATCH[2]}"
    new_v+="-''${BASH_REMATCH[3]}-''${BASH_REMATCH[4]}"
  else
    dieusage "new version should be a package version (got '$new_v')"
  fi

  local upgrade_from="$pkg-$old_v"
  local upgrade_to="$pkg-$new_v"

  warn "upgrading $pkg $upgrade_from -> $upgrade_to"
  local -a ps
  if [[ 0 -eq ''${#UpgradePkgs[@]} ]]; then
    ps=($( gocmd2nodryrun 19 ls -1 "$DISTS"/*/*.nix \
             | while read d; do
                 gocmd3nodryrun 30 basename "$( gocmd3nodryrun 41 dirname "$d")"
               done \
             | gocmd2nodryrun 31 sort --unique ))
    check_ "ls $DISTS/*/*.nix | while .. basename \$(dirname d); done | sort -u"
  else
    ps=("''${UpgradePkgs[@]}")
  fi
  for p in "''${ps[@]}"; do
    ## factor this into a function ##
    local d="$DISTS/$p"
    if [[ -n $( builtin echo "$d"/*.nix ) ]]; then
      local dist_nix
      dist_nix="$( gocmdnodryrun 20 ls -1 "$d"/*.nix        \
                     | gocmdnodryrun 21 sort --version-sort \
                     | gocmdnodryrun 22 tail --lines 1      )"
      check_ 'ls | sort | tail'
      if [ 0 -ne $? ]; then
        die 3 "failed listing from $p/*.nix"
      fi

      local continue
      gocmdnoexitnodryrun grep --quiet --word-regexp "$upgrade_from" "$dist_nix"
      case $? in
        0) continue=true  ;;
        1) continue=false ;;
        *) die 5 "grep --word-regexp ')$upgrade_from' $dist_nix failed"
      esac

      if $continue; then
## factor this into a function ##
        while read nix_from nix_to; do
          debug "nix_from: '$nix_from'"
          debug "nix_to  : '$nix_to'"
          warn "  ''${nix_from#$DISTS/} -> ''${nix_to#$DISTS/}"
          # count & check #replacements
          local rargs=( --from="(?<!\w)$upgrade_from(?!\w)"
                        --to="$upgrade_to" "$nix_from" )
          if ! $DryRun; then
            rargs+=( --output="$nix_to" )
          fi
          gocmdnodryrun 7 replace "''${rargs[@]}"
          local overlay
          overlay="$overlays/$(gocmd2noexitnodryrun basename "$p").nix"
          check_ "basename $p"
          if [[ -e $overlay ]]; then
            from="$(gocmd2nodryrun 8 basename "$nix_from" .nix)"
            to="$(gocmd2nodryrun 9 basename "$nix_to" .nix)"
            # count & check #replacements
            local rargs=( --fromto="/$from.nix=/$to.nix"
                          --fromto="(?<!\w)vnix \"$from\"(?!\w)=vnix \"$to\""
                          "$overlay" )
            if ! $DryRun; then
              rargs+=( --output="$overlay" --overwrite )
            fi
            gocmdnodryrun 23 replace "''${rargs[@]}"

          else
            warn "no such overlay: '$overlay'"
          fi
        done < <( gocmdnodryrun 6 nix-dist-version-bump "$dist_nix" )

    fi
  fi
done
}

# ------------------------------------------------------------------------------

Usage="$(''${Cmd[cat]} <<EOF
Usage: $Progname OPTION* [PKG_NAME] [OLD_VERSION] [NEW_VERSION]

Create new dist-builds, and edit overlays, for an upgraded package.

Arguments:
  PKG_NAME    ) The name of the package to upgrade.  If not specified, the
                package name is taken to be the last element of the pwd.
  OLD_VERSION ) The version to upgrade from.  If not specified, the version is
                derived from the penultimate (sorted by name) available .nix in
                dists.
  NEW_VERSION ) The version to upgrade to.  If not specified, the version is
                derived from the latest (sorted by name) available .nix in
                dists.

Options:
 -u | --upgrade PKGS  Upgrade these packages only.  Packages may by split by
                      commas, and/or this option may be repeated.

 -v | --verbose
 --debug              Output additional developer debugging.
 --dry-run
 --help
EOF
)"

orig_args=("$@")
getopt_args=( -o vu: --long verbose,dry-run,help,debug,upgrade: )
OPTS=$( ''${Cmd[getopt]} "''${getopt_args[@]}" -n "$Progname" -- "$@" )

[ $? -eq 0 ] || dieusage "options parsing failed (--help for help)"

# copy the values of OPTS (getopt quotes them) into the shell's $@
eval set -- "$OPTS"

DISTS=$HOME/rc/nixpkgs/dists
overlays=$HOME/rc/nixpkgs/overlays

args=()
while true; do
  case "$1" in
    -u | --upgrade  )
      old_IFS="$IFS"
      IFS=, UpgradePkgs+=("$2")
      IFS="$old_IFS"
      shift 2
      ;;
    # !!! don't forget to update usage !!!
    -v | --verbose  ) Verbose=$((Verbose+1)) ; shift ;;
    --help          ) usage                          ;;
    --dry-run       ) DryRun=true            ; shift ;;
    --debug         ) Debug=true             ; shift ;;
    --              ) args+=("''${@:2}")     ; break ;;
    *               ) args+=("$1")           ; shift ;;
  esac
done

if [[ 0 -ne ''${#args[@]} ]]; then
  debug "CALLED AS: $0 $(showcmd "''${orig_args[@]}")"
fi

case ''${#args[@]} in
  0 ) main ;;
  1 ) main "''${args[@]}" ;;
  2 ) main "''${args[@]}" ;;
  3 ) main "''${args[@]}" ;;
  * ) usage               ;;
esac

# -- that's all, folks! --------------------------------------------------------
''

# Local Variables:
# mode: sh
# End:
