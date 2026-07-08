local M = {}

function M.setup()
	vim.opt.fileformats = { "unix" }
	vim.opt.endofline = true
	vim.opt.fixendofline = true
end

return M

