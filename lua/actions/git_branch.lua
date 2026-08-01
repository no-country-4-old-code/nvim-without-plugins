-- Command built on the list overlay: browse all git branches, with a preview
-- showing which files differ between the highlighted branch and the current one.
-- <CR> checks the branch out, <Esc> closes.
-- Same overlay as find_files / rip_grep / git_status.

local overlay = require("actions.gui.list_simple_overlay")

local M = {}

local function git_root()
	local out = vim.fn.systemlist({ "git", "rev-parse", "--show-toplevel" })
	if vim.v.shell_error ~= 0 then return nil end
	return out[1]
end

-- "  branch", "* branch" or "  remotes/origin/branch" -> the bare branch name
local function branch_name(line)
	return line:gsub("^[%*%+]?%s+", ""):gsub("^remotes/", ""):gsub("%s+%->.*$", "")
end

function M.open()
	local root = git_root()
	if not root then
		vim.notify("Not a git repo", vim.log.levels.WARN)
		return
	end

	overlay.open({
		title = "Git branches",
		start_on_list = true, -- focus starts on the list, not the filter box
		items = function()
			return vim.fn.systemlist({ "git", "-C", root, "branch", "--all", "--format=%(refname:short)" })
		end,
		preview = function(branch)
			branch = branch_name(branch)
			-- files that differ between the picked branch and the working tree's HEAD
			local out = vim.fn.systemlist({ "git", "-C", root, "diff", "--stat", "HEAD..." .. branch })
			if vim.tbl_isempty(out) then
				return { "-- no differences from current branch --" }
			end
			return out
		end,
		on_select = function(branch)
			branch = branch_name(branch)
			local out = vim.fn.systemlist({ "git", "-C", root, "checkout", branch })
			vim.notify(table.concat(out, "\n"),
				vim.v.shell_error == 0 and vim.log.levels.INFO or vim.log.levels.ERROR)
			vim.cmd("checktime")
		end,
	})
end

return M
