# c-link-farm

This gives clangd (C/C++ LSP) a view of hundreds of repos when the Makefiles are
too messy for `bear` or `compile_commands.json`.

## Why a farm

If you add every header folder as its own `-I`, you get thousands of include
paths. clangd then checks every folder for each `#include`, and it stops
responding. Header names are unique, so the script puts one symlink per
header into **one** folder and uses a single `-I` for that folder.

```
~/.cache/c-farm/
  include/foo.h   -> /work/libfoo/inc/foo.h      # every header
  src/foo.cpp     -> /work/libfoo/src/foo.cpp    # every .c/.cpp
  compile_flags.txt                              # -I~/.cache/c-farm/include + your -f flags
  index/compile_commands.json                    # every real source file with those flags
  farm.conf                                      # roots, -x and -f, for `update`
```

## Usage

`link-farm.sh -h` shows the full help with examples.

```sh
link-farm.sh build /work/libs /work/apps                  # new farm over several folders
link-farm.sh build -x test -x third_party /work           # skip more folder names
link-farm.sh build -f -DUNIT_TEST -f -std=gnu11 /work     # flags for every file
link-farm.sh add /work/tools                              # one more folder, same farm
link-farm.sh update                                       # pick up new / deleted / renamed files
link-farm.sh update /work/libs/foo                        # ... only below this folder (fast)
link-farm.sh status                                       # roots, flags, link counts
link-farm.sh check                                        # health report (-v: list every finding)
```

`build` reports duplicate names and keeps the first one it finds.

`update` is incremental: it deletes links whose file is gone and links only
names that are new. Existing links stay as they are, and
`compile_commands.json` is rewritten only when sources were added or removed,
so clangd has nothing to reload after a no-op run. Most of the cost is walking
the roots with `find`. `update PATH` walks only PATH, which takes well under
a second, so it can run often, for example from a git hook in every repo:

```sh
# .git/hooks/post-checkout and .git/hooks/post-merge (chmod +x)
#!/bin/sh
~/.config/nvim/tools/c-link-farm/link-farm.sh update -q "$(git rev-parse --show-toplevel)"
```

Runs are serialized with `flock`, so a hook and a cron job can overlap
safely.

## Two levels

The `~/.nvim-config.lua` setting `farm_index` chooses the level:

| `farm_index` | clangd reads | You get |
|---|---|---|
| `false` | `compile_flags.txt` | Diagnostics, completion and hover in open files. *Go to declaration* reaches any header. |
| `true`  | `index/compile_commands.json` | All of the above. clangd also indexes every `.c/.cpp` in the background, so *go to definition* and *references* reach files you never opened. The first run takes some time; the index is cached in `index/.cache`. |

With either level, `<leader>6` switches between `foo.h` and `foo.c(pp)` by
looking up the name in the farm.

## Limits

- Includes that contain a path (`#include "sub/foo.h"`) do not resolve.
  The farm is flat. Add that repo's root with `-f -I/work/repo`.
- Every file gets the same flags. If one lib needs special `-D`s, add them
  with `-f`, or give that lib its own `.clangd` file.

## How to use on big repos without LSP

This is a getting-started guide for a large workspace where LSP does not work
yet. The example layout is:

```
~/workspace/software/        <- you work here
~/workspace/software/libs/   <- ~400 lib repos
~/workspace/software/...     <- projects that use the libs
```

### 1. Build the farm

Keep the farm outside the workspace. The default `~/.cache/c-farm` stays out
of git, out of `<leader>ff` / `<leader>fg` results and out of any backups of
the workspace.

Scan all of `software`, not only `libs`. Then jumps work both ways: from a
project into a lib, and (with the index on) from a lib back to its users.

```sh
~/.config/nvim/tools/c-link-farm/link-farm.sh build ~/workspace/software
```

Check the `duplicate ...` lines the script prints:

- Duplicate sources such as `main.c` are harmless. They only affect `<leader>6`.
- Duplicate headers matter, because the first one found wins. If projects
  repeat names like `config.h`, scan only the libs. Each project's own headers
  are still found next to the file that includes them.

  ```sh
  ~/.config/nvim/tools/c-link-farm/link-farm.sh build ~/workspace/software/libs ~/workspace/software/projects
  ```

If the Makefiles pass important defines or a language standard, add them with
`-f`. Skip folder names such as tests or vendored code with `-x`:

```sh
~/.config/nvim/tools/c-link-farm/link-farm.sh build -f -DTARGET_LINUX -f -std=gnu11 -x third_party ~/workspace/software
```

To keep the farm up to date, run `update` after pulling (it remembers the
roots and flags), use the git hook from [Usage](#usage), or run it from cron
every night:

```
0 6 * * * $HOME/.config/nvim/tools/c-link-farm/link-farm.sh update -q
```

### 2. Configure nvim

```sh
cp ~/.config/nvim/example/.nvim-config.lua ~/.nvim-config.lua
```

In `~/.nvim-config.lua`, change these lines:

```lua
local clangd_mode = "farm"
local farm_dir = vim.fn.expand("~/.cache/c-farm")
local farm_index = false   -- start with this, see step 3

return {
	search = {
		root = "~/workspace/software",
		ignore_folders = { "build", ".git", "obj" },
	},
	...
```

The farm values are already the defaults in the example. Remove or adapt the
example keymaps `<leader>1`-`5`, which run `main.cpp`, cargo and so on.

To use a normal `compile_commands.json` instead (CMake, `bear`), set
`clangd_mode = "project"`. clangd then reads `<cwd>/<build_dir>`.

### 3. Use it

```sh
cd ~/workspace/software && nvim
```

It does not matter which folder you start nvim in. A single clangd serves
every repo because its root is the farm.

- **`farm_index = false`**: starts at once. You get diagnostics, completion,
  hover and go to declaration into any header.
- **`farm_index = true`**: switch to this once the above works. clangd indexes
  every `.c` / `.cpp` in the background, so go to definition and references
  reach files you never opened.
  - With 400 repos the first run can take a long time and a lot of CPU. The
    result is cached in `~/.cache/c-farm/index/.cache`, and later runs only
    re-index changed files.
  - Indexing runs on 4 threads (`"-j=4"` in `clangd_cmd` in
    `~/.nvim-config.lua`). Lower it if the machine gets too slow; raise it on
    a big machine to finish sooner.
- **`<leader>6`**: switches between `foo.h` and `foo.c` / `foo.cpp`.

### Watching the index

- **Statusline**: shows `⟳ clangd indexing 6%` while clangd indexes. The
  text disappears when indexing is done.
- **`<leader>cI`**: every indexing / progress task, running and finished, with
  elapsed time and a rough time-left estimate. Updates live.
- **`<leader>cS`**: which servers run, their root and cmd, and whether the
  current buffer has one attached.
- **`<leader>cL`**: opens the LSP log in a new tab, at the end. clangd writes
  everything to it: `I[...]` lines are info, `E[...]` lines are errors. nvim
  tags all of them `[ERROR] ... "stderr"`, which does not mean anything failed.
  Run `:e` to reload the log.
- **`<leader>cE`**: puts every clangd error line (`E[...]`) into the quickfix
  list.
- **From a shell** (without nvim): compare how many files are in the index with
  how many sources exist:

  ```sh
  ls ~/.cache/c-farm/index/.cache/clangd/index | wc -l   # indexed files (sources + headers)
  ls ~/.cache/c-farm/src | wc -l                         # sources to index
  ```

The LSP log is at `~/.local/state/nvim/lsp.log` and keeps growing. Delete it
when it gets big; nvim creates a new one.

### Troubleshooting

Start with `link-farm.sh check`. It changes nothing and reports, each with its
fix: missing roots, missing clangd, links to deleted files, files not linked
yet, headers shadowed by a same-named header, sources left out of the index
because of a duplicate name, stale `compile_flags.txt` /
`compile_commands.json`, and `#include "dir/foo.h"` lines that clangd cannot
resolve. It exits with 1 on errors. It scans every root and greps every
file, so it is slower than `update`.

- **Warning `no link farm at ...`**: step 1 has not run, or `farm_dir` points
  somewhere else.
- **`'foo.h' file not found`**: the include has a path (`"sub/foo.h"`), or the
  header is in a skipped folder. Add that folder with `-f -I/path/to/folder`.
- **Wrong or odd diagnostics in one lib**: it needs its own defines. Add them
  with `-f`, or put a `.clangd` file in that repo.
- **New file not found by clangd**: run `link-farm.sh update` (or
  `update <repo>`); a name that already exists in the farm is a duplicate and
  stays linked to the first file.
- **LSP log**: `<leader>cL`, or `<leader>cE` for errors only. `<leader>cS`
  shows whether clangd is attached.
