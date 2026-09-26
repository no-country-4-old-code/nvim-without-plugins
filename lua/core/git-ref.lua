-- Git context for the "what changed" views: which repo they look at, and
-- against which base.
--
-- The repo is always the one the *current file* lives in (M.root), not the one
-- the process was started in -- opening a file from another checkout shows that
-- checkout's changes.
--
-- With `git.ref_base` in ~/.nvim-config.lua set to a branch or a commit,
-- behaviour.git-signs and actions.git_status show the changes since the commit
-- the current branch started from (`git merge-base <ref> HEAD`) instead of the
-- changes towards the index / HEAD -- commits that landed on the ref after
-- branching off do not show up as changes:
--
--   return { git = { ref_base = "origin/main" } }
--
-- Unset (or an unresolvable ref / no common history) keeps the default behaviour.

local config = require("core.config")

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

local warned = {} -- ref -> already complained about

--- the commit the current branch started from -- the merge-base of HEAD and
--- the configured base ref -- or nil when unset / not resolvable in `cwd`.
--- Not cached: HEAD and the ref move (commit, checkout, fetch), and callers
--- are debounced, so one `git merge-base` per call is cheap enough.
--- @return string|nil commit hash, string|nil the configured ref
function M.get(cwd)
	local ref = config.get().git.ref_base
	if not ref or ref == "" then return nil end

	cwd = cwd or vim.fn.getcwd()
	local out = vim.fn.systemlist({ "git", "-C", cwd, "merge-base", ref, "HEAD" })
	if vim.v.shell_error ~= 0 or not out[1] then
		if not warned[ref] then
			warned[ref] = true
			vim.notify(
				string.format("git.ref_base: no common commit with '%s' -- comparing against the index instead", ref),
				vim.log.levels.WARN
			)
		end
		return nil
	end
	return out[1], ref
end

return M
