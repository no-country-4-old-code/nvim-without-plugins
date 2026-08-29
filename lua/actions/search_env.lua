-- $NVIM_SEARCH_* environment for the search actions (find_files, rip_grep).
--
--   NVIM_SEARCH_ROOT           pin searches to this folder instead of the cwd
--   NVIM_SEARCH_IGNORE_FOLDER  folder names to skip, separated by , : or space
--
-- Both are only honoured when nvim's cwd lies inside $NVIM_SEARCH_ROOT -- an
-- nvim started outside that tree is a different project and keeps the plain
-- "search the cwd, hide nothing" default.

local M = {}

-- trailing slashes off, symlinks/.. resolved, so the prefix test below compares
-- two paths of the same shape
local function normalize(path)
	local full = vim.fn.fnamemodify(vim.fn.expand(path), ":p")
	return (full:gsub("/+$", ""))
end

-- cwd is $NVIM_SEARCH_ROOT itself or below it?
local function cwd_inside(root)
	local cwd = normalize(vim.fn.getcwd())
	return cwd == root or cwd:sub(1, #root + 1) == root .. "/"
end

--- Search root: $NVIM_SEARCH_ROOT when set, non-empty and containing the cwd,
--- else nil -> the caller searches the cwd (the path nvim was started in).
--- @return string|nil
function M.root()
	local dir = vim.env.NVIM_SEARCH_ROOT
	if not dir or dir == "" then
		return nil
	end
	dir = normalize(dir)
	if not cwd_inside(dir) then
		return nil
	end
	return dir
end

--- Folder names from $NVIM_SEARCH_IGNORE_FOLDER, empty while the cwd is outside
--- $NVIM_SEARCH_ROOT (or no root is pinned at all).
--- @return string[]
function M.ignored_folders()
	if not M.root() then
		return {}
	end
	local folders = {}
	for name in (vim.env.NVIM_SEARCH_IGNORE_FOLDER or ""):gmatch("[^,:%s]+") do
		table.insert(folders, (name:gsub("/+$", "")))
	end
	return folders
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
