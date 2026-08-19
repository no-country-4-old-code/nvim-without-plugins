-- Reusable sidebar widget (plugin-free): a nested, foldable list in a vertical
-- split beside the editor -- the netrw/nvim-tree shape, but generic. Knows
-- nothing about files: callers hand over a root node, a children() function and
-- a label(), the widget draws the tree and reports the picked node back.
--
-- Keys (defined here, inherited by every command):
--   j / k    move in the list (native motion)
--   l        parent node : fold / unfold it
--            leaf node   : on_open in the window next to the sidebar,
--                          focus stays in the list
--   h        unfolded parent : fold it
--            anything else   : jump to the parent node and fold it
--            top level, nothing to fold : on_collapse_root
--   <CR>     parent node : same as l
--            leaf node   : same as l, but jump to that window and close the list
--   <Esc>    close the sidebar
--
-- The tree is rebuilt from children() on every fold/unfold, so it never shows a
-- stale view of its source. The sidebar is narrow, so instead of truncating deep
-- rows the view scrolls sideways -- but only when the cursor walks into a folder
-- that does not read, or back out to one that does not (see fit_view).

local M = {}

local NS = vim.api.nvim_create_namespace("nested_sidebar")
local INDENT = 2 -- columns per level -- also the sideways shift per level
-- blank columns left of the rows -- drawn by 'statuscolumn', so the sideways
-- scrolling never eats them. the top is padded with an empty winbar line, which
-- costs no buffer line and leaves the row math alone.
local PAD = 1

--- Open the sidebar.
--- @param opts table {
---   root      = any,                        -- top node, handed back untouched;
---                                            --   it has no row of its own, the
---                                            --   list starts at its children
---   children  = fun(node):any[],            -- child nodes of a parent node
---   is_parent = fun(node):boolean,          -- optional: can node be unfolded
---                                            --   (default: nothing is a parent)
---   label     = fun(node):string,           -- optional: row text without the
---                                            --   indent (default tostring)
---   highlight = fun(node):string|nil,       -- optional: highlight group the row
---                                            --   is painted in (default: none)
---   key       = fun(node):string,           -- optional: stable id used to
---                                            --   remember the fold state
---                                            --   (default tostring -- only fine
---                                            --   when children() returns the
---                                            --   very same nodes every time)
---   on_activate = fun(node):boolean,        -- optional: first say on l / <CR>;
---                                            --   return true to keep the widget
---                                            --   from folding / opening the node
---   on_collapse_root = fun(),               -- optional: h on a top-level row with
---                                            --   nothing left to fold
---   on_open   = fun(node, win),             -- optional: l on a leaf; win is the
---                                            --   window next to the sidebar
---   on_select = fun(node, win),             -- optional: <CR> on a leaf
---                                            --   (default: on_open)
---   reveal    = string[],                    -- optional: keys from the root down
---                                            --   to a node -- everything above it
---                                            --   starts unfolded and the cursor
---                                            --   opens on it (still folded)
---   width     = integer,                    -- default 30 (room for the rows --
---                                            --   the padding comes on top)
---   side      = "left" | "right",           -- default "left"
---   filetype  = string,                     -- default "nestedsidebar"; a second
---                                            --   open replaces the first one
--- }
function M.open(opts)
	opts = opts or {}
	local children = opts.children or function() return {} end
	local is_parent = opts.is_parent or function() return false end
	local label = opts.label or tostring
	local highlight = opts.highlight or function() return nil end
	local key = opts.key or tostring
	local width = opts.width or 30
	local left = opts.side ~= "right"
	local filetype = opts.filetype or "nestedsidebar"

	-- only one sidebar of a kind: a second open replaces the first
	for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		if vim.bo[vim.api.nvim_win_get_buf(w)].filetype == filetype then
			vim.api.nvim_win_close(w, true)
		end
	end

	-- the window the sidebar was opened from == the one to open files in
	local target = vim.api.nvim_get_current_win()

	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].filetype = filetype
	vim.cmd(left and "topleft vsplit" or "botright vsplit")
	local win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(win, buf)
	vim.api.nvim_win_set_width(win, width + PAD)
	vim.wo[win].winfixwidth = true
	vim.wo[win].statuscolumn = string.rep(" ", PAD) -- padding left
	vim.wo[win].winbar = " " -- padding top: one empty line above the list
	vim.wo[win].winhighlight = "WinBar:Normal,WinBarNC:Normal"
	vim.wo[win].number = false
	vim.wo[win].relativenumber = false
	vim.wo[win].signcolumn = "no"
	vim.wo[win].cursorline = true
	vim.wo[win].wrap = false
	vim.wo[win].sidescrolloff = 0 -- so a shifted row ends flush with the window

	-- tree state ----------------------------------------------------------
	local expanded = {} -- the root has no row, its children are the top level
	local rows = {} -- flat view of the tree: { node = ..., depth = ... }

	-- the sidebar is narrow, so a deep path runs out of the window. the view
	-- scrolls sideways, but it sticks: it only moves when the cursor needs it to.
	--   going in   -- some row of the folder the cursor sits in is cut off on the
	--                 right : scroll left (indent steps) until it reads, never
	--                 further than one column short of the folder's own indent,
	--                 so no name is ever cut on the left
	--   going out  -- the third folder up the tree is cut off on the left :
	--                 scroll back until it reads with one indent of air in front
	-- Everything in between leaves the view where it is. The cursor has to sit on
	-- the first shown column -- setting leftcol alone is undone at the next
	-- redraw, which keeps the cursor visible.
	local shift, was_deep = 0, 0

	-- width of the widest row of the folder around line (its rows at that depth)
	local function folder_width(line, depth)
		local widest = 0
		local function scan(from, to, step)
			for i = from, to, step do
				if rows[i].depth < depth then return end
				if rows[i].depth == depth then
					local w = INDENT * depth + vim.fn.strdisplaywidth(label(rows[i].node))
					widest = math.max(widest, w)
				end
			end
		end
		scan(line, 1, -1)
		scan(line + 1, #rows, 1)
		return widest
	end

	local function fit_view()
		if not vim.api.nvim_win_is_valid(win) then return end
		local line = vim.api.nvim_win_get_cursor(win)[1]
		local row = rows[line]
		if not row then return end
		local depth = row.depth
		local width = vim.api.nvim_win_get_width(win) - PAD

		if depth < was_deep then -- left the folder: give the third parent back
			shift = math.min(shift, math.max((depth - 4) * INDENT, 0))
		else -- entered a folder: only scroll if it does not read as it is
			local missing = folder_width(line, depth) - width
			local wanted = math.ceil(missing / INDENT) * INDENT
			shift = math.min(math.max(shift, wanted), math.max(depth * INDENT - 1, 0))
		end
		was_deep = depth

		local text = vim.api.nvim_buf_get_lines(buf, line - 1, line, false)[1] or ""
		local col = math.min(shift, math.max(#text - 1, 0))
		vim.api.nvim_win_set_cursor(win, { line, col })
		vim.api.nvim_win_call(win, function() vim.fn.winrestview({ leftcol = col }) end)
	end

	local function render()
		rows = {}
		local function add(node, depth)
			rows[#rows + 1] = { node = node, depth = depth }
			if is_parent(node) and expanded[key(node)] then
				for _, child in ipairs(children(node) or {}) do
					add(child, depth + 1)
				end
			end
		end
		for _, child in ipairs(children(opts.root) or {}) do
			add(child, 0)
		end

		-- no fold markers: what a row is shows in its highlight, whether it is
		-- unfolded shows in the rows below it
		local lines = {}
		for i, row in ipairs(rows) do
			lines[i] = string.rep(" ", INDENT * row.depth) .. label(row.node)
		end
		local line = vim.api.nvim_win_get_cursor(win)[1]
		vim.bo[buf].modifiable = true
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
		vim.bo[buf].modifiable = false
		vim.api.nvim_buf_clear_namespace(buf, NS, 0, -1)
		for i, row in ipairs(rows) do
			local group = highlight(row.node)
			if group then
				vim.api.nvim_buf_set_extmark(buf, NS, i - 1, 0, {
					end_col = #lines[i],
					hl_group = group,
				})
			end
		end
		vim.api.nvim_win_set_cursor(win, { math.min(line, #lines), 0 })
		fit_view()
	end

	-- actions --------------------------------------------------------------
	local function close()
		if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
	end

	-- the window files are opened in: the one the sidebar was opened from, else
	-- any other normal window, else a fresh split next to the sidebar
	local function open_win()
		if target ~= win and vim.api.nvim_win_is_valid(target) then return target end
		for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
			if w ~= win and vim.api.nvim_win_get_config(w).relative == "" then
				target = w
				return w
			end
		end
		vim.api.nvim_win_call(win, function()
			vim.cmd(left and "rightbelow vsplit" or "leftabove vsplit")
			target = vim.api.nvim_get_current_win()
		end)
		vim.api.nvim_win_set_width(win, width + PAD)
		return target
	end

	-- l / <CR>: unfold parents, hand leaves over to the caller. focus keeps the
	-- list unless jump is set (<CR>), which also closes the sidebar.
	local function activate(jump)
		local row = rows[vim.api.nvim_win_get_cursor(win)[1]]
		if not row then return end
		if opts.on_activate and opts.on_activate(row.node) then return end
		if is_parent(row.node) then
			local k = key(row.node)
			expanded[k] = not expanded[k] or nil
			render()
			return
		end
		local action = jump and (opts.on_select or opts.on_open) or opts.on_open
		if not action then return end
		local w = open_win()
		action(row.node, w)
		if jump then
			close()
			if vim.api.nvim_win_is_valid(w) then vim.api.nvim_set_current_win(w) end
		end
	end

	-- h: one level out. on an unfolded parent that is the node itself, anywhere
	-- else the cursor jumps to the parent row and folds it away. at the top level
	-- there is nothing left to fold -- the caller decides what "out" means there.
	local function collapse()
		local line = vim.api.nvim_win_get_cursor(win)[1]
		local row = rows[line]
		if not row then return end
		if is_parent(row.node) and expanded[key(row.node)] then
			expanded[key(row.node)] = nil
			render()
			return
		end
		for i = line - 1, 1, -1 do
			if rows[i].depth < row.depth then
				expanded[key(rows[i].node)] = nil
				vim.api.nvim_win_set_cursor(win, { i, 0 })
				render()
				return
			end
		end
		if opts.on_collapse_root then opts.on_collapse_root() end
	end

	-- keymaps ---------------------------------------------------------------
	local function map(lhs, fn)
		vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true })
	end
	vim.api.nvim_create_autocmd("CursorMoved", { buffer = buf, callback = fit_view })

	map("<Esc>", close)
	map("l", function() activate(false) end)
	map("h", collapse)
	map("<CR>", function() activate(true) end)

	-- reveal: unfold everything above the last key, park the cursor on that key.
	-- the revealed node itself stays folded -- walking out of a folder lands on
	-- it closed, walking in is what unfolds it
	local reveal = opts.reveal or {}
	local wanted = reveal[#reveal]
	for i = 1, #reveal - 1 do
		expanded[reveal[i]] = true
	end

	render()

	if wanted then
		for i, row in ipairs(rows) do
			if key(row.node) == wanted then
				vim.api.nvim_win_set_cursor(win, { i, 0 })
				fit_view()
				break
			end
		end
	end
end

return M
