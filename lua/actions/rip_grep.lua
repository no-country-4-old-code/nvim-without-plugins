-- Command built on the list overlay: search file contents with ripgrep, live.
-- The overlay's filter box IS the rg query -- every keystroke re-runs ripgrep
-- and the list shows the matches. <CR> jumps to file:line:col, <Esc> closes.
-- Same overlay as find_files / git_status.

local overlay = require("actions.gui.list_simple_overlay")

local M = {}

local MAX_RESULTS = 1000 -- cap rows in the list; rg can match far more than is useful

-- Search root: $NVIM_ROOT when set and non-empty, else nil -> rg searches the cwd
-- (the path nvim was started in), i.e. the unchanged default behaviour.
local function root()
	local dir = vim.env.NVIM_ROOT
	if dir and dir ~= "" then
		return vim.fn.expand(dir)
	end
end

-- "file:line:col:text" (rg --vimgrep) -> its pieces
local function parse(line)
	local file, lnum, col, text = line:match("^(.-):(%d+):(%d+):(.*)$")
	return file, tonumber(lnum), tonumber(col), text
end

function M.open(query)
	if vim.fn.executable("rg") == 0 then
		vim.notify("ripgrep (rg) not found", vim.log.levels.WARN)
		return
	end

	local dir = root()

	overlay.open({
		title = dir and ("Rip grep  " .. vim.fn.fnamemodify(dir, ":~")) or "Rip grep",
		query = query, -- optional: prefill the filter box (e.g. word under cursor)
		on_query = function(query) -- typed in the filter box; run on every keystroke
			-- don't run for small input
			if #query < 3 then
				return {}
			end

            -- build command
			local cmd = {
				"rg", "--vimgrep", "--smart-case", "--hidden", "--glob", "!.git", "-e", query,
			}
			if dir then
				-- adding "dir" to end of command to search there instead of cwd
				table.insert(cmd, dir)
			end

			-- run
			local results = vim.fn.systemlist(cmd)

			-- trim results to prevent nvim from collapse
			if #results > MAX_RESULTS then -- keep the list snappy; show only the first N
				results = vim.list_slice(results, 1, MAX_RESULTS)
			end
			return results
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
