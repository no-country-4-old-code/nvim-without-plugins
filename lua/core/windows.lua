-- Plugin-free window picker (replaces nvim-window-picker).
-- Shows a letter label in each window, jumps on keypress.

local M = {}

local CHARS = "ASDFJKLGH"

function M.pick_window_to_jump()
	local wins = {}
	for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		if vim.api.nvim_win_get_config(w).relative == "" then
			wins[#wins + 1] = w
		end
	end
	if #wins <= 1 then return end
	if #wins == 2 then -- only one other window: just go there
		vim.cmd("wincmd w")
		return
	end

	local floats = {}
	for i, w in ipairs(wins) do
		local char = CHARS:sub(i, i)
		local buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "  " .. char .. "  " })
		local pos = vim.api.nvim_win_get_position(w)
		local width = vim.api.nvim_win_get_width(w)
		local height = vim.api.nvim_win_get_height(w)
		floats[#floats + 1] = vim.api.nvim_open_win(buf, false, {
			relative = "editor",
			row = pos[1] + math.floor(height / 2),
			col = pos[2] + math.floor(width / 2) - 2,
			width = 5,
			height = 1,
			style = "minimal",
			border = "single",
			focusable = false,
			zindex = 300,
		})
	end
	vim.cmd("redraw")

	local ok, key = pcall(vim.fn.getcharstr)
	for _, f in ipairs(floats) do
		if vim.api.nvim_win_is_valid(f) then vim.api.nvim_win_close(f, true) end
	end
	if not ok then return end

	local idx = CHARS:find(key:upper(), 1, true)
	if idx and wins[idx] and vim.api.nvim_win_is_valid(wins[idx]) then
		vim.api.nvim_set_current_win(wins[idx])
	end
end

return M
