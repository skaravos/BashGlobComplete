# shellcheck shell=bash
#
# Copyright (C) 2026 Stephen Karavos
# SPDX-License-Identifier: GPL-3.0-only
#
# <https://github.com/skaravos/BashGlobComplete>
#
# This file is meant to be sourced by an interactive Bash shell.
# It works both before and after bash-completion is loaded, and it is resilient
# to either file being sourced again afterwards.
#

[[ -n ${PS1} ]] && echo "dot sourcing ${BASH_SOURCE[0]}"

# ---
#  candidate generation
# ---

function __glob_complete_word_has_glob() {
  local _word=${1-}

  if [[ $_word == *'*'* || $_word == *'?'* || $_word == *'['* ]]; then
    return 0
  fi

  shopt -q extglob || return 1
  [[ $_word == *'@('* || $_word == *'+('* || $_word == *'!('* ]]
}

function __glob_complete_word_has_glob_in_directory() {
  local _word=${1-}
  local _directory

  [[ $_word == */* ]] || return 1
  _directory=${_word%/*}
  __glob_complete_word_has_glob "$_directory"
}

function __glob_complete_expand_variable_prefix() {
  local _word=$1
  local _expanded_word_name=$2
  local _expanded_prefix_name=$3
  local _typed_prefix_name=$4
  local _variable_name
  local _variable_declaration
  local _variable_value
  local _remainder
  local _prefix_spelling
  local -n _expanded_word_output=$_expanded_word_name
  local -n _expanded_prefix_output=$_expanded_prefix_name
  local -n _typed_prefix_output=$_typed_prefix_name

  _expanded_word_output=$_word
  _expanded_prefix_output=
  _typed_prefix_output=

  if [[ $_word =~ ^\$([_a-zA-Z][_a-zA-Z0-9]*)(/.*)?$ ]]; then
    _variable_name=${BASH_REMATCH[1]}
    _remainder=${BASH_REMATCH[2]}
    _prefix_spelling=\$$_variable_name
  elif [[ $_word =~ ^\$\{([_a-zA-Z][_a-zA-Z0-9]*)\}(/.*)?$ ]]; then
    _variable_name=${BASH_REMATCH[1]}
    _remainder=${BASH_REMATCH[2]}
    _prefix_spelling="\${${_variable_name}}"
  else
    return 1
  fi

  if ! _variable_declaration=$(declare -p -- "$_variable_name" 2>/dev/null)
  then
    return 1
  fi

  # Do not dereference arrays or namerefs.  In particular, a hostile nameref
  # target can execute expansions when read indirectly.
  if [[ $_variable_declaration =~ ^declare\ -[^[:space:]]*[aAn] ]]; then
    return 1
  fi

  _variable_value=${!_variable_name}
  _expanded_word_output=$_variable_value$_remainder
  _expanded_prefix_output=$_variable_value
  _typed_prefix_output=$_prefix_spelling
}

function __glob_complete_expand_tilde_prefix() {
  local _word=$1
  local _expanded_word_name=$2
  local _expanded_prefix_name=$3
  local _typed_prefix_name=$4
  local _remainder
  local _prefix_value
  local _prefix_spelling
  local -n _expanded_word_output=$_expanded_word_name
  local -n _expanded_prefix_output=$_expanded_prefix_name
  local -n _typed_prefix_output=$_typed_prefix_name

  _expanded_word_output=$_word
  _expanded_prefix_output=
  _typed_prefix_output=

  [[ $_word == '~'* ]] || return 1
  _prefix_spelling=${_word%%/*}
  _remainder=${_word#"$_prefix_spelling"}

  case $_prefix_spelling in
    '~')  _prefix_value=${HOME-} ;;
    '~+') _prefix_value=$PWD ;;
    '~-') _prefix_value=${OLDPWD-} ;;
    *)
      [[ $_prefix_spelling =~ ^~[a-zA-Z0-9._-]+$ ]] || return 1
      # The validated expression contains no shell metacharacters other than
      # the leading tilde and is evaluated only to invoke Bash's user lookup.
      eval -- "_prefix_value=$_prefix_spelling"
      [[ $_prefix_value != "$_prefix_spelling" ]] || return 1
      ;;
  esac
  [[ -n $_prefix_value ]] || return 1

  _expanded_word_output=$_prefix_value$_remainder
  _expanded_prefix_output=$_prefix_value
  _typed_prefix_output=$_prefix_spelling
}

function __glob_complete_expand_prefix() {
  __glob_complete_expand_variable_prefix "$@" ||
    __glob_complete_expand_tilde_prefix "$@"
}

function __glob_complete_expand_pattern() {
  local _pattern=$1
  local _output_name=$2
  local _nullglob_was_set=0
  local _failglob_was_set=0
  local _noglob_was_set=0
  local IFS=
  local -n _arr_pattern_output=$_output_name

  shopt -q nullglob && _nullglob_was_set=1
  shopt -q failglob && _failglob_was_set=1
  [[ $- == *f* ]] && _noglob_was_set=1

  shopt -s nullglob
  shopt -u failglob
  set +f

  # shellcheck disable=SC2206 # Pathname expansion must populate array entries.
  _arr_pattern_output=( $_pattern )

  ((_nullglob_was_set)) || shopt -u nullglob
  ((_failglob_was_set)) && shopt -s failglob
  ((_noglob_was_set)) && set -f
  return 0
}

function __glob_complete_collect_filedir() {
  local _arg=$1
  local _word=$2
  local _output_name=$3
  local _quote_as_shell_text=${4-off}
  local _pattern=$_word
  local _candidate
  local _display_candidate
  local _quoted_remainder
  local _remainder
  local _expanded_prefix=
  local _typed_prefix=
  local _xspec=
  local -a _arr_matches=()
  local -a _arr_filtered=()
  local -n _arr_output=$_output_name

  __glob_complete_expand_prefix \
    "$_word" _pattern _expanded_prefix _typed_prefix || true

  # Readline's glob-complete-word implicitly adds a trailing '*'.  Doing the
  # same is what makes '*a' match both 'bar' and 'baz'.
  _pattern+='*'
  __glob_complete_expand_pattern "$_pattern" _arr_matches

  if [[ $_arg != -d && -n $_arg ]]; then
    _xspec="*.@($_arg|${_arg^^})"
  fi

  for _candidate in "${_arr_matches[@]}"; do
    # Match bash-completion's normal filedir semantics: -d means directories
    # only; an extension filter still permits directories.
    if [[ $_arg == -d && ! -d $_candidate ]]; then
      continue
    fi
    # shellcheck disable=SC2053 # _xspec is intentionally an extglob pattern.
    if [[ -n $_xspec && ! -d $_candidate && $_candidate != $_xspec ]]; then
      continue
    fi
    if [[ $_word != */.. ]]; then
      case $_candidate in
        .|..|*/.|*/..)
            continue
          ;;
      esac
    fi
    _display_candidate=$_candidate
    if [[ -n $_typed_prefix && $_candidate == "$_expanded_prefix"* ]]; then
      _remainder=${_candidate#"$_expanded_prefix"}
      printf -v _quoted_remainder '%q' "$_remainder"
      _display_candidate=$_typed_prefix$_quoted_remainder
      if [[ -d $_candidate ]] &&
        [[ $_quote_as_shell_text == on || $_quoted_remainder != "$_remainder" ]]; then
        _display_candidate+=/
      fi
    elif [[ $_quote_as_shell_text == on ]]; then
      printf -v _display_candidate '%q' "$_candidate"
      [[ -d $_candidate ]] && _display_candidate+=/
    fi
    _arr_filtered+=("$_display_candidate")
  done

  _arr_output=("${_arr_filtered[@]}")
}

function __glob_complete_default() {
  local _cur=${2-}
  local _expanded_word
  local _expanded_prefix
  local _typed_prefix
  local _quote_as_shell_text=off

  COMPREPLY=()
  if __glob_complete_word_has_glob "$_cur"; then
    if __glob_complete_word_has_glob_in_directory "$_cur"; then
      _quote_as_shell_text=on
    fi
    __glob_complete_collect_filedir \
      '' "$_cur" COMPREPLY "$_quote_as_shell_text"
    if ((${#COMPREPLY[@]})); then
      if [[ $_quote_as_shell_text == on ]]; then
        # Readline displays only the basename of candidates marked as
        # filenames.  Preserve the full path when a directory component is a
        # glob, while retaining filename-safe insertion through pre-quoting.
        compopt +o filenames -o noquote 2>/dev/null || true
      else
        compopt -o filenames 2>/dev/null || true
      fi
      if [[ $_quote_as_shell_text == off ]] && __glob_complete_expand_prefix \
        "$_cur" _expanded_word _expanded_prefix _typed_prefix 2>/dev/null; then
        compopt -o noquote 2>/dev/null || true
      fi
    fi
  fi
}

function __glob_complete_generate_bash_completion_filedir() {
  local _arg=${1-}
  local _expanded_word
  local _expanded_prefix
  local _typed_prefix
  local _quote_as_shell_text=off
  local -a _arr_results=()

  if __glob_complete_word_has_glob_in_directory "${cur-}"; then
    _quote_as_shell_text=on
  fi
  __glob_complete_collect_filedir \
    "$_arg" "${cur-}" _arr_results "$_quote_as_shell_text"
  if ((${#_arr_results[@]})); then
    if [[ $_quote_as_shell_text == on ]]; then
      compopt +o filenames -o noquote 2>/dev/null || true
    else
      compopt -o filenames 2>/dev/null || true
    fi
    if [[ $_quote_as_shell_text == off ]] && __glob_complete_expand_prefix \
      "${cur-}" _expanded_word _expanded_prefix _typed_prefix 2>/dev/null; then
      compopt -o noquote 2>/dev/null || true
    fi
  fi
  _comp_compgen_set "${_arr_results[@]}"
}

# ---
#  installation
# ---

function __glob_complete_install_default() {
  complete -D -F __glob_complete_default -o bashdefault -o default
}

function __glob_complete_install_bash_completion() {
  local _definition

  declare -F -- _comp_compgen_filedir >/dev/null || return 1

  _definition=$(declare -f _comp_compgen_filedir)
  if [[ $_definition != *'__glob_complete_generate_bash_completion_filedir'* ]]; then
    _definition=${_definition/#_comp_compgen_filedir /__glob_complete_original_filedir }
    eval -- "$_definition"
  fi

  # shellcheck disable=SC2120 # Called with arguments by external completers.
  function _comp_compgen_filedir() {
    if __glob_complete_word_has_glob "${cur-}"; then
      __glob_complete_generate_bash_completion_filedir "${1-}"
    else
      __glob_complete_original_filedir "$@"
    fi
  }

  # When lazy loading finds no command-specific completion, bash-completion
  # installs this minimal function.  Preserve glob completion in that path as
  # well, without replacing bash-completion's default lazy loader.
  if declare -F -- _comp_complete_minimal >/dev/null; then
    _definition=$(declare -f _comp_complete_minimal)
    if [[ $_definition != *'__glob_complete_word_has_glob'* ]]; then
      _definition=${_definition/#_comp_complete_minimal /__glob_complete_original_minimal }
      eval -- "$_definition"
    fi

    function _comp_complete_minimal() {
      if __glob_complete_word_has_glob "${2-}"; then
        # shellcheck disable=SC2034 # Populated dynamically by _comp_initialize.
        local cur prev words cword comp_args
        _comp_initialize -- "$@" || return
        # shellcheck disable=SC2119 # Unfiltered filename completion is intended.
        _comp_compgen_filedir
      else
        __glob_complete_original_minimal "$@"
      fi
    }
  fi
}

function __glob_complete_register_bash_completion_reentry() {
  local _source_dir
  local _this_file
  local _user_file

  # NOTE: 'readlink' and 'realpath' on Git for Windows cannot canonicalize files
  # or absolute directories on a WSL UNC share. As a workaround we let Bash
  # enter the directory and report its physical path instead; this also works
  # with ordinary Linux paths and relative names
  _source_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
  _this_file=$_source_dir/$(basename -- "${BASH_SOURCE[0]}")
  _user_file=${BASH_COMPLETION_USER_FILE:-${HOME}/.bash_completion}

  if [[ ! -v _GLOB_COMPLETE_CHAINED_USER_FILE ]]; then
    if [[ $_user_file != "$_this_file" ]]; then
      declare -g _GLOB_COMPLETE_CHAINED_USER_FILE=$_user_file
    else
      declare -g _GLOB_COMPLETE_CHAINED_USER_FILE=
    fi
  fi

  # bash-completion sources this file near the end of its initialization.  It
  # therefore provides a generic, loader-independent way to install the
  # integration after bash-completion defines its helper functions.
  declare -g BASH_COMPLETION_USER_FILE=$_this_file
}

function __glob_complete_is_bash_completion_reentry() {
  local _source_file
  local _source_basename

  for _source_file in "${BASH_SOURCE[@]:1}"; do
    _source_basename=${_source_file##*/}
    case $_source_basename in
      bash_completion|bash_completion.sh) return 0 ;;
    esac
  done
  return 1
}

function __glob_complete_source_chained_user_file() {
  local _user_file=${_GLOB_COMPLETE_CHAINED_USER_FILE-}
  local _source_file

  if [[ -z $_user_file ]]; then
    return 0 # no user file
  fi

  for _source_file in "${BASH_SOURCE[@]}"; do
    if [[ $_user_file = "$_source_file" ]]; then
      return 0 # user file was already sourced in the current call stack
    fi
  done

  if [[ ! -r $_user_file || ! -f $_user_file || $_user_file = /dev/null ]]; then
    return 0 # user file cannot be read or is not a valid file
  fi

  # shellcheck disable=SC1090 # User-selected completion file is dynamic.
  . "$_user_file"
}

function __glob_complete_enable() {
  if declare -F -- _comp_compgen_filedir >/dev/null; then
    __glob_complete_install_bash_completion
  else
    __glob_complete_install_default
  fi
}

if declare -F -- _comp_compgen_filedir >/dev/null; then
  # If bash-completion called us through BASH_COMPLETION_USER_FILE, preserve
  # the user file that occupied that hook before this script registered itself.
  if __glob_complete_is_bash_completion_reentry; then
    __glob_complete_source_chained_user_file
  fi
fi

__glob_complete_enable

# Register the hook even when bash-completion is already loaded: sourcing
# bash-completion again replaces its helper functions, which would otherwise
# discard the integration installed above.
__glob_complete_register_bash_completion_reentry
