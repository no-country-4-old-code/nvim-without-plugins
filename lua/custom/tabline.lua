-- Tab labels with the file name only (the built-in tabline shortens the
-- leading directories instead of dropping them).

local M = {}

function _G.Tabline()
	local cur = vim.api.nvim_get_current_tabpage()
	local parts = {}
	for i, tab in ipairs(vim.api.nvim_list_tabpages()) do
		local buf = vim.api.nvim_win_get_buf(vim.api.nvim_tabpage_get_win(tab))
		local name = vim.api.nvim_buf_get_name(buf)
		local label = name ~= "" and vim.fn.fnamemodify(name, ":t") or "[No Name]"
		if label == "" then label = name end -- directories (netrw) end in "/"
		if vim.bo[buf].modified then label = label .. " +" end
		parts[#parts + 1] = (tab == cur and "%#TabLineSel#" or "%#TabLine#")
			.. "%" .. i .. "T " .. label:gsub("%%", "%%%%") .. " "
	end
	return table.concat(parts) .. "%#TabLineFill#%T"
end

function M.setup()
	vim.o.tabline = "%!v:lua.Tabline()"
end

return M
