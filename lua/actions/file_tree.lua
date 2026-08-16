-- Command built on the nested sidebar: a file tree of the project.
-- Root is $NVIM_ROOT when set and non-empty, else the cwd (same rule as
-- actions.rip_grep). It opens with the current file revealed: every folder on
-- its path unfolded and the cursor on it. l unfolds a folder / opens a file in
-- the window to the right without leaving the tree, h folds the folder above,
-- <CR> opens it and jumps there, <Esc> closes.
--
-- The top row is ".." -- the tree root. l / <CR> on it re-opens the tree one
-- directory further up, so the sidebar can walk out of the project.

local sidebar = require("actions.gui.list_nested_sidebar")

local M = {}

local IGNORE = { [".git"] = true }

-- node = { path = absolute path, name = shown name, dir = boolean }
local function node(path, name)
	return { path = path, name = name, dir = vim.fn.isdirectory(path) == 1 }
end

local function root_dir()
	local dir = vim.env.NVIM_ROOT
	if dir and dir ~= "" then
		return vim.fn.fnamemodify(vim.fn.expand(dir), ":p:h")
	end
	return vim.fn.getcwd()
end

-- folders first, then files, both case-insensitive by name
local function entries(dir)
	local items = {}
	for name in vim.fs.dir(dir) do
		if not IGNORE[name] then
			items[#items + 1] = node(dir .. "/" .. name, name)
		end
	end
	table.sort(items, function(a, b)
		if a.dir ~= b.dir then return a.dir end
		return a.name:lower() < b.name:lower()
	end)
	return items
end

-- node keys from the root down to path (root first), nil when the path does not
-- exist or lives outside the tree -- the sidebar unfolds exactly this chain
local function chain(root, path)
	if not path or path == "" or not vim.uv.fs_stat(path) then return nil end
	path = vim.fn.fnamemodify(path, ":p"):gsub("/+$", "")
	if path == root then return { root } end
	if path:sub(1, #root + 1) ~= root .. "/" then return nil end
	local keys, cur = { root }, root
	for part in path:sub(#root + 2):gmatch("[^/]+") do
		cur = cur .. "/" .. part
		keys[#keys + 1] = cur
	end
	return keys
end

-- focus = path to reveal (the current file, or the folder we just came from)
local function open_at(dir, focus)
	local up = node(dir, "..")
	up.up = true -- l / <CR> on it re-roots the tree instead of folding it

	sidebar.open({
		reveal = chain(dir, focus),
		filetype = "filetree",
		root = up,
		key = function(n) return n.path end,
		label = function(n) return n.name end,
		highlight = function(n) return n.dir and "Directory" or nil end,
		is_parent = function(n) return n.dir end,
		children = function(n) return entries(n.path) end,
		on_activate = function(n)
			if not n.up then return false end
			local parent = vim.fn.fnamemodify(n.path, ":h")
			if parent == n.path then return true end -- already at "/"
			-- keep the file revealed when it is still inside the new root,
			-- otherwise point at the directory we are leaving
			local next_focus = chain(parent, focus) and focus or n.path
			vim.schedule(function() open_at(parent, next_focus) end)
			return true
		end,
		on_open = function(n, win) -- open in the window next to the tree
			vim.api.nvim_win_call(win, function()
				vim.cmd("edit " .. vim.fn.fnameescape(n.path))
			end)
		end,
	})
end

function M.open()
	local file = vim.api.nvim_buf_get_name(0) -- before the split steals focus
	open_at(root_dir(), file)
end

return M
