# Glob-aware completion for Bash

[`glob-complete.bash`](./glob-complete.bash) lets Bash complete pathname globs.
Type a pattern such as `cd *a` and press Tab to complete matching entries such
as `bar` and `baz`.

It works on its own or alongside
[bash-completion](https://github.com/scop/bash-completion). When
bash-completion is present, command-specific completers still decide where
filenames are valid; this script only changes how those filenames are
generated.

## Setup

Source the script from `.bashrc` using its absolute path:

```bash
. /path/to/bash-completer/glob-complete.bash
```

The order does not matter. You can source it before or after bash-completion,
and it will reinstall its integration if bash-completion is loaded again
later. An existing `BASH_COMPLETION_USER_FILE` is preserved and sourced as
usual.

The bash-completion integration requires version 2.12 or newer. Without
bash-completion, the script installs a default completer for commands that do
not already have one.

## Usage

Standard Bash glob syntax works wherever filename completion is available:

```text
cd *a<Tab>
rm report-202?-*.pdf<Tab>
less src/[ch]*/main.*<Tab>
```

With `extglob` enabled, extended patterns work too:

```bash
shopt -s extglob
```

```text
cd @(build|dist)<Tab>
```

With `nocaseglob` enabled, suggestions are case-insensitive:

```bash
shopt -s nocaseglob
```

Leading variables and tilde expressions are expanded for matching without
being replaced in the command line:

```text
cd $HOME/proj*<Tab>
cd ${HOME}/proj*<Tab>
cd ~/proj*<Tab>
```

For example, a match under `$HOME` is inserted as `$HOME/project/`, not as its
absolute path. Special characters in the rest of the pathname are escaped.
Array and nameref variables are not expanded.

## Menu-style completion

To make Tab select one match at a time and Shift-Tab move backwards, add these
Readline bindings after sourcing the script:

```bash
bind 'set menu-complete-display-prefix on'
bind 'TAB: menu-complete'
bind '"\e[Z": menu-complete-backward'
```

Readline briefly returns to the original text or common prefix after the last
match before cycling again. For matches `bar/` and `baz/`, the sequence may be
`bar/`, `baz/`, `ba`, `bar/`. This is built-in Readline behavior and cannot be
changed by a Bash completion function.

## Quick test

Start a clean shell so you can try the script without editing `.bashrc`:

```bash
bash --noprofile --norc
. /path/to/bash-completer/glob-complete.bash
mkdir -p /tmp/glob-demo/{foo,bar,baz}
cd /tmp/glob-demo
```

Now type `cd *a` and press Tab. The matches should be `bar` and `baz`.

Run the automated checks with:

```bash
./test-glob-complete.bash
```
