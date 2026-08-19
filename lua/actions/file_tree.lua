-- Command built on the nested sidebar: a file tree of the project.
-- Root is the folder of the current file -- no project root, no cwd rule; only
-- a buffer without a name falls back to the cwd. It opens with the current file
-- revealed: the cursor sits on it. l unfolds a folder / opens a file in the
-- window to the right without leaving the tree, h folds the folder above,
-- <CR> opens it and jumps there, <Esc> closes.
--
-- The path of the current file -- the file itself and every folder above it --
-- is painted brighter than the rest, so the tree always shows where you are.
--
-- h on a top-level row has nothing left to fold: it re-opens the tree one
-- directory further up, cursor on the folder just left, so the sidebar can walk
-- out of the project. The marked path grows with it.

local sidebar = require("actions.gui.list_nested_sidebar")

local M = {}

local IGNORE = { [".git"] = true }

-- node = { path = absolute path, name = shown name, dir = boolean }
local function node(path, name)
	return { path = path, name = name, dir = vim.fn.isdirectory(path) == 1 }
end

-- the folder the tree starts in: the one holding file (":p:h" leaves a folder
-- itself alone), the cwd when no file is open
local function root_dir(file)
	if not file or file == "" then return vim.fn.getcwd() end
	return vim.fn.fnamemodify(file, ":p:h")
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

-- file  = the current file: it and every folder above it are marked
-- focus = the row the cursor opens on (the file, or the folder h walked out of)
local function open_at(dir, file, focus)
	-- tokyonight magenta, set off against the blue of every other folder
	vim.api.nvim_set_hl(0, "FileTreePath", { fg = "#bb9af7", bold = true })

	local marked = {}
	for _, path in ipairs(chain(dir, file) or {}) do
		marked[path] = true
	end

	sidebar.open({
		reveal = chain(dir, focus),
		filetype = "filetree",
		root = node(dir, dir),
		key = function(n) return n.path end,
		label = function(n) return n.name end,
		highlight = function(n)
			if marked[n.path] then return "FileTreePath" end
			return n.dir and "Directory" or nil
		end,
		is_parent = function(n) return n.dir end,
		children = function(n) return entries(n.path) end,
		on_collapse_root = function() -- h at the top level: re-root one up
			local parent = vim.fn.fnamemodify(dir, ":h")
			if parent == dir then return end -- already at "/"
			vim.schedule(function() open_at(parent, file, dir) end)
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
	open_at(root_dir(file), file, file)
end

return M
