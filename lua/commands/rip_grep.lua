-- Command built on the list overlay: search file contents with ripgrep, live.
-- The overlay's filter box IS the rg query -- every keystroke re-runs ripgrep
-- and the list shows the matches. <CR> jumps to file:line:col, <Esc> closes.
-- Same overlay as find_files / git_status.

local overlay = require("commands.gui.list_simple_overlay")

local M = {}

-- "file:line:col:text" (rg --vimgrep) -> its pieces
local function parse(line)
	local file, lnum, col, text = line:match("^(.-):(%d+):(%d+):(.*)$")
	return file, tonumber(lnum), tonumber(col), text
end

function M.open()
	if vim.fn.executable("rg") == 0 then
		vim.notify("ripgrep (rg) not found", vim.log.levels.WARN)
		return
	end

	overlay.open({
		title = "Rip grep",
		on_query = function(query) -- typed in the filter box; run on every keystroke
			return vim.fn.systemlist({
				"rg", "--vimgrep", "--smart-case", "--hidden", "--glob", "!.git", "-e", query,
			})
		end,
		display = function(line) -- list rows drop the file name: "line: matched text"
			local _, lnum, _, text = parse(line)
			if not lnum then return line end
			return string.format("%4d  %s", lnum, (text or ""):gsub("^%s+", ""))
		end,
		preview = function(line)
			local file, lnum = parse(line)
			if not file or vim.fn.filereadable(file) == 0 then
				return { "-- not readable --" }
			end
			-- title = file name; center the matched line (read past it for context)
			local title = vim.fn.fnamemodify(file, ":~:.")
			return vim.fn.readfile(file, "", (lnum or 1) + 200),
				vim.filetype.match({ filename = file }), title, lnum
		end,
		on_select = function(line)
			local file, lnum, col = parse(line)
			if not file then return end
			vim.cmd("edit " .. vim.fn.fnameescape(file))
			pcall(vim.api.nvim_win_set_cursor, 0, { lnum or 1, (col or 1) - 1 })
		end,
	})
end

return M
