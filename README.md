# The Ludwig Editor

```text
{**********************************************************************}
{                                                                      }
{            L      U   U   DDDD   W      W  IIIII   GGGG              }
{            L      U   U   D   D   W    W     I    G                  }
{            L      U   U   D   D   W ww W     I    G   GG             }
{            L      U   U   D   D    W  W      I    G    G             }
{            LLLLL   UUU    DDDD     W  W    IIIII   GGGG              }
{                                                                      }
{**********************************************************************}
```

[![Check](https://github.com/clstrfsck/ludwig-go/actions/workflows/check.yml/badge.svg)](https://github.com/clstrfsck/ludwig-go/actions/workflows/check.yml)

## About

Ludwig is a text editor developed at the University of Adelaide.
It is an interactive, screen-oriented text editor.
It may be used to create and modify computer programs, documents
or any other text which consists only of printable characters.

Ludwig may also be used on hardcopy terminals or non-interactively,
but it is primarily an interactive screen editor.

This repository now contains the Zig implementation of Ludwig. The original Pascal
code is available here: [cjbarter/ludwig](https://github.com/cjbarter/ludwig).
There is also a C++ port available here:
[clstrfsck/ludwig-c](https://github.com/clstrfsck/ludwig-c) and a Go port here:
[clstrfsck/lugwig-go](https://github.com/clstrfsck/ludwig-go).

## Building

The primary workflow is `zig build`. The build is multi-stage: it generates the
indexed help files, embeds them into the editor binary, and installs the Zig
artifacts into `zig-out/bin`.

Prerequisites:

- Zig `0.15.2`
- `ncurses`
- `pcre2`

Using `zig build`:

```sh
# Build debug binary
zig build build
# Build release binary (no symbols)
zig build build-release
# Install the primary artifacts into zig-out/bin
zig build
# Run unit tests
zig build test
# Run system tests when the external suite is present
zig build system-test
# Build everything and run all available tests
zig build check
```

`zig build` installs `ludwig`, `ludwighlpbld`, `ludwighlp.idx`, and
`ludwignewhlp.idx` into `zig-out/bin`. For the full step list, run
`zig build --help` or inspect `build.zig`.

If you would prefer to use a different help file than the embedded
documentation, you can set the environment variables `LUD_HELPFILE` and
`LUD_NEWHELPFILE` to point to the locations of the old and new command help
files respectively.

## Coverage

Unit test coverage is quite low right now.  This is being worked on as
refactoring and modernisation continues.

## System Tests

There is reasonable system test coverage.  The system tests leverage
Ludwig's batch mode, where a command string is provided on stdin.  The
general approach is:

- The test provides a selection of initial filenames and contents, together
  with expected output files and contents and a command string
- The test framework creates a temporary directory and populates it with the
  supplied files
- The command string is piped into a Ludwig process running in the temporary
  directory
- Once the process completes, the files in the temporary directory are
  collected and compared against expectations

You can clone the
[system tests](https://github.com/clstrfsck/ludwig-system-test) using:

```sh
git clone https://github.com/clstrfsck/ludwig-system-test system-test
python3 -m venv .venv
source ./.venv/bin/activate
pip install -r system-test/requirements.txt
zig build system-test
```

The intention is that the system tests are cloned into a subdirectory of
the main `ludwig-go` project.  If you would like to arrange things differently,
you can use the environment variable `LUDWIG_EXE` to point the tests to
your executable.  Note that this path will need to be an absolute path.

Once the tests are running, you should see a bunch of dots, followed by
something like:

```text
426 passed, 7 skipped in 10.57s
```

### More tips on setting up Python

You can use `virtual-env` to easily set up an environment without adding to
your global python packages:

```sh
python3 -m venv .venv
source ./.venv/bin/activate
pip install pytest
pip install pexpect
```

**Please be aware** that the `run-system-test.sh` script included in the
system tests will automatically source `./.venv/bin/activate` if it is found
in the current directory.

## Usage

There is a `man` file in `ludwig.1`.  You can read it without copying it
anywhere by typing:

```sh
man ./ludwig.1
```

Once in the editor, typing `\h` will bring up the embedded help information.
Use `\q` to quit the editor.

## Divergence from the original

This repository preserves the behavior of the historical Ludwig implementations
while using a native Zig codebase. Notable modernizations include:

- The help files for both the old and new command sets are generated during
  `zig build` and embedded into the executable, making the default build
  self-contained.
- The editor includes syntax highlighting, with both basic and richer color
  paths depending on terminal capability.
- The editor has an option to set the width of tabstops on startup.
