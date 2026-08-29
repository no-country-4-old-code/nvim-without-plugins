-- Command built on the list overlay: search file contents with ripgrep, live.
-- The overlay's filter box IS the rg query -- every keystroke re-runs ripgrep
-- and the list shows the matches. <CR> jumps to file:line:col, <Esc> closes.
-- Same overlay as find_files / git_status.

local overlay = require("actions.gui.list_simple_overlay")
local search_env = require("actions.search_env")

local M = {}

local MAX_RESULTS = 1000 -- cap rows in the list; rg can match far more than is useful

local MIN_CHARS = 3 -- shorter query: don't search at all
local RUSH_CHARS = 6 -- from this length on: search immediately, the query is specific
local PAUSE_MS = 250 -- short query: only search after this long without new input

-- Debounce: a short query matches half the tree, so rg blocks nvim long enough
-- that typing freezes. Wait for a typing pause before starting it.
--
-- `runs` counts calls: every call takes a ticket, then waits -- if a later call
-- took a ticket meanwhile (re-entry through the event loop) this one is stale
-- and gives up. The wait also peeks at the input queue (getchar(1), which does
-- not consume), because a blocking wait is exactly when keystrokes pile up
-- there unprocessed: they are the "new input" we want to abort for.
--
-- Returns true when nothing happened for PAUSE_MS, i.e. rg may run.
local runs = 0
local function typing_paused()
	runs = runs + 1
	local mine = runs
	local interrupted = vim.wait(PAUSE_MS, function()
		return runs ~= mine or vim.fn.getchar(1) ~= 0
	end, 20)
	return not interrupted
end

-- "file:line:col:text" (rg --vimgrep) -> its pieces
local function parse(line)
	local file, lnum, col, text = line:match("^(.-):(%d+):(%d+):(.*)$")
	return file, tonumber(lnum), tonumber(col), text
end

--- @param query string|nil prefill the filter box
--- @param dir string|nil search below this folder instead of $NVIM_SEARCH_ROOT / the cwd
function M.open(query, dir)
	if vim.fn.executable("rg") == 0 then
		vim.notify("ripgrep (rg) not found", vim.log.levels.WARN)
		return
	end

	dir = dir or search_env.root()
	local last = {} -- results of the last rg run; shown while the query is still growing

	overlay.open({
		title = dir and ("Rip grep  " .. vim.fn.fnamemodify(dir, ":~")) or "Rip grep",
		query = query, -- optional: prefill the filter box (e.g. word under cursor)
		on_query = function(query) -- typed in the filter box; run on every keystroke
			-- don't run for small input
			if #query < MIN_CHARS then
				last = {}
				return last
			end

			-- short query: only run it once the typing stopped
			if #query < RUSH_CHARS and not typing_paused() then
				return last -- keep the list as is until the next keystroke lands
			end

            -- build command
			local cmd = {
				"rg", "--vimgrep", "--smart-case", "--hidden", "--glob", "!.git",
			}
			-- $NVIM_SEARCH_IGNORE_FOLDER: `--glob !name` skips those folders
			vim.list_extend(cmd, search_env.rg_globs())
			vim.list_extend(cmd, { "-e", query })
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
			last = results
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
