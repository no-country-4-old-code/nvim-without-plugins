-- Git context for the "what changed" views: which repo they look at, and
-- against which base.
--
-- The repo is always the one the *current file* lives in (M.root), not the one
-- the process was started in -- opening a file from another checkout shows that
-- checkout's changes.
--
-- The base is the commit the current branch started from: the merge-base of
-- HEAD and the repo's default branch (origin/HEAD, else main / master).
-- Without a default branch the views compare against the index / HEAD.

local M = {}

--- directory the git commands should run in: the folder of the current
--- buffer's file, the browsed directory in netrw, else the cwd
local function context_dir()
	-- netrw names its listing buffer after the cwd, not after the tree it
	-- shows -- b:netrw_curdir is the directory actually being browsed
	if vim.b.netrw_curdir and vim.b.netrw_curdir ~= "" then return vim.b.netrw_curdir end

	local name = vim.api.nvim_buf_get_name(0)
	if name ~= "" and vim.bo.buftype == "" then
		name = vim.fn.fnamemodify(name, ":p")
		return vim.fn.isdirectory(name) == 1 and name or vim.fs.dirname(name)
	end
	return vim.fn.getcwd()
end

--- top level of the repo the current file belongs to, nil outside a repo
function M.root()
	local out = vim.fn.systemlist({ "git", "-C", context_dir(), "rev-parse", "--show-toplevel" })
	if vim.v.shell_error ~= 0 then return nil end
	return out[1]
end

local DEFAULT_BRANCHES = { "origin/HEAD", "origin/main", "origin/master", "main", "master" }

--- the commit the current branch started from, nil when no default branch
--- shares history with HEAD in `cwd`
--- @return string|nil commit hash, string|nil the default branch it was found on
function M.get(cwd)
	cwd = cwd or vim.fn.getcwd()
	for _, branch in ipairs(DEFAULT_BRANCHES) do
		local out = vim.fn.systemlist({ "git", "-C", cwd, "merge-base", branch, "HEAD" })
		if vim.v.shell_error == 0 and out[1] then return out[1], branch end
	end
	return nil
end

return M
