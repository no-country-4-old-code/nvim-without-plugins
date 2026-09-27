-- Yank ring: the last 10 yanks into the default register, newest first.
--
-- A new yank always lands in slot 1, the older ones shift down (1 -> 2, ...,
-- 9 -> 0) and the one in slot 0 drops out. open() shows the slots in a small
-- float in the top right corner, green rounded border (slot number + first line
-- of the text, the count of further lines on the right); the newest (slot 1)
-- gets a green bar and bold green text, empty slots a dimmed dot. 0-9 pastes
-- that slot after the cursor (like p) and closes the float, <Esc> just closes it.

local M = {}

local SIZE = 10
local ns = vim.api.nvim_create_namespace("yank-ring")

local slots = {} -- newest first: [1..10] -> { lines = string[], regtype = string }; 10 is key 0

local BAR = "▎"

-- " ▎1 text" for the newest slot, "  2 text" for the others, "  3 ·" when empty
local function label(i)
	local s = slots[i]
	local lead = (i == 1 and s) and BAR or " "
	local text = s and (s.lines[1] or ""):gsub("\t", " "):gsub("^%s+", "") or "·"
	return (" %s%d %s"):format(lead, i % 10, text)
end

local function decorate(buf)
	for i = 1, SIZE do
		local s, row = slots[i], i - 1
		local lead = (i == 1 and s) and #BAR or 1
		local digit = 1 + lead -- byte col of the slot number
		if not s then
			vim.api.nvim_buf_set_extmark(buf, ns, row, digit, { end_col = digit + 2 + #"·", hl_group = "Comment" })
		elseif i == 1 then
			vim.api.nvim_buf_set_extmark(buf, ns, row, 0, { end_row = row + 1, hl_group = "YankRingLast" })
		else
			vim.api.nvim_buf_set_extmark(buf, ns, row, digit, { end_col = digit + 1, hl_group = "Comment" })
		end
		if s and #s.lines > 1 then
			vim.api.nvim_buf_set_extmark(buf, ns, row, 0, {
				virt_text = { { ("+%d "):format(#s.lines - 1), "Comment" } },
				virt_text_pos = "right_align",
			})
		end
	end
end

function M.open()
	local rows = {}
	for i = 1, SIZE do rows[#rows + 1] = label(i) end

	local from = vim.api.nvim_get_current_win()
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, rows)
	vim.bo[buf].modifiable = false
	vim.bo[buf].bufhidden = "wipe"
	decorate(buf)

	local width = math.min(vim.o.columns - 4, 60)
	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		width = width,
		height = SIZE,
		row = 0,
		col = vim.o.columns - width - 2, -- border takes the last 2 columns
		title = " Yanks ",
		title_pos = "left",
		style = "minimal",
	})
	vim.wo[win].cursorline = false

	local function close()
		if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
	end
	local map = function(lhs, fn) vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true }) end
	map("<Esc>", close)
	for i = 1, SIZE do
		map(tostring(i % 10), function()
			close()
			local s = slots[i]
			if not s or not vim.api.nvim_win_is_valid(from) then return end
			vim.api.nvim_set_current_win(from)
			vim.api.nvim_put(s.lines, s.regtype, true, true)
		end)
	end
	vim.api.nvim_create_autocmd("WinLeave", { buffer = buf, once = true, callback = close })
end

function M.setup()
	vim.api.nvim_set_hl(0, "YankRingLast", { default = true, fg = "#9ece6a", bold = true })
	vim.api.nvim_create_autocmd("TextYankPost", {
		group = vim.api.nvim_create_augroup("yank-ring", { clear = true }),
		callback = function()
			local e = vim.v.event
			if e.operator ~= "y" or e.regname ~= "" then return end
			table.insert(slots, 1, { lines = vim.deepcopy(e.regcontents), regtype = e.regtype })
			slots[SIZE + 1] = nil
		end,
	})
end

return M
