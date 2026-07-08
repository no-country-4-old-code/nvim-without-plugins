-- Plugin-free nvim config (requires nvim >= 0.11).
-- Reduced version of https://github.com/no-country-4-old-code/nvim
-- No package manager, no external plugins. External BINARIES still used
-- if available: clangd / rust-analyzer / pyright (LSP), rg (grep), gdb (debug).

vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- colorscheme: tokyonight (storm), provided as a native colors/ file (no plugin)
vim.cmd.colorscheme("tokyonight")

-- netrw as file tree (nvim-tree replacement)
vim.g.netrw_banner = 0
vim.g.netrw_liststyle = 3
vim.g.netrw_winsize = 30

-- ripgrep for :grep if available (telescope live_grep replacement)
if vim.fn.executable("rg") == 1 then
	vim.o.grepprg = "rg --vimgrep --smart-case --hidden --glob !.git"
	vim.o.grepformat = "%f:%l:%c:%m"
else
	vim.o.grepprg = "grep -rnH --exclude-dir=.git $* ."
end

-- built-in treesitter highlighting for bundled parsers (c, lua, vim, markdown, ...)
vim.api.nvim_create_autocmd("FileType", {
	callback = function(args)
		pcall(vim.treesitter.start, args.buf)
	end,
})

-- fuzzy cmdline completion as a bonus (:find, :b, ...)
vim.opt.wildoptions:append("fuzzy")
vim.opt.path:append("**")

-- load custom settings (unchanged from the full config)
require("custom.enforce-unix-eol").setup()
require("custom.line-numbers").setup()
require("custom.tabs").setup()
require("custom.dep-graph").setup()
-- custom.cppcheck is required on demand from a project's .nvim.lua (see its header)

-- plugin replacements
require("core.lsp").setup()
require("core.debug").setup()
require("core.statusline").setup()
require("core.key-mappings").setup()

-- No swap file please !
vim.opt.swapfile = false

-- Load .nvim.lua from project root if present (nvim will prompt to trust on first load)
vim.opt.exrc = true
