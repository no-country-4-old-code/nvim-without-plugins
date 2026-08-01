-- Command built on the nested sidebar: a file tree of the project.
-- Root is $NVIM_ROOT when set and non-empty, else the cwd (same rule as
-- actions.rip_grep). l unfolds a folder / opens a file in the window to the
-- right without leaving the tree, <CR> opens it and jumps there, <Esc> closes.

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

function M.open()
	local dir = root_dir()

	sidebar.open({
		title = "Files",
		filetype = "filetree",
		root = node(dir, vim.fn.fnamemodify(dir, ":~")),
		key = function(n) return n.path end,
		label = function(n) return n.name end,
		is_parent = function(n) return n.dir end,
		children = function(n) return entries(n.path) end,
		on_open = function(n, win) -- open in the window next to the tree
			vim.api.nvim_win_call(win, function()
				vim.cmd("edit " .. vim.fn.fnameescape(n.path))
			end)
		end,
	})
end

return M
