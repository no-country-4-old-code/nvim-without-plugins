-- Command built on the list overlay: browse the cursor history, newest first,
-- with a live code preview of the highlighted entry. <CR> jumps to file:line:col,
-- <Esc> closes. Same overlay as find_files / rip_grep / git_status.
--
-- The source is custom.cursor-history (seeded from vim's jumplist at startup),
-- including the places a new branch dropped from CTRL-O / CTRL-I: those are no
-- longer reachable by going back, but they are still places we have been.
-- One entry per place -- positions a few lines apart are listed once.

local overlay = require("actions.gui.list_simple_overlay")

local M = {}

-- "file:line:col" -> its pieces
local function parse(line)
	local file, lnum, col = line:match("^(.-):(%d+):(%d+)$")
	return file, tonumber(lnum), tonumber(col)
end

function M.open()
	local items = {}
	for _, e in ipairs(require("custom.cursor-history").entries()) do -- newest first
		items[#items + 1] = string.format("%s:%d:%d",
			vim.fn.fnamemodify(e.file, ":~:."), e.lnum, (e.col or 0) + 1)
	end

	overlay.open({
		title = "Cursor history",
		start_on_list = true, -- focus starts on the list, not the filter box
		items = items,
		display = function(line) -- list rows drop the col: "file:line"
			local file, lnum = parse(line)
			if not lnum then return line end
			return string.format("%s:%d", file, lnum)
		end,
		preview = function(line)
			local file, lnum = parse(line)
			if not file or vim.fn.filereadable(file) == 0 then
				return { "-- not readable --" }
			end
			-- title = file name; center the jump line (read past it for context)
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
