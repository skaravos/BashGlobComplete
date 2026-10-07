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

function __assert_array() {
  local -a _arr_expected=("$@")
  local _index

  ((${#COMPREPLY[@]} == ${#_arr_expected[@]})) ||
    __fail "expected [${_arr_expected[*]}], got [${COMPREPLY[*]}]"
  for _index in "${!_arr_expected[@]}"; do
    [[ ${COMPREPLY[_index]} == "${_arr_expected[_index]}" ]] ||
      __fail "expected [${_arr_expected[*]}], got [${COMPREPLY[*]}]"
  done
}

function __complete() {
  local _spec
  local _function
  local _attempt
  local _status

  COMP_WORDS=("$@")
  COMP_CWORD=$((${#COMP_WORDS[@]} - 1))
  COMP_LINE=${_TEST_LINE:-${COMP_WORDS[*]}}
  COMP_POINT=${#COMP_LINE}
  COMPREPLY=()
  _TEST_OPTIONS=()

  for _attempt in 1 2; do
    _spec=$(complete -p -- "$1" 2>/dev/null) || _spec=$(complete -p -D)
    [[ $_spec =~ -F\ ([^[:space:]]+) ]] || __fail "no function in $_spec"
    _function=${BASH_REMATCH[1]}
    _status=0
    "$_function" "$1" "${COMP_WORDS[COMP_CWORD]}" \
      "${COMP_WORDS[COMP_CWORD-1]}" || _status=$?
    [[ $_status == 124 ]] || return 0
  done
  __fail 'completion did not finish after lazy loading'
}

# Capture the options which compopt normally changes during real completion.
function compopt() {
  local _value
  while (($#)); do
    case $1 in
      -o) _value=on ;;
      +o) _value=off ;;
      *) __fail "unexpected compopt argument $1" ;;
    esac
    shift
    _TEST_OPTIONS[$1]=$_value
    shift
  done
}

function __cleanup() {
  # The absolute parent is recorded before mktemp creates the directory.
  case ${_TEST_TMP_DIR-} in
    "${_TEST_TMP_PARENT:?}"/glob-complete-git.*)
      if [[ -d $_TEST_TMP_DIR ]]; then
        rm -rf -- "$_TEST_TMP_DIR" || true
      fi
      ;;
  esac
}

# ---
#  isolated integration cases
# ---

function __case() {
  local _case=${1:?"missing case"}
  local _root=${2:?"missing fixture directory"}
  local _git_completion=${3:?"missing Git completion file"}
  local _bash_completion=${4-}
  local _glob=$_SCRIPT_DIR/glob-complete.bash
  local _pwd_before
  local _oldpwd_before
  local -a _arr_stack_before=()
  local -a _arr_native=()

  declare -g -A _TEST_OPTIONS=()
  export BASH_COMPLETION_USER_FILE=/dev/null
  unset GLOB_COMPLETE_FZF GLOB_COMPLETE_FZF_SKIP GIT_WORK_TREE GIT_DIR
  cd -- "$_root"

  case $_case in
    standalone)
      # shellcheck disable=SC1090 # No Git or bash-completion scripts loaded.
      . "$_glob"
      ;;
    after)
      # shellcheck disable=SC1090 # The caller locates the installed Git script.
      . "$_git_completion"
      # shellcheck disable=SC1090 # The module path is relative to this script.
      . "$_glob"
      ;;
    before|reload)
      # shellcheck disable=SC1090 # The module path is relative to this script.
      . "$_glob"
      # shellcheck disable=SC1090 # The caller locates the installed Git script.
      . "$_git_completion"
      __glob_complete_git_prompt
      if [[ $_case == reload ]]; then
        # shellcheck disable=SC1090 # Exercise independent Git script reloads.
        . "$_git_completion"
        __glob_complete_git_prompt
        # shellcheck disable=SC1090 # Exercise repeated module loads.
        . "$_glob"
      fi
      ;;
    lazy-before|lazy-after)
      if [[ $_case == lazy-before ]]; then
        # shellcheck disable=SC1090 # Optional installed dependency.
        . "$_bash_completion"
      fi
      # shellcheck disable=SC1090 # The module path is relative to this script.
      . "$_glob"
      if [[ $_case == lazy-after ]]; then
        # shellcheck disable=SC1090 # Optional installed dependency.
        . "$_bash_completion"
      fi
      # A first completion must load Git and run the adapter on the retry.
      declare -F -- __git_func_wrap >/dev/null && __fail 'Git loaded too early'
      ;;
    legacy-loader)
      function _completion_loader() {
        # shellcheck disable=SC1090 # The fixture selects the installed script.
        . "$_git_completion"
        return 124
      }
      complete -D -F _completion_loader
      # shellcheck disable=SC1090 # The module path is relative to this script.
      . "$_glob"
      [[ $(complete -p -D) == *'-F _completion_loader'* ]] ||
        __fail 'the legacy Git lazy loader was replaced'
      ;;
    *) __fail "unknown case $_case" ;;
  esac

  # -- the reported failures and directory-only filtering
  __complete git checkout -- './*foo'
  __assert_array \
    './alpha-foo.txt' './beta-foo.txt' './ignored-foo.txt' \
    './scratch-foo.txt' './space foo.txt'
  [[ ${_TEST_OPTIONS[nospace]-} == off ]] || __fail 'Git nospace was not cleared'

  __complete git -C './some/dir/*xampl'
  __assert_array './some/dir/example-one' './some/dir/example-two'
  __complete git -C ./some -C 'dir/*xampl'
  __assert_array 'dir/example-one/' 'dir/example-two/'
  __complete git -C./some '-Cdir/*xampl'
  __assert_array '-Cdir/example-one/' '-Cdir/example-two/'

  _pwd_before=$PWD
  _oldpwd_before=${OLDPWD-}
  _arr_stack_before=("${DIRSTACK[@]}")
  __complete git -C ./some -C '' -C dir/example-one checkout -- '*foo'
  __assert_array 'inner-foo.txt'
  [[ $PWD == "$_pwd_before" && ${OLDPWD-} == "$_oldpwd_before" ]] ||
    __fail 'Git completion changed PWD or OLDPWD'
  [[ ${DIRSTACK[*]} == "${_arr_stack_before[*]}" ]] ||
    __fail 'Git completion changed the directory stack'

  __complete git --work-tree=./some/dir/example-one checkout -- '*foo'
  __assert_array 'inner-foo.txt'
  __complete git --work-tree ./some/dir/example-one checkout -- '*foo'
  __assert_array 'inner-foo.txt'
  # Simulate Bash's '=' word break for an attached directory option.
  _TEST_LINE='git --work-tree=./some/dir/*xampl' \
    __complete git --work-tree = './some/dir/*xampl'
  __assert_array './some/dir/example-one' './some/dir/example-two'
  export GIT_WORK_TREE=./some/dir/example-one
  __complete git checkout -- '*foo'
  __assert_array 'inner-foo.txt'
  unset GIT_WORK_TREE

  __complete git checkout -- './some/dir/*xampl*/*foo'
  __assert_array './some/dir/example-one/inner-foo.txt'
  [[ ${_TEST_OPTIONS[noquote]-} == on && ${_TEST_OPTIONS[filenames]-} == off ]] ||
    __fail 'full-path display did not use pre-quoted candidates'

  __complete git -C './some/*/example-o'
  __assert_array './some/dir/example-one/'
  [[ ${_TEST_OPTIONS[nospace]-} == on ]] || __fail 'directory gets a trailing space'

  # -- prefixes, extglob, letter case, and paths outside a repository
  export GIT_TEST_ROOT=$_root
  # shellcheck disable=SC2016 # Keep the variable prefix as command-line text.
  __complete git checkout -- '$GIT_TEST_ROOT/alpha*foo'
  # shellcheck disable=SC2016 # Completion must retain the variable prefix.
  __assert_array '$GIT_TEST_ROOT/alpha-foo.txt'
  HOME=$_root
  # shellcheck disable=SC2088 # Test the literal tilde prefix.
  __complete git checkout -- '~/alpha*foo'
  # shellcheck disable=SC2088 # Completion must retain the tilde prefix.
  __assert_array '~/alpha-foo.txt'

  shopt -s extglob
  __complete git checkout -- '@(alpha|beta)-foo'
  __assert_array 'alpha-foo.txt' 'beta-foo.txt'
  shopt -u extglob
  shopt -s nocaseglob
  __complete git checkout -- 'ALPHA*foo'
  __assert_array 'alpha-foo.txt'
  shopt -u nocaseglob

  __complete git -C ./some/dir/example-one -C "$_root" checkout -- 'alpha*foo'
  __assert_array 'alpha-foo.txt'
  # Prefixes expand in the invoking shell, before Git applies -C.
  # shellcheck disable=SC2016 # Keep variable prefixes as command-line text.
  __complete git -C ./some/dir/example-one checkout -- '$PWD/alpha*foo'
  # shellcheck disable=SC2016 # Retain the variable prefix.
  __assert_array '$PWD/alpha-foo.txt'
  # shellcheck disable=SC2088 # Test literal tilde prefixes.
  __complete git -C ./some/dir/example-one checkout -- '~+/alpha*foo'
  # shellcheck disable=SC2088 # Retain the tilde prefix.
  __assert_array '~+/alpha-foo.txt'
  OLDPWD=$_root
  # shellcheck disable=SC2016 # Keep variable prefixes as command-line text.
  __complete git -C ./some/dir/example-one checkout -- '$OLDPWD/beta*foo'
  # shellcheck disable=SC2016 # Retain the variable prefix.
  __assert_array '$OLDPWD/beta-foo.txt'
  # shellcheck disable=SC2088 # Test literal tilde prefixes.
  __complete git -C ./some/dir/example-one checkout -- '~-/beta*foo'
  # shellcheck disable=SC2088 # Retain the tilde prefix.
  __assert_array '~-/beta-foo.txt'

  __complete git --work-tree ./some/dir/example-one tag -F 'alpha*foo'
  __assert_array 'alpha-foo.txt'
  _TEST_LINE='git --work-tree ./some/dir/example-one tag --file=alpha*foo' \
    __complete git --work-tree ./some/dir/example-one tag --file = 'alpha*foo'
  __assert_array 'alpha-foo.txt'
  __complete git -C ./some/dir/example-one --work-tree "$_root" tag -F 'inner*foo'
  __assert_array 'inner-foo.txt'
  __complete git --work-tree ./some/dir/example-one commit -F 'inner*foo'
  __assert_array 'inner-foo.txt'

  __complete git -C does-not-exist checkout -- 'alpha*foo'
  __assert_array
  cd -- "$_root/some/dir/example-one"
  __complete git -C '*'
  __assert_array
  cd -- "$_root"

  if command -v cygpath >/dev/null 2>&1; then
    local _windows_root
    _windows_root=$(cygpath -m "$_root")
    _TEST_LINE="git -C $_windows_root/some/dir/*xampl" \
      __complete git -C "${_windows_root%%:*}" : "${_windows_root#*:}/some/dir/*xampl"
    __assert_array \
      "${_windows_root#*:}/some/dir/example-one/" \
      "${_windows_root#*:}/some/dir/example-two/"
    _TEST_LINE="git -C$_windows_root/some/dir/*xampl" \
      __complete git "-C${_windows_root%%:*}" : "${_windows_root#*:}/some/dir/*xampl"
    __assert_array \
      "${_windows_root#*:}/some/dir/example-one/" \
      "${_windows_root#*:}/some/dir/example-two/"
    __complete git -C "$_windows_root" checkout -- 'alpha*foo'
    __assert_array 'alpha-foo.txt'
  fi

  # -- additional path contexts
  __complete git add '*foo'
  __assert_array \
    'alpha-foo.txt' 'beta-foo.txt' 'ignored-foo.txt' 'scratch-foo.txt' 'space foo.txt'
  __complete git log -- 'alpha*foo'
  __assert_array 'alpha-foo.txt'
  __complete git reset -- 'alpha*foo'
  __assert_array 'alpha-foo.txt'
  __complete git commit -F 'alpha*foo'
  __assert_array 'alpha-foo.txt'
  __complete git init './some/dir/*xampl'
  __assert_array './some/dir/example-one' './some/dir/example-two'

  if [[ $_case == standalone ]]; then
    printf 'Git case standalone: ok\n'
    return
  fi

  # -- repository aliases and shell quoting
  __complete git co -- 'alpha*foo'
  __assert_array 'alpha-foo.txt'
  __complete git checkout -- './space\ *foo'
  __assert_array './space foo.txt'
  _TEST_LINE='git commit --file=alpha*foo' \
    __complete git commit --file = 'alpha*foo'
  __assert_array 'alpha-foo.txt'

  # -- the fzf feature uses the same directory base and completion options
  PATH=$_root/tools:$PATH
  export GLOB_COMPLETE_FZF=1
  export GIT_TEST_FZF_SELECTION=inner-foo.txt
  __complete git -C ./some/dir/example-one checkout -- '**'
  __assert_array 'inner-foo.txt'
  # Prefix restoration also applies to fzf selections from a different -C root.
  export GIT_TEST_FZF_SELECTION=$_root/alpha-foo.txt
  # shellcheck disable=SC2016 # Keep the variable prefix as command-line text.
  __complete git -C ./some/dir/example-one checkout -- '$PWD/**'
  # shellcheck disable=SC2016 # Retain the variable prefix.
  __assert_array '$PWD/alpha-foo.txt'
  # shellcheck disable=SC2088 # Test the literal tilde prefix.
  __complete git -C ./some/dir/example-one checkout -- '~+/**'
  # shellcheck disable=SC2088 # Retain the tilde prefix.
  __assert_array '~+/alpha-foo.txt'
  export GIT_TEST_FZF_SELECTION=some/dir/example-one/
  __complete git -C '**'
  __assert_array 'some/dir/example-one'
  export GIT_TEST_FZF_SELECTION='sub room/'
  __complete git -C ./some/dir/example-two -C '**'
  __assert_array 'sub\ room/'
  [[ ${_TEST_OPTIONS[nospace]-} == on ]] || __fail 'fzf directory gets a space'
  export GIT_TEST_FZF_CANCEL=1
  __complete git checkout -- './space\ *foo**'
  __assert_array './space\ *foo**'
  [[ ${_TEST_OPTIONS[noquote]-} == on && ${_TEST_OPTIONS[nospace]-} == on ]] ||
    __fail 'fzf cancellation did not preserve the command line'
  unset GIT_TEST_FZF_CANCEL
  export GIT_TEST_FZF_ERROR=1
  __complete git checkout -- 'alpha*foo**'
  __assert_array 'alpha-foo.txt'
  unset GIT_TEST_FZF_ERROR GLOB_COMPLETE_FZF

  # -- Git's own completion remains authoritative without a path context
  __complete git checkout ma
  __assert_array 'main '
  __complete git checkout --qui
  __assert_array '--quiet '

  local _command
  for _command in branch tag log; do
    __complete git "$_command" 'alpha*foo'
    _arr_native=("${COMPREPLY[@]}")
    COMPREPLY=()
    __glob_complete_original_git_wrap __git_main || true
    __assert_array "${_arr_native[@]}"
  done
  __complete git checkout -b 'alpha*foo'
  __assert_array
  __complete git commit -C 'alpha*foo'
  __assert_array
  __complete git log --format='alpha*foo'
  __assert_array
  __complete git branch -- 'alpha*foo'
  __assert_array

  # -- git.exe and aliases registered through Git's public API
  __git_complete git.exe git
  __complete git.exe checkout -- 'alpha*foo'
  __assert_array 'alpha-foo.txt'
  __git_complete gc git_checkout
  __complete gc -- 'alpha*foo'
  __assert_array 'alpha-foo.txt'

  # -- prompt callbacks retain their status, structure and order
  PROMPT_COMMAND='_TEST_PROMPT_STATUS=$?'
  __glob_complete_register_git_prompt
  __glob_complete_register_git_prompt
  set +e
  (exit 7)
  eval "$PROMPT_COMMAND"
  set -e
  [[ $_TEST_PROMPT_STATUS == 7 ]] || __fail 'scalar prompt lost exit status'
  unset PROMPT_COMMAND
  declare -a PROMPT_COMMAND=('_TEST_PROMPT_STATUS=$?' '_TEST_PROMPT_SECOND=ok')
  __glob_complete_register_git_prompt
  __glob_complete_register_git_prompt
  ((${#PROMPT_COMMAND[@]} == 3)) || __fail 'array prompt hook was duplicated'
  set +e
  (exit 9)
  eval "${PROMPT_COMMAND[0]}"
  eval "${PROMPT_COMMAND[1]}"
  eval "${PROMPT_COMMAND[2]}"
  set -e
  [[ $_TEST_PROMPT_STATUS == 9 && $_TEST_PROMPT_SECOND == ok ]] ||
    __fail 'array prompt lost exit status or callback order'

  printf 'Git case %s: ok\n' "$_case"
}

# ---
#  main
# ---

function __main() {
  if [[ ${1-} == --case ]]; then
    shift
    __case "$@"
    return
  fi

  local _git_completion=${GIT_COMPLETION_FILE-}
  local _bash_completion=${BASH_COMPLETION_FILE:-/usr/share/bash-completion/bash_completion}
  local _git_exec_path
  local _candidate
  local _case
  local -a _arr_cases=(standalone after before reload legacy-loader)

  if ! command -v git >/dev/null 2>&1; then
    printf 'Git tests skipped: git is not installed\n'
    return
  fi
  if [[ -z $_git_completion ]]; then
    _git_exec_path=$(git --exec-path)
    for _candidate in \
      /usr/share/bash-completion/completions/git \
      /usr/share/git/completion/git-completion.bash \
      "$_git_exec_path/../../share/git/completion/git-completion.bash"; do
      if [[ -r $_candidate ]]; then
        _git_completion=$_candidate
        break
      fi
    done
  fi
  if [[ ! -r $_git_completion ]]; then
    printf 'Git tests skipped: set GIT_COMPLETION_FILE to git-completion.bash\n'
    return
  fi
  if [[ -r $_bash_completion ]]; then
    _arr_cases+=(lazy-before lazy-after)
  fi

  declare -g _TEST_TMP_PARENT
  _TEST_TMP_PARENT=$(cd -- "${TMPDIR:-/tmp}" && pwd -P)
  declare -g _TEST_TMP_DIR
  _TEST_TMP_DIR=$(mktemp -d "$_TEST_TMP_PARENT/glob-complete-git.XXXXXX")
  trap __cleanup EXIT
  mkdir -p -- \
    "$_TEST_TMP_DIR/some/dir/example-one" "$_TEST_TMP_DIR/some/dir/example-two/sub room"
  touch -- \
    "$_TEST_TMP_DIR/alpha-foo.txt" "$_TEST_TMP_DIR/beta-foo.txt" \
    "$_TEST_TMP_DIR/space foo.txt" "$_TEST_TMP_DIR/some/dir/example-file" \
    "$_TEST_TMP_DIR/some/dir/example-one/inner-foo.txt"
  printf 'ignored-foo.txt\n' > "$_TEST_TMP_DIR/.gitignore"
  git -C "$_TEST_TMP_DIR" -c init.defaultBranch=main init -q
  git -C "$_TEST_TMP_DIR" -c core.autocrlf=false add .
  git -C "$_TEST_TMP_DIR" -c user.name=Test -c user.email=test@example.invalid \
    -c commit.gpgsign=false commit -qm 'Completion fixture'
  touch -- "$_TEST_TMP_DIR/scratch-foo.txt" "$_TEST_TMP_DIR/ignored-foo.txt"
  git -C "$_TEST_TMP_DIR" config alias.co checkout

  mkdir -- "$_TEST_TMP_DIR/tools"
  # shellcheck disable=SC2016 # These variables belong to the fake fzf process.
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    '[[ ${GIT_TEST_FZF_CANCEL-} != 1 ]] || exit 130' \
    '[[ ${GIT_TEST_FZF_ERROR-} != 1 ]] || exit 2' \
    'printf "%s\0" "$GIT_TEST_FZF_SELECTION"' > "$_TEST_TMP_DIR/tools/fzf"
  chmod +x -- "$_TEST_TMP_DIR/tools/fzf"

  for _case in "${_arr_cases[@]}"; do
    bash --noprofile --norc "$_SCRIPT_DIR/$_SCRIPT_BASENAME" \
      --case "$_case" "$_TEST_TMP_DIR" "$_git_completion" "$_bash_completion"
  done
  printf 'all Git tests passed\n'
}

__main "$@"
