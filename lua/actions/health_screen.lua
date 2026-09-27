-- Health screen: everything about the state of this nvim in one tab. A menu on
-- the left (nested sidebar, flat), one screen on the right that shows the entry
-- under the cursor:
--
--   LSP status     running clients, root, cmd, attached buffers
--   LSP indexing   $/progress tasks of every server (updates live)
--   LSP errors     error lines of the LSP log
--   LSP log        the log file itself, cursor at the end
--   Health: LSP    :checkhealth vim.lsp
--   Health: all    :checkhealth (slow -- run once, then kept until r)
--
-- Menu:   j / k show the entry, l / <CR> jump into the screen,
--         r refreshes it, q / <Esc> close the tab.
-- Screen: <Esc> back to the menu, q closes the tab.

local sidebar = require("actions.gui.list_nested_sidebar")
local lsp = require("actions.lsp_screen")

local M = {}

-- kind "lines": text from fn(), "file": that file, "health": :checkhealth <arg>
local ENTRIES = {
	{ label = "LSP status", kind = "lines", fn = function(s) return lsp.status_lines(s.from_buf) end },
	{ label = "LSP indexing", kind = "lines", fn = lsp.indexing_lines, live = true },
	{ label = "LSP errors", kind = "lines", fn = lsp.error_lines },
	{ label = "LSP log", kind = "file", path = vim.lsp.get_log_path },
	{ label = "Health: LSP", kind = "health", arg = "vim.lsp" },
	{ label = "Health: all", kind = "health", arg = "" },
}

function M.open()
	-- state of this screen: the buffer it was opened from (for LSP status), the
	-- screen window, its text buffer, cached checkhealth buffers, live timer
	local s = { from_buf = vim.api.nvim_get_current_buf(), health = {} }
	vim.cmd("tabnew")
	s.win = vim.api.nvim_get_current_win()
	s.text = vim.api.nvim_get_current_buf()
	vim.bo[s.text].buftype = "nofile"
	vim.bo[s.text].bufhidden = "hide"
	vim.bo[s.text].swapfile = false

	local function close_tab()
		if not pcall(vim.cmd.tabclose) then vim.cmd("enew") end
	end
	local function stop_timer()
		if s.timer then
			s.timer:stop()
			s.timer:close()
			s.timer = nil
		end
	end

	-- q / <Esc> on whatever buffer the screen shows
	local function screen_keys(buf)
		vim.keymap.set("n", "q", close_tab, { buffer = buf, nowait = true })
		vim.keymap.set("n", "<Esc>", function()
			if s.menu and vim.api.nvim_win_is_valid(s.menu) then vim.api.nvim_set_current_win(s.menu) end
		end, { buffer = buf, nowait = true })
	end
	screen_keys(s.text)

	local function set_text(lines)
		vim.bo[s.text].modifiable = true
		vim.api.nvim_buf_set_lines(s.text, 0, -1, false, lines)
		vim.bo[s.text].modifiable = false
	end

	-- :checkhealth opens its own buffer in a split: take the buffer, drop the split.
	-- it also wipes any buffer named "health://" first -- so each cached report
	-- gets a name of its own, or the next run wipes it out of the screen window
	local function run_health(e)
		vim.api.nvim_win_call(s.win, function()
			vim.cmd("horizontal checkhealth " .. e.arg)
			local buf = vim.api.nvim_get_current_buf()
			vim.api.nvim_buf_set_name(buf, "health://" .. e.label)
			-- the rename leaves an alternate buffer under the old name behind
			pcall(vim.api.nvim_buf_delete, vim.fn.bufnr("^health://$"), { force = true })
			vim.bo[buf].bufhidden = "hide"
			vim.api.nvim_win_close(0, true)
			s.health[e.label] = buf
			screen_keys(buf)
		end)
	end

	local function show(e, refresh)
		if not vim.api.nvim_win_is_valid(s.win) then return end
		stop_timer()
		if e.kind == "lines" then
			set_text(e.fn(s))
			vim.api.nvim_win_set_buf(s.win, s.text)
			if e.live then
				s.timer = vim.uv.new_timer()
				s.timer:start(1000, 1000, vim.schedule_wrap(function()
					if s.timer and vim.api.nvim_buf_is_valid(s.text) then set_text(e.fn(s)) end
				end))
			end
		elseif e.kind == "file" then
			vim.api.nvim_win_call(s.win, function()
				vim.cmd((refresh and "edit! +$ " or "edit +$ ") .. vim.fn.fnameescape(e.path()))
			end)
			screen_keys(vim.api.nvim_win_get_buf(s.win))
		else
			local buf = s.health[e.label]
			if refresh or not (buf and vim.api.nvim_buf_is_valid(buf)) then
				if buf and vim.api.nvim_buf_is_valid(buf) then
					vim.api.nvim_win_set_buf(s.win, s.text) -- deleting a shown buffer closes its window
					vim.api.nvim_buf_delete(buf, { force = true })
				end
				run_health(e)
			end
			vim.api.nvim_win_set_buf(s.win, s.health[e.label])
		end
	end

	local function focus_screen()
		if vim.api.nvim_win_is_valid(s.win) then vim.api.nvim_set_current_win(s.win) end
	end

	sidebar.open({
		filetype = "healthmenu",
		width = 20,
		root = {},
		children = function() return ENTRIES end,
		key = function(e) return e.label end,
		label = function(e) return e.label end,
		on_move = function(e) show(e) end,
		on_open = function(e) show(e) end,
		keys = {
			["<CR>"] = focus_screen,
			["ö"] = focus_screen,
			["l"] = focus_screen,
			["r"] = function(e) show(e, true) end,
			["q"] = close_tab,
			["<Esc>"] = close_tab,
		},
	})
	sidebar.set_title("Health")
	s.menu = vim.api.nvim_get_current_win()

	-- the tab goes away: stop the live timer, drop the screen's buffers
	vim.api.nvim_create_autocmd("BufWipeout", {
		buffer = vim.api.nvim_get_current_buf(), once = true,
		callback = function()
			stop_timer()
			for _, buf in pairs(vim.list_extend({ s.text }, vim.tbl_values(s.health))) do
				if vim.api.nvim_buf_is_valid(buf) then pcall(vim.api.nvim_buf_delete, buf, { force = true }) end
			end
		end,
	})

	show(ENTRIES[1])
end

return M
