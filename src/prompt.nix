{ pkgs, bash-header }: ''

set -u -o pipefail -o noclobber; shopt -s nullglob
PATH=/dev/null

source ${bash-header}

Cmd[tput]=${pkgs.ncurses}/bin/tput

# ------------------------------------------------------------------------------

declare -A tput_attr=( [underscore]=smul )

# --------------------------------------

main() {
  local val="$1"

  local -a attr=( underscore )

  local -a tputs=()
  local i attr tput
  for i in "''${attr[@]}"; do
    attr="''${tput_attr[$i]}"
    capture tput gocmd 10 tput "$attr"
    tputs+=( "$tput" )
  done

  echo -n "$(''${Cmd[tput]} setaf 219)''${tputs[@]}$val$(''${Cmd[tput]} sgr0)"

  local tmuxen=( fg=color219 bg=default blink underscore )
  local IFS=,
  printf "\033k#[''${tmuxen[*]}]$val\033\\"
}

# ------------------------------------------------------------------------------

branch=master

Usage="$(''${Cmd[cat]} <<EOF
Usage: $Progname OPTION* MSG

Example
  $Progname foo

Options:

Standard Options:
  -v | --verbose  Be more garrulous, including showing external commands.
  --dry-run       Make no changes to the so-called real world.
  --help          This help.
EOF
)"

getopt_args=( -o v
              --long verbose,dry-run,help
              -n "$Progname" -- "$@" )
OPTS=$( ''${Cmd[getopt]} ''${getopt_args[@]} )

[ $? -eq 0 ] || dieusage "options parsing failed (--help for help)"

# copy the values of OPTS (getopt quotes them) into the shell's $@
eval set -- "$OPTS"

while true; do
  case "$1" in
    # don't forget to update $Usage!!

    # hidden option for testing
    -v | --verbose  ) Verbose=$((Verbose+1)) ; shift   ;;
    --help          ) usage                            ;;
    --dry-run       ) DryRun=true   ; shift   ;;
    -- ) shift; break ;;
    * ) break ;;
  esac
done

[ $# -eq 1 ]  || usage

main "$1"

# that's all, folks! -----------------------------------------------------------
''

# Local Variables:
# mode: sh
# sh-basic-offset: 2
# End:
