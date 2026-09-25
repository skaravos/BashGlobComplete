# Glob-aware completion for Bash

Use wildcard patterns to find files and directories with Tab.
[`glob-complete.bash`](./glob-complete.bash) adds glob matching to Bash filename
completion: type `cd *a`, press Tab, and get matches such as `bar/` and `baz/`.

The script works on its own or with
[bash-completion](https://github.com/scop/bash-completion). With bash-completion,
commands keep their usual completion rules, such as suggesting only directories
for `cd` or only files with certain extensions.

## Setup

Add this line to your `~/.bashrc`, replacing the path with the script's actual
location:

```bash
. /path/to/BashGlobComplete/glob-complete.bash
```

You can source the script before or after bash-completion. If bash-completion
is loaded again later, the script restores its integration automatically. Any
existing `BASH_COMPLETION_USER_FILE` is preserved and sourced as usual.

Integration with bash-completion requires version 2.12 or newer. If you don't
use bash-completion, the script provides completion for commands that don't
already have a completer.

## Complete a path

Type a Bash glob wherever filename completion is available, then press Tab.
In these examples, `<Tab>` means pressing the Tab key:

```text
cd *a<Tab>
rm report-202?-*.pdf<Tab>
less src/[ch]*/main.*<Tab>
```

Variable and tilde prefixes stay as you typed them:

```text
cd $HOME/proj*<Tab>
cd ${HOME}/proj*<Tab>
cd ~/proj*<Tab>
```

For example, a match for `$HOME/proj*` is inserted as `$HOME/project/`, keeping
`$HOME` in the command line. Special characters elsewhere in the path are
escaped. Array and nameref variables are not expanded.

### Extended patterns and case-insensitive matching

Enable Bash's `extglob` option to use extended patterns:

```bash
shopt -s extglob
```

You can then complete patterns such as:

```text
cd @(build|dist)<Tab>
```

To make matching case-insensitive, enable `nocaseglob`:

```bash
shopt -s nocaseglob
```

## Pick a path with fzf

If you have `fzf` installed, you can use an interactive picker to search below
a directory. Enable it by setting `GLOB_COMPLETE_FZF` to any non-empty value:

```bash
export GLOB_COMPLETE_FZF=1
. /path/to/BashGlobComplete/glob-complete.bash
```

End the word with `**` or `***`, then press Tab to open the picker:

```text
cd proj**<Tab>
less src/mai**<Tab>
stat ./***<Tab>
```

| Suffix | What the picker searches |
| --- | --- |
| `**` | Files and visible directories, including hidden files inside visible directories. Hidden directories are excluded. |
| `***` | Files and directories, including hidden directories and their contents. |

The picker shows the search root in a fixed header. Select a path to replace
the word being completed; variable and tilde prefixes are preserved.
Press Escape or Ctrl-C to leave the command line unchanged.

When bash-completion is active, the picker follows its directory-only and
file-extension filters. Without bash-completion, it offers both files and
directories because it has no command-specific context.

If `fzf` is missing or cannot start with the required options, the script falls
back silently to ordinary glob completion. You don't need fzf's shell
integration; using `eval "$(fzf --bash)"` alongside this feature is not
recommended.

### Choose which directories to skip

By default, the picker skips `.git` and `node_modules`. Set
`GLOB_COMPLETE_FZF_SKIP` to a comma-separated list to replace those defaults:

```bash
export GLOB_COMPLETE_FZF_SKIP='.git,node_modules,__pycache__,venv'
```

To allow searching all directories, set it to an empty string:

```bash
export GLOB_COMPLETE_FZF_SKIP=''
```

Use directory names only, not paths or patterns. Entries cannot contain `/`,
and a non-empty list cannot contain empty entries. If any entry is invalid,
the picker silently falls back to ordinary glob completion for that attempt.

### How a pattern becomes a search

The script reads the path from left to right, using each directory component
that resolves to exactly one directory to narrow the search root. The remaining
components become the initial fzf query:

- Literal text in unresolved directory components becomes an exact-match term.
- The final component becomes a fuzzy-search term.

For example, suppose `~/proj*` matches only `~/projects`. Completing
`~/proj*/*Docker*/sc**` searches below `~/projects` with the query `'Docker sc`.
The leading single quote tells fzf to match `Docker` exactly, while `sc` uses
normal fuzzy matching.

If the final component is empty, the query ends with a space so that anything
you type starts a new fuzzy-search term.

### Advanced: choose a file scanner

For directory-only searches and searches without extension restrictions, the
picker uses fzf's built-in filesystem walker. When bash-completion limits files
to particular extensions, the script uses the first available scanner in this
order: `find`, `fdfind`, `fd`, then a pure Bash fallback. Directories are still
offered, but files with other extensions are omitted.

All scanners respect the `**` or `***` hidden-directory choice and the directory
skip list. The pure Bash fallback does not follow directory symlinks, avoiding
cycles without an external path-resolution command.

To choose a scanner yourself, set `GLOB_COMPLETE_FIND_COMMAND`:

```bash
export GLOB_COMPLETE_FIND_COMMAND=bash
```

Accepted values are `find`, `fd`, `fdfind`, `bash`, or a path to one of those
external commands. This setting applies to searches with extension restrictions.
If the chosen command is unsupported or unavailable, those requests silently
fall back to ordinary glob completion.

## Make completion lists easier to read

When a glob appears in a directory component, Readline's `possible-completions`
command lists the full matching paths. This helps distinguish matches that
share a filename. For example, `~/projects/*/.vscode` may display:

```text
~/projects/foo/.vscode/  ~/projects/bar/.vscode/
```

To shorten repeated prefixes, add this to `~/.inputrc`:

```inputrc
set completion-prefix-display-length 1
```

The same list would then look like this:

```text
...foo/.vscode/  ...bar/.vscode/
```

This setting affects all completion lists. The number is the longest common
prefix Readline will show without abbreviating it. Any value above zero enables
abbreviation; `1` shortens nearly every nontrivial common prefix.

To try it in the current shell first, run:

```bash
bind 'set completion-prefix-display-length 1'
```

## Cycle through matches with Tab

To have Tab select one match at a time and Shift-Tab move backwards, add these
bindings to `~/.bashrc` after sourcing the script:

```bash
bind 'set menu-complete-display-prefix on'
bind 'TAB: menu-complete'
bind '"\e[Z": menu-complete-backward'
```

After the last match, Readline briefly returns to the original text or common
prefix before cycling again. For `bar/` and `baz/`, you may see the sequence
`bar/`, `baz/`, `ba`, `bar/`. This is built-in Readline behavior and cannot be
changed by a Bash completion function.

## Try it without changing your setup

Start a clean Bash session, source the script, and create a few test directories:

```bash
bash --noprofile --norc
. /path/to/BashGlobComplete/glob-complete.bash
mkdir -p /tmp/glob-demo/{foo,bar,baz}
cd /tmp/glob-demo
```

Type `cd *a` and press Tab. The matches should be `bar/` and `baz/`.
Run `exit` when you're done to return to your previous shell.

To run the automated checks from the repository directory:

```bash
./test-glob-complete.bash
```
