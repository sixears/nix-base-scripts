{ pkgs, bash-header }: ''

set -u -o pipefail -o noclobber; shopt -s nullglob
PATH=/dev/null

source ${bash-header}

Cmd[git]=${pkgs.git}/bin/git
Cmd[perl]=${pkgs.perl}/bin/perl
Cmd[rsync]=${pkgs.rsync}/bin/rsync

TAB="$( echo -en '\t' )"

Top=/nix/var/nixpkgs
TmpDir=""
NoCopy=false
ExtantTest=true

# ------------------------------------------------------------------------------

check_no_overwrite_dir() {
  local dir="$1"

  if [ -e "$dir" ]; then
    if $DryRun; then
      warn "would not overwrite extant dir $dir"
    else
      die 3 "not overwriting extant dir $dir"
    fi
  fi
}

# --------------------------------------

# make tmpdir, if one is not provided.
# Sets $TmpDir
mktmpdir() {
  if [ 2 -eq $# ]; then
    local varname="$1" infix="$2"
  else
    dieinternal "$(loc 1): takes one arg (varname)"
  fi
  if [[ -z ''${!varname} ]]; then
    mktemp --dir --exit 12 --infix "$infix" --tmpdir "$Top" "$varname"
    $DryRun && TmpDir="$Top/<TMPDIR>"
  fi
}

# --------------------------------------

# dirname, with no dry-run
dirnamendr() { gocmdnodryrun "$1" dirname "''${@:2}"; }

# --------------------------------------

find_archive() {
  local cfgs=( "$Top"/*/.git/config )
  if [ 0 -ne ''${#cfgs[@]} ]; then
    local grep_args=( --files-with-matches
                      'url = https://github.com/nixos/nixpkgs/' ''${cfgs[@]} )
    local archives="$(gocmdnoexitnodryrun grep "''${grep_args[@]}" \
                      | gocmdnodryrun 14 tail --lines=1 )"
    rv=$?; [ 0 -eq $rv ] || die $rv "grep|tail failed"

    if [[ ! -z $archives ]]; then
      local d1="$(gocmdnodryrun 15 dirname "$archives")"; rv=$?
      rv=$?; [ 0 -eq $rv ] || die $rv "dirname \"$archives\" failed"
      local d2="$(gocmdnodryrun 16 dirname "$d1")"; rv=$?
      rv=$?; [ 0 -eq $rv ] || die $rv "dirname \"$d1\" failed"
      echo "$d2"
    fi
  fi
}

# --------------------------------------

main() {
  local commit="$1" branch="$2"

  local trim="''${commit:0:8}"

  [[ -d $Top ]] || die 9 "no such top dir '$Top'"
  local extant="$(echo "$Top"/*."$trim")"
  if $ExtantTest; then
    [[ -z $extant ]] || die 32 "not operating in presence of extant '$extant'"
  fi

  exec_as_root; check $? exec_as_root

  mktmpdir TmpDir "$trim"
  warn "using tmpdir $TmpDir"

  local rsync_remote=nixpkgs::nixpkgs/"$branch.*.$trim"
  local rsync=( rsync --port 7798 )

  local available
  available="$(gocmdnoexitnodryrun "''${rsync[@]}" "$rsync_remote" 2>/dev/null \
                 | gocmdnoexitnodryrun perl -nlF"\s+" -E 'say $F[4]')"

  # check for revision on nixpkgs::nixpkgs rsync server
  if [[ ! -z $available ]]; then
    local rsync_cmd=( "''${rsync[@]}" "$rsync_remote/" "''${TmpDir%/}"
                       --verbose --progress --partial --archive )
    gocmd 31 "''${rsync_cmd[@]}"
    local target_dir="$Top/$available"
  else
    local archive=""
    $NoCopy || archive="$(find_archive)"; check $? find_archive
    if [[ -z $archive ]]; then
      tmpbase="$(''${Cmd[basename]} "$TmpDir")"
      tmpdir_d="$(gocmdnodryrun 13 dirname "$TmpDir")"; check $? dirname
      go 4 cd "$tmpdir_d"
      gocmd 5 git clone https://github.com/nixos/nixpkgs/ -b "$branch" "$tmpbase"
    else
      warn "copying $archive -> $TmpDir"
      cp_dir "$archive" "$TmpDir"
    fi

    go 17 cd "$TmpDir"

#    gocmd 33 git pull origin
#    gocmd  6 "git" pull origin "$branch"
    warn "git pull..."; gocmd 26 "git" pull --quiet --progress origin "$branch"
    gocmd 25 "git" checkout "$commit"
    local commit_date
    commit_date="$( gocmd 30 git log --pretty=format:%cs --max-count=1 )"
    check_ "git log"

    gocmd 10 chown -R root: "$TmpDir/"
    gocmd 11 chmod -R go+rX "$TmpDir/"

    local base="''$branch.$commit_date.$trim"
    local target_dir="$Top/$base"
  fi

  check_no_overwrite_dir "$target_dir"
  gocmd 7 mv "$TmpDir/" "$target_dir/"
}

# ------------------------------------------------------------------------------

branch=master

Usage="$(''${Cmd[cat]} <<EOF
Usage: $Progname [OPTION]... COMMIT

Example
  $Progname --branch release-18.09 b5fd3a0bc70 -v

Options:
  -b | --branch  BRANCH  Use this git branch.  Defaults to '$branch'.
                         The branch name is used of the base of the output
                         directory.
  -T | --top     TOP     Top directory in which to place new nixpkgs.
                         Defaults to '$Top'.
  -t | --tmpdir  TMPDIR  Write temporary files here.  Defaults to an auto-made
                         name in TOP.
  --no-copy              Don't copy a prior dir to initialize the directory;
                         perform a fresh download (git clone) from github.

Standard Options:
  -v | --verbose  Be more garrulous, including showing external commands.
  --dry-run       Make no changes to the so-called real world.
  --help          This help.
EOF
)"

getopt_args=( -o tT:b:v
              --long tmpdir:,git:,top:,no-copy,branch:,verbose,dry-run,help
              --long no-extant-test
              -n "$Progname" -- "$@" )
OPTS=$( ''${Cmd[getopt]} ''${getopt_args[@]} )

[ $? -eq 0 ] || dieusage "options parsing failed (--help for help)"

# copy the values of OPTS (getopt quotes them) into the shell's $@
eval set -- "$OPTS"

while true; do
  case "$1" in
    -b | --branch   ) branch="$2"   ; shift 2 ;;
    -t | --tmpdir   ) TmpDir="$2"   ; shift 2 ;;
    -T | --top      ) Top="$2"      ; shift 2 ;;
    --no-copy       ) NoCopy=true   ; shift   ;;
    # don't forget to update $Usage!!

    # hidden option for testing
    --no-extant-test ) ExtantTest=false ; shift ;;

    -v | --verbose  ) Verbose=$((Verbose+1)) ; shift   ;;
    --help          ) usage                            ;;
    --dry-run       ) DryRun=true   ; shift   ;;
    -- ) shift; break ;;
    * ) break ;;
  esac
done

[ $# -eq 1 ]  || usage

main "$1" "$branch"

# that's all, folks! -----------------------------------------------------------
''

# Local Variables:
# mode: sh
# sh-basic-offset: 2
# End:
