-- Auto-completion without a plugin (replaces blink.cmp).
--
-- Sources, chosen per buffer (like blink's "lsp, path, snippets, buffer"):
--   * LSP  -- vim.lsp.completion (snippets are expanded by it on accept)
--   * path -- built-in i_CTRL-X_CTRL-F, auto-triggered while typing a path
--   * buffer/window words -- built-in i_CTRL-N, used when no LSP is attached
--
-- Keys:  <Tab> accept (selects the first entry if none is selected),
--        <S-Tab> previous entry, <C-n>/<C-p> next/previous, <C-e> dismiss.
--        Everything else stays native insert-mode completion.

local M = {}

-- do not pop up a menu before that many word characters were typed
local MIN_CHARS = 2

-- text before the cursor looks like a (partial) path: ./foo, ~/ba, src/ma
local PATH_PATTERN = "[%w%._%-%$~/\\]*[/\\][%w%._%-%$]*$"

local function completion_disabled(buf)
	-- no menus in prompts, terminals, netrw, the overlay lists, ...
	return vim.bo[buf].buftype ~= "" or vim.bo[buf].filetype == "netrw"
end

local function has_lsp_completion(buf)
	for _, client in ipairs(vim.lsp.get_clients({ bufnr = buf })) do
		if client:supports_method("textDocument/completion") then return true end
	end
	return false
end

local function feed(keys)
	vim.api.nvim_feedkeys(vim.keycode(keys), "n", false)
end

-- what (if anything) should be completed at the cursor
local function trigger_for(buf, line_before_cursor)
	if line_before_cursor:match(PATH_PATTERN) then return "path" end
	if not line_before_cursor:match("[%w_]$") then return nil end
	if #(line_before_cursor:match("[%w_]*$")) < MIN_CHARS then return nil end
	return has_lsp_completion(buf) and "lsp" or "buffer"
end

function M.setup()
	-- menu also for a single match, never insert/select on our own, show the
	-- documentation of the selected entry in a popup next to the menu
	vim.opt.completeopt = { "menu", "menuone", "noselect", "popup" }
	-- keyword source: this buffer, visible windows, loaded buffers (skip the
	-- slow default extras like tag files and included files)
	vim.o.complete = ".,w,b"
	vim.opt.shortmess:append("c") -- no "match 1 of 5" / "Pattern not found" spam

	-- LSP source: trigger characters ('.', '->', '::', ...) are handled by
	-- nvim itself, plain word typing by the autocmd below.
	vim.api.nvim_create_autocmd("LspAttach", {
		callback = function(args)
			local client = vim.lsp.get_client_by_id(args.data.client_id)
			if client and client:supports_method("textDocument/completion") then
				vim.lsp.completion.enable(true, client.id, args.buf, { autotrigger = true })
			end
		end,
	})

	-- auto-trigger while typing ------------------------------------------------
	local skip_next = false -- accepting an entry ends on a word char -> would re-open

	vim.api.nvim_create_autocmd("CompleteDone", {
		callback = function() skip_next = true end,
	})

	vim.api.nvim_create_autocmd("TextChangedI", {
		callback = function(args)
			local skipped = skip_next
			skip_next = false
			if skipped or vim.fn.pumvisible() == 1 then return end
			-- never fight with a macro being recorded or replayed
			if vim.fn.reg_recording() ~= "" or vim.fn.reg_executing() ~= "" then return end
			if completion_disabled(args.buf) then return end

			local col = vim.api.nvim_win_get_cursor(0)[2]
			local before = vim.api.nvim_get_current_line():sub(1, col)
			local trigger = trigger_for(args.buf, before)

			if trigger == "path" then
				feed("<C-x><C-f>")
			elseif trigger == "lsp" then
				vim.lsp.completion.get() -- async, unlike i_CTRL-X_CTRL-O
			elseif trigger == "buffer" then
				feed("<C-n>")
			end
		end,
	})

	-- keys ---------------------------------------------------------------------
	vim.keymap.set("i", "<Tab>", function()
		if vim.fn.pumvisible() == 0 then return "<Tab>" end
		-- nothing selected (noselect): take the first entry, like blink's accept
		if vim.fn.complete_info({ "selected" }).selected == -1 then return "<C-n><C-y>" end
		return "<C-y>"
	end, { expr = true, desc = "Complete : Accept entry (else insert a Tab)" })

	vim.keymap.set("i", "<S-Tab>", function()
		return vim.fn.pumvisible() == 1 and "<C-p>" or "<S-Tab>"
	end, { expr = true, desc = "Complete : Previous entry" })
end

return M
