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

  local fg_colour=051 bg_colour=""
  local -a attrs=( underscore )

  local -a tputs=()
  if [[ -n $fg_colour ]]; then
    local tput
    capture tput gocmd 10 tput setaf "$fg_colour"
    tputs+=( "$tput" )
  fi

  local i attr tput
  for i in "''${attrs[@]}"; do
    attr="''${tput_attr[$i]}"
    capture tput gocmd 10 tput "$attr"
    tputs+=( "$tput" )
  done

  echo -n "''${tputs[@]}$val$(''${Cmd[tput]} sgr0)" | ${pkgs.coreutils}/bin/cat -tev
  echo -n "''${tputs[@]}$val$(''${Cmd[tput]} sgr0)"

  local tmuxen=( fg=color"''${fg_colour:-default}" bg="''${bg_colour:-default}"
                 "''${attrs[@]}" )
#  local tmuxen=( fg=color051 bg=default "''${attr[@]}" )
  local IFS=,
echo "TMUXEN: #[''${tmuxen[*]}]"
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

orig_args=("$@")
getopt_args=( -o v
              --long verbose,debug,dry-run,help
              -n "$Progname" -- "$@" )
OPTS=$( ''${Cmd[getopt]} "''${getopt_args[@]}" )

[ $? -eq 0 ] || dieusage "options parsing failed (--help for help)"

# copy the values of OPTS (getopt quotes them) into the shell's $@
eval set -- "$OPTS"

args=()
while true; do
  case "$1" in
    # don't forget to update $Usage!!

    # hidden option for testing
    -v | --verbose  ) Verbose=$((Verbose+1)) ; shift ;;
    --help          ) usage                          ;;
    --dry-run       ) DryRun=true            ; shift ;;
    --debug         ) Debug=true             ; shift ;;
    --              ) shift; args+=( "$@" )  ; break ;;
    *               ) args+=( "$1" )         ; shift ;;
  esac
done

debug "CALLED AS: ''${0@Q} ''${orig_args[*]@Q}"
debug "ARG# (''${#args[@]})"
for i in ''${!args[@]}; do
  debug "ARG($i): ''${args[$i]@Q}"
done

case "''${#args[@]}" in
  1 ) main "''${args[0]}" ;;
  * ) usage               ;;
esac

# that's all, folks! -----------------------------------------------------------
''

# Local Variables:
# mode: sh
# sh-basic-offset: 2
# End:
