-- Example command built on the list overlay: fuzzy-find a project file, with a
-- live preview of the highlighted file. <CR> opens it, <Esc> closes.
-- The same overlay is meant to back "rg files", "git status", etc.

local overlay = require("actions.gui.list_simple_overlay")

local M = {}

-- Search root: $NVIM_ROOT when set and non-empty, else nil -> search the cwd
-- (the path nvim was started in), i.e. the unchanged default behaviour.
local function root()
	local dir = vim.env.NVIM_ROOT
	if dir and dir ~= "" then
		return vim.fn.expand(dir)
	end
end

-- project files below `dir`, nil = the cwd (rg -> git -> find fallback).
-- rg/find echo the root back into every path they print, so the rows stay
-- openable from the cwd; git ls-files prints repo-relative paths, prefix them.
local function list_files(dir)
	if vim.fn.executable("rg") == 1 then
		local cmd = { "rg", "--files", "--hidden", "--glob", "!.git" }
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
		return files
	end
	return vim.fn.systemlist({ "find", dir or ".", "-type", "f", "-not", "-path", "*/.git/*" })
end

function M.open()
	local dir = root()

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
