#!/usr/bin/env bash
set -eo pipefail

_SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
_SCRIPT_BASENAME=$(basename -- "${BASH_SOURCE[0]}")

# ---
#  test helpers
# ---

function __fail() {
  >&2 printf '%s: %s\n' "$_SCRIPT_BASENAME" "$*"
  exit 1
}

function __print_warn() {
  >&2 printf '%s: warning: %s\n' "$_SCRIPT_BASENAME" "$*"
}

function __assert_array() {
  local -a _arr_expected=("$@")
  local _arrays_match=1
  local _index
  local _expected_display=
  local _actual_display=

  if ((${#_arr_expected[@]} == ${#COMPREPLY[@]})); then
    for _index in "${!_arr_expected[@]}"; do
      if [[ ${_arr_expected[_index]} != "${COMPREPLY[_index]}" ]]; then
        _arrays_match=0
        break
      fi
    done
    ((_arrays_match)) && return 0
  fi

  if ((${#_arr_expected[@]})); then
    printf -v _expected_display '%q ' "${_arr_expected[@]}"
    _expected_display=${_expected_display% }
  fi
  if ((${#COMPREPLY[@]})); then
    printf -v _actual_display '%q ' "${COMPREPLY[@]}"
    _actual_display=${_actual_display% }
  fi
  __fail "expected [$_expected_display], got [$_actual_display]"
}

# ---
#  main
# ---

function __main() {
  local _bash_completion=${BASH_COMPLETION_FILE:-/usr/share/bash-completion/bash_completion}
  local _tmp_dir

  BASH_COMPLETION_USER_FILE=/dev/null
  shopt -u extglob
  # shellcheck disable=SC1091 # Path is resolved relative to this test script.
  . "$_SCRIPT_DIR/glob-complete.bash" ||
    __fail 'could not dot-source glob-complete.bash'

  complete -p -D | grep -q -- '__glob_complete_default' ||
    __fail 'standalone default completion was not installed'
  [[ $BASH_COMPLETION_USER_FILE == "$_SCRIPT_DIR/glob-complete.bash" ]] ||
    __fail 'generic bash-completion re-entry was not registered'

  _tmp_dir=$(mktemp -d)
  declare -g _TEST_TMP_DIR=$_tmp_dir
  trap 'rm -rf -- "${_TEST_TMP_DIR:?}"' EXIT
  mkdir \
    -- \
    "$_tmp_dir/bar" \
    "$_tmp_dir/baz" \
    "$_tmp_dir/foo" \
    "$_tmp_dir/tilde-root" \
    "$_tmp_dir/prefix room"
  touch \
    -- \
    "$_tmp_dir/data.txt" \
    "$_tmp_dir/data.log" \
    "$_tmp_dir/"$'split\nentry' \
    "$_tmp_dir/white room" \
    "$_tmp_dir/"$'key\tword'
  cd -- "$_tmp_dir"
  HOME=$_tmp_dir

  COMPREPLY=()
  __glob_complete_default cd '*a' cd
  __assert_array bar baz data.log data.txt

  # shellcheck disable=SC2034 # Read indirectly by the completion function.
  declare -g TEST_GLOB_ROOT=$_tmp_dir
  COMPREPLY=()
  # shellcheck disable=SC2016 # The literal parameter expansion is test input.
  __glob_complete_default cd '$TEST_GLOB_ROOT/*a' cd
  # shellcheck disable=SC2016 # The parameter syntax is expected output.
  __assert_array \
    '$TEST_GLOB_ROOT/bar' \
    '$TEST_GLOB_ROOT/baz' \
    '$TEST_GLOB_ROOT/data.log' \
    '$TEST_GLOB_ROOT/data.txt'

  COMPREPLY=()
  # shellcheck disable=SC2016 # The literal parameter expansion is test input.
  __glob_complete_default cd '${TEST_GLOB_ROOT}/*a' cd
  # shellcheck disable=SC2016 # The parameter syntax is expected output.
  __assert_array \
    '${TEST_GLOB_ROOT}/bar' \
    '${TEST_GLOB_ROOT}/baz' \
    '${TEST_GLOB_ROOT}/data.log' \
    '${TEST_GLOB_ROOT}/data.txt'

  COMPREPLY=()
  __glob_complete_default cd 'split*' cd
  __assert_array $'split\nentry'

  COMPREPLY=()
  __glob_complete_default cd 'white*' cd
  __assert_array 'white room'

  COMPREPLY=()
  __glob_complete_default cd 'key*' cd
  __assert_array $'key\tword'

  COMPREPLY=()
  # shellcheck disable=SC2016 # The literal parameter expansion is test input.
  __glob_complete_default cd '$TEST_GLOB_ROOT/white*' cd
  # shellcheck disable=SC2016 # The parameter syntax is expected output.
  __assert_array '$TEST_GLOB_ROOT/white\ room'

  COMPREPLY=()
  # shellcheck disable=SC2088 # The literal tilde is test input.
  __glob_complete_default cd '~/tilde*' cd
  # shellcheck disable=SC2088 # The literal tilde is expected output.
  __assert_array '~/tilde-root'

  COMPREPLY=()
  # shellcheck disable=SC2088 # The literal tilde is test input.
  __glob_complete_default cd '~/prefix*' cd
  # shellcheck disable=SC2088 # The literal tilde is expected output.
  __assert_array '~/prefix\ room/'

  COMPREPLY=()
  __glob_complete_default cd '~+/tilde*' cd
  __assert_array '~+/tilde-root'

  OLDPWD=$_tmp_dir
  COMPREPLY=()
  __glob_complete_default cd '~-/tilde*' cd
  __assert_array '~-/tilde-root'

  COMPREPLY=(sentinel)
  __glob_complete_default cd '@(bar|foo)' cd
  __assert_array

  shopt -s extglob
  COMPREPLY=()
  __glob_complete_default cd '@(bar|foo)' cd
  __assert_array bar foo
  __glob_complete_word_has_glob '+(bar|foo)' ||
    __fail 'extglob +() pattern was not detected'
  __glob_complete_word_has_glob '!(bar|foo)' ||
    __fail 'extglob !() pattern was not detected'
  shopt -u extglob

  shopt -s nullglob failglob dotglob
  set -f
  COMPREPLY=(sentinel)
  __glob_complete_default cd 'no-match*' cd
  __assert_array
  shopt -q nullglob || __fail 'nullglob option was not restored'
  shopt -q failglob || __fail 'failglob option was not restored'
  shopt -q dotglob || __fail 'dotglob option was not preserved'
  [[ $- == *f* ]] || __fail 'noglob option was not restored'
  set +f
  shopt -u nullglob failglob dotglob

  if [[ ! -r $_bash_completion ]]; then
    __print_warn "not found: $_bash_completion; skipping bash-completion integration tests"
    printf 'all standalone tests passed\n'
    return 0
  fi

  # shellcheck disable=SC1090,SC1091 # Optional system dependency.
  . "$_bash_completion"
  declare -f _comp_compgen_filedir |
    grep -q -- '__glob_complete_generate_bash_completion_filedir' ||
    __fail 'bash-completion filename generator was not wrapped'
  declare -f _comp_complete_minimal |
    grep -q -- '__glob_complete_word_has_glob' ||
    __fail 'bash-completion minimal fallback was not wrapped'

  cur='*a'
  COMPREPLY=()
  _comp_compgen_filedir -d || true
  __assert_array bar baz

  # shellcheck disable=SC2016 # The literal parameter expansion is test input.
  cur='$TEST_GLOB_ROOT/*a'
  COMPREPLY=()
  _comp_compgen_filedir -d || true
  # shellcheck disable=SC2016 # The parameter syntax is expected output.
  __assert_array '$TEST_GLOB_ROOT/bar' '$TEST_GLOB_ROOT/baz'

  # shellcheck disable=SC2088 # The literal tilde is test input.
  cur='~/tilde*'
  COMPREPLY=()
  _comp_compgen_filedir -d || true
  # shellcheck disable=SC2088 # The literal tilde is expected output.
  __assert_array '~/tilde-root'

  cur='white*'
  COMPREPLY=()
  _comp_compgen_filedir || true
  __assert_array 'white room'

  cur='key*'
  COMPREPLY=()
  _comp_compgen_filedir || true
  __assert_array $'key\tword'

  cur='split*'
  COMPREPLY=()
  _comp_compgen_filedir || true
  __assert_array $'split\nentry'

  shopt -s extglob
  cur='@(bar|foo)'
  COMPREPLY=()
  _comp_compgen_filedir -d || true
  __assert_array bar foo
  shopt -u extglob

  cur='ba'
  COMPREPLY=()
  _comp_compgen_filedir -d || true
  __assert_array bar baz

  # shellcheck disable=SC2034 # Read indirectly by _comp_compgen_filedir.
  cur='*.t'
  COMPREPLY=()
  _comp_compgen_filedir txt || true
  __assert_array 'data.txt'

  # ---
  #  sourcing-order matrix
  # ---

  # A stand-in user completion file occupying BASH_COMPLETION_USER_FILE first.
  # It must never be discarded, regardless of sourcing order.  The name avoids
  # the letter 'a' so the fixture globs above never match it.
  local _user_file=$_tmp_dir/hook.sh
  # shellcheck disable=SC2016 # The counter must expand in the child Bash.
  printf \
    '%s\n' \
    '_CHAINED_USER_FILE_COUNT=$(( ${_CHAINED_USER_FILE_COUNT:-0} + 1 ))' \
    > "$_user_file"

  local _case
  local -a _arr_failed_cases=()
  for _case in 1 2 3 4 5 6; do
    # Verify each sourcing order in a completely fresh Bash process.
    # shellcheck disable=SC2016 # Positional parameters belong to the child Bash.
    if ! bash \
      --noprofile \
      --norc \
      -c \
      '
      set -eo pipefail

      _case=$1
      _tmp_dir=$2
      _glob=$3
      _bash_completion=$4
      _user_file=$5

      cd -- "$_tmp_dir"
      declare -g TEST_GLOB_ROOT=$_tmp_dir
      declare -g _CHAINED_USER_FILE_COUNT=0

      if [[ $_case == 4 ]]; then
        BASH_COMPLETION_USER_FILE=$_glob
      else
        BASH_COMPLETION_USER_FILE=$_user_file
      fi

      case $_case in
        1) . "$_glob" ;;
        2) . "$_glob"; . "$_bash_completion" ;;
        3) . "$_bash_completion"; . "$_glob" ;;
        4) . "$_bash_completion" ;;
        5) . "$_glob"; . "$_bash_completion"; . "$_glob" ;;
        6) . "$_bash_completion"; . "$_glob"; . "$_bash_completion" ;;
      esac

      [[ $BASH_COMPLETION_USER_FILE == "$_glob" ]] || {
        >&2 echo "case $_case: re-entry hook lost"
        exit 1
      }

      if [[ $_case == 1 ]]; then
        [[ $(complete -p -D) == *"__glob_complete_default"* ]] || {
          >&2 echo "case $_case: standalone default completion missing"
          exit 1
        }
        COMPREPLY=()
        __glob_complete_default cd "*a" cd
        [[ $(printf "%s " "${COMPREPLY[@]}") == "bar baz data.log data.txt " ]] || {
          >&2 echo "case $_case: bad COMPREPLY [${COMPREPLY[*]}]"
          exit 1
        }
      else
        [[ $(declare -f _comp_compgen_filedir) == *"__glob_complete_generate_bash_completion_filedir"* ]] || {
          >&2 echo "case $_case: filedir generator not wrapped"
          exit 1
        }
        [[ $(declare -f _comp_complete_minimal) == *"__glob_complete_word_has_glob"* ]] || {
          >&2 echo "case $_case: minimal fallback not wrapped"
          exit 1
        }

        cur="*a"
        COMPREPLY=()
        _comp_compgen_filedir -d || true
        [[ $(printf "%s " "${COMPREPLY[@]}") == "bar baz " ]] || {
          >&2 echo "case $_case: bad glob COMPREPLY [${COMPREPLY[*]}]"
          exit 1
        }

        cur="\$TEST_GLOB_ROOT/*a"
        COMPREPLY=()
        _comp_compgen_filedir -d || true
        [[ $(printf "%s " "${COMPREPLY[@]}") == "\$TEST_GLOB_ROOT/bar \$TEST_GLOB_ROOT/baz " ]] || {
          >&2 echo "case $_case: bad variable COMPREPLY [${COMPREPLY[*]}]"
          exit 1
        }

        cur="ba"
        COMPREPLY=()
        _comp_compgen_filedir -d || true
        [[ $(printf "%s " "${COMPREPLY[@]}") == "bar baz " ]] || {
          >&2 echo "case $_case: bad literal COMPREPLY [${COMPREPLY[*]}]"
          exit 1
        }
      fi

      # bash-completion sources the user file on every load; when this script
      # has taken over the hook, it sources the remembered file instead.
      _expected_count=1
      case $_case in
        1|4) _expected_count=0 ;;
        6)   _expected_count=2 ;;
      esac
      [[ $_CHAINED_USER_FILE_COUNT == "$_expected_count" ]] || {
        >&2 echo "case $_case: user file sourced $_CHAINED_USER_FILE_COUNT time(s), expected $_expected_count"
        exit 1
      }

      echo "case $_case: ok"
      ' \
      bash \
      "$_case" \
      "$_tmp_dir" \
      "$_SCRIPT_DIR/glob-complete.bash" \
      "$_bash_completion" \
      "$_user_file"
    then
      _arr_failed_cases+=("$_case")
    fi
  done

  if ((${#_arr_failed_cases[@]} != 0)); then
    __fail "sourcing-order case(s) failed: ${_arr_failed_cases[*]}"
  fi

  printf 'all tests passed\n'
}

__main "$@"
