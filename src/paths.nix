{ pkgs, bash-header, path-edit }: pkgs.writers.writeBashBin "paths" ''

source ${bash-header}

: ''${USER:=$(''${Cmd[id]} --user --name)}

Cmd[path-edit]=${path-edit}/bin/path-edit

paths=( ~
        ~/.nix-profile ~/.nix-profiles/*
        /etc/profiles/per-user/$USER
        /run/wrappers /run/current-system/sw /usr
      )

# ------------------------------------------------------------------------------

Usage="$(${Cmd[cat]} <<EOF
usage: $Progname [Cmd]

-) If no cmd is provided; write a standard set of paths (PATH,MANPATH) to
   stdout

-) if a cmd is provided; run that command with the standard set of paths

Standard Options:
  -v | --verbose  Be more garrulous, including showing external commands.
  --dry-run       Make no changes to the so-called real world.
  --debug         Output development/debugging messages.
  --help          This help.
EOF
)"

# ------------------------------------------------------------------------------

main() {
  local cmd=( "$@" )

  case $# in
    0) gocmd 10 path-edit -C prepend "${paths[@]}" ;;
    *) local new_paths
       capture new_paths gocmdnodryrun 11 path-edit -C prepend "${paths[@]}"
       debug "new_paths: ${new_paths[*]}"
       goeval 12 "${new_paths[*]}"
       go 13 exec "$@" ;;
  esac
}

# ------------------------------------------------------------------------------

orig_args="$@"
getopt_opts=( -o v --long verbose,dry-run,debug,help )
OPTS=$( ${Cmd[getopt]} "${getopt_opts[@]}" -n "$Progname" -- "$@" )

[ $? -eq 0 ] || die 2 "options parsing failed (--help for help)"

# copy the values of OPTS (getopt quotes them) into the shell's $@
eval set -- "$OPTS"

args=()
action=toggle
while true; do
  case "$1" in
    # !!! don't forget to update usage !!!
    -v | --verbose  ) Verbose=$((Verbose+1)) ; shift   ;;
    --help          ) usage                            ;;
    --dry-run       ) DryRun=true            ; shift   ;;
    --debug         ) Debug=true             ; shift   ;;
    --              ) shift; args+=( "$@" )  ; break   ;;
    *               ) args+=( "$1" )         ; shift   ;;
  esac
done

main "''${args[@]}"
''

# Local Variables:
# mode: sh
# End:
