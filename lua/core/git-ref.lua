-- Git context for the "what changed" views: which repo they look at, and
-- against which base.
--
-- The repo is always the one the *current file* lives in (M.root), not the one
-- the process was started in -- opening a file from another checkout shows that
-- checkout's changes.
--
-- With $NVIM_GIT_REF_BASE set to a branch or a commit, behaviour.git-signs and
-- actions.git_status show the changes towards that ref instead of the changes
-- towards the index / HEAD:
--
--   NVIM_GIT_REF_BASE=origin/main nvim src/foo.c
--
-- Unset (or an unresolvable ref) keeps the default behaviour.

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

local resolvable = {} -- cwd .. "\0" .. ref -> boolean
local warned = {}     -- ref -> already complained about

--- the configured base ref, or nil when unset / not resolvable in `cwd`
--- (one `git rev-parse` per directory, cached -- callers may run in a loop)
function M.get(cwd)
	local ref = vim.env.NVIM_GIT_REF_BASE
	if not ref or ref == "" then return nil end

	cwd = cwd or vim.fn.getcwd()
	local key = cwd .. "\0" .. ref
	if resolvable[key] == nil then
		vim.fn.system({ "git", "-C", cwd, "rev-parse", "--verify", "--quiet", ref .. "^{commit}" })
		resolvable[key] = vim.v.shell_error == 0
		if not resolvable[key] and not warned[ref] then
			warned[ref] = true
			vim.notify(
				string.format("NVIM_GIT_REF_BASE: unknown ref '%s' -- comparing against the index instead", ref),
				vim.log.levels.WARN
			)
		end
	end
	return resolvable[key] and ref or nil
end

return M
