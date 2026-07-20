-- Same keymaps as before — plugin-free targets.
-- telescope -> core.picker / :grep / native cmds
-- nvim-tree -> netrw          diffview/fugitive/gitsigns -> core.git
-- dap/dapui -> core.debug (termdebug)   trouble/calltree -> loclist/quickfix

local M = {}

function M.setup()
	local picker = require("core.picker")
	local git = require("core.git")
	local windows = require("core.windows")
	local dbg = require("core.debug")

	-- helper -------------------------------------------------------------
	local function show_keymaps()
		local items = {}
		for _, mode in ipairs({ "n", "v", "x", "o", "i" }) do
			for _, km in ipairs(vim.api.nvim_get_keymap(mode)) do
				if km.desc and km.desc ~= "" then
					items[#items + 1] = {
						text = string.format("%s  %-14s %s", mode, km.lhs:gsub(" ", "<Space>"), km.desc),
						lhs = km.lhs,
						mode = mode,
					}
				end
			end
		end
		table.sort(items, function(a, b) return a.text < b.text end)
		picker.pick(items, { prompt = "Keymaps" })
	end

	local function live_grep()
		vim.ui.input({ prompt = "Grep: " }, function(q)
			if not q or q == "" then return end
			vim.cmd("silent grep! " .. vim.fn.escape(q, "%#|\""))
			vim.cmd("copen")
		end)
	end

	local function grep_word_under_cursor()
		vim.cmd("silent grep! " .. vim.fn.escape(vim.fn.expand("<cWORD>"), "%#|\""))
		vim.cmd("copen")
	end

	local function open_file_tree() -- netrw replaces nvim-tree
		for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
			if vim.bo[vim.api.nvim_win_get_buf(w)].filetype == "netrw" then
				vim.api.nvim_win_close(w, true)
				return
			end
		end
		vim.cmd("Lexplore " .. vim.fn.fnameescape(vim.fn.expand("%:p:h")))
	end

	-- shared l / <CR> / <Esc> keys for list-like windows (netrw tree, quickfix):
	-- run the window's native open action, then decide by focus: unchanged =
	-- nothing opened elsewhere (e.g. folder toggled inline), moved = entry opened.
	-- l keeps focus in the list, <CR> jumps to the entry and closes the list.
	local function set_list_keys(buf, native_open)
		local function open_entry(after_open)
			local list_win = vim.api.nvim_get_current_win()
			if not pcall(vim.cmd, native_open) then return end
			if vim.api.nvim_get_current_win() ~= list_win and vim.api.nvim_win_is_valid(list_win) then
				after_open(list_win)
			end
		end
		local opts = { buffer = buf }
		vim.keymap.set("n", "l", function()
			open_entry(vim.api.nvim_set_current_win)
		end, opts)
		vim.keymap.set("n", "<CR>", function()
			open_entry(function(w) vim.api.nvim_win_close(w, true) end)
		end, opts)
		vim.keymap.set("n", "<Esc>", function()
			pcall(vim.api.nvim_win_close, 0, true)
		end, opts)
	end

	vim.api.nvim_create_autocmd("FileType", {
		pattern = "netrw",
		callback = function(args)
			set_list_keys(args.buf, [[execute "normal \<Plug>NetrwLocalBrowseCheck"]])
		end,
	})
	vim.api.nvim_create_autocmd("FileType", {
		pattern = "qf", -- grep results, diagnostics, references, ... (quickfix + loclist)
		callback = function(args)
			set_list_keys(args.buf, [[execute "normal! \<CR>"]])
		end,
	})

	local function browse_buffers()
		local items = {}
		for _, b in ipairs(vim.fn.getbufinfo({ buflisted = 1 })) do
			items[#items + 1] = {
				text = string.format("%3d  %s%s", b.bufnr, vim.fn.fnamemodify(b.name, ":~:."), b.changed == 1 and " [+]" or ""),
				bufnr = b.bufnr,
			}
		end
		picker.pick(items, {
			prompt = "Buffers",
			on_select = function(it) vim.cmd("buffer " .. it.bufnr) end,
		})
	end

	local function browse_jumplist()
		local jumps = vim.fn.getjumplist()[1]
		local items = {}
		for i = #jumps, 1, -1 do
			local j = jumps[i]
			local name = j.bufnr and vim.fn.bufname(j.bufnr) or ""
			if name ~= "" then
				items[#items + 1] = { text = string.format("%s:%d", vim.fn.fnamemodify(name, ":~:."), j.lnum), j = j }
			end
		end
		picker.pick(items, {
			prompt = "Jumplist",
			on_select = function(it)
				vim.cmd("buffer " .. it.j.bufnr)
				pcall(vim.api.nvim_win_set_cursor, 0, { it.j.lnum, it.j.col })
			end,
		})
	end

	local lsp_border = { "┏", "━", "┓", "┃", "┛", "━", "┗", "┃" }
	local function lsp_hover() vim.lsp.buf.hover({ border = lsp_border }) end
	local function lsp_signature() vim.lsp.buf.signature_help({ border = lsp_border }) end

	-- general --------------------------------------------------------------
	vim.keymap.set("n", "<leader>h", show_keymaps, { desc = "Show keymaps" })

	-- navigation -----------------------------------------------------------
	vim.keymap.set("n", "<leader>ft", open_file_tree, { desc = "Navigation : Open file tree" })
	vim.keymap.set("n", "<leader>fj", browse_jumplist, { desc = "Navigation : Browse jump history" })
	vim.keymap.set("n", "<leader>ff", require("commands.find_files").open, { desc = "Navigation : Search by file name" })
	vim.keymap.set("n", "<leader>fg", live_grep, { desc = "Navigation : Search in file contents" })
	vim.keymap.set("n", "<leader>fs", require("commands.rip_grep").open, { desc = "Navigation : Rip grep file contents (list overlay)" })
	vim.keymap.set("n", "<leader>fG", grep_word_under_cursor, { desc = "Navigation : Search word under cursor in file contents" })
	vim.keymap.set("n", "<leader>fr", "<cmd>registers<CR>", { desc = "Navigation : Browse copy & paste registers" })
	vim.keymap.set("n", "<leader>fb", browse_buffers, { desc = "Navigation : Browse open buffers" })
	vim.keymap.set("n", "<leader>w", windows.pick_window_to_jump, { desc = "Navigation : Pick window to jump to" })
	vim.keymap.set("n", "<C-o>", "<C-o>", { desc = "Navigation : Jump back to previous position" })
	vim.keymap.set("n", "<C-i>", "<C-i>", { desc = "Navigation : Jump forward again" })
	vim.keymap.set({ "n", "o", "x" }, ",", "^", { desc = "Navigation : Set cursor to start of line" })
	vim.keymap.set({ "n", "o", "x" }, ".", "$", { desc = "Navigation : Set cursor to end of line" })

	-- code navigation (lsp) --------------------------------------------------
	vim.keymap.set("n", "<leader>cl", function()
		vim.diagnostic.setqflist({ open = true })
	end, { desc = "LSP : Browse diagnostics (linter)" })
	vim.keymap.set("n", "<leader>cd", vim.lsp.buf.definition, { desc = "LSP : Go to definition" })
	vim.keymap.set("n", "<leader>cu", vim.lsp.buf.references, { desc = "LSP : Find usages / references" })
	-- incoming/outgoing calls land in the quickfix list natively (replaces calltree)
	vim.keymap.set("n", "<leader>ci", vim.lsp.buf.incoming_calls, { desc = "LSP : Incoming calls (who calls this)" })
	vim.keymap.set("n", "<leader>co", vim.lsp.buf.outgoing_calls, { desc = "LSP : Outgoing calls (what this calls)" })
	vim.keymap.set("n", "<leader>cs", function() -- replaces Trouble symbols
		vim.lsp.buf.document_symbol()
	end, { desc = "LSP : Symbol outline of current file (loclist)" })
	vim.keymap.set("n", "<leader>cg", "<cmd>CDeps<CR>", { desc = "C/C++ : Folder dependency graph" })
	vim.keymap.set("n", "<leader>cr", vim.lsp.buf.rename, { desc = "LSP : Rename symbol" })
	vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, { desc = "LSP : Code actions" })
	vim.keymap.set("n", "<leader>cm", vim.lsp.buf.implementation, { desc = "LSP : Jump to implementation" })
	vim.keymap.set("n", "<leader>ck", lsp_hover, { desc = "LSP : Hover docs of var" })
	vim.keymap.set("n", "<leader>cf", lsp_signature, { desc = "LSP : Show Fn-Signature help" })

	-- tabs -------------------------------------------------------------------
	vim.keymap.set("n", "<leader>tn", "<cmd>tabnew<CR>", { desc = "Tabs : New empty tab (tabs)" })
	vim.keymap.set("n", "<leader>ts", "<cmd>tab split<CR>", { desc = "Tabs : Open current file in new tab (tabs)" })
	vim.keymap.set("n", "<leader>tx", "<cmd>tabclose<CR>", { desc = "Tabs : Close current tab (tabs)" })

	-- git ----------------------------------------------------------------------
	vim.keymap.set("n", "<leader>gq", require("commands.git_status").open, { desc = "Git : Open git status (quick overview)" })
	vim.keymap.set("n", "<leader>gs", git.diff_against_index, { desc = "Git : Diff current file vs index (working tree diff)" })
	vim.keymap.set("n", "<leader>gc", function() git.commits() end, { desc = "Git : Browse commits" })
	vim.keymap.set("n", "<leader>gb", git.branches, { desc = "Git : Browse branches" })

	-- git history -------------------------------------------------------------
	vim.keymap.set("n", "<leader>hr", git.repo_history, { desc = "Git-History: View repo history" })
	vim.keymap.set("n", "<leader>hf", git.file_history, { desc = "Git-History: View file history " })
	vim.keymap.set("n", "<leader>hd", git.diff_range, { desc = "Git-History : View diff between 2 commits" })

	-- debug (termdebug) ---------------------------------------------------------
	vim.keymap.set("n", "<leader>db", dbg.toggle_breakpoint, { desc = "Debug : Toggle breakpoint" })
	vim.keymap.set("n", "<leader>dc", dbg.continue, { desc = "Debug : Continue / start" })
	vim.keymap.set("n", "<leader>dn", dbg.step_over, { desc = "Debug : Step over" })
	vim.keymap.set("n", "<leader>di", dbg.step_into, { desc = "Debug : Step into" })
	vim.keymap.set("n", "<leader>do", dbg.step_out, { desc = "Debug : Step out" })
	vim.keymap.set("n", "<leader>dx", dbg.terminate, { desc = "Debug : Terminate" })
	vim.keymap.set("n", "<leader>dp", dbg.pause, { desc = "Debug : Pause" })
	vim.keymap.set("n", "<leader>dr", dbg.restart, { desc = "Debug : Restart" })
	vim.keymap.set("n", "<leader>du", dbg.toggle_ui, { desc = "Debug : Jump gdb <-> source window" })
	vim.keymap.set("n", "<leader>de", dbg.eval, { desc = "Debug : Evaluate expression" })
	vim.keymap.set("n", "<leader>dw", dbg.watch_word, { desc = "Debug : Add word under cursor to watch (gdb display)" })
end

return M
