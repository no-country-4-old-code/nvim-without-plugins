-- Command built on the nested sidebar: every LSP diagnostic of all loaded
-- buffers, one row each ("E file:line message"), errors first, then by file
-- and line. j / k walk them and the window next to the sidebar follows. <CR>
-- jumps there and closes the list, <Esc> goes back to where you started.
-- Same sidebar as function_list, just flat (no nesting).

local sidebar = require("actions.gui.list_nested_sidebar")

local M = {}

local SEVERITY = {
	[vim.diagnostic.severity.ERROR] = { "E", "DiagnosticError" },
	[vim.diagnostic.severity.WARN] = { "W", "DiagnosticWarn" },
	[vim.diagnostic.severity.INFO] = { "I", "DiagnosticInfo" },
	[vim.diagnostic.severity.HINT] = { "H", "DiagnosticHint" },
}

-- show diagnostic d in win: its buffer there, cursor on it, centered
local function show(d, win)
	if not vim.api.nvim_buf_is_valid(d.bufnr) then return end
	if vim.api.nvim_win_get_buf(win) ~= d.bufnr then vim.api.nvim_win_set_buf(win, d.bufnr) end
	pcall(vim.api.nvim_win_set_cursor, win, { d.lnum + 1, d.col })
	vim.api.nvim_win_call(win, function() vim.cmd("normal! zvzz") end)
end

function M.open()
	local diags = vim.diagnostic.get()
	if #diags == 0 then
		vim.notify("No diagnostics", vim.log.levels.INFO)
		return
	end
	local name = {}
	for _, d in ipairs(diags) do
		name[d.bufnr] = name[d.bufnr] or vim.fn.fnamemodify(vim.api.nvim_buf_get_name(d.bufnr), ":t")
	end
	table.sort(diags, function(a, b)
		if a.severity ~= b.severity then return a.severity < b.severity end
		if a.bufnr ~= b.bufnr then return name[a.bufnr] < name[b.bufnr] end
		if a.lnum ~= b.lnum then return a.lnum < b.lnum end
		return a.col < b.col
	end)

	vim.cmd("normal! m'") -- <CR> jumps away: CTRL-O comes back here
	sidebar.open({
		filetype = "diagnosticlist",
		width = 50,
		root = {}, -- no row of its own
		children = function() return diags end, -- rows are leaves: only the root asks
		key = function(d) return d.bufnr .. ":" .. d.lnum .. ":" .. d.col .. ":" .. d.message end,
		label = function(d)
			local msg = d.message:gsub("%s*\n%s*", " ")
			return (SEVERITY[d.severity] or { "?" })[1] .. " " .. name[d.bufnr] .. ":" .. (d.lnum + 1) .. " " .. msg
		end,
		highlight = function(d) return (SEVERITY[d.severity] or {})[2] end,
		on_move = show,
		on_open = show,
	})
	sidebar.set_title("Diagnostics (" .. #diags .. ")")
end

return M
