-- Git change markers in the sign column (replaces gitsigns.nvim).
--
-- Compares the buffer against its version in the git index -- or in
-- $NVIM_GIT_REF_BASE when that names a branch / commit (see core.git-ref) -- and marks
--   "+"  lines that were added      (green)
--   "~"  lines that were modified   (green)
--   "_"  lines were deleted here    (red, on the line above the gap -- the
--        deleted text itself is gone, so there is no own line to mark)
-- The sign column is only turned on for buffers that actually have changes --
-- unmodified files keep the gutter (and therefore the line numbers) exactly
-- where they were.

local M = {}

local ns = vim.api.nvim_create_namespace("git-signs")

local SIGN_ADD = "+"
local SIGN_CHANGE = "~"
local SIGN_DELETE = "_"
local DEBOUNCE_MS = 200

local timers = {} -- buf -> uv timer

local function set_highlights()
	-- tokyonight greens
	vim.api.nvim_set_hl(0, "GitSignAdd", { fg = "#9ece6a" })
	vim.api.nvim_set_hl(0, "GitSignChange", { fg = "#73daca" })
	vim.api.nvim_set_hl(0, "GitSignDelete", { fg = "#914c54" })
end

-- signcolumn is window-local: set it per window *for this buffer only*
-- (vim.wo[win][0]), so other buffers in the same window are unaffected.
local function show_signcolumn(buf, on)
	vim.b[buf].git_signs_on = on
	for _, win in ipairs(vim.fn.win_findbuf(buf)) do
		vim.wo[win][0].signcolumn = on and "yes:1" or "no"
	end
end

local function clear(buf)
	vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
	show_signcolumn(buf, false)
end

local function tracked(buf)
	return vim.api.nvim_buf_is_valid(buf)
		and vim.bo[buf].buftype == ""
		and vim.api.nvim_buf_get_name(buf) ~= ""
end

--- place the signs for the hunks between the index version and the buffer
local function apply(buf, index_text)
	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	local buf_text = table.concat(lines, "\n") .. "\n"
	local ok, hunks = pcall(vim.diff, index_text, buf_text, {
		result_type = "indices",
		algorithm = "histogram",
	})
	if not ok or not hunks then return clear(buf) end

	-- collect first, place once: every line gets at most one sign
	local marks = {}
	local function sign(row, text, hl)
		marks[math.max(0, math.min(row, #lines - 1))] = { text, hl }
	end

	for _, hunk in ipairs(hunks) do
		local old_count, start, count = hunk[2], hunk[3], hunk[4]
		if count == 0 then
			-- pure deletion: `start` is the buffer line the removed text
			-- followed (0 if it was removed at the top of the file)
			sign(start - 1, SIGN_DELETE, "GitSignDelete")
		else
			local added = old_count == 0
			for lnum = start, start + count - 1 do
				sign(lnum - 1, added and SIGN_ADD or SIGN_CHANGE,
					added and "GitSignAdd" or "GitSignChange")
			end
			-- hunk replaced more lines than it produced: last line is a
			-- change *and* a deletion -> keep "~", but in the delete color
			if old_count > count then
				sign(start + count - 1, SIGN_CHANGE, "GitSignDelete")
			end
		end
	end

	vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
	local any = false
	for row, mark in pairs(marks) do
		pcall(vim.api.nvim_buf_set_extmark, buf, ns, row, 0, {
			sign_text = mark[1],
			sign_hl_group = mark[2],
		})
		any = true
	end
	show_signcolumn(buf, any)
end

--- read the file's base version (async, so typing never blocks) and diff it
local function update(buf)
	if not tracked(buf) then return end
	local file = vim.api.nvim_buf_get_name(buf)
	local dir, name = vim.fs.dirname(file), vim.fs.basename(file)
	local base = require("core.git-ref").get(dir) or "" -- "" -> the index
	local ok = pcall(vim.system, { "git", "--no-optional-locks", "show", base .. ":./" .. name }, {
		cwd = dir,
		text = true,
	}, vim.schedule_wrap(function(res)
		if not vim.api.nvim_buf_is_valid(buf) then return end
		-- no repo / file not in the base version (untracked, new file): no signs
		if res.code ~= 0 then return clear(buf) end
		apply(buf, res.stdout)
	end))
	if not ok then clear(buf) end
end

--- first line (0-based) of every block of consecutive signs
local function hunk_starts(buf)
	local starts, prev = {}, nil
	for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {})) do
		local row = mark[2]
		if not prev or row > prev + 1 then starts[#starts + 1] = row end
		prev = row
	end
	return starts
end

--- jump to the start of the next (dir > 0) / previous changed block, wrapping
--- around at the end of the file
function M.goto_hunk(dir)
	local buf = vim.api.nvim_get_current_buf()
	local starts = hunk_starts(buf)
	if #starts == 0 then
		return vim.notify("No changes in this file", vim.log.levels.INFO)
	end

	local cur = vim.api.nvim_win_get_cursor(0)[1] - 1
	local target
	if dir > 0 then
		for _, row in ipairs(starts) do
			if row > cur then
				target = row
				break
			end
		end
		target = target or starts[1]
	else
		for i = #starts, 1, -1 do
			if starts[i] < cur then
				target = starts[i]
				break
			end
		end
		target = target or starts[#starts]
	end

	vim.cmd("normal! m'") -- leave a jumplist entry, so '' gets back
	vim.api.nvim_win_set_cursor(0, { target + 1, 0 })
end

local function schedule_update(buf)
	local timer = timers[buf]
	if not timer then
		timer = vim.uv.new_timer()
		timers[buf] = timer
	end
	timer:stop()
	timer:start(DEBOUNCE_MS, 0, vim.schedule_wrap(function() update(buf) end))
end

function M.setup()
	-- gutter off by default -- only changed buffers get the extra column
	vim.o.signcolumn = "no"

	set_highlights()
	vim.api.nvim_create_autocmd("ColorScheme", { callback = set_highlights })

	vim.api.nvim_create_autocmd({ "BufReadPost", "BufWritePost", "TextChanged", "InsertLeave" }, {
		callback = function(args) schedule_update(args.buf) end,
	})

	-- buffer shown in another window: restore its gutter state there
	vim.api.nvim_create_autocmd("BufWinEnter", {
		callback = function(args)
			if vim.b[args.buf].git_signs_on ~= nil then
				show_signcolumn(args.buf, vim.b[args.buf].git_signs_on)
			end
			schedule_update(args.buf)
		end,
	})

	-- external changes (checkout, commit, ...)
	vim.api.nvim_create_autocmd("FocusGained", {
		callback = function() schedule_update(vim.api.nvim_get_current_buf()) end,
	})

	vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
		callback = function(args)
			local timer = timers[args.buf]
			if timer then
				timer:stop()
				timer:close()
				timers[args.buf] = nil
			end
		end,
	})
end

return M
