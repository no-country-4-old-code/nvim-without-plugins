-- Format on save: after a write, run an external formatter on the file and
-- reload the buffer when it succeeds. Which formatter runs for which files
-- comes from ~/.nvim-config.lua (see core.config):
--
--   format = {
--   	{ pattern = { "*.c", "*.h" }, cmd = { "format.sh", "-f", "-p" } },
--   }
--
-- The absolute file path is appended to `cmd`; it runs in the file's folder.
-- No entries (the default) -> nothing happens on save.

local config = require("core.config")

local M = {}

local function run(entry, bufnr)
	local file = vim.api.nvim_buf_get_name(bufnr)
	local cmd = vim.list_extend(vim.deepcopy(entry.cmd), { file })
	if vim.fn.executable(cmd[1]) == 0 then
		vim.notify("format on save: " .. cmd[1] .. " not found", vim.log.levels.WARN)
		return
	end
	vim.fn.jobstart(cmd, {
		cwd = vim.fs.dirname(file), -- the script sees the file's repository
		on_exit = function(_, code)
			vim.schedule(function()
				if code ~= 0 then
					vim.notify(("format on save: %s exited with %d"):format(cmd[1], code), vim.log.levels.WARN)
				elseif vim.api.nvim_buf_is_valid(bufnr) then
					vim.cmd("checktime " .. bufnr)
				end
			end)
		end,
	})
end

function M.setup()
	local group = vim.api.nvim_create_augroup("format-on-save", { clear = true })
	for _, entry in ipairs(config.get().format or {}) do
		vim.api.nvim_create_autocmd("BufWritePost", {
			group = group,
			pattern = entry.pattern,
			callback = function(args)
				run(entry, args.buf)
			end,
		})
	end
end

return M
