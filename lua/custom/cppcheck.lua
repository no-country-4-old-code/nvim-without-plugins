local M = {}

function M.qf_format(info)
	local items = vim.fn.getqflist({ id = info.id, items = 1 }).items
	local result = {}
	for i = info.start_idx, info.end_idx do
		local item = items[i]
		local fname = item.bufnr ~= 0 and vim.fn.fnamemodify(vim.fn.bufname(item.bufnr), ":t") or "?"
		table.insert(result, string.format("%-30s|%4d| %s", fname, item.lnum or 0, item.text or ""))
	end
	return result
end

local function preview_in_main(qf_win, items)
	local idx = vim.fn.line(".")
	local item = items[idx]
	if not item then return end

	local target_win
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		local cfg = vim.api.nvim_win_get_config(win)
		if cfg.relative == "" and win ~= qf_win then
			local bt = vim.bo[vim.api.nvim_win_get_buf(win)].buftype
			if bt ~= "quickfix" and bt ~= "nofile" then
				target_win = win
				break
			end
		end
	end
	if not target_win then return end

	local fname = item.filename
	if not fname or fname == "" then
		if item.bufnr and item.bufnr ~= 0 then
			fname = vim.api.nvim_buf_get_name(item.bufnr)
		end
	end
	if not fname or fname == "" then return end
	if not fname:match("^/") then
		fname = vim.fn.getcwd() .. "/" .. fname
	end

	-- Load the buffer without switching windows (avoids spurious CursorMoved events).
	-- Force filetype detection so the FileType event fires → treesitter attaches.
	local buf = vim.fn.bufadd(fname)
	if vim.fn.bufloaded(buf) == 0 then vim.fn.bufload(buf) end
	if vim.api.nvim_buf_get_option(buf, "filetype") == "" then
		vim.api.nvim_buf_call(buf, function() vim.cmd("filetype detect") end)
	end

	vim.api.nvim_win_set_buf(target_win, buf)
	if item.lnum and item.lnum > 0 then
		local lnum = math.min(item.lnum, vim.api.nvim_buf_line_count(buf))
		vim.api.nvim_win_set_cursor(target_win, { lnum, math.max(0, (item.col or 1) - 1) })
	end
end

-- On-save per-file checking is configured in lua/plugins/lint.lua.
-- Call this from a project's .nvim.lua to bind a full-project check to a key:
--   local cppcheck = require("custom.cppcheck")
--   vim.keymap.set("n", "<leader>5", function()
--       cppcheck.check_project(vim.fn.getcwd() .. "/build/compile_commands.json")
--   end, { desc = "cppcheck full project" })
function M.check_project(compile_db)
	vim.notify("Running cppcheck on full project...", vim.log.levels.INFO)
	local lines = vim.fn.systemlist(
		"cppcheck --project=" .. compile_db ..
		" --enable=warning,style,performance,information" ..
		" --inline-suppr --quiet --suppress=missingIncludeSystem" ..
		" '--template={file}:{line}:{column}: [{id}] {severity}: {message}' 2>&1"
	)
	local qf = {}
	for _, line in ipairs(lines) do
		local file, lnum, col, id, sev, msg =
			line:match("^(.-):(%d+):(%d+): %[(.-)%] (%S+): (.+)$")
		if file then
			table.insert(qf, {
				filename = file, lnum = tonumber(lnum), col = tonumber(col),
				text = "[" .. id .. "] " .. sev .. ": " .. msg,
				type = sev == "error" and "E" or "W",
			})
		end
	end
	vim.fn.setqflist(qf)
	vim.cmd("copen")

	local bufnr = vim.api.nvim_get_current_buf()
	local qf_win = vim.api.nvim_get_current_win()
	vim.o.quickfixtextfunc = "v:lua.require('custom.cppcheck').qf_format"

	vim.keymap.set("n", "l", "<CR>", { buffer = bufnr, noremap = true, desc = "Open entry in main window" })
	vim.keymap.set("n", "<Esc>", "<cmd>cclose<CR>", { buffer = bufnr, noremap = true, desc = "Close cppcheck window" })

	local items = vim.fn.getqflist()
	vim.api.nvim_create_autocmd("CursorMoved", {
		buffer = bufnr,
		callback = function() preview_in_main(qf_win, items) end,
	})

	vim.notify("cppcheck: " .. #qf .. " issues", vim.log.levels.INFO)
end

return M
