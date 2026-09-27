-- Command built on the nested sidebar: the cursor history, newest first, one
-- row per place ("file:line"). j / k walk the places and the window next to the
-- sidebar follows. <CR> / o jump there and close the list, <Esc> closes it.
-- Same sidebar as function_list, just flat (no nesting).
--
-- The source is custom.cursor-history of the current tab (seeded from vim's
-- jumplist at startup). One entry per place -- positions a few lines apart are
-- listed once.

local sidebar = require("actions.gui.list_nested_sidebar")

local M = {}

-- show the place e in win: load its file there, cursor on it, centered
local function show(e, win)
	local buf = vim.fn.bufadd(e.file)
	vim.fn.bufload(buf)
	vim.bo[buf].buflisted = true
	if vim.api.nvim_win_get_buf(win) ~= buf then vim.api.nvim_win_set_buf(win, buf) end
	pcall(vim.api.nvim_win_set_cursor, win, { e.lnum, e.col or 0 })
	vim.api.nvim_win_call(win, function() vim.cmd("normal! zvzz") end)
end

function M.open()
	local entries = {}
	for _, e in ipairs(require("custom.cursor-history").entries()) do -- newest first
		if vim.fn.filereadable(e.file) == 1 then entries[#entries + 1] = e end
	end
	if #entries == 0 then
		vim.notify("Cursor history is empty", vim.log.levels.WARN)
		return
	end

	vim.cmd("normal! m'") -- <CR> jumps away: CTRL-O comes back here
	sidebar.open({
		filetype = "jumplist",
		width = 35,
		root = {}, -- no row of its own
		children = function() return entries end, -- rows are leaves: only the root asks
		key = function(e) return e.file .. ":" .. e.lnum end,
		label = function(e) return vim.fn.fnamemodify(e.file, ":t") .. ":" .. e.lnum end,
		on_move = show,
		on_open = show,
	})
	sidebar.set_title("Cursor history")
end

return M
