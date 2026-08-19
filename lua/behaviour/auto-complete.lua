-- Auto-completion without a plugin (replaces blink.cmp).
--
-- Deliberately dumb and therefore fast: the only source is the keywords of the
-- current file (built-in i_CTRL-N with 'complete' set to "."). No LSP request,
-- no path scan, no other buffers -- nothing that can block while typing.
--
-- Keys:  <Tab> accept (selects the first entry if none is selected),
--        <S-Tab> previous entry, <C-n>/<C-p> next/previous, <C-e> dismiss.
--        Everything else stays native insert-mode completion.

local M = {}

-- do not pop up a menu before that many word characters were typed
local MIN_CHARS = 3

local function completion_disabled(buf)
	-- no menus in prompts, terminals, netrw, the overlay lists, ...
	return vim.bo[buf].buftype ~= "" or vim.bo[buf].filetype == "netrw"
end

-- Is there a keyword in this buffer that "word" could grow into?
--
-- This is the same question i_CTRL-N asks, asked before we press it: firing
-- CTRL-N when nothing can match makes Neovim re-enter completion on every
-- further keystroke, which swallows the typed text and leaves the menu on
-- screen. Pattern: "word" at a word boundary plus at least one more keyword
-- character (a candidate that is only the word itself completes to nothing).
local function has_match(word)
	local case = vim.o.ignorecase and "\\c" or "\\C"
	local pattern = case .. "\\<" .. word .. "\\k"
	return vim.fn.search(pattern, "nw") ~= 0
end

function M.setup()
	-- menu also for a single match, never insert/select on our own
	vim.opt.completeopt = { "menu", "menuone", "noselect" }
	-- keyword source: this buffer only
	vim.o.complete = "."
	vim.opt.shortmess:append("c") -- no "match 1 of 5" / "Pattern not found" spam

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
			local line = vim.api.nvim_get_current_line()
			local word = line:sub(1, col):match("[%w_]*$")
			if #word < MIN_CHARS then return end
			-- editing inside a word: a completion would be inserted into its middle
			if line:sub(col + 1, col + 1):match("[%w_]") then return end
			-- nothing left to offer -> stay quiet and let the menu close
			if not has_match(word) then return end

			vim.api.nvim_feedkeys(vim.keycode("<C-n>"), "n", false)
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
