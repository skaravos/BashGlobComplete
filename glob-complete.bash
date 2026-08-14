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
#region shared completion functions
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

function __glob_complete_format_candidate() {
  local _candidate=$1
  local _expanded_prefix=$2
  local _typed_prefix=$3
  local _quote_as_shell_text=$4
  local _output_name=$5
  local _quoted_remainder
  local _remainder
  local -n _output=$_output_name

  _output=$_candidate
  if [[ -n $_typed_prefix && $_candidate == "$_expanded_prefix"* ]]; then
    _remainder=${_candidate#"$_expanded_prefix"}
    printf -v _quoted_remainder '%q' "$_remainder"
    _output=$_typed_prefix$_quoted_remainder
    if [[ -d $_candidate ]] &&
      [[ $_quote_as_shell_text == on || $_quoted_remainder != "$_remainder" ]]; then
      _output+=/
    fi
  elif [[ $_quote_as_shell_text == on ]]; then
    printf -v _output '%q' "$_candidate"
    [[ -d $_candidate ]] && _output+=/
  fi
  return 0
}

#endregion

# ---
#region fzf-specific functions
# ---

function __glob_complete_select_find_command() {
  local _backend_name=$1
  local _command_name=$2
  local _candidate
  local _candidate_name
  local _candidate_path
  local -n _backend_output=$_backend_name
  local -n _command_output=$_command_name

  _backend_output=
  _command_output=

  if [[ -n ${GLOB_COMPLETE_FIND_COMMAND-} ]]; then
    _candidate=$GLOB_COMPLETE_FIND_COMMAND
    _candidate_name=${_candidate##*/}
    case $_candidate_name in
      bash)
        _backend_output=bash
        return 0
        ;;
      find) _backend_output='find' ;;
      fdfind|fd) _backend_output=fd ;;
      *) return 1 ;;
    esac
    _candidate_path=$(type -P -- "$_candidate" 2>/dev/null) || return 1
    [[ -x $_candidate_path ]] || return 1
    _command_output=$_candidate
    return 0
  fi

  for _candidate in find fdfind fd; do
    _candidate_path=$(type -P -- "$_candidate" 2>/dev/null) || continue
    [[ -x $_candidate_path ]] || continue
    case $_candidate in
      find) _backend_output='find' ;;
      fdfind|fd) _backend_output=fd ;;
    esac
    _command_output=$_candidate
    return 0
  done

  _backend_output=bash
}

function __glob_complete_generate_bash_fzf_paths() {
  local _root=$1
  local _type=${2-all}

  (
    shopt -s nullglob
    shopt -u dotglob

    function __glob_complete_walk_bash_fzf_directory() {
      local _directory=$1
      local _candidate

      for _candidate in "${_directory%/}"/*; do
        [[ -e $_candidate || -L $_candidate ]] || continue
        case ${_candidate##*/} in
          .git|node_modules) continue ;;
        esac
        if [[ $_type != directory || -d $_candidate ]]; then
          printf '%s\0' "$_candidate"
        fi
        if [[ -d $_candidate && ! -L $_candidate ]]; then
          __glob_complete_walk_bash_fzf_directory "$_candidate"
        fi
      done
    }

    __glob_complete_walk_bash_fzf_directory "$_root"
  )
}

function __glob_complete_generate_fzf_paths() {
  local _backend=$1
  local _command=$2
  local _root=$3

  case $_backend in
    find)
      command "$_command" -L "$_root" -mindepth 1 \
        \( -name .git -o -name node_modules -o -name '.*' \) -prune -o \
        \( -type d -o -type f -o -type l \) -print0 2>/dev/null
      ;;
    fd)
      command "$_command" \
        --color=never \
        --follow \
        --no-ignore \
        --exclude .git \
        --exclude node_modules \
        --print0 \
        . "$_root" 2>/dev/null
      ;;
    bash)
      __glob_complete_generate_bash_fzf_paths "$_root"
      ;;
    *) return 1 ;;
  esac
}

function __glob_complete_generate_fzf_candidates() {
  local _filedir_filter=${1-}
  local _root=$2
  local _backend=$3
  local _command=${4-}
  local _fzf_candidate
  local _fzf_display_candidate
  local _xspec="*.@($_filedir_filter|${_filedir_filter^^})"

  (
    shopt -s extglob

    while IFS= read -r -d '' _fzf_candidate; do
      _fzf_candidate=${_fzf_candidate%/}
      # shellcheck disable=SC2053 # _xspec is intentionally an extglob pattern.
      if [[ ! -d $_fzf_candidate && $_fzf_candidate != $_xspec ]]; then
        continue
      fi

      _fzf_display_candidate=$_fzf_candidate
      if [[ $_root == . && $_fzf_display_candidate == ./* ]]; then
        _fzf_display_candidate=${_fzf_display_candidate#./}
      fi
      [[ -d $_fzf_candidate ]] && _fzf_display_candidate+=/
      printf '%s\0' "$_fzf_display_candidate"
    done < <(
      __glob_complete_generate_fzf_paths \
        "$_backend" "$_command" "$_root"
    )
  )
}

function __glob_complete_append_fzf_exact_term() {
  local _term=$1
  local _query_name=$2
  local _escaped_term
  local -n _query_output=$_query_name

  [[ -n $_term && $_term != +('/') ]] || return 0
  _escaped_term=${_term//\\/\\\\}
  _escaped_term=${_escaped_term// /\\ }
  [[ -n $_query_output ]] && _query_output+=' '
  _query_output+="'$_escaped_term"
}

function __glob_complete_append_fzf_fuzzy_term() {
  local _term=$1
  local _query_name=$2
  local _escaped_term
  local -n _query_output=$_query_name

  [[ -n $_term ]] || return 0
  _escaped_term=${_term//\\/\\\\}
  _escaped_term=${_escaped_term// /\\ }
  [[ -n $_query_output ]] && _query_output+=' '
  _query_output+=$_escaped_term
}

function __glob_complete_build_fzf_query() {
  local _pattern=$1
  local _output_name=$2
  local _term_type=${3-exact}
  local _built_query=
  local _char
  local _chunk=
  local _depth
  local _index=0
  local _next_char
  local -n _output=$_output_name

  while ((_index < ${#_pattern})); do
    _char=${_pattern:_index:1}
    _next_char=${_pattern:_index+1:1}

    # Treat an extglob as one non-literal region.  Its alternatives cannot be
    # represented as fzf's space-separated AND terms without changing meaning.
    if [[ $_char == [@+!?*] && $_next_char == '(' ]]; then
      if [[ $_term_type == exact ]]; then
        __glob_complete_append_fzf_exact_term "$_chunk" _built_query
        _chunk=
      fi
      _depth=1
      _index=$((_index + 2))
      while ((_index < ${#_pattern} && _depth > 0)); do
        _char=${_pattern:_index:1}
        case $_char in
          '(') _depth=$((_depth + 1)) ;;
          ')') _depth=$((_depth - 1)) ;;
          \\) _index=$((_index + 1)) ;;
        esac
        _index=$((_index + 1))
      done
      continue
    fi

    case $_char in
      '*'|'?')
        if [[ $_term_type == exact ]]; then
          __glob_complete_append_fzf_exact_term "$_chunk" _built_query
          _chunk=
        fi
        ;;
      '[')
        if [[ $_term_type == exact ]]; then
          __glob_complete_append_fzf_exact_term "$_chunk" _built_query
          _chunk=
        fi
        _index=$((_index + 1))
        while ((_index < ${#_pattern})); do
          _char=${_pattern:_index:1}
          if [[ $_char == \\ ]]; then
            _index=$((_index + 2))
            continue
          fi
          _index=$((_index + 1))
          [[ $_char == ']' ]] && break
        done
        continue
        ;;
      \\)
        if [[ -n $_next_char ]]; then
          _chunk+=$_next_char
          _index=$((_index + 1))
        fi
        ;;
      *) _chunk+=$_char ;;
    esac
    _index=$((_index + 1))
  done
  if [[ $_term_type == exact ]]; then
    __glob_complete_append_fzf_exact_term "$_chunk" _built_query
  else
    __glob_complete_append_fzf_fuzzy_term "$_chunk" _built_query
  fi
  _output=$_built_query
}

function __glob_complete_resolve_fzf_root() {
  local _base=$1
  local _root_name=$2
  local _query_name=$3
  local _candidate_pattern
  local _component
  local _directory_remainder
  local _leaf
  local _leaf_query
  local _unresolved_pattern
  local -a _arr_directory_matches=()
  local -a _arr_directory_results=()
  local -n _root_output=$_root_name
  local -n _query_output=$_query_name

  if [[ $_base != */* ]]; then
    _root_output=.
    __glob_complete_build_fzf_query "$_base" "$_query_name" fuzzy
    return 0
  fi

  _leaf=${_base##*/}
  _directory_remainder=${_base%/*}
  if [[ $_base == /* ]]; then
    _root_output=/
    _directory_remainder=${_directory_remainder#/}
  else
    _root_output=.
  fi

  # Resolve directory components from left to right.  Each unambiguous match
  # narrows the root, even if a later component is ambiguous or unmatched.
  while [[ -n $_directory_remainder ]]; do
    _component=${_directory_remainder%%/*}
    if [[ $_directory_remainder == */* ]]; then
      _directory_remainder=${_directory_remainder#*/}
    else
      _directory_remainder=
    fi
    [[ -n $_component ]] || continue

    if [[ $_root_output == / ]]; then
      _candidate_pattern=/$_component
    elif [[ $_root_output == . ]]; then
      _candidate_pattern=$_component
    else
      _candidate_pattern=$_root_output/$_component
    fi

    _arr_directory_matches=()
    _arr_directory_results=()
    __glob_complete_expand_pattern \
      "$_candidate_pattern" _arr_directory_matches
    for _candidate_pattern in "${_arr_directory_matches[@]}"; do
      [[ -d $_candidate_pattern ]] &&
        _arr_directory_results+=("$_candidate_pattern")
    done
    if ((${#_arr_directory_results[@]} == 1)); then
      _root_output=${_arr_directory_results[0]}
      continue
    fi

    _unresolved_pattern=$_component
    [[ -n $_directory_remainder ]] &&
      _unresolved_pattern+="/$_directory_remainder"
    __glob_complete_build_fzf_query \
      "$_unresolved_pattern" "$_query_name"
    __glob_complete_build_fzf_query "$_leaf" _leaf_query fuzzy
    [[ -n $_query_output ]] && _query_output+=' '
    _query_output+=$_leaf_query
    return 0
  done

  __glob_complete_build_fzf_query "$_leaf" "$_query_name" fuzzy
}

function __glob_complete_redraw_after_fzf() {
  # Ask the terminal for its status after fzf restores the screen.
  # The reply is bound to Readline's redraw command so the prompt and complete
  # edit buffer are painted again instead of leaving fzf's selected row drawn
  # over the pre-existing command line.
  [[ $- == *i* && -t 0 && -t 1 ]] || return 0
  if bind '"\e[0n": redraw-current-line' 2>/dev/null; then
    printf '\e[5n'
  fi
  return 0
}

function __glob_complete_collect_fzf() {
  local _filedir_filter=${1-}
  local _word=$2
  local _output_name=$3
  local _state_name=$4
  local _base
  local _candidate
  local _expanded_base
  local _expanded_prefix
  local _formatted_candidate
  local _find_backend
  local _find_command
  local _fzf_pid
  local _fzf_status=0
  local _query
  local _quote_as_shell_text=off
  local _root
  local _typed_prefix
  local -a _arr_fzf_args=(
    '--height=40%'
    '--header-first'
    '--no-multi-line'
    '--print0'
    '--reverse'
    '--scheme=path'
    '--walker-skip=.git,node_modules'
  )
  local -a _arr_selected=()
  local -n _arr_output=$_output_name
  local -n _state_output=$_state_name

  _arr_output=()
  _state_output=inactive
  [[ -n ${GLOB_COMPLETE_FZF-} && $_word == *'**' ]] || return 1
  command -v fzf >/dev/null 2>&1 || return 1

  _base=${_word:0:${#_word}-2}
  __glob_complete_expand_prefix \
    "$_base" _expanded_base _expanded_prefix _typed_prefix ||
    _expanded_base=$_base

  __glob_complete_resolve_fzf_root "$_expanded_base" _root _query
  _arr_fzf_args+=(--header "root: $_root" --query "$_query")

  if [[ $_filedir_filter == '-d' ]]; then
    # use fzf's native walker to find directories only.
    _arr_fzf_args+=('--walker=dir,follow' --walker-root "$_root")
  elif [[ -z $_filedir_filter ]]; then
    # use fzf's native walker to find both files and directories.
    _arr_fzf_args+=('--walker=file,dir,follow' --walker-root "$_root")
  else
    # use a separate scanner to find only items matching an extension filter
    __glob_complete_select_find_command _find_backend _find_command || return 1
    _arr_fzf_args+=(--read0)
  fi

  if [[ -z $_filedir_filter || $_filedir_filter == '-d' ]]; then
    readarray -d '' -t _arr_selected < <(
      unset FZF_DEFAULT_COMMAND FZF_DEFAULT_OPTS_FILE
      command fzf "${_arr_fzf_args[@]}" 2>/dev/null
    )
  else
    readarray -d '' -t _arr_selected < <(
      __glob_complete_generate_fzf_candidates \
        "$_filedir_filter" "$_root" "$_find_backend" "$_find_command" |
        (
          unset FZF_DEFAULT_COMMAND FZF_DEFAULT_OPTS_FILE
          command fzf "${_arr_fzf_args[@]}" 2>/dev/null
        )
    )
  fi
  _fzf_pid=$!
  if wait "$_fzf_pid"; then
    _fzf_status=0
  else
    _fzf_status=$?
  fi

  if ((${#_arr_selected[@]} == 0)); then
    case $_fzf_status in
      0|1|130)
        # Keep the command line unchanged when the picker is cancelled or has
        # no matches.  Returning the typed word also suppresses completion's
        # ordinary fallback processing for this attempt.  Prevent Readline
        # from quoting that sentinel candidate or appending a space.
        _arr_output=("$_word")
        _state_output=cancelled
        compopt +o filenames -o noquote -o nospace 2>/dev/null || true
        __glob_complete_redraw_after_fzf
        return 0
        ;;
      *)
        # An installed but unusable fzf (for example, an older version without
        # a required option) should degrade just like a missing executable.
        _state_output=inactive
        __glob_complete_redraw_after_fzf
        return 1
        ;;
    esac
  fi

  _candidate=${_arr_selected[0]%/}
  if __glob_complete_word_has_glob_in_directory "$_word"; then
    _quote_as_shell_text=on
  fi
  __glob_complete_format_candidate \
    "$_candidate" "$_expanded_prefix" "$_typed_prefix" \
    "$_quote_as_shell_text" _formatted_candidate
  _arr_output=("$_formatted_candidate")
  _state_output=selected
  __glob_complete_redraw_after_fzf
}

#endregion

# ---
#region glob-completion functions
# ---

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
  local _filedir_filter=$1
  local _word=$2
  local _output_name=$3
  local _quote_as_shell_text=${4-off}
  local _pattern=$_word
  local _candidate
  local _display_candidate
  local _expanded_prefix=
  local _typed_prefix=
  local _xspec=
  local -a _arr_matches=()
  local -a _arr_filtered=()
  # shellcheck disable=SC2178 # The referenced caller variable is an array.
  local -n _arr_output=$_output_name

  __glob_complete_expand_prefix \
    "$_word" _pattern _expanded_prefix _typed_prefix || true

  # Readline's glob-complete-word implicitly adds a trailing '*'.  Doing the
  # same is what makes '*a' match both 'bar' and 'baz'.
  _pattern+='*'
  __glob_complete_expand_pattern "$_pattern" _arr_matches

  if [[ $_filedir_filter != '-d' && -n $_filedir_filter ]]; then
    _xspec="*.@($_filedir_filter|${_filedir_filter^^})"
  fi

  for _candidate in "${_arr_matches[@]}"; do
    # Match bash-completion's normal filedir semantics: -d means directories
    # only; an extension filter still permits directories.
    if [[ $_filedir_filter == '-d' && ! -d $_candidate ]]; then
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
    __glob_complete_format_candidate \
      "$_candidate" "$_expanded_prefix" "$_typed_prefix" \
      "$_quote_as_shell_text" _display_candidate
    _arr_filtered+=("$_display_candidate")
  done

  _arr_output=("${_arr_filtered[@]}")
}

function __glob_complete_apply_completion_options() {
  local _word=$1
  local _quote_as_shell_text=$2
  local _expanded_word
  local _expanded_prefix
  local _typed_prefix

  if [[ $_quote_as_shell_text == on ]]; then
    # Readline displays only the basename of candidates marked as filenames.
    # Preserve the full path when a directory component is a glob, while
    # retaining filename-safe insertion through pre-quoting.
    compopt +o filenames -o noquote 2>/dev/null || true
  else
    compopt -o filenames 2>/dev/null || true
  fi
  if [[ $_quote_as_shell_text == off ]] && __glob_complete_expand_prefix \
    "$_word" _expanded_word _expanded_prefix _typed_prefix 2>/dev/null; then
    compopt -o noquote 2>/dev/null || true
  fi
}

function __glob_complete_default() {
  local _cur=${2-}
  local _fzf_state=inactive
  local _quote_as_shell_text=off

  COMPREPLY=()
  if __glob_complete_word_has_glob "$_cur"; then
    if __glob_complete_word_has_glob_in_directory "$_cur"; then
      _quote_as_shell_text=on
    fi
    if __glob_complete_collect_fzf '' "$_cur" COMPREPLY _fzf_state; then
      if [[ $_fzf_state == selected ]]; then
        __glob_complete_apply_completion_options \
          "$_cur" "$_quote_as_shell_text"
      fi
      return 0
    fi
    __glob_complete_collect_filedir \
      '' "$_cur" COMPREPLY "$_quote_as_shell_text"
    if ((${#COMPREPLY[@]})); then
      __glob_complete_apply_completion_options \
        "$_cur" "$_quote_as_shell_text"
    fi
  fi
}

function __glob_complete_generate_bash_completion_filedir() {
  local _filedir_filter=${1-}
  local _fzf_state=inactive
  local _quote_as_shell_text=off
  local -a _arr_results=()

  if __glob_complete_word_has_glob_in_directory "${cur-}"; then
    _quote_as_shell_text=on
  fi
  if __glob_complete_collect_fzf \
    "$_filedir_filter" "${cur-}" _arr_results _fzf_state; then
    if [[ $_fzf_state == selected ]]; then
      __glob_complete_apply_completion_options \
        "${cur-}" "$_quote_as_shell_text"
    fi
    _comp_compgen_set "${_arr_results[@]}"
    return 0
  fi
  __glob_complete_collect_filedir \
    "$_filedir_filter" "${cur-}" _arr_results "$_quote_as_shell_text"
  if ((${#_arr_results[@]})); then
    __glob_complete_apply_completion_options \
      "${cur-}" "$_quote_as_shell_text"
  fi
  _comp_compgen_set "${_arr_results[@]}"
}

#endregion

# ---
#region installation
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

#endregion
