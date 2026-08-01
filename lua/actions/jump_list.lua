-- Command built on the list overlay: browse the jump history, newest first,
-- with a live code preview of the highlighted entry. <CR> jumps to file:line:col,
-- <Esc> closes. Same overlay as find_files / rip_grep / git_status.

local overlay = require("actions.gui.list_simple_overlay")

local M = {}

-- "file:line:col" -> its pieces
local function parse(line)
	local file, lnum, col = line:match("^(.-):(%d+):(%d+)$")
	return file, tonumber(lnum), tonumber(col)
end

function M.open()
	local jumps = vim.fn.getjumplist()[1]
	local items = {}
	for i = #jumps, 1, -1 do -- newest jump first
		local j = jumps[i]
		local name = j.bufnr and vim.fn.bufname(j.bufnr) or ""
		if name ~= "" then
			items[#items + 1] = string.format("%s:%d:%d",
				vim.fn.fnamemodify(name, ":~:."), j.lnum, (j.col or 0) + 1)
		end
	end

	overlay.open({
		title = "Jumplist",
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
