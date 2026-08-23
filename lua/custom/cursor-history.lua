-- CTRL-O / CTRL-I as a history of the places you *stayed at*, not vim's jumplist.
--
-- Vim only records real "jumps" and forgets where you worked; here the history
-- is one list plus a "current point" (the entry you are standing on). Entries
-- are added when
--   * the cursor sits on the same line for 3 seconds (a 0.5s timer checks), or
--   * a jump happens (vim's jumplist grew: /, G, gd, :grep, a picker, ...) --
--     then both the position you left and the one you landed on are pushed.
-- A position is never added while the current point is already within 5 lines
-- of it, so idling after a CTRL-O writes nothing and CTRL-I still works.
-- Anything else (a jump / a settled line farther away) rewrites the history
-- from the current point on: the forward entries are dropped.
--
-- At startup the list is seeded from vim's jumplist (restored from shada), so
-- a fresh session already knows the places of the previous one.
--
-- Positions of loaded buffers are stored as extmarks and follow the text; the
-- seeded ones stay plain file:line until they are visited.

local M = {}

local MAX = 100 -- entries kept
local NEAR = 5 -- lines: this close counts as the same place
local DWELL = 3000 -- ms on one line before it is remembered
local TICK = 500 -- ms between checks

local ns = vim.api.nvim_create_namespace("cursor-history")

local hist, idx = {}, 0 -- oldest -> newest, idx = where we currently are
local dwell = {} -- line the cursor is sitting on right now
local jump_mark = { n = 0, file = "", lnum = 0 } -- last seen end of vim's jumplist
local timer

-- entry -> line, col (nil if its buffer / extmark is gone)
local function entry_pos(entry)
	if not entry then return nil end
	if entry.id then
		if not vim.api.nvim_buf_is_valid(entry.buf) then return nil end
		local ok, m = pcall(vim.api.nvim_buf_get_extmark_by_id, entry.buf, ns, entry.id, {})
		if not ok or not m[1] then return nil end
		return m[1] + 1, m[2]
	end
	return entry.lnum, entry.col
end

local function entry_file(entry)
	if entry.id then
		if not vim.api.nvim_buf_is_valid(entry.buf) then return nil end
		return vim.api.nvim_buf_get_name(entry.buf)
	end
	return entry.file
end

local function drop(entry)
	if entry and entry.id and vim.api.nvim_buf_is_valid(entry.buf) then
		pcall(vim.api.nvim_buf_del_extmark, entry.buf, ns, entry.id)
	end
end

local function near(entry, file, lnum)
	if not entry then return false end
	local l = entry_pos(entry)
	return l ~= nil and entry_file(entry) == file and math.abs(l - lnum) <= NEAR
end

-- real files only (no netrw, quickfix, picker overlays, ...)
local function recordable(buf)
	return vim.bo[buf].buftype == "" and vim.bo[buf].buflisted and vim.api.nvim_buf_get_name(buf) ~= ""
end

local function here()
	local buf = vim.api.nvim_get_current_buf()
	local cur = vim.api.nvim_win_get_cursor(0)
	return buf, cur[1], cur[2], vim.api.nvim_buf_get_name(buf)
end

-- forget entries whose buffer was unloaded / wiped, keeping idx on its entry
local function prune()
	for i = #hist, 1, -1 do
		if not entry_pos(hist[i]) then
			table.remove(hist, i)
			if i <= idx then idx = idx - 1 end
		end
	end
	if idx < 1 and #hist > 0 then idx = 1 end
	if idx > #hist then idx = #hist end
end

local function make_entry(buf, lnum, col, file)
	if buf and vim.api.nvim_buf_is_loaded(buf) then
		local ok, id = pcall(vim.api.nvim_buf_set_extmark, buf, ns, lnum - 1, col, {})
		if ok then return { buf = buf, id = id } end
	end
	return { file = file, lnum = lnum, col = col }
end

-- remember a position: everything after the current point is history no more
local function record(buf, lnum, col, file)
	for i = #hist, idx + 1, -1 do
		drop(hist[i])
		hist[i] = nil
	end
	hist[#hist + 1] = make_entry(buf, lnum, col, file)
	while #hist > MAX do
		drop(hist[1])
		table.remove(hist, 1)
		idx = idx - 1
	end
	idx = #hist
end

-- the cursor is where it should be: do not record this spot again
local function anchor(file, lnum, col, done)
	dwell = { file = file, lnum = lnum, col = col, at = vim.uv.now(), done = done }
end

local function goto_entry(entry)
	local lnum, col = entry_pos(entry)
	if not lnum then return end
	if entry.id then
		if entry.buf ~= vim.api.nvim_get_current_buf()
			and not pcall(vim.api.nvim_set_current_buf, entry.buf) then
			return
		end
	elseif vim.api.nvim_buf_get_name(0) ~= entry.file then
		if vim.fn.filereadable(entry.file) == 0 then return end
		vim.cmd("edit " .. vim.fn.fnameescape(entry.file))
		-- the file is loaded now: keep the position as an extmark from here on
		local buf = vim.api.nvim_get_current_buf()
		local ok, id = pcall(vim.api.nvim_buf_set_extmark, buf, ns, lnum - 1, col, {})
		if ok then
			entry.buf, entry.id = buf, id
		end
	end
	pcall(vim.api.nvim_win_set_cursor, 0, { lnum, col })
	vim.cmd("normal! zv") -- open folds around the target
	local _, l, c, file = here()
	jump_mark = M._jumplist_state() -- our own move is not a jump
	anchor(file, l, c, true)
end

-- end of vim's jumplist, i.e. the position of the most recent jump
function M._jumplist_state()
	local list = vim.fn.getjumplist()[1]
	local last = list[#list]
	if not last then return { n = 0, file = "", lnum = 0 } end
	local buf = last.bufnr
	local file = (buf and vim.api.nvim_buf_is_valid(buf)) and vim.api.nvim_buf_get_name(buf) or ""
	return { n = #list, file = file, lnum = last.lnum, col = last.col or 0, buf = buf }
end

-- a jump happened: push where we came from and where we are now
local function on_jump(from)
	if from.buf and vim.api.nvim_buf_is_valid(from.buf) and recordable(from.buf)
		and from.file ~= "" and not near(hist[idx], from.file, from.lnum) then
		record(from.buf, from.lnum, from.col, from.file)
	end
	local buf, lnum, col, file = here()
	if recordable(buf) and not near(hist[idx], file, lnum) then
		record(buf, lnum, col, file)
	end
	anchor(file, lnum, col, true)
end

local function tick()
	local buf, lnum, col, file = here()

	local state = M._jumplist_state()
	local jumped = state.n ~= jump_mark.n or state.file ~= jump_mark.file or state.lnum ~= jump_mark.lnum
	jump_mark = state
	if jumped then
		on_jump(state)
		return
	end

	if not recordable(buf) then
		dwell = {}
		return
	end
	if file ~= dwell.file or lnum ~= dwell.lnum then
		anchor(file, lnum, col, false) -- moved: start counting again
		return
	end
	if dwell.done or vim.uv.now() - dwell.at < DWELL then return end
	dwell.done = true
	if not near(hist[idx], file, lnum) then record(buf, lnum, col, file) end
end

function M.back()
	prune()
	local buf, lnum, col, file = here()
	-- standing somewhere the history does not know: keep it, so CTRL-I returns
	if recordable(buf) and not near(hist[idx], file, lnum) then record(buf, lnum, col, file) end
	if idx < 2 then return end
	idx = idx - 1
	goto_entry(hist[idx])
end

function M.forward()
	prune()
	if idx >= #hist then return end
	idx = idx + 1
	goto_entry(hist[idx])
end

-- start from vim's jumplist (shada restored it from the previous session)
local function seed()
	for _, j in ipairs(vim.fn.getjumplist()[1]) do
		local name = j.bufnr and vim.fn.bufname(j.bufnr) or ""
		local file = name ~= "" and vim.fn.fnamemodify(name, ":p") or ""
		if file ~= "" and vim.fn.filereadable(file) == 1 and not near(hist[#hist], file, j.lnum) then
			hist[#hist + 1] = { file = file, lnum = j.lnum, col = j.col or 0 }
		end
	end
	idx = #hist
	jump_mark = M._jumplist_state()
	local _, lnum, col, file = here()
	anchor(file, lnum, col, true)
end

function M.setup()
	vim.api.nvim_create_autocmd("VimEnter", {
		group = vim.api.nvim_create_augroup("cursor-history", { clear = true }),
		once = true,
		callback = seed,
	})

	if timer then timer:stop() end
	timer = vim.uv.new_timer()
	timer:start(TICK, TICK, vim.schedule_wrap(function()
		pcall(tick)
	end))
end

return M
