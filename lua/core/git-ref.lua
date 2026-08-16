-- Optional review base for the "what changed" views.
--
-- With $NVIM_GIT_REF_BASE set to a branch or a commit, behaviour.git-signs and
-- actions.git_status show the changes towards that ref instead of the changes
-- towards the index / HEAD:
--
--   NVIM_GIT_REF_BASE=origin/main nvim src/foo.c
--
-- Unset (or an unresolvable ref) keeps the default behaviour.

local M = {}

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
