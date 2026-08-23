-- "Copy mode": a modus for exchanging text with the outside world.
--   * y / p (and Y / P) work on the system clipboard ("+)
--   * pasted text is normalised to unix line breaks (\r\n and \r -> \n)
--   * line numbers, signs, cursorline and diagnostics are hidden, mouse is
--     released, so a terminal mouse selection grabs the plain text only
-- Toggle with the keymap in core.key-mappings, leave with <Esc>.

local M = {}

local active = false
local saved = {}

function _G.Statusline_copymode()
	return active and "  COPY " or ""
end

function M.active()
	return active
end

-- window-local options are applied to every open window, and to vim.o so that
-- windows opened while the mode is on inherit them.
local win_opts = { number = false, relativenumber = false, cursorline = false, signcolumn = "no" }

local function set_win(win, opts)
	for name, value in pairs(opts) do
		pcall(function() vim.wo[win][name] = value end)
	end
end

local function apply_windows()
	for name, value in pairs(win_opts) do vim.o[name] = value end
	for _, win in ipairs(vim.api.nvim_list_wins()) do set_win(win, win_opts) end
end

local function save_windows()
	saved.global = {}
	saved.wins = {}
	for name in pairs(win_opts) do saved.global[name] = vim.o[name] end
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		local opts = {}
		for name in pairs(win_opts) do opts[name] = vim.wo[win][name] end
		saved.wins[win] = opts
	end
end

local function restore_windows()
	for name, value in pairs(saved.global) do vim.o[name] = value end
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		set_win(win, saved.wins[win] or saved.global)
	end
end

-- Rewrite the clipboard register with unix line breaks, so the plain "+p can
-- do the actual put (keeps count, visual-mode replace, register type, ...).
local function normalise_clipboard()
	local info = vim.fn.getreginfo("+")
	local contents = info.regcontents
	if not contents or #contents == 0 then return end
	local lines = {}
	local changed = false
	for _, line in ipairs(contents) do
		if line:find("\r") then changed = true end
		-- CRLF arrives as a trailing \r on each register line, a lone CR (old
		-- mac) as an embedded one that still has to become a line break.
		line = line:gsub("\r$", ""):gsub("\r\n?", "\n")
		for _, part in ipairs(vim.split(line, "\n", { plain = true })) do
			lines[#lines + 1] = part
		end
	end
	if changed then
		vim.fn.setreg("+", lines, info.regtype or "v")
	end
end

local function map(lhs, rhs, desc)
	vim.keymap.set({ "n", "x" }, lhs, rhs, { expr = type(rhs) == "function", desc = desc })
end

local function paste(key)
	return function()
		normalise_clipboard()
		return '"+' .. key
	end
end

function M.start()
	if active then return end
	active = true

	save_windows()
	saved.mouse = vim.o.mouse
	saved.diagnostics = vim.diagnostic.is_enabled()

	apply_windows()
	vim.o.mouse = ""
	if saved.diagnostics then vim.diagnostic.enable(false) end

	map("y", '"+y', "Copy mode : Yank to clipboard")
	map("Y", '"+y$', "Copy mode : Yank to end of line to clipboard")
	map("p", paste("p"), "Copy mode : Paste clipboard (unix line breaks)")
	map("P", paste("P"), "Copy mode : Paste clipboard before (unix line breaks)")
	vim.keymap.set("n", "<Esc>", M.stop, { desc = "Copy mode : Leave" })

	vim.cmd("redrawstatus")
	vim.notify("-- COPY --")
end

function M.stop()
	if not active then return end
	active = false

	for _, lhs in ipairs({ "y", "Y", "p", "P" }) do
		pcall(vim.keymap.del, { "n", "x" }, lhs)
	end
	pcall(vim.keymap.del, "n", "<Esc>")

	restore_windows()
	vim.o.mouse = saved.mouse
	if saved.diagnostics then vim.diagnostic.enable(true) end

	vim.cmd("redrawstatus")
	vim.notify("")
end

function M.toggle()
	if active then M.stop() else M.start() end
end

function M.setup()
	-- windows opened while the mode is on must not get their numbers back
	vim.api.nvim_create_autocmd({ "WinNew", "BufWinEnter" }, {
		group = vim.api.nvim_create_augroup("CopyMode", { clear = true }),
		callback = function()
			if active then apply_windows() end
		end,
	})
end

return M
