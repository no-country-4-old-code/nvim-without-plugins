local M = {}

function M.setup()
	-- Line numbers
	vim.opt.number = true
	vim.opt.relativenumber = true
	vim.opt.cursorline = true
	vim.opt.termguicolors = true

	-- Highlights
	local function set_line_number_colors()
		vim.api.nvim_set_hl(0, "LineNr", { fg = "#5eacd3" })
		vim.api.nvim_set_hl(0, "CursorLineNr", { fg = "#24283b", bg = "#ff9e64", bold = true })
		vim.api.nvim_set_hl(0, "CursorLine", { bg = "#1e3a44" })
		vim.api.nvim_set_hl(0, "CursorLineSign", { bg = "#1e3a44" })
		vim.api.nvim_set_hl(0, "CursorLineFold", { bg = "#1e3a44" })
	end

	set_line_number_colors()
	vim.api.nvim_create_autocmd("ColorScheme", { callback = set_line_number_colors })

	-- Relative numbers only in normal mode
	local copy_mode = require("custom.copy-mode")

	vim.api.nvim_create_autocmd("InsertEnter", {
		callback = function()
			if copy_mode.active() then return end
			vim.opt.relativenumber = false
			vim.opt.number = true
		end,
	})
	vim.api.nvim_create_autocmd("InsertLeave", {
		callback = function()
			if copy_mode.active() then return end
			vim.opt.relativenumber = true
			vim.opt.number = true
		end,
	})
end

return M
