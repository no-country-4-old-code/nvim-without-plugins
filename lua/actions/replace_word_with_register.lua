-- Paste over the word under the cursor without the deleted word landing in any
-- register, so the same text can be pasted over word after word.
--
-- Takes the register the mapping was called with ("a<leader>r uses register a), and
-- leaves the visual marks as they were -- the "viw" it needs internally would
-- otherwise clobber '< and '>.

local M = {}

function M.run()
	local text = vim.fn.getreg(vim.v.register):gsub("\n$", "")
	if text == "" then return end
	local line = vim.api.nvim_get_current_line()
	local col = vim.api.nvim_win_get_cursor(0)[2]
	if not vim.regex("^\\k"):match_str(line:sub(col + 1)) then return end -- not on a word
	local marks = { vim.fn.getpos("'<"), vim.fn.getpos("'>") }
	vim.cmd.normal({ "viw" .. vim.keycode("<Esc>"), bang = true })
	local srow, scol = unpack(vim.api.nvim_buf_get_mark(0, "<"))
	local erow, ecol = unpack(vim.api.nvim_buf_get_mark(0, ">"))
	vim.fn.setpos("'<", marks[1])
	vim.fn.setpos("'>", marks[2])
	local last = vim.fn.strcharpart(vim.fn.getline(erow):sub(ecol + 1), 0, 1) -- may be multibyte
	vim.api.nvim_buf_set_text(0, srow - 1, scol, erow - 1, ecol + #last, vim.split(text, "\n"))
	vim.api.nvim_win_set_cursor(0, { srow, scol })
end

return M
