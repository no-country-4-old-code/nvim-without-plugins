-- <leader>n / <leader>b as a history of the places you *worked at*, not vim's jumplist.
--
-- One list plus a "current point" (the entry you are standing on). An entry is
-- added on
--   * every jump (vim's jumplist of the window grew: /, G, gd, :grep, a
--     picker, ...) -- both the position you left and the one you landed on,
--   * entering / leaving insert mode,
--   * entering / leaving visual mode,
--   * a yank and a paste.
-- A position on the line of the current point is not added again. Adding an
-- entry drops everything after the current point (like vim's jumplist).
--
-- Every tab has its own history. A new tab starts with a copy of the history of
-- the tab it was opened from and grows independently from there.
--
-- At startup the first tab's list is seeded from vim's jumplist (restored from
-- shada), so a fresh session already knows the places of the previous one.
--
-- Positions of loaded buffers are stored as extmarks and follow the text; the
-- seeded ones stay plain file:line until they are visited.

local M = {}

local MAX = 100 -- entries kept per tab
local NEAR = 5 -- lines: the list overlay shows positions this close once

local ns = vim.api.nvim_create_namespace("cursor-history")

local tabs = {} -- tabpage -> { hist = oldest -> newest, idx = where we currently are }
local parent -- tab left last: a new tab copies its history
local jump_marks = {} -- window -> last seen end of its jumplist

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

local function make_entry(buf, lnum, col, file)
	if buf and vim.api.nvim_buf_is_loaded(buf) then
		local ok, id = pcall(vim.api.nvim_buf_set_extmark, buf, ns, lnum - 1, col, {})
		if ok then return { buf = buf, id = id } end
	end
	return { file = file, lnum = lnum, col = col }
end

-- history of the current tab; a new tab starts as a copy of its parent's
local function state()
	local tab = vim.api.nvim_get_current_tabpage()
	if tabs[tab] then return tabs[tab] end
	local s = { hist = {}, idx = 0 }
	local from = parent and tabs[parent]
	if from then
		for _, entry in ipairs(from.hist) do
			local lnum, col = entry_pos(entry)
			local file = lnum and entry_file(entry)
			if file then -- own extmarks: the tabs drop their entries independently
				s.hist[#s.hist + 1] = make_entry(entry.id and entry.buf, lnum, col, file)
			end
			if entry == from.hist[from.idx] then s.idx = #s.hist end
		end
	end
	tabs[tab] = s
	return s
end

-- real files only (no netrw, quickfix, picker overlays, ...)
local function recordable(buf)
	return vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buftype == "" and vim.bo[buf].buflisted
		and vim.api.nvim_buf_get_name(buf) ~= ""
end

local function here()
	local buf = vim.api.nvim_get_current_buf()
	local cur = vim.api.nvim_win_get_cursor(0)
	return buf, cur[1], cur[2], vim.api.nvim_buf_get_name(buf)
end

-- forget entries whose buffer was unloaded / wiped, keeping idx on its entry
local function prune(s)
	for i = #s.hist, 1, -1 do
		if not entry_pos(s.hist[i]) then
			table.remove(s.hist, i)
			if i <= s.idx then s.idx = s.idx - 1 end
		end
	end
	s.idx = math.max(math.min(s.idx, #s.hist), #s.hist > 0 and 1 or 0)
end

-- remember a position; everything after the current point leaves the history
local function record(buf, lnum, col, file)
	if not recordable(buf) then return end
	local s = state()
	local cur = s.hist[s.idx]
	if cur and entry_file(cur) == file and entry_pos(cur) == lnum then return end
	for i = #s.hist, s.idx + 1, -1 do
		drop(s.hist[i])
		s.hist[i] = nil
	end
	s.hist[#s.hist + 1] = make_entry(buf, lnum, col, file)
	while #s.hist > MAX do
		drop(table.remove(s.hist, 1))
	end
	s.idx = #s.hist
end

local function record_here()
	record(here())
end

-- end of the current window's jumplist, i.e. the position of the most recent jump
local function jumplist_state()
	local list = vim.fn.getjumplist()[1]
	local last = list[#list]
	if not last then return { n = 0, lnum = 0 } end
	return { n = #list, buf = last.bufnr, lnum = last.lnum, col = last.col or 0 }
end

-- the current window's jumplist as it is now is known: no jump to report
local function sync_jumps()
	jump_marks[vim.api.nvim_get_current_win()] = jumplist_state()
end

-- CursorMoved: did the window's jumplist grow? Then push where we came from
-- and where we are now.
local function check_jump()
	local win = vim.api.nvim_get_current_win()
	local old, now = jump_marks[win], jumplist_state()
	jump_marks[win] = now
	if not old or (now.n == old.n and now.buf == old.buf and now.lnum == old.lnum) then return end
	if now.buf and vim.api.nvim_buf_is_valid(now.buf) then
		record(now.buf, now.lnum, now.col, vim.api.nvim_buf_get_name(now.buf))
	end
	record_here()
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
	sync_jumps() -- our own move is not a jump
end

-- the places of the current tab, newest first. Positions within NEAR lines of
-- an already listed one are left out, the newest of them wins. Columns are
-- 0-based, as everywhere.
function M.entries()
	local s = state()
	prune(s)
	local out = {}
	for i = #s.hist, 1, -1 do
		local lnum, col = entry_pos(s.hist[i])
		local file = lnum and entry_file(s.hist[i]) or nil
		if file and file ~= "" then
			local known = false
			for _, o in ipairs(out) do
				if o.file == file and math.abs(o.lnum - lnum) <= NEAR then
					known = true
					break
				end
			end
			if not known then out[#out + 1] = { file = file, lnum = lnum, col = col } end
		end
	end
	return out
end

function M.back()
	local s = state()
	prune(s)
	-- standing somewhere the history does not know: keep it, so forward returns
	record_here()
	if s.idx < 2 then return end
	s.idx = s.idx - 1
	goto_entry(s.hist[s.idx])
end

function M.forward()
	local s = state()
	prune(s)
	if s.idx >= #s.hist then return end
	s.idx = s.idx + 1
	goto_entry(s.hist[s.idx])
end

-- start from vim's jumplist (shada restored it from the previous session)
local function seed()
	local s = state()
	for _, j in ipairs(vim.fn.getjumplist()[1]) do
		local name = j.bufnr and vim.fn.bufname(j.bufnr) or ""
		local file = name ~= "" and vim.fn.fnamemodify(name, ":p") or ""
		local last = s.hist[#s.hist]
		if file ~= "" and vim.fn.filereadable(file) == 1
			and not (last and last.file == file and last.lnum == j.lnum) then
			s.hist[#s.hist + 1] = { file = file, lnum = j.lnum, col = j.col or 0 }
		end
	end
	s.idx = #s.hist
	sync_jumps()
end

local function is_visual(mode)
	return mode:match("^[vV\22]") ~= nil
end

function M.setup()
	local group = vim.api.nvim_create_augroup("cursor-history", { clear = true })
	local function on(event, callback, opts)
		vim.api.nvim_create_autocmd(event, vim.tbl_extend("force",
			{ group = group, callback = function() pcall(callback) end }, opts or {}))
	end

	on("VimEnter", seed, { once = true })
	on("CursorMoved", check_jump)
	on({ "InsertEnter", "InsertLeave" }, record_here)
	on("ModeChanged", function()
		local old, new = vim.v.event.old_mode, vim.v.event.new_mode
		if is_visual(old) ~= is_visual(new) then record_here() end
	end)
	on("TextYankPost", function()
		if vim.v.event.operator == "y" then record_here() end
	end)
	on("TabLeave", function() parent = vim.api.nvim_get_current_tabpage() end)
	on("TabClosed", function()
		for tab, s in pairs(tabs) do
			if not vim.api.nvim_tabpage_is_valid(tab) then
				for _, entry in ipairs(s.hist) do drop(entry) end
				tabs[tab] = nil
			end
		end
	end)
	on("WinClosed", function(args) jump_marks[tonumber(args.match)] = nil end)

	-- paste has no autocmd: watch for p / P (also gp, "xp, copy mode's "+p, ...)
	-- typed in normal / visual mode and record where the paste landed
	vim.on_key(function(key)
		if (key == "p" or key == "P") and (vim.fn.mode() == "n" or is_visual(vim.fn.mode())) then
			vim.schedule(function() pcall(record_here) end)
		end
	end, ns)
end

return M
