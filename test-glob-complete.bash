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

  unset GLOB_COMPLETE_FIND_COMMAND GLOB_COMPLETE_FZF
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
  mkdir -p \
    -- \
    "$_tmp_dir/bar" \
    "$_tmp_dir/baz" \
    "$_tmp_dir/foo" \
    "$_tmp_dir/project-one/first-Docker-app" \
    "$_tmp_dir/project-one/second-Docker-app" \
    "$_tmp_dir/project-one/.vscode" \
    "$_tmp_dir/project-two/.vscode" \
    "$_tmp_dir/.hidden" \
    "$_tmp_dir/node_modules/package" \
    "$_tmp_dir/tilde-root" \
    "$_tmp_dir/prefix room"
  touch \
    -- \
    "$_tmp_dir/data.txt" \
    "$_tmp_dir/data.log" \
    "$_tmp_dir/.hidden/ignored.txt" \
    "$_tmp_dir/node_modules/package/ignored.txt" \
    "$_tmp_dir/"$'split\nentry' \
    "$_tmp_dir/white room" \
    "$_tmp_dir/"$'key\tword' \
    "$_tmp_dir/project-one/read me.txt" \
    "$_tmp_dir/project-two/read me.txt"
  ln -s -- \
    "$_tmp_dir/project-one" \
    "$_tmp_dir/project-one/cycle"
  cd -- "$_tmp_dir"
  HOME=$_tmp_dir

  local _find_backend
  local _find_command
  local _found_data_txt=0
  local _found_directory=0
  local _found_excluded_path=0
  local _followed_symlink_cycle=0
  local _fzf_candidate
  local _scanner_name
  local _scanner_test_bin=$_tmp_dir/tools
  local -a _arr_fzf_candidates=()
  GLOB_COMPLETE_FIND_COMMAND=bash
  __glob_complete_select_find_command _find_backend _find_command ||
    __fail 'could not select the explicit Bash candidate scanner'
  [[ $_find_backend == bash && -z $_find_command ]] ||
    __fail "unexpected explicit scanner: $_find_backend [$_find_command]"
  readarray -d '' -t _arr_fzf_candidates < <(
    __glob_complete_generate_fzf_candidates \
      txt "$_tmp_dir" "$_find_backend" "$_find_command"
  )
  for _fzf_candidate in "${_arr_fzf_candidates[@]}"; do
    case $_fzf_candidate in
      "$_tmp_dir/data.txt") _found_data_txt=1 ;;
      "$_tmp_dir/project-one/") _found_directory=1 ;;
      */.hidden/*|*/node_modules/*) _found_excluded_path=1 ;;
      */cycle/?*) _followed_symlink_cycle=1 ;;
    esac
  done
  ((_found_data_txt)) || __fail 'Bash scanner omitted a matching file'
  ((_found_directory)) || __fail 'Bash scanner omitted a directory'
  ((! _found_excluded_path)) || __fail 'Bash scanner included an excluded path'
  ((! _followed_symlink_cycle)) || __fail 'Bash scanner followed a directory symlink'
  unset GLOB_COMPLETE_FIND_COMMAND

  mkdir -p -- "$_scanner_test_bin"
  for _scanner_name in find fdfind fd; do
    printf '#!/usr/bin/env bash\n' > "$_scanner_test_bin/$_scanner_name"
  done
  chmod +x -- "$_scanner_test_bin"/*

  PATH=$_scanner_test_bin \
    __glob_complete_select_find_command _find_backend _find_command ||
    __fail 'could not select find'
  [[ $_find_backend == find && $_find_command == find ]] ||
    __fail "find was not selected first: $_find_backend [$_find_command]"
  chmod -x -- "$_scanner_test_bin/find"

  PATH=$_scanner_test_bin \
    __glob_complete_select_find_command _find_backend _find_command ||
    __fail 'could not select fdfind'
  [[ $_find_backend == fd && $_find_command == fdfind ]] ||
    __fail "fdfind was not selected second: $_find_backend [$_find_command]"
  chmod -x -- "$_scanner_test_bin/fdfind"

  PATH=$_scanner_test_bin \
    __glob_complete_select_find_command _find_backend _find_command ||
    __fail 'could not select fd'
  [[ $_find_backend == fd && $_find_command == fd ]] ||
    __fail "fd was not selected third: $_find_backend [$_find_command]"
  chmod -x -- "$_scanner_test_bin/fd"

  PATH=$_scanner_test_bin \
    __glob_complete_select_find_command _find_backend _find_command ||
    __fail 'could not select the automatic Bash candidate scanner'
  [[ $_find_backend == bash && -z $_find_command ]] ||
    __fail "Bash was not selected last: $_find_backend [$_find_command]"

  GLOB_COMPLETE_FIND_COMMAND=unsupported
  if __glob_complete_select_find_command _find_backend _find_command; then
    __fail 'an unsupported explicit scanner was accepted'
  fi
  unset GLOB_COMPLETE_FIND_COMMAND

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
  __glob_complete_default cd 'project-*/.vscode' cd
  __assert_array \
    'project-one/.vscode/' \
    'project-two/.vscode/'

  COMPREPLY=()
  # shellcheck disable=SC2088 # The literal tilde is test input.
  __glob_complete_default cd '~/project-*/.vscode' cd
  # shellcheck disable=SC2088 # The literal tilde is expected output.
  __assert_array \
    '~/project-one/.vscode/' \
    '~/project-two/.vscode/'

  COMPREPLY=()
  __glob_complete_default stat 'project-*/*me.txt' stat
  __assert_array \
    'project-one/read\ me.txt' \
    'project-two/read\ me.txt'

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

  local _resolved_query
  local _resolved_root
  __glob_complete_resolve_fzf_root \
    "$_tmp_dir/project-o*/read" _resolved_root _resolved_query
  [[ $_resolved_root == "$_tmp_dir/project-one" ]] ||
    __fail "unexpected fzf root: $_resolved_root"
  [[ $_resolved_query == read ]] ||
    __fail "unexpected fzf query: $_resolved_query"

  __glob_complete_resolve_fzf_root \
    "$_tmp_dir/project-*/read" _resolved_root _resolved_query
  [[ $_resolved_root == "$_tmp_dir" ]] ||
    __fail "unexpected ambiguous fzf root: $_resolved_root"
  [[ $_resolved_query == "'project- read" ]] ||
    __fail "unexpected ambiguous fzf query: $_resolved_query"

  __glob_complete_resolve_fzf_root \
    "$_tmp_dir/project-o*/*Docker*/sc" _resolved_root _resolved_query
  [[ $_resolved_root == "$_tmp_dir/project-one" ]] ||
    __fail "unexpected partial fzf root: $_resolved_root"
  [[ $_resolved_query == "'Docker sc" ]] ||
    __fail "unexpected partial fzf query: $_resolved_query"

  __glob_complete_resolve_fzf_root \
    "$_tmp_dir/project-*/*Docker*/sc" _resolved_root _resolved_query
  [[ $_resolved_root == "$_tmp_dir" ]] ||
    __fail "unexpected multi-glob fzf root: $_resolved_root"
  [[ $_resolved_query == "'project- 'Docker sc" ]] ||
    __fail "unexpected multi-glob fzf query: $_resolved_query"

  __glob_complete_build_fzf_query 'literal\*star' _resolved_query fuzzy
  [[ $_resolved_query == 'literal*star' ]] ||
    __fail "unexpected escaped-glob fzf query: $_resolved_query"

  # Exercise fzf integration without requiring fzf itself.  The stand-in reads
  # the NUL-delimited candidate stream and returns the requested candidate.
  local _fzf_bin_dir=$_tmp_dir/fzf-bin
  local _original_path=$PATH
  mkdir -p -- "$_fzf_bin_dir"
  # shellcheck disable=SC2016 # The expressions belong to the generated script.
  printf \
    '%s\n' \
    '#!/usr/bin/env bash' \
    'set -eo pipefail' \
    '_header=' \
    '_query=' \
    '_read_stdin=0' \
    '_root=' \
    '_walker=' \
    'while (($#)); do' \
    '  case $1 in' \
    '    --header) _header=$2; shift 2 ;;' \
    '    --query) _query=$2; shift 2 ;;' \
    '    --read0) _read_stdin=1; shift ;;' \
    '    --walker-root) _root=$2; shift 2 ;;' \
    '    --walker=*) _walker=${1#--walker=}; shift ;;' \
    '    *) shift ;;' \
    '  esac' \
    'done' \
    '[[ $_header == "${GLOB_COMPLETE_FZF_TEST_HEADER-}" ]] || exit 2' \
    '[[ $_query == "${GLOB_COMPLETE_FZF_TEST_QUERY-}" ]] || exit 2' \
    '[[ $_root == "${GLOB_COMPLETE_FZF_TEST_ROOT-}" ]] || exit 2' \
    '[[ $_walker == "${GLOB_COMPLETE_FZF_TEST_WALKER-}" ]] || exit 2' \
    'case ${GLOB_COMPLETE_FZF_TEST_MODE-} in' \
    '  cancel) exit 130 ;;' \
    '  error) exit 2 ;;' \
    'esac' \
    '[[ -n ${GLOB_COMPLETE_FZF_TEST_SELECTION-} ]] || exit 2' \
    'if ((_read_stdin)); then' \
    '  while IFS= read -r -d "" _candidate; do :; done' \
    'fi' \
    'printf "%s\\0" "$GLOB_COMPLETE_FZF_TEST_SELECTION"' \
    > "$_fzf_bin_dir/fzf"
  chmod +x -- "$_fzf_bin_dir/fzf"

  PATH=$_fzf_bin_dir:$_original_path
  GLOB_COMPLETE_FZF=1
  export GLOB_COMPLETE_FZF_TEST_HEADER='root: .'
  export GLOB_COMPLETE_FZF_TEST_MODE=
  export GLOB_COMPLETE_FZF_TEST_QUERY=project
  export GLOB_COMPLETE_FZF_TEST_ROOT=.
  export GLOB_COMPLETE_FZF_TEST_SELECTION='project-one/read me.txt'
  export GLOB_COMPLETE_FZF_TEST_WALKER=file,dir,follow
  COMPREPLY=()
  __glob_complete_default stat 'project**' stat
  __assert_array 'project-one/read me.txt'

  GLOB_COMPLETE_FZF_TEST_QUERY='split'
  GLOB_COMPLETE_FZF_TEST_SELECTION=$'split\nentry'
  COMPREPLY=()
  __glob_complete_default stat 'split**' stat
  __assert_array $'split\nentry'

  GLOB_COMPLETE_FZF_TEST_QUERY='read'
  GLOB_COMPLETE_FIND_COMMAND=bash
  GLOB_COMPLETE_FZF_TEST_HEADER="root: $_tmp_dir/project-one"
  GLOB_COMPLETE_FZF_TEST_ROOT=$_tmp_dir/project-one
  GLOB_COMPLETE_FZF_TEST_SELECTION=$_tmp_dir/project-one/read\ me.txt
  COMPREPLY=()
  # shellcheck disable=SC2088 # The literal tilde is test input.
  __glob_complete_default stat '~/project-o*/read**' stat
  # shellcheck disable=SC2088 # The literal tilde is expected output.
  __assert_array '~/project-one/read\ me.txt'

  GLOB_COMPLETE_FZF_TEST_HEADER='root: .'
  GLOB_COMPLETE_FZF_TEST_MODE=cancel
  GLOB_COMPLETE_FZF_TEST_QUERY=project
  GLOB_COMPLETE_FZF_TEST_ROOT=.
  GLOB_COMPLETE_FZF_TEST_SELECTION=
  COMPREPLY=()
  __glob_complete_default stat 'project**' stat
  __assert_array 'project**'

  GLOB_COMPLETE_FZF_TEST_MODE=error
  GLOB_COMPLETE_FZF_TEST_QUERY=a
  GLOB_COMPLETE_FZF_TEST_WALKER=file,dir,follow
  COMPREPLY=()
  __glob_complete_default stat '*a**' stat
  __assert_array bar baz data.log data.txt

  # A missing executable takes the same ordinary-glob fallback path.
  # shellcheck disable=SC2123 # An empty PATH deliberately hides fzf.
  PATH=
  GLOB_COMPLETE_FZF_TEST_MODE=
  COMPREPLY=()
  __glob_complete_default stat '*a**' stat
  __assert_array bar baz data.log data.txt
  PATH=$_original_path
  unset \
    GLOB_COMPLETE_FZF \
    GLOB_COMPLETE_FZF_TEST_HEADER \
    GLOB_COMPLETE_FIND_COMMAND \
    GLOB_COMPLETE_FZF_TEST_MODE \
    GLOB_COMPLETE_FZF_TEST_QUERY \
    GLOB_COMPLETE_FZF_TEST_ROOT \
    GLOB_COMPLETE_FZF_TEST_SELECTION \
    GLOB_COMPLETE_FZF_TEST_WALKER

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

  PATH=$_fzf_bin_dir:$_original_path
  GLOB_COMPLETE_FZF=1
  export GLOB_COMPLETE_FZF_TEST_HEADER='root: .'
  export GLOB_COMPLETE_FZF_TEST_MODE=
  export GLOB_COMPLETE_FZF_TEST_QUERY=project
  export GLOB_COMPLETE_FZF_TEST_ROOT=.
  export GLOB_COMPLETE_FZF_TEST_SELECTION='project-one/'
  export GLOB_COMPLETE_FZF_TEST_WALKER=dir,follow
  cur='project**'
  COMPREPLY=()
  _comp_compgen_filedir -d || true
  __assert_array project-one

  GLOB_COMPLETE_FZF_TEST_QUERY='read'
  GLOB_COMPLETE_FIND_COMMAND=bash
  GLOB_COMPLETE_FZF_TEST_HEADER='root: project-one'
  GLOB_COMPLETE_FZF_TEST_ROOT=
  GLOB_COMPLETE_FZF_TEST_SELECTION='project-one/read me.txt'
  GLOB_COMPLETE_FZF_TEST_WALKER=
  cur='project-one/read**'
  COMPREPLY=()
  _comp_compgen_filedir txt || true
  __assert_array 'project-one/read me.txt'

  PATH=$_original_path
  unset \
    GLOB_COMPLETE_FZF \
    GLOB_COMPLETE_FZF_TEST_HEADER \
    GLOB_COMPLETE_FIND_COMMAND \
    GLOB_COMPLETE_FZF_TEST_MODE \
    GLOB_COMPLETE_FZF_TEST_QUERY \
    GLOB_COMPLETE_FZF_TEST_ROOT \
    GLOB_COMPLETE_FZF_TEST_SELECTION \
    GLOB_COMPLETE_FZF_TEST_WALKER

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

  cur='project-*/.vscode'
  COMPREPLY=()
  _comp_compgen_filedir -d || true
  __assert_array \
    'project-one/.vscode/' \
    'project-two/.vscode/'

  # shellcheck disable=SC2088 # The literal tilde is test input.
  cur='~/project-*/.vscode'
  COMPREPLY=()
  _comp_compgen_filedir -d || true
  # shellcheck disable=SC2088 # The literal tilde is expected output.
  __assert_array \
    '~/project-one/.vscode/' \
    '~/project-two/.vscode/'

  cur='project-*/*me.txt'
  COMPREPLY=()
  _comp_compgen_filedir || true
  __assert_array \
    'project-one/read\ me.txt' \
    'project-two/read\ me.txt'

  shopt -s extglob
  cur='@(bar|foo)'
  COMPREPLY=()
  _comp_compgen_filedir -d || true
  __assert_array bar foo
  shopt -u extglob

  cur='ba'
  COMPREPLY=()
  _comp_compgen_filedir -d || true
  # NOTE: a pattern with no glob chars is delegated to bash-completion, whose
  # direct call to 'compgen' returns entries in an unspecified order
  [[ ${COMPREPLY[*]} == 'bar baz' || ${COMPREPLY[*]} == 'baz bar' ]] ||
    __fail "expected bar and baz in either order, got [${COMPREPLY[*]}]"

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

  # shellcheck disable=SC2016 # Positional parameters belong to the child Bash.
  local _child_script='
      set -eo pipefail

      _case=${1:?"missing arg 1"}
      _tmp_dir=${2:?"missing arg 2"}
      _glob=${3:?"missing arg 3"}
      _bash_completion=${4:?"missing arg 4"}
      _user_file=${5:?"missing arg 5"}

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
        [[ ${COMPREPLY[*]} == "bar baz" || ${COMPREPLY[*]} == "baz bar" ]] || {
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
      '

  local _case
  local -a _arr_failed_cases=()
  for _case in 1 2 3 4 5 6; do
    # Verify each sourcing order in a completely fresh Bash process.
    local -a _arr_bash_args=(
      --noprofile
      --norc
      -c
      "$_child_script"
      bash              # $0
      "$_case"          # $1
      "$_tmp_dir"       # ...
      "$_SCRIPT_DIR/glob-complete.bash"
      "$_bash_completion"
      "$_user_file"
    )
    if ! bash "${_arr_bash_args[@]}"; then
      _arr_failed_cases+=("$_case")
    fi
  done

  if ((${#_arr_failed_cases[@]} != 0)); then
    __fail "sourcing-order case(s) failed: ${_arr_failed_cases[*]}"
  fi

  printf 'all tests passed\n'
}

__main "$@"
