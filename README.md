# nvim-min — plugin-free config

Reduced version of [no-country-4-old-code/nvim](https://github.com/no-country-4-old-code/nvim)
with **zero plugins** and **all keymaps preserved** (same bindings, same descriptions —
`<leader>h` still shows them all).

## Requirements

- **nvim >= 0.11** (uses `vim.lsp.config` / `vim.lsp.enable` / `vim.lsp.completion`)
- Optional binaries (everything degrades gracefully if missing):
  - `clangd`, `rust-analyzer`, `pyright`, `omnisharp` — LSP (auto-enabled only if found on `$PATH`)
  - `rg` — fast `<leader>fg` grep (falls back to recursive `grep`)
  - `gdb` — debugging via built-in **termdebug**
  - `cppcheck`, `graphviz` — for the unchanged `custom/cppcheck.lua` and `:CDeps`

## Install

Copy this folder to `~/.config/nvim` (backup the old one first).

## What replaced what

| Plugin | Replacement |
|---|---|
| telescope | `lua/core/picker.lua` — minimal fuzzy picker (`matchfuzzy`) for files, buffers, jumplist, keymaps, git |
| nvim-tree | netrw (`<leader>ft` toggles) |
| lspconfig, mason, blink.cmp | native `vim.lsp.config/enable` + built-in autocompletion (`lua/core/lsp.lua`) |
| trouble, calltree | native loclist / quickfix (symbols, incoming/outgoing calls) |
| diffview `<leader>gs` | `lua/core/git.lua` — `:diffsplit` against git index; `f`/`t` hunk jump, `<leader>gp/gl` diffput/get, `q` closes |
| telescope git / fugitive | pickers over `git status/log/branch` (`<leader>gq/gc/gb`), checkout on select |
| diffview history | `git show`/`git diff`/`git log` in scratch tabs (`<leader>hf/hd/hr`, `q` closes) |
| nvim-dap + dap-ui | built-in **termdebug** (`lua/core/debug.lua`) — `<leader>dc` asks for the executable on first start |
| window-picker | `lua/core/windows.lua` — letter labels per window |
| lualine | one-line statusline with git branch + diagnostic counts |
| treesitter plugin | built-in `vim.treesitter.start()` for bundled parsers (c, lua, vim, markdown, …) |
| tokyonight | built-in `habamax` (your custom line-number highlights still applied on top) |

Unchanged: `custom/tabs.lua`, `custom/line-numbers.lua`, `custom/enforce-unix-eol.lua`,
`custom/dep-graph.lua` + `scripts/cdeps.sh`, `custom/cppcheck.lua` (was already plugin-free).

## Known behavior changes

- **Hunk staging** (`<leader>ga/gu`) and inline git signs are gone — use `git add -p`
  in a terminal. `f`/`t` hunk navigation only works inside diff views now.
- **Breakpoints** (`<leader>db`) can only be set after the gdb session started
  (`<leader>dc` first) — termdebug limitation.
- `<leader>dw` uses gdb `display` (prints the variable on every stop) instead of a
  watch panel; `<leader>du` jumps between gdb and source window instead of toggling a UI.
- Pickers select with `<CR>` only; the extra telescope mappings (`<C-h>`, `<C-o>`
  in commit/branch previews) are folded into the default action.
