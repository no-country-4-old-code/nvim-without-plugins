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
local NS = vim.api.nvim_create_namespace("ListOverlayPreview") -- marks the focus line

--- Open the overlay.
--- @param opts table {
---   title         = string,                       -- shown on the filter box
---   items         = string[] | fun():string[],    -- rows to pick from (static)
---   on_query      = fun(query):string[],          -- optional: replaces the built-in
---                                                  --   fuzzy filter with a live source,
---                                                  --   re-run on every keystroke (e.g. rg)
---   display       = fun(item):string              -- optional: how the item is shown
---                                                  --   in the list (defaults to the item
---                                                  --   itself); preview/on_select still get
---                                                  --   the raw item
---   preview       = fun(item):string[],string?,string?,integer?
---                                                  -- optional: lines[, filetype[, window
---                                                  --   title[, line to center on]]]
---   on_select     = fun(item)                      -- optional: <CR> action
---   start_on_list = boolean,                       -- default false; true starts
---                                                  --   focus on the list, not the filter
---   query         = string,                        -- optional: prefill the filter box
---                                                  --   (and run the initial filter)
--- }
function M.open(opts)
	opts = opts or {}
	local items = type(opts.items) == "function" and opts.items() or opts.items or {}
	if not opts.on_query and #items == 0 then
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
	-- highlight for the matched line in the preview (theme-aware)
	vim.api.nvim_set_hl(0, "ListOverlayMatch", { link = "Visual", default = true })

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
	vim.wo[lwin].wrap = false -- keep every list entry on a single line

	local filtered = items

	-- refresh helpers -----------------------------------------------------
	local function update_preview()
		local item = filtered[1]
		if vim.api.nvim_win_is_valid(lwin) then
			item = filtered[vim.api.nvim_win_get_cursor(lwin)[1]]
		end
		local lines, ft, title, focus = {}, nil, nil, nil
		if item and opts.preview then
			lines, ft, title, focus = opts.preview(item)
		end
		vim.bo[pbuf].modifiable = true
		vim.api.nvim_buf_set_lines(pbuf, 0, -1, false, lines or {})
		vim.bo[pbuf].modifiable = false
		vim.bo[pbuf].filetype = ft or "" -- triggers FileType -> treesitter (init.lua)
		if not vim.api.nvim_win_is_valid(pwin) then return end
		vim.api.nvim_win_set_config(pwin, {
			title = " " .. (title or "preview") .. " ", title_pos = "center",
		})
		vim.api.nvim_buf_clear_namespace(pbuf, NS, 0, -1)
		if focus then -- put the interesting line in the middle and mark it
			local n = vim.api.nvim_buf_line_count(pbuf)
			local ln = math.min(math.max(focus, 1), n)
			vim.api.nvim_win_set_cursor(pwin, { ln, 0 })
			vim.api.nvim_win_call(pwin, function() vim.cmd("normal! zz") end)
			vim.api.nvim_buf_set_extmark(pbuf, NS, ln - 1, 0, {
				line_hl_group = "ListOverlayMatch",
			})
		end
	end

	local function render_list()
		vim.bo[lbuf].modifiable = true
		local rows = opts.display and vim.tbl_map(opts.display, filtered) or filtered
		vim.api.nvim_buf_set_lines(lbuf, 0, -1, false, rows)
		vim.bo[lbuf].modifiable = false
		if #filtered > 0 then
			vim.api.nvim_win_set_cursor(lwin, { 1, 0 })
		end
		update_preview()
	end

	local function refilter()
		local query = vim.api.nvim_buf_get_lines(fbuf, 0, 1, false)[1] or ""
		if opts.on_query then -- live source (e.g. rg): query drives the results
			filtered = query == "" and {} or (opts.on_query(query) or {})
		else -- static list: fuzzy-narrow it locally
			filtered = query == "" and items or vim.fn.matchfuzzy(items, query)
		end
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
	local function choose(item)
		close()
		if item and opts.on_select then opts.on_select(item) end
	end
	-- <CR> from the list picks the highlighted row; from the filter, the first match
	local function select_highlighted() choose(filtered[vim.api.nvim_win_get_cursor(lwin)[1]]) end
	local function select_first() choose(filtered[1]) end
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
	map(fbuf, { "i", "n" }, "<CR>", select_first)
	map(lbuf, "n", "<Tab>", focus_filter)
	map(lbuf, "n", "<Esc>", close)
	map(lbuf, "n", "<CR>", select_highlighted)
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

	if opts.query and opts.query ~= "" then
		vim.api.nvim_buf_set_lines(fbuf, 0, 1, false, { opts.query })
		refilter() -- run the initial filter with the prefilled query
	else
		render_list()
	end
	if opts.start_on_list then focus_list() else focus_filter() end
end

return M
