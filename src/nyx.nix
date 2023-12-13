{pkgs,bash-header,profile-members}: pkgs.writers.writeBashBin "nyx" ''

# build (locally / in temp dir); remove result; remove pkg; install


# in tempdir (copy in flake):
# x=$(nix profile list --profile /nix/var/nix/profiles/per-user/martyn/test | wc -l) && nix profile remove -v $( seq 0 $(($x-1)) ) --profile /nix/var/nix/profiles/per-user/martyn/test && nix profile install -v --profile /nix/var/nix/profiles/per-user/martyn/test $( nix flake show --json | jq  '.packages."x86_64-linux"|keys[]'| xargs -I {} echo .#{} ) && jq -r '.elements | to_entries | .[] .value.storePaths | .[]' < /nix/var/nix/profiles/per-user/martyn/test/manifest.json

# nix  flake show --json | jq -r '.packages | to_entries | .[] | values | .value | to_entries | .[].value.name'
# jq -r '.elements | to_entries | .[] | { key, attrPath : .value.attrPath } ' < /nix/var/nix/profiles/per-user/martyn/test/manifest.json


set -u -o pipefail -o noclobber; shopt -s nullglob

source ${bash-header}

# bizarrely, nix uses git from the path!
PATH=${pkgs.git}/bin

Cmd[jq]=${pkgs.jq}/bin/jq
Cmd[perl]=${pkgs.perl}/bin/perl
Cmd[profile-members]=${profile-members}

TOP="$HOME/rc/nixpkgs"
CONFIG_TOP="$HOME/rc/nixpkgs/configs"
NIXP="$HOME/nix"

CNames=()
NoProfile=false
ListConfigs=false
Configs=()
AllConfigs=false
Isolated=false
Remote=false
Mode="" # install, query, available, or list(configs)
Quiet=false
NoFlake=false
NoPriorities=false
InstallAll=false
RemoveAll=false

[[ -z $USER ]] && dieusage '$USER must be set'

# ------------------------------------------------------------------------------

# list all the configs, in $TOP/*/flake.nix, $CONFIG_TOP/*/flake.nix, and
# the remainers in $CONFIG_TOP/*.nix that don't have a superceding flake
allConfigs() {
  gocmdnodryrun 4 ls -1 "$CONFIG_TOP"/*/flake.nix "$TOP"/*/flake.nix "$NIXP"/*/flake.nix;
  local i;
  for i in "$CONFIG_TOP"/*.nix; do
    local b; capture b gocmdnodryrun 10 basename "$i" .nix
    [[ -e $CONFIG_TOP/$b/flake.nix ]] || echo "$i"
  done
}

# --------------------------------------

set_mode() {
  local new_mode="$1"
  if [[ -z $Mode ]] || { [[ query == $Mode ]] && [[ available == $new_mode ]]; }; then
    Mode="$new_mode"
  else
    dieusage "cannot change mode from '$Mode' to '$new_mode'"
  fi
}

# --------------------------------------

# profile dir for a given name
# (e.g., desktop => /nix/var/nix/profiles/per-user/martyn/desktop)
profile_dir() {
  [ $# -eq 1 ] || dieinternal "$(loc 1): takes a single argument: profile"
  echo "/nix/var/nix/profiles/per-user/$USER/$1"
}

# --------------------------------------

lndir() {
  [ $# -eq 1 ] || dieinternal "$(loc 1): takes a single argument: profile"
  echo "$HOME/.nix-profiles/$1"
}

# ------------------------------------------------------------------------------

main() {
  args=( "$@" )

  case "$Mode" in
    install   ) : ;;
    query     ) : ;;
    available ) : ;;
    list      ) allConfigs; return                                  ;;
    ""        ) dieusage "Please select a mode (-i, -q, -a, or -L)" ;;
    *         ) dieinternal "Invalid mode '$Mode'"                  ;;
  esac

  if [ 0 -eq ''${#Configs[@]} ] && [ 0 -eq ''${#CNames[@]} ]; then
    Configs=( "$NIXP/default/flake.nix" )
  else
    for c in "''${CNames[@]}"; do
      local flk_="$NIXP/$c/flake.nix"
      local flk="$TOP/$c/flake.nix"
      local flake="$CONFIG_TOP/$c/flake.nix"
      local config_nix="$CONFIG_TOP/$c.nix"
      if [[ -e $flk_ ]] && ! $NoFlake; then
        Configs+=( "$flk_" )
      elif [[ -e $flk ]] && ! $NoFlake; then
        Configs+=( "$flk" )
      elif [[ -e $flake ]] && ! $NoFlake; then
        Configs+=( "$flake" )
      elif [[ -e $config_nix ]]; then
        Configs+=( "$config_nix" )
      else
        dieusage "not found: [ $flk, $flake, $config_nix ]"
      fi
    done
  fi

  if $AllConfigs; then
    Configs=($(allConfigs))
  fi

  cmds=()
  for config in "''${Configs[@]}"; do
    local is_flake pname
    if [[ flake.nix == ''${config##*/} ]]; then
      is_flake=true
      pname="$(gocmdnodryrun 9 basename "''${config%/flake.nix}" .nix)"
      check_ basename
    else
      is_flake=false
      pname="$(gocmdnodryrun 9 basename "$config" .nix)"; check_ basename
    fi

    if ! $is_flake; then
      local tempdir; mktemp tempdir --dir --no-dry-run; gonodryrun 11 cd $tempdir
    fi

    if $is_flake; then
      cmd=( ''${Cmd[nix]} profile -v )
      case "$Mode" in
        install   ) cmd+=( install )                                    ;;

        query     ) # cmd is ignored, the full thing is handled below
                    cmd+=()                                             ;;
        available ) # cmd is ignored, the full thing is handled below
                    cmd+=()                                             ;;
        *         ) dieinternal "don't know how to handle mode '$Mode'" ;;
      esac
    else # ! $is_flake
      if $RemoveAll; then
        args+=( --remove-all )
      fi
      cmd=( ''${Cmd[env]} NIX_PATH=
            ''${Cmd[nix-env]} --file $config --show-trace )
    fi

    # it is important that we use this rather than our ~/.nix-profiles/*;
    # because nix will put the links (e.g., scripts-1-link) into the dir of
    # the profile.  We don't want that to be in ~/.nix-profiles/
    local profile_dir="/nix/var/nix/profiles/per-user/$USER/$pname"
    if ! $NoProfile; then
      cmd+=( --profile $profile_dir )
    fi

    local -a opts=()
    if $Isolated; then
      opts+=( --option substituters "" )
    elif $Remote; then
      opts+=( --option substituters https://cache.nixos.org/ )
    fi

    local -A prio
    if [[ install == $Mode ]] && ! $NoPriorities; then
      priorities="''${config%.nix}.priorities"
      debug "Priorities: $priorities"
      if [ -e "$priorities" ]; then
        mapfile -t prio_lines < "$priorities"
        for i in "''${prio_lines[@]}"; do
          # skip blank lines & comments
          [[ $i =~ ^[[:space:]]*(\#.*)?$ ]] && continue

          if [[ $i =~ ^([^[:space:]]*)[[:space:]]+([[:digit:]]+)$ ]]; then
            pkg="''${BASH_REMATCH[1]}"
            prio="''${BASH_REMATCH[2]}"
            if $is_flake; then
              prio[$pkg]=$prio
            else
              cmds+=( "$(printf '%q ' "''${cmd[@]}" ''${opts[@]} --set-flag priority $prio "$pkg")" )
            fi
          else
            die 5 "bad line '$i' in priorities file '$priorities'"
          fi
        done
      fi
    fi

    $Quiet && cmd+=( --quiet )

    case "$Mode" in
      install )
        if $is_flake; then
          local -A profile_members=() profile_versions flake_versions
          if [[ -d $profile_dir ]]; then
            local profile
            # the use of ##*/ here is a fop to profile-members which currently
            # doesn't accept an abspath (but maybe it should)
            capture profile \
                    gocmdnodryrun 13 profile-members --version "''${profile_dir##*/}"
            local index pkg vers
            if [[ -n $profile ]]; then
              # we need the [[ -n $profile ]]; because otherwise bash runs the
              # loop once with an empty string, meaning index et. al are each
              # empty.
              while read index pkg vers; do
                profile_members[$pkg]="$index"
                profile_versions[$pkg]="$vers"
              done <<<"$profile"
            fi
          fi

          debug "found ''${#profile_members[@]} profile_members"

          local config_dir
          capture config_dir gocmdnodryrun 19 dirname "$config"
          local pkgs_; capture pkgs_ gocmdnodryrun 17 nix flake show --json "$config_dir" --show-trace ''${opts[@]}
          local pkgs
          capture pkgs gocmdnodryrun 18 jq -r '.packages."x86_64-linux"|to_entries|.[]|(.value.name) +" "+ (.key)' <<<"$pkgs_"

          local pkg name
          while read pkg name; do
            if [[ $pkg =~ ^([A-Za-z_][[:alnum:]._]*(-[A-Za-z_][[:alnum:]._]*)*)(-([[:digit:]][-._[:alnum:]]+))?$ ]]; then
              # a scan of the output of nix-env -qaP showed a max pkgname
              # length of 32
              local p="''${BASH_REMATCH[1]}"
              local v="''${BASH_REMATCH[4]}"
              flake_versions[$p]="$v"
              debug "p: '$p'\tv: '$v'\told_vers: ''${profile_versions[$p]-UNSET}"
              if $InstallAll; then
                # existing version is unset, (pkg is not currently installed)
                # or if versions differ
                # or if versions are (implicitly) equal, and existing version
                #    (and therefore both) are empty
                if    [[ SET != ''${profile_versions[$p]+SET}  ]]       \
                   || [[ $v != ''${profile_versions[$p]:-}     ]]       \
                   || [[ "" == ''${profile_versions[$p]:-} ]]; then
                   debug "adding '$p' to args"
                   args+=( "$name" )
                 fi
              fi
            else
              warn "no match: '$pkg'"
            fi
          done <<<"$pkgs"

          local -a removals=() new_installs=()
          local a
          # XXX zoom-us; change args to an assoc array from name to install name
          for a in "''${args[@]}"; do
            if [[ -z ''${profile_members[$a]:-} ]]; then
              warn "installing $a"
              new_installs+=( "$a" )
            else
              warnf "upgrading\t%-32s\tfrom\t%16s\tto\t%s\n" "$a" \
                        "''${profile_versions[$a]}" "''${flake_versions[$a]:-NONE}"
              removals+=( "''${profile_members[$a]}" )
            fi
          done

          debug "''${#args[@]} args; ''${#removals[@]} removals; ''${#new_installs[@]} new_installs"
          # This is only necessary if we remove packages one at a time,
          # potentially causing the profile array to shift around.
          # While we're using one command for all removals, it's redundant.
          # However, for possible future safety, I'm leaving it: it does
          # no harm.
          removals=($(for i in "''${removals[@]}"; do echo $i; done | \
                      gocmdnodryrun 14 sort -nr))
          if [[ 0 -ne ''${#removals[@]} ]]; then
            local rcmd=( ''${Cmd[nix]} profile remove -v "''${removals[@]}" )
            $NoProfile || rcmd+=( --profile $profile_dir )
            cmds+=( "$( printf '%q ' "''${rcmd[@]}" )" )
          fi

          if [[ 0 -eq ''${#args[@]} ]]; then
            if [[ install == $Mode ]]; then

              die 99 "nothing to do; nothing to install.  this may be because we don't handle versions properly"
            else
              cmds+=( "$( printf '%q ' "''${cmd[@]}" ''${opts[@]} )" )
            fi
          else
            local a;
            for a in "''${args[@]}"; do
              local cmd_="$( printf '%q ' "''${cmd[@]}" ''${opts[@]} ) $( printf '%q#%q ' "$config_dir" "$a")"
              if [[ x != ''${prio[$a]:-x} ]]; then
                cmd_+=" --priority ''${prio[$a]}"
              fi
              cmds+=( "$cmd_" )
            done
          fi

        else
          # XXX install all-at-once?  Name flake explicitly, no need for tmpdir
          # XXX how does priority work with all-at-once?
          cmds+=( "$( printf '%q ' "''${cmd[@]}" ''${opts[@]} "''${args[@]}" --install )"  )
        fi
        ;;

      query   )
        if $is_flake; then
          cmds+=( "''${Cmd[profile-members]} --no-index --version $profile_dir" )
        else
          cmds+=( "$( printf '%q ' "''${cmd[@]}" ''${opts[@]} "''${args[@]}" --query )"  )
        fi
        ;;

      available )
        if $is_flake; then
          local config_dir
          capture config_dir gocmdnodryrun 20 dirname "$config"
          local json; capture json gocmd 15 nix flake show --json "$config_dir"
          local -a pkgs
          capture_array pkgs \
            gocmd 16 jq -r '.packages|to_entries|.[].value|to_entries|.[].value.name' <<<"$json"
          local pkg
          for pkg in "''${pkgs[@]}"; do
            if [[ $pkg =~ ^([A-Za-z_][[:alnum:]_]*(-[A-Za-z_][[:alnum:]_]*)*)(-([[:digit:]][-._[:alnum:]]+))?$ ]]; then
              # a scan of the output of nix-env -qaP showed a max pkgname
              # length of 32
              printf "%-31s\t%s\n" "''${BASH_REMATCH[1]}" "''${BASH_REMATCH[4]}"
            else
              echo "no match: '$pkg'" 1>&2
            fi
          done
        else
          cmds+=( "$( printf '%q ' "''${cmd[@]}" ''${opts[@]} "''${args[@]}" --query --available )" )
        fi
        ;;
      *       ) dieinternal "invalid mode '$Mode'" ;;
    esac

    if [[ install == $Mode ]]; then
      local l
      l="$(lndir "$pname")"; check_ lndir # ~/.nix-profiles/"$pname"
      if [ ! -e "$l" ] && ! $NoProfile; then
        cmds+=("$(printf '%q ' ''${Cmd[ln]} -sfn "$profile_dir" "$l")")
      fi
    fi
  done
  for c in "''${cmds[@]}"; do
    go 3 $c
  done
}

# ------------------------------------------------------------------------------

Usage="$(''${Cmd[cat]} << EOF
usage: $Progname OPTIONS

Options:
  -P|--no-profile         Typically we install into a specific nix profile,
                          named after the basename of the config.

                          With this option, we install into ~/.nix-profile,
                          which should already be a link to
                          /nix/var/nix/profiles/per-user/$USER/profile.
  -C|--config      CFG    Add this name to the list of configs to be used.
                          By default, the single config
                          $CONFIG_TOP/default.nix
                          is used; this is overriden by use of one or --cname
                          or --config options (or both).
  -c|--cname       CNAME  --cname CNAME is equivalent to
                          --config $CONFIG_TOP/CNAME.nix
  -i|--install            Install each argument (or everything found in configs,
                          if no arguments are provided).  If arguments and
                          multiple configs are provided, then all arguments are
                          provided to all configs - this is unlikely to be what
                          you want, and is subject to change in future.
  -q|--query              Pass --query through to nix-env.
  -a|--available          Pass --available through to nix-env.  Implies --query.
  -L|--list-configs       Show a list of the available configs found.
  -A|--all-configs        Perform action on each config; a short-hand for taking
                          each config (as listed by --list-configs), and
                          citing them (as if passed to --config).
  --remote    | -r        Act as if disconnected from sixears network; limit
                          binary caches that would otherwise bork the build due
                          to unavailability.
  --isolated  | -R        Act as if disconnected from all networks; cite no
                          binary caches.
  --no-priorities         Ignore priority settings; may be occasionally needed
                          for arcane reasons to get a thing installed before the
                          priorities are set (because, e.g., we set priorities
                          on
                          rxvt-unicode-with-perl-with-unicode3-with-plugins-9.22
                          but it's not installed with that name, so setting its
                          priority will not work before it is installed).
  --no-flake              Ignore any flake.nix, even if present in the
                          appropriate directory.

Standard Options:
  -v | --verbose  Be more garrulous, including showing external commands.
  --dry-run       Make no changes to the so-called real world.
  --debug         Output additional developer debugging.
  --help          This help.
EOF
)"

getopt_args=( -o vc:C:iqaPLAIRr
              --long cname:,config:,install,query,available,no-profile,remote
              --long list-configs,all-configs,isolated,install-configs,quiet
              --long no-priorities,no-flake
              --long verbose,dry-run,help,debug
              -n "$Progname" -- "$@" )
OPTS=$( ''${Cmd[getopt]} "''${getopt_args[@]}" )

[ $? -eq 0 ] || dieusage "options parsing failed (--help for help)"

# copy the values of OPTS (getopt quotes them) into the shell's $@
eval set -- "$OPTS"

args=()
args_are_cnames=false

while true; do
  case "$1" in
    -P | --no-profile      ) NoProfile=true                         ; shift   ;;
    -c | --cname           ) CNames+=("$2")                         ; shift 2 ;;
    -C | --config          ) Configs+=("$2")                        ; shift 2 ;;
    -i | --install         ) set_mode install                       ; shift   ;;
    -q | --query           ) set_mode query                         ; shift   ;;
    -a | --available       ) set_mode available                     ; shift   ;;
    -L | --list-configs    ) set_mode list                          ; shift   ;;
    -A | --all-configs     ) AllConfigs=true                        ; shift   ;;
    -R | --isolated        ) Isolated=true                          ; shift   ;;
    -r | --remote          ) Remote=true                            ; shift   ;;
    -I | --install-configs ) set_mode install; args_are_cnames=true;
                             InstallAll=true
                             RemoveAll=true                         ; shift   ;;
    --no-priorities        ) NoPriorities=true                      ; shift   ;;
    --no-flake             ) NoFlake=true                           ; shift   ;;
    --quiet                ) Quiet=true                             ; shift   ;;
    # don't forget to update $Usage!!

    # hidden option for testing

    -v | --verbose  ) Verbose=$((Verbose+1)) ; shift   ;;
    --help          ) usage                            ;;
    --dry-run       ) DryRun=true            ; shift   ;;
    --debug         ) Debug=true             ; shift   ;;
    --              ) shift; args+=( "$@" )  ; break   ;;
    *               ) args+=( "$1" )         ; shift   ;;
  esac
done

if $args_are_cnames; then
  CNames+=( "''${args[@]}" )
  args=()
fi

main "''${args[@]}"

# that's all, folks! -----------------------------------------------------------
''

# Local Variables:
# mode: sh
# sh-basic-offset: 2
# End:

# ------------------------------------------------------------------------------
