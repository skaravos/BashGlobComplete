# Glob completion for Bash

Use wildcard patterns to find files and directories with the Tab key.
[`glob-complete.bash`](./glob-complete.bash) adds glob completion to Bash filename
completion. For example, `cd *a` can give the matches `bar/` and `baz/`.

The script operates independently or with
[bash-completion](https://github.com/scop/bash-completion). With bash-completion,
commands keep their usual completion rules. For example, `cd` gives only directories.
Other commands can limit files to specified extensions.

## Set up the script

1. In `~/.bashrc`, add the line below.
2. Replace `/path/to/BashGlobComplete` with the directory that contains the script.

```bash
. /path/to/BashGlobComplete/glob-complete.bash
```

You can load the script before or after bash-completion. If bash-completion loads
again, the script automatically restores the integration. The script keeps any
existing `BASH_COMPLETION_USER_FILE` and loads that file as usual.

Integration with bash-completion requires version 2.12 or newer. Without
bash-completion, the script supplies completion for commands that have no completion
function.

## Complete a path

1. Where filename completion is available, type a Bash glob.
2. Press Tab.

In these examples, `<Tab>` identifies the Tab key:

```text
cd *a<Tab>
rm report-202?-*.pdf<Tab>
less src/[ch]*/main.*<Tab>
```

The script keeps variable and tilde prefixes unchanged:

```text
cd $HOME/proj*<Tab>
cd ${HOME}/proj*<Tab>
cd ~/proj*<Tab>
```

For example, the script can insert `$HOME/project/` for `$HOME/proj*`.
The command line keeps the `$HOME` prefix. The script adds escape characters to
special characters elsewhere in the path. The script does not expand array or
nameref variables.

### Use extended patterns

1. To use extended patterns, enable the Bash `extglob` option.

```bash
shopt -s extglob
```

With this option, you can complete patterns such as:

```text
cd @(build|dist)<Tab>
```

### Ignore letter case

1. To ignore letter case in glob matches, enable `nocaseglob`.

```bash
shopt -s nocaseglob
```

## Complete Git paths

The script also integrates with Git's Bash completion script. This integration does
not require bash-completion or extra configuration. You can load this script before
or after Git's completion script.

1. In a Git path argument, type a glob.
2. Press Tab.

```text
git checkout -- ./*foo<Tab>
git add src/*test<Tab>
git -C ./some/dir/*xampl<Tab>
git -C ./some/dir checkout -- ./*foo<Tab>
```

For `git -C`, completion gives only directories. Earlier `-C` arguments change the
base directory for later path arguments. An explicit work tree also changes the
base for repository paths. Variable and tilde prefixes remain unchanged.

Explicit globs use filesystem matches, including untracked and ignored files.
Git might not accept every path. Without globs, Git keeps its usual completion
rules for files, branches, tags, options, and commands.

The script checks the Git integration before each interactive prompt. The script
also restores the integration after a completion loader loads Git's script.
This supports the first Tab request when Git completion loads on demand.

## Select a path with fzf

The fzf path selector lets you search below a directory. This feature requires
`fzf`.

1. Set `GLOB_COMPLETE_FZF` to a value that is not empty.
2. Load the script.

```bash
export GLOB_COMPLETE_FZF=1
. /path/to/BashGlobComplete/glob-complete.bash
```

1. At the end of the word, type `**` or `***`.
2. To open the path selector, press Tab.

```text
cd proj**<Tab>
less src/mai**<Tab>
stat ./***<Tab>
```

| Suffix | Search contents |
| --- | --- |
| `**` | Files and visible directories. This includes hidden files in visible directories, but not hidden directories. |
| `***` | Files and directories. This includes hidden directories and their contents. |

The path selector shows the search root in a fixed header. The script keeps
variable and tilde prefixes unchanged.

1. To replace the word, select a path.

To keep the command line unchanged, use this step instead:

1. Press Escape or Ctrl-C.

With bash-completion, the path selector obeys the directory-only and file-extension
filters. Without bash-completion, the path selector shows files and directories.
The script has no command-specific information in this mode.

If `fzf` is absent or cannot start with the necessary options, the script uses
ordinary glob completion without a message. This feature does not require the fzf
shell integration. Do not use `eval "$(fzf --bash)"` with this feature.

### Exclude directories from the search

By default, the path selector excludes `.git` and `node_modules`.

1. To replace the defaults, set `GLOB_COMPLETE_FZF_SKIP` to a list of directory names
   separated by commas.

```bash
export GLOB_COMPLETE_FZF_SKIP='.git,node_modules,__pycache__,venv'
```

To search all directories, use this step instead:

1. Set `GLOB_COMPLETE_FZF_SKIP` to an empty string.

```bash
export GLOB_COMPLETE_FZF_SKIP=''
```

Use only directory names in the list. Do not use paths or patterns. Entries cannot
contain `/`. A list that is not empty cannot contain empty entries. If an entry is
invalid, the script uses ordinary glob completion for that attempt without a message.

### Convert a pattern to a search query

The script reads the path from left to right. Each directory component that matches
exactly one directory limits the search root. The script converts the remaining
components to the initial fzf query:

- Literal text in unresolved directory components becomes an exact-match term.
- The last component becomes a fuzzy-search term.

For example, assume that `~/proj*` matches only `~/projects`.
For `~/proj*/*Docker*/sc**`, the script searches below `~/projects` with the query
`'Docker sc`. The initial single quote tells fzf to match `Docker` exactly.
The term `sc` uses fuzzy matching.

If the last component is empty, the query ends with a space. Text that you type
then starts a new fuzzy-search term.

### Select a file scanner

For directory-only searches, the path selector uses the built-in fzf filesystem
walker. The path selector also uses this walker for searches without file-extension
restrictions.

With file-extension restrictions from bash-completion, the script uses the first
available scanner in this order:

1. `find`
2. `fdfind`
3. `fd`
4. The Bash scanner

The path selector still shows directories. The path selector does not show files
with other extensions.

All scanners obey the `**` or `***` choice for hidden directories. All scanners also
obey the list of directories to exclude. The Bash scanner does not follow directory
symlinks. This prevents cycles without an external command for path resolution.

1. To select a scanner, set `GLOB_COMPLETE_FIND_COMMAND`.

```bash
export GLOB_COMPLETE_FIND_COMMAND=bash
```

Permitted values are `find`, `fd`, `fdfind`, `bash`, or a path to one of those external
commands. This setting applies only to searches with file-extension restrictions.
If the selected command is unsupported or unavailable, the script uses ordinary
glob completion for those requests without a message.

## Show shorter completion lists

When a directory component contains a glob, the Readline `possible-completions`
command shows the full paths of matches. Full paths help you identify matches with
the same filename. For example, `~/projects/*/.vscode` can show:

```text
~/projects/foo/.vscode/  ~/projects/bar/.vscode/
```

1. To shorten repeated prefixes, add this line to `~/.inputrc`.

```inputrc
set completion-prefix-display-length 1
```

The list then has this form:

```text
...foo/.vscode/  ...bar/.vscode/
```

This setting affects all completion lists. The number specifies the maximum length
of a common prefix that Readline shows in full. A value above zero enables prefix
abbreviation. The value `1` shortens almost all common prefixes longer than one
character.

1. To test the setting in the current shell, run this command.

```bash
bind 'set completion-prefix-display-length 1'
```

## Select matches with Tab

These key bindings let Tab select one match at a time. Shift-Tab selects the
previous match.

1. In `~/.bashrc`, add these key bindings after the line that loads the script.

```bash
bind 'set menu-complete-display-prefix on'
bind 'TAB: menu-complete'
bind '"\e[Z": menu-complete-backward'
```

After the last match, Readline briefly returns to the original text or common
prefix. Readline then starts the sequence again. For `bar/` and `baz/`, the sequence
can be `bar/`, `baz/`, `ba`, `bar/`. A Bash completion function cannot change this
Readline behavior.

## Test without changes to your configuration

1. Start a Bash session without profile or configuration files.

```bash
bash --noprofile --norc
```

2. Load the script.

```bash
. /path/to/BashGlobComplete/glob-complete.bash
```

3. Create the test directories.

```bash
mkdir -p /tmp/glob-demo/{foo,bar,baz}
```

4. Go to the test directory.

```bash
cd /tmp/glob-demo
```

5. Type `cd *a`.
6. Press Tab.

The expected matches are `bar/` and `baz/`.

7. To return to your previous shell, run `exit`.

### Run the automated checks

1. From the repository directory, run this command.

```bash
./test-glob-complete.bash
```

The checks include `test-git-complete.bash`. Integration checks require the relevant
completion scripts. The checks skip an integration when its completion script is
unavailable.

1. To select a Git completion script for the checks, set `GIT_COMPLETION_FILE`.
2. To select a bash-completion script for the checks, set `BASH_COMPLETION_FILE`.
