-- Reusable overlay widget (plugin-free): a fuzzy filter box, a list, and a
-- preview, shown as three floating windows. Knows nothing about files/git/rg;
-- callers hand over plain strings + a preview/select callback, so the same
-- widget backs "find files", "rg files", "git status", ...
--
-- Keys (defined here, inherited by every command):
--   <Tab>          toggle focus filter <-> list
--   j / k          move in the list (native motion; preview follows the cursor)
--   <Up>/<Down>    scroll the preview window (while focus is on the list)
--   <Left>/<Right> scroll the preview horizontally
--   <CR>           run on_select on the highlighted item, then close
--   <Esc>          close the overlay
--
-- Fuzzy filtering lives here (vim.fn.matchfuzzy), matching core.picker.

local M = {}

local BORDER = { "┏", "━", "┓", "┃", "┛", "━", "┗", "┃" }
local SCROLL = { down = vim.keycode("<C-e>"), up = vim.keycode("<C-y>") }

--- Open the overlay.
--- @param opts table {
---   title         = string,                       -- shown on the filter box
---   items         = string[] | fun():string[],    -- rows to pick from
---   preview       = fun(item):string[],string?    -- optional: lines[, filetype]
---   on_select     = fun(item)                      -- optional: <CR> action
---   start_on_list = boolean,                       -- default false; true starts
---                                                  --   focus on the list, not the filter
--- }
function M.open(opts)
	opts = opts or {}
	local items = type(opts.items) == "function" and opts.items() or opts.items or {}
	if #items == 0 then
		vim.notify("Nothing to show", vim.log.levels.INFO)
		return
	end

	-- geometry: centered 80% box; 1-line filter on top, list + preview below
	local ui_w = math.floor(vim.o.columns * 0.8)
	local ui_h = math.floor(vim.o.lines * 0.8)
	local row = math.floor((vim.o.lines - ui_h) / 2)
	local col = math.floor((vim.o.columns - ui_w) / 2)
	local body_row = row + 3 -- below filter's line + its top/bottom border
	local body_h = ui_h - 4
	local list_w = math.floor(ui_w / 2)
	local prev_w = ui_w - list_w - 3 -- gap for the two borders between panes

	-- tokyonight blue border for every pane of the overlay
	vim.api.nvim_set_hl(0, "ListOverlayBorder", { fg = "#7aa2f7" })

	local function make_buf()
		local b = vim.api.nvim_create_buf(false, true)
		vim.bo[b].bufhidden = "wipe"
		return b
	end
	local fbuf, lbuf, pbuf = make_buf(), make_buf(), make_buf()

	local function float(buf, cfg)
		cfg.relative = "editor"
		cfg.style = "minimal"
		cfg.border = BORDER
		local win = vim.api.nvim_open_win(buf, false, cfg)
		vim.wo[win].winhighlight = "FloatBorder:ListOverlayBorder"
		return win
	end
	local fwin = float(fbuf, {
		row = row, col = col, width = ui_w, height = 1,
		title = " " .. (opts.title or "Filter") .. " ", title_pos = "center",
	})
	local lwin = float(lbuf, {
		row = body_row, col = col, width = list_w, height = body_h,
		title = " list ", title_pos = "center",
	})
	local pwin = float(pbuf, {
		row = body_row, col = col + list_w + 3, width = prev_w, height = body_h,
		title = " preview ", title_pos = "center", focusable = false,
	})
	vim.wo[lwin].cursorline = true
	vim.wo[lwin].scrolloff = 2

	local filtered = items

	-- refresh helpers -----------------------------------------------------
	local function update_preview()
		local item = filtered[1]
		if vim.api.nvim_win_is_valid(lwin) then
			item = filtered[vim.api.nvim_win_get_cursor(lwin)[1]]
		end
		local lines, ft = {}, nil
		if item and opts.preview then
			lines, ft = opts.preview(item)
		end
		vim.bo[pbuf].modifiable = true
		vim.api.nvim_buf_set_lines(pbuf, 0, -1, false, lines or {})
		vim.bo[pbuf].modifiable = false
		vim.bo[pbuf].filetype = ft or "" -- triggers FileType -> treesitter (init.lua)
	end

	local function render_list()
		vim.bo[lbuf].modifiable = true
		vim.api.nvim_buf_set_lines(lbuf, 0, -1, false, filtered)
		vim.bo[lbuf].modifiable = false
		if #filtered > 0 then
			vim.api.nvim_win_set_cursor(lwin, { 1, 0 })
		end
		update_preview()
	end

	local function refilter()
		local query = vim.api.nvim_buf_get_lines(fbuf, 0, 1, false)[1] or ""
		filtered = query == "" and items or vim.fn.matchfuzzy(items, query)
		render_list()
	end

	-- focus + close -------------------------------------------------------
	local closed = false
	local function close()
		if closed then return end
		closed = true
		for _, w in ipairs({ fwin, lwin, pwin }) do
			if vim.api.nvim_win_is_valid(w) then vim.api.nvim_win_close(w, true) end
		end
	end
	local function focus_filter()
		vim.api.nvim_set_current_win(fwin)
		vim.cmd("startinsert!")
	end
	local function focus_list()
		vim.cmd("stopinsert")
		vim.api.nvim_set_current_win(lwin)
	end
	local function select()
		local item = filtered[vim.api.nvim_win_get_cursor(lwin)[1]]
		close()
		if item and opts.on_select then opts.on_select(item) end
	end
	-- run a scroll motion inside the (unfocused) preview window
	local function scroll_preview(keys)
		if not vim.api.nvim_win_is_valid(pwin) then return end
		vim.api.nvim_win_call(pwin, function() vim.cmd("normal! " .. keys) end)
	end

	-- keymaps -------------------------------------------------------------
	local function map(buf, modes, lhs, fn)
		vim.keymap.set(modes, lhs, fn, { buffer = buf, nowait = true })
	end
	map(fbuf, { "i", "n" }, "<Tab>", focus_list)
	map(fbuf, { "i", "n" }, "<Esc>", close)
	map(fbuf, { "i", "n" }, "<CR>", select)
	map(lbuf, "n", "<Tab>", focus_filter)
	map(lbuf, "n", "<Esc>", close)
	map(lbuf, "n", "<CR>", select)
	-- arrow keys scroll the preview while focus stays on the list
	map(lbuf, "n", "<Down>", function() scroll_preview(SCROLL.down) end)
	map(lbuf, "n", "<Up>", function() scroll_preview(SCROLL.up) end)

    -- live refresh --------------------------------------------------------
	vim.api.nvim_create_autocmd({ "TextChangedI", "TextChanged" }, {
		buffer = fbuf, callback = refilter,
	})
	vim.api.nvim_create_autocmd("CursorMoved", {
		buffer = lbuf, callback = update_preview,
	})

	render_list()
	if opts.start_on_list then focus_list() else focus_filter() end
end

return M
