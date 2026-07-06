{ pkgs, termfake }: ''
set -eu -o pipefail

declare -A CMD
CMD[tty]=${pkgs.coreutils}/bin/tty
CMD[termfake]=${termfake}/bin/termfake

readonly -A CMD

IFS=""

while tput bel; do
  read -s -d $'\v' -t 2.0 -n 1 REPLY || true
  if [[ -n $REPLY ]]; then
    break
  fi
done

if [[ $REPLY != $'\n' ]]; then
  "''${CMD[termfake]}" -n -- "$REPLY"
fi

# that's all, folks! -----------------------------------------------------------
''

# Local Variables:
# mode: sh
# sh-basic-offset: 2
# End:
