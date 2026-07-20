-- Example command built on the list overlay: fuzzy-find a project file, with a
-- live preview of the highlighted file. <CR> opens it, <Esc> closes.
-- The same overlay is meant to back "rg files", "git status", etc.

local overlay = require("commands.gui.list_simple_overlay")

local M = {}

-- project files relative to the cwd (rg -> git -> find fallback, as in key-mappings)
local function list_files()
	if vim.fn.executable("rg") == 1 then
		return vim.fn.systemlist({ "rg", "--files", "--hidden", "--glob", "!.git" })
	elseif vim.fn.isdirectory(".git") == 1 then
		return vim.fn.systemlist({ "git", "ls-files" })
	end
	return vim.fn.systemlist({ "find", ".", "-type", "f", "-not", "-path", "*/.git/*" })
end

function M.open()
	overlay.open({
		title = "Find files",
		items = list_files,
		preview = function(path)
			if vim.fn.filereadable(path) == 0 then
				return { "-- not readable --" }
			end
			-- cap at 500 lines; filetype so the preview gets treesitter highlighting
			return vim.fn.readfile(path, "", 500), vim.filetype.match({ filename = path })
		end,
		on_select = function(path)
			vim.cmd("edit " .. vim.fn.fnameescape(path))
		end,
	})
end

return M
