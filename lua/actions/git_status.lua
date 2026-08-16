-- Command built on the list overlay: browse the working-tree status, with a
-- live diff preview of the highlighted file. <CR> opens the file, <Esc> closes.
-- Same overlay as find_files / rg files.

local overlay = require("actions.gui.list_simple_overlay")

local M = {}

local function git_root()
	local out = vim.fn.systemlist({ "git", "rev-parse", "--show-toplevel" })
	if vim.v.shell_error ~= 0 then return nil end
	return out[1]
end

-- "XY path" (or "XY old -> new" for renames) -> the path git points at
local function status_path(line)
	return line:sub(4):gsub("^.* %-> ", "")
end

-- changes towards $NVIM_GIT_REF_BASE, rendered like `git status --porcelain`
-- ("M  path"), with the untracked files appended as git would list them
local function status_vs(root, base)
	local lines = {}
	for _, line in ipairs(vim.fn.systemlist({ "git", "-C", root, "diff", "--name-status", base })) do
		local code, paths = line:match("^(%a)%S*\t(.*)$")
		if code then -- renames/copies list old and new path: keep the new one
			lines[#lines + 1] = string.format("%-2s %s", code, paths:match("([^\t]*)$"))
		end
	end
	for _, path in ipairs(vim.fn.systemlist({ "git", "-C", root, "ls-files", "--others", "--exclude-standard" })) do
		lines[#lines + 1] = "?? " .. path
	end
	return lines
end

function M.open()
	local root = git_root()
	if not root then
		vim.notify("Not a git repo", vim.log.levels.WARN)
		return
	end
	local base = require("core.git-ref").get(root)

	overlay.open({
		title = base and ("Git status vs " .. base) or "Git status",
		start_on_list = true, -- focus starts on the list, not the filter box
	 	items = function()
			if base then return status_vs(root, base) end
			return vim.fn.systemlist({ "git", "-C", root, "status", "--porcelain" })
		end,
		preview = function(line)
			local path = status_path(line)
			if line:sub(1, 2):match("%?") then -- untracked: no base version, show the file
				return vim.fn.readfile(root .. "/" .. path, "", 500),
					vim.filetype.match({ filename = path })
			end
			return vim.fn.systemlist({ "git", "-C", root, "diff", base or "HEAD", "--", path }), "diff"
		end,
		on_select = function(line)
			vim.cmd("edit " .. vim.fn.fnameescape(root .. "/" .. status_path(line)))
		end,
	})
end

return M
