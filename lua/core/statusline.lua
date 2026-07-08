-- Minimal statusline (replaces lualine).

local M = {}

local branch = ""

local function update_branch()
	if vim.fn.executable("git") == 0 then return end
	vim.system({ "git", "branch", "--show-current" }, { text = true }, function(o)
		vim.schedule(function()
			branch = (o.code == 0 and o.stdout) and vim.trim(o.stdout) or ""
			vim.cmd("redrawstatus")
		end)
	end)
end

function _G.Statusline_branch()
	return branch ~= "" and ("  " .. branch) or ""
end

function _G.Statusline_diag()
	local e = #vim.diagnostic.get(0, { severity = vim.diagnostic.severity.ERROR })
	local w = #vim.diagnostic.get(0, { severity = vim.diagnostic.severity.WARN })
	local parts = {}
	if e > 0 then parts[#parts + 1] = "E:" .. e end
	if w > 0 then parts[#parts + 1] = "W:" .. w end
	return #parts > 0 and (" " .. table.concat(parts, " ")) or ""
end

function M.setup()
	vim.api.nvim_create_autocmd({ "BufEnter", "FocusGained", "DirChanged" }, { callback = update_branch })
	update_branch()
	vim.o.laststatus = 2
	vim.o.statusline = " %f %m%r%{v:lua.Statusline_branch()}%{v:lua.Statusline_diag()}%= %{&filetype} │ %l:%c │ %p%% "
end

return M
