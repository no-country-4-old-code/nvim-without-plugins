-- Example command built on the list overlay: fuzzy-find a project file, with a
-- live preview of the highlighted file. <CR> opens it, <Esc> closes.
-- The same overlay is meant to back "rg files", "git status", etc.

local overlay = require("actions.gui.list_simple_overlay")
local search_env = require("actions.search_env")

local M = {}

-- project files below `dir`, nil = the cwd (rg -> git -> find fallback).
-- rg/find echo the root back into every path they print, so the rows stay
-- openable from the cwd; git ls-files prints repo-relative paths, prefix them.
-- $NVIM_SEARCH_IGNORE_FOLDER drops folders: rg knows the globs itself, the two
-- fallbacks get filtered afterwards.
local function list_files(dir)
	if vim.fn.executable("rg") == 1 then
		local cmd = { "rg", "--files", "--hidden", "--glob", "!.git" }
		vim.list_extend(cmd, search_env.rg_globs())
		if dir then
			table.insert(cmd, dir)
		end
		return vim.fn.systemlist(cmd)
	elseif vim.fn.isdirectory((dir or ".") .. "/.git") == 1 then
		local files = vim.fn.systemlist({ "git", "-C", dir or ".", "ls-files" })
		if dir then
			for i, f in ipairs(files) do
				files[i] = dir .. "/" .. f
			end
		end
		return search_env.filter(files)
	end
	return search_env.filter(
		vim.fn.systemlist({ "find", dir or ".", "-type", "f", "-not", "-path", "*/.git/*" })
	)
end

function M.open()
	local dir = search_env.root()

	overlay.open({
		title = dir and ("Find files  " .. vim.fn.fnamemodify(dir, ":~")) or "Find files",
		items = function()
			return list_files(dir)
		end,
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
