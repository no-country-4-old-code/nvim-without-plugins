-- Same keymaps as before — plugin-free targets.
-- telescope -> core.picker / :grep / native cmds
-- nvim-tree -> netrw          diffview/fugitive/gitsigns -> core.git
-- dap/dapui -> core.debug (termdebug)   trouble/calltree -> loclist/quickfix

local M = {}

function M.setup()
	local git = require("core.git")
	local windows = require("core.windows")
	local dbg = require("core.debug")

	-- helper -------------------------------------------------------------
	local lsp_border = { "┏", "━", "┓", "┃", "┛", "━", "┗", "┃" }
	local function lsp_hover() vim.lsp.buf.hover({ border = lsp_border }) end
	local function lsp_signature() vim.lsp.buf.signature_help({ border = lsp_border }) end

	-- general --------------------------------------------------------------
	vim.keymap.set("n", "<leader>h", require("actions.show_keymaps").open, { desc = "Show keymaps" })
	vim.keymap.set("n", "<leader>y", require("custom.copy-mode").toggle, { desc = "Copy mode : Clipboard y/p, no line numbers (<Esc> leaves)" })
	vim.keymap.set("n", "<leader>r", require("actions.replace_word_with_register").run, { desc = "Edit : Replace word under cursor with register (register kept)" })

	-- navigation -----------------------------------------------------------
	vim.keymap.set("n", "<leader>l", require("actions.file_tree").open, { desc = "Navigation : Project file tree (nested sidebar)" })
	vim.keymap.set("n", "<leader>j", require("actions.jump_list").open, { desc = "Navigation : Browse jump history (list overlay)" })
	vim.keymap.set("n", "<leader>f", require("actions.find_files").open, { desc = "Navigation : Search by file name" })
	vim.keymap.set("n", "<leader>K", require("actions.rip_grep").open, { desc = "Navigation : Rip grep file contents (list overlay)" })
	vim.keymap.set("n", "<leader>k", function() require("actions.rip_grep").open(vim.fn.expand("<cword>")) end, { desc = "Navigation : Rip grep word under cursor (list overlay, prefilled)" })
	vim.keymap.set("n", "<leader>fr", "<cmd>registers<CR>", { desc = "Navigation : Browse copy & paste registers" })
	local signs = require("behaviour.git-signs")
	vim.keymap.set("n", "f", function() signs.goto_hunk(1) end, { desc = "Navigation : Next modified block (git)" })
	vim.keymap.set("n", "F", function() signs.goto_hunk(-1) end, { desc = "Navigation : Previous modified block (git)" })
	vim.keymap.set("n", "<leader>w", windows.pick_window_to_jump, { desc = "Navigation : Pick window to jump to" })
	local history = require("custom.cursor-history") -- richer than vim's jumplist: every visited area
	vim.keymap.set("n", "<leader>n", history.back, { desc = "Navigation : Go back to previous position" })
	vim.keymap.set("n", "<leader>b", history.forward, { desc = "Navigation : Go forward again" })
	vim.keymap.set({ "n", "o", "x" }, ",", "^", { desc = "Navigation : Set cursor to start of line" })
	vim.keymap.set({ "n", "o", "x" }, ".", "$", { desc = "Navigation : Set cursor to end of line" })

	-- code navigation (lsp) --------------------------------------------------
	vim.keymap.set("n", "<leader>cl", function()
		vim.diagnostic.setqflist({ open = true })
	end, { desc = "LSP : Browse diagnostics (linter)" })
	vim.keymap.set("n", "<leader>d", vim.lsp.buf.definition, { desc = "LSP : Go to definition" })
	vim.keymap.set("n", "<leader>u", vim.lsp.buf.references, { desc = "LSP : Find usages / references" })
	-- incoming/outgoing calls land in the quickfix list natively (replaces calltree)
	vim.keymap.set("n", "<leader>ci", vim.lsp.buf.incoming_calls, { desc = "LSP : Incoming calls (who calls this)" })
	vim.keymap.set("n", "<leader>co", vim.lsp.buf.outgoing_calls, { desc = "LSP : Outgoing calls (what this calls)" })
	vim.keymap.set("n", "<leader>ct", require("actions.call_tree").open, { desc = "LSP : Call tree of current function (nested sidebar, h = callers)" })
	vim.keymap.set("n", "<leader>cd", require("actions.function_list").open, { desc = "LSP : Functions of current file (nested sidebar, j/k walks them)" })
	vim.keymap.set("n", "<leader>cs", function() -- replaces Trouble symbols
		vim.lsp.buf.document_symbol()
	end, { desc = "LSP : Symbol outline of current file (loclist)" })
	vim.keymap.set("n", "<leader>cg", "<cmd>CDeps<CR>", { desc = "C/C++ : Folder dependency graph" })
	-- t / T only exist in C/C++ buffers: elsewhere they stay vim's till-motion
	vim.api.nvim_create_autocmd("FileType", {
		pattern = { "c", "cpp" },
		callback = function(args)
			local fn = require("custom.goto-function")
			vim.keymap.set("n", "t", function() fn.jump(1) end,
				{ buffer = args.buf, desc = "C/C++ : Jump to next function definition" })
			vim.keymap.set("n", "T", function() fn.jump(-1) end,
				{ buffer = args.buf, desc = "C/C++ : Jump to previous function definition" })
		end,
	})
	vim.keymap.set("n", "<leader>cr", vim.lsp.buf.rename, { desc = "LSP : Rename symbol" })
	vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, { desc = "LSP : Code actions" })
	vim.keymap.set("n", "<leader>cm", vim.lsp.buf.implementation, { desc = "LSP : Jump to implementation" })
	vim.keymap.set("n", "<leader>ck", lsp_hover, { desc = "LSP : Hover docs of var" })
	vim.keymap.set("n", "<leader>cf", lsp_signature, { desc = "LSP : Show Fn-Signature help" })
	local lsp_screen = require("actions.lsp_screen")
	vim.keymap.set("n", "<leader>cS", lsp_screen.status, { desc = "LSP : Status of running servers" })
	vim.keymap.set("n", "<leader>cI", lsp_screen.indexing, { desc = "LSP : Indexing / progress (live)" })
	vim.keymap.set("n", "<leader>cL", lsp_screen.log, { desc = "LSP : Open log (new tab)" })
	vim.keymap.set("n", "<leader>cE", lsp_screen.errors, { desc = "LSP : Errors from log -> quickfix" })

	-- tabs -------------------------------------------------------------------
	vim.keymap.set("n", "<leader>tn", "<cmd>tabnew<CR>", { desc = "Tabs : New empty tab (tabs)" })
	vim.keymap.set("n", "<leader>ts", "<cmd>tab split<CR>", { desc = "Tabs : Open current file in new tab (tabs)" })
	vim.keymap.set("n", "<leader>tx", "<cmd>tabclose<CR>", { desc = "Tabs : Close current tab (tabs)" })

	-- git ----------------------------------------------------------------------
	vim.keymap.set("n", "<leader>g", require("actions.git_status").open, { desc = "Git : Browse every changed block (git status)" })

end

return M
