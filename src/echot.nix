{ pkgs, bash-header }: ''

set -u -o pipefail -o noclobber; shopt -s nullglob
PATH=/dev/null

source ${bash-header}

Cmd[clear]=${pkgs.ncurses}/bin/clear
Cmd[tput]=${pkgs.ncurses}/bin/tput

# ------------------------------------------------------------------------------

declare -Ar tput_attr=( [underscore]=smul/rmul [underline]=smul/rmul [bold]=bold
                        [dim]=dim [italic]=sitm [underlined]=smul/rmul
                        # blink=[blink] # no terminal supports this
                        [invisible]=invis
                        [reverse]=rev [standout]=smso/rmso [strikeout]=smxx
                        [reset]=sgr0
                      )

declare -Ar colour_ansi_8=( [black]=0 [red]=1 [green]=2 [orange]=3 [blue]=4
                            [purple]=5 [cyan]=6 [light-grey]=7
                            [dark-grey]=8 [light-red]=9 [light-green]=10
                            [yellow]=11 [light-blue]=12 [pink]=13 [teal]=14
                            [white]=15
                          )

declare -Ar colour_ansi_256=( [black]=0 [red]=124 [green]=22 [orange]=209 [blue]=18
                              [purple]=90 [cyan]=45 [light-grey]=248
                              [dark-grey]=240 [light-red]=196 [light-green]=76
                              [yellow]=226 [light-blue]=51 [pink]=207 [teal]=49
                              [white]=15
                            )

declare -n colour_ansi

# --------------------------------------

do_256() {
  local i
  for ((i=0; i<256; i++)); do
    echo -n '  '
    gocmd 10 tput setab $i
    gocmd 11 tput setaf $(( ( (i>231&&i<244 ) || ( (i<17)&& (i%8<2)) ||
      (i>16&&i<232)&& ((i-16)%6 <(i<100?3:2) ) && ((i-16)%36<15) )?7:16))
    go 12 printf " C %03d " $i
    gocmd 13 tput op
    (( ((i<16||i>231) && ((i+1)%8==0)) || ((i>16&&i<232)&& ((i-15)%6==0)) )) &&
      go 14 printf "\n" ""
  done
}

# --------------------------------------

do_256_2() {
  # https://unix.stackexchange.com/questions/269077/tput-setaf-color-table-how-to-determine-color-codes

  color(){
    for c; do
      printf '\e[48;5;%dm%03d' $c $c
    done
    printf '\e[0m \n'
  }

  IFS=$' \t\n'
  color {0..15}
  for ((i=0;i<6;i++)); do
    color $(gocmd 15 seq $((i*36+16)) $((i*36+51)))
  done
  color {232..255}
}

# --------------------------------------

do_8() {
  # https://linuxcommand.org/lc3_adv_tput.php
  # tput_colors - Demonstrate color combinations.

  for fg_color in {0..7}; do
    set_foreground=$(gocmd 16 tput setaf $fg_color)
    for bg_color in {0..7}; do
      set_background=$(gocmd 17 tput setab $bg_color)
      echo -n $set_background$set_foreground
      # printf ' F:%s B:%s ' $fg_color $bg_color
      go 18 printf ' %s/%s ' $fg_color $bg_color
    done
    echo $(gocmd 18 tput sgr0)
  done
}

# --------------------------------------

#  gocmd 19 clear
attr() {
  local -a attr
  readarray -t -d / attr < <(gonodryrun 19 echo -n "''${tput_attr[$1]:-}")
for a in "''${attr[@]}"; do echo "A: '$a' (''${tput_attr[$1]:-})"; done
  case "$attr" in
    "" ) die "unknown attribute '$1'" ;;
    *  ) gocmd 20 tput "''${attr[0]}" ;;
  esac
}

do_examples() {
# tput_characters - Test various character attributes
  echo "tput character test"
  echo "==================="
  echo

  xmpl() {
    gocmd 20 tput "$1"
    printf "This text has the %10s attribute (%s)" "''${2:-$1}" "$1"
    gocmd 21 tput "''${3:-sgr0}"
    echo
  }

  xmpl bold
  xmpl dim
  xmpl sitm italic
  xmpl smul underlined rmul
  # Most terminal emulators do not support blinking text (though xterm
  # does) because blinking text is considered to be in bad taste ;-)
  xmpl blink

  echo The line below is invisible
  echo vvvvvvvvvvvvvvvvvvvvvvvvvvv
  xmpl invis invisible
  echo ^^^^^^^^^^^^^^^^^^^^^^^^^^^

  xmpl rev  reverse
  xmpl smso standout  rmso
  xmpl smxx strikeout

  local name
  for name in "''${!tput_attr[@]}"; do
    attr "$name"
    printf "This text has the %10s attribute (%s)" "$name" "''${tput_attr[$name]}"
    gocmd 21 tput sgr0 # "''${3:-sgr0}"
    echo
  done


}

# --------------------------------------

do_list_colours() {
  local bg

  for bg in "''${!colour_ansi[@]}"; do
    gocmd 22 tput setab ''${colour_ansi[$bg]}
    local fg
    case $bg in
      black | red | light-red | dark-grey | blue | green | purple ) fg=white ;;
      *                                                           ) fg=black ;;
    esac
    gocmd 23 tput setaf ''${colour_ansi[$fg]}
    echo $bg
    gocmd 24 tput sgr0
  done
}

# --------------------------------------

set_fg() {
  local code=''${colour_ansi["$1"]:-}

  if [[ -z $code ]]; then
    dieusage "unknown colour '$1'"
  else
    gocmd 25 tput setaf "$code"
  fi
}

main() {
  if [[ "$1" =~ ^\{fg:([a-zA-Z-]+)\}$ ]]; then
    set_fg "''${BASH_REMATCH[1]}"
  else
    echo -n "$1"
  fi

  return 0

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

colour_mode=256
no_newline=false
no_reset=false

Usage="$(''${Cmd[cat]} <<EOF
Usage: $Progname OPTION* MSG

Wrapper around tput.  The plan was to provide a cmdline way to write, e.g.,

  echot {fg:blue}{attr:underline}hello, mum!

and have it auto-reset (or not, per attribute); but I haven't finished the
cmdline parser.  I also started on ~/nix/base-scripts/src/ecco.hs for this,
but haven't finished that, either.

Example
  $Progname foo

Options:
  --no-newline | -n    ) Do not emit a terminating newline.
  --no-reset   | -r    ) Do not emit a terminating reset.

  --show [8|256|256-2] ) Dump a tput/ANSI colour-chart, in 8/256 colours.
                         256-2 dumps an alternate, shorter tput/ANSI chart.
                         The command will take no further arguments/options.
  --8 | --256          ) Set colour mode.  Default: $colour_mode.
  --examples           ) Dump some examples of output with text attributes.
  --list-colours       ) List known colour names.

Standard Options:
  -v | --verbose  Be more garrulous, including showing external commands.
  --dry-run       Make no changes to the so-called real world.
  --help          This help.
EOF
)"

orig_args=("$@")
getopt_args=( -o vnr
              --long verbose,debug,dry-run,help,show:,examples
              --long list-colours,8,256,no-newline,no-reset
              -n "$Progname" -- "$@" )
OPTS=$( ''${Cmd[getopt]} "''${getopt_args[@]}" )

[ $? -eq 0 ] || dieusage "options parsing failed (--help for help)"

# copy the values of OPTS (getopt quotes them) into the shell's $@
eval set -- "$OPTS"

mode=""
set_mode() {
  if [[ -z $mode ]]; then
    mode="$1"
  else
    dieusage "Cannot re-select mode (got '$1'; already set to '$mode')"
  fi
}

set_show_colour_mode() {
  local colour_mode="$1"

  case "$colour_mode" in
    8 | 256 | 256-2 ) set_mode "$colour_mode"                             ;;
    *               ) dieusage "invalid argument to show: '$colour_mode'" ;;
  esac
}

args=()
while true; do
  case "$1" in
    # don't forget to update $Usage!!
    --no-newline | -n ) no_newline=true        ; shift   ;;
    --no-reset   | -r ) no_reset=true          ; shift   ;;

    --show         ) set_show_colour_mode "$2" ; shift 2 ;;
    --examples     ) set_mode examples         ; shift   ;;
    --list-colours ) set_mode list-colours     ; shift   ;;
    --8 | --256    ) colour_mode="''${1#--}"   ; shift   ;;

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

case "$colour_mode" in
  8   ) colour_ansi=colour_ansi_8                         ;;
  256 ) colour_ansi=colour_ansi_256                       ;;
  *   ) dieinternal "invalid colour mode: '$colour_mode'" ;;
esac

case "''${#args[@]}" in
  0 ) case "$mode" in
        8            ) do_8                                              ;;
        256          ) do_256                                            ;;
        256-2        ) do_256_2                                          ;;
        examples     ) do_examples                                       ;;
        list-colours ) do_list_colours                                   ;;
        ""           ) exit 0                                            ;;
        *            ) dieusage "mode '$mode' takes 1 or more arguments" ;;
      esac
      ;;

  * ) for ((i=0; i<''${#args[@]}; i+=1)); do
        word="''${args[$i]}"

        if [[ "$word" =~ ^\{fg:([a-zA-Z-]+)\}$ ]]; then
          set_fg "''${BASH_REMATCH[1]}"
        else
          echo -n "$word"
          [[ $((i+1)) -lt ''${#args[@]} ]] && echo -en ' '
        fi

      done
      $no_reset   || gocmd 26 tput sgr0
      $no_newline || echo
      ;;
esac

# gocmd 19 clear



# that's all, folks! -----------------------------------------------------------
''

# Local Variables:
# mode: sh
# sh-basic-offset: 2
# End:
