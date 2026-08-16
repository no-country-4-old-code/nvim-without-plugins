-- CTRL-O / CTRL-I as a history of the lines you *worked on*, not vim's jumplist.
--
-- Vim only records real "jumps" (G, /, {, gd, :grep, ...), so the line you just
-- edited three files ago is lost. Here a line enters the history when you do
-- something with it: start inserting, change / yank / delete, or enter visual
-- mode. A line already in the history is never added a second time.
--
-- Two stacks. The top of the back stack is where you are; CTRL-O moves it onto
-- the forward stack and jumps to the entry below it, CTRL-I moves it back.
-- Standing on a line that is not in the history, CTRL-O pushes that line onto
-- the forward stack first, so CTRL-I always returns where you came from.
--
-- Positions are stored as extmarks, so they follow the text when lines are
-- inserted or deleted above them.

local M = {}

local MAX = 100 -- entries kept per stack

local ns = vim.api.nvim_create_namespace("cursor-history")

local back, fwd = {}, {} -- oldest -> newest, { buf = bufnr, id = extmark }

-- extmark -> line, col (nil if the buffer or the mark is gone)
local function pos_of(entry)
	if not (entry and vim.api.nvim_buf_is_valid(entry.buf)) then return nil end
	local ok, m = pcall(vim.api.nvim_buf_get_extmark_by_id, entry.buf, ns, entry.id, {})
	if not ok or not m[1] then return nil end
	return m[1] + 1, m[2]
end

local function drop(entry)
	if vim.api.nvim_buf_is_valid(entry.buf) then
		pcall(vim.api.nvim_buf_del_extmark, entry.buf, ns, entry.id)
	end
end

-- forget entries whose buffer was unloaded / wiped
local function prune()
	for _, stack in ipairs({ back, fwd }) do
		for i = #stack, 1, -1 do
			if not pos_of(stack[i]) then table.remove(stack, i) end
		end
	end
end

local function holds(stack, buf, lnum)
	for _, entry in ipairs(stack) do
		if entry.buf == buf and pos_of(entry) == lnum then return true end
	end
	return false
end

local function push(stack, buf, lnum, col)
	stack[#stack + 1] = { buf = buf, id = vim.api.nvim_buf_set_extmark(buf, ns, lnum - 1, col, {}) }
	while #stack > MAX do
		drop(stack[1])
		table.remove(stack, 1)
	end
end

local function recordable()
	return vim.bo.buftype == "" and vim.bo.buflisted -- real files only (no netrw, quickfix, ...)
end

-- worked on the current line: remember it, unless it is already known
local function record()
	if not recordable() then return end
	local buf = vim.api.nvim_get_current_buf()
	local cur = vim.api.nvim_win_get_cursor(0)
	if holds(back, buf, cur[1]) or holds(fwd, buf, cur[1]) then return end
	push(back, buf, cur[1], cur[2])
end

local function goto_entry(entry)
	local lnum, col = pos_of(entry)
	if not lnum then return end
	if entry.buf ~= vim.api.nvim_get_current_buf() and not pcall(vim.api.nvim_set_current_buf, entry.buf) then
		return
	end
	pcall(vim.api.nvim_win_set_cursor, 0, { lnum, col })
	vim.cmd("normal! zv") -- open folds around the target
end

function M.back()
	prune()
	local buf = vim.api.nvim_get_current_buf()
	local cur = vim.api.nvim_win_get_cursor(0)
	local top = back[#back]
	if top and top.buf == buf and pos_of(top) == cur[1] then
		if #back < 2 then return end -- nothing further back
		fwd[#fwd + 1] = table.remove(back) -- the line we leave -> top of the forward stack
	elseif #back > 0 and recordable() then
		push(fwd, buf, cur[1], cur[2]) -- came from a line nobody recorded
	end
	if #back > 0 then goto_entry(back[#back]) end
end

function M.forward()
	prune()
	if #fwd == 0 then return end
	back[#back + 1] = table.remove(fwd)
	goto_entry(back[#back])
end

function M.setup()
	local group = vim.api.nvim_create_augroup("cursor-history", { clear = true })

	-- insert / change / yank / delete on a line
	vim.api.nvim_create_autocmd({ "InsertEnter", "TextChanged", "TextYankPost" }, {
		group = group,
		callback = record,
	})

	-- entering visual / visual-line / visual-block mode
	vim.api.nvim_create_autocmd("ModeChanged", {
		group = group,
		pattern = "*:[vV\22]*",
		callback = record,
	})
end

return M
