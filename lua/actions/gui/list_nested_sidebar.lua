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
--   <CR>     parent node : same as l
--            leaf node   : same as l, but jump to that window and close the list
--   <Esc>    close the sidebar
--
-- The tree is rebuilt from children() on every fold/unfold, so it never shows a
-- stale view of its source.

local M = {}

local MARKER = { open = "▾ ", closed = "▸ ", leaf = "  " }

--- Open the sidebar.
--- @param opts table {
---   title     = string,                     -- shown on the window bar
---   root      = any,                        -- top node, handed back untouched
---   children  = fun(node):any[],            -- child nodes of a parent node
---   is_parent = fun(node):boolean,          -- optional: can node be unfolded
---                                            --   (default: nothing is a parent)
---   label     = fun(node):string,           -- optional: row text without indent
---                                            --   and fold marker (default tostring)
---   key       = fun(node):string,           -- optional: stable id used to
---                                            --   remember the fold state
---                                            --   (default tostring -- only fine
---                                            --   when children() returns the
---                                            --   very same nodes every time)
---   on_open   = fun(node, win),             -- optional: l on a leaf; win is the
---                                            --   window next to the sidebar
---   on_select = fun(node, win),             -- optional: <CR> on a leaf
---                                            --   (default: on_open)
---   width     = integer,                    -- default 30
---   side      = "left" | "right",           -- default "left"
---   filetype  = string,                     -- default "nestedsidebar"; a second
---                                            --   open replaces the first one
--- }
function M.open(opts)
	opts = opts or {}
	local children = opts.children or function() return {} end
	local is_parent = opts.is_parent or function() return false end
	local label = opts.label or tostring
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
	vim.api.nvim_win_set_width(win, width)
	vim.wo[win].winfixwidth = true
	vim.wo[win].number = false
	vim.wo[win].relativenumber = false
	vim.wo[win].signcolumn = "no"
	vim.wo[win].cursorline = true
	vim.wo[win].wrap = false
	if opts.title then -- splits have no border title: use the winbar instead
		vim.wo[win].winbar = "%=" .. opts.title:gsub("%%", "%%%%") .. "%="
	end

	-- tree state ----------------------------------------------------------
	local expanded = { [key(opts.root)] = true } -- root starts unfolded
	local rows = {} -- flat view of the tree: { node = ..., depth = ... }

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
		add(opts.root, 0)

		local lines = {}
		for i, row in ipairs(rows) do
			local marker = MARKER.leaf
			if is_parent(row.node) then
				marker = expanded[key(row.node)] and MARKER.open or MARKER.closed
			end
			lines[i] = string.rep("  ", row.depth) .. marker .. label(row.node)
		end
		local line = vim.api.nvim_win_get_cursor(win)[1]
		vim.bo[buf].modifiable = true
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
		vim.bo[buf].modifiable = false
		vim.api.nvim_win_set_cursor(win, { math.min(line, #lines), 0 })
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
		vim.api.nvim_win_set_width(win, width)
		return target
	end

	-- l / <CR>: unfold parents, hand leaves over to the caller. focus keeps the
	-- list unless jump is set (<CR>), which also closes the sidebar.
	local function activate(jump)
		local row = rows[vim.api.nvim_win_get_cursor(win)[1]]
		if not row then return end
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

	-- keymaps ---------------------------------------------------------------
	local function map(lhs, fn)
		vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true })
	end
	map("<Esc>", close)
	map("l", function() activate(false) end)
	map("<CR>", function() activate(true) end)

	render()
end

return M
