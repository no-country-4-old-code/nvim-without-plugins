-- Search settings for the search actions (find_files, rip_grep), read from
-- ~/.nvim-config.lua (see core.config):
--
--   search.root            pin searches to this folder instead of the cwd
--   search.ignore_folders  folder names to skip
--
-- Both are only honoured when nvim's cwd lies inside search.root -- an nvim
-- started outside that tree is a different project and keeps the plain
-- "search the cwd, hide nothing" default.

local config = require("core.config")

local M = {}

-- trailing slashes off, symlinks/.. resolved, so the prefix test below compares
-- two paths of the same shape
local function normalize(path)
	local full = vim.fn.fnamemodify(vim.fn.expand(path), ":p")
	return (full:gsub("/+$", ""))
end

-- cwd is search.root itself or below it?
local function cwd_inside(root)
	local cwd = normalize(vim.fn.getcwd())
	return cwd == root or cwd:sub(1, #root + 1) == root .. "/"
end

--- Search root: search.root when set, non-empty and containing the cwd, else
--- nil -> the caller searches the cwd (the path nvim was started in).
--- @return string|nil
function M.root()
	local dir = config.get().search.root
	if not dir or dir == "" then
		return nil
	end
	dir = normalize(dir)
	if not cwd_inside(dir) then
		return nil
	end
	return dir
end

--- Folder names from search.ignore_folders, empty while the cwd is outside
--- search.root (or no root is pinned at all).
--- @return string[]
function M.ignored_folders()
	if not M.root() then
		return {}
	end
	return config.get().search.ignore_folders
end

--- The ignored folders as rg arguments: `--glob !name` skips a directory of
--- that name anywhere in the tree, contents included (gitignore semantics).
--- @return string[]
function M.rg_globs()
	local args = {}
	for _, name in ipairs(M.ignored_folders()) do
		table.insert(args, "--glob")
		table.insert(args, "!" .. name)
	end
	return args
end

--- Does `path` run through one of the ignored folders? For the git/find
--- fallbacks, which have no rg-style glob handling.
--- @return boolean
function M.is_ignored(path)
	for _, name in ipairs(M.ignored_folders()) do
		if ("/" .. path .. "/"):find("/" .. vim.pesc(name) .. "/") then
			return true
		end
	end
	return false
end

--- Drop the rows below an ignored folder.
--- @return string[]
function M.filter(paths)
	if #M.ignored_folders() == 0 then
		return paths
	end
	return vim.tbl_filter(function(p)
		return not M.is_ignored(p)
	end, paths)
end

return M
