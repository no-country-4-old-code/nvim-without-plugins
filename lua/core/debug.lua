-- Debugging via the BUILT-IN termdebug (gdb frontend shipped with nvim).
-- Replaces the nvim-dap / dap-ui keymap targets for C/C++/Rust (anything gdb runs).
-- Note: breakpoints can only be set once a session is running (gdb limitation
-- of termdebug). Start with <leader>dc first.

local M = {}

local breakpoints = {} -- "file:line" -> true

local function started()
	return vim.fn.exists(":Continue") == 2
end

function M.setup()
	if vim.fn.exists(":Termdebug") ~= 0 then
		return
	end
	if vim.v.vim_did_enter == 0 then
		-- during startup: only add to runtimepath; nvim sources it once
		-- in the plugin-load phase (plain packadd would source it twice)
		vim.cmd("packadd! termdebug")
	else
		vim.cmd.packadd("termdebug")
	end
	vim.g.termdebug_config = { wide = 163, winbar = 0 }
end

--- <leader>dc : continue, or start a session (asks for the executable)
function M.continue()
	if started() then
		vim.cmd("Continue")
		return
	end
	vim.ui.input({ prompt = "Executable to debug: ", default = vim.fn.getcwd() .. "/", completion = "file" }, function(path)
		if path and path ~= "" then
			vim.cmd("Termdebug " .. vim.fn.fnameescape(path))
		end
	end)
end

--- <leader>db : toggle breakpoint at cursor
function M.toggle_breakpoint()
	if not started() then
		vim.notify("Start the debugger first (<leader>dc)", vim.log.levels.WARN)
		return
	end
	local key = vim.api.nvim_buf_get_name(0) .. ":" .. vim.fn.line(".")
	if breakpoints[key] then
		vim.cmd("Clear")
		breakpoints[key] = nil
	else
		vim.cmd("Break")
		breakpoints[key] = true
	end
end

local function gdb_cmd(cmd)
	return function()
		if not started() then
			vim.notify("No debug session (<leader>dc to start)", vim.log.levels.WARN)
			return
		end
		vim.cmd(cmd)
	end
end

M.step_over = gdb_cmd("Over")
M.step_into = gdb_cmd("Step")
M.step_out = gdb_cmd("Finish")
M.pause = gdb_cmd("Stop")
M.eval = gdb_cmd("Evaluate")

--- <leader>dx : terminate the program being debugged
function M.terminate()
	if started() then
		vim.fn.TermDebugSendCommand("kill")
	end
end

--- <leader>dr : restart the program
function M.restart()
	if started() then
		vim.fn.TermDebugSendCommand("run")
	end
end

--- <leader>du : jump between gdb window and source window
function M.toggle_ui()
	if not started() then
		vim.notify("No debug session (<leader>dc to start)", vim.log.levels.WARN)
		return
	end
	if vim.bo.buftype == "terminal" then
		vim.cmd("Source")
	else
		vim.cmd("Gdb")
	end
end

--- <leader>dw : auto-display word under cursor on every stop (gdb 'display')
function M.watch_word()
	if not started() then
		vim.notify("No debug session (<leader>dc to start)", vim.log.levels.WARN)
		return
	end
	vim.fn.TermDebugSendCommand("display " .. vim.fn.expand("<cword>"))
end

return M
