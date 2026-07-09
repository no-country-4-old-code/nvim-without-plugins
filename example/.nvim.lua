-- Project-local keymaps
-- Copy this file to the root of your project and adjust to your needs.
-- Neovim will prompt you to trust it on first load (once per file change).

-- directory which contains compile-commands.json for LSP like clangd or cppcheck
local build_dir = "build"

vim.lsp.config("clangd", {
	cmd = {
		"clangd",
		"--compile-commands-dir=" .. build_dir,
		-- system has a partial GCC 12 install without libstdc++ headers; make
		-- clangd take include paths from the real compiler instead of guessing
		"--query-driver=/usr/bin/c++",
		"--clang-tidy",
		"--background-index",
		"--completion-style=detailed",
	},
})


-- Use <leader>1 through <leader>9 for project-specific shortcuts.
-- Example: C project
vim.keymap.set("n", "<leader>1", function()
	vim.cmd("w")
	vim.cmd("! g++ main.cpp -o main")
	vim.cmd("! ./main")
	vim.cmd("! rm main")
end, { desc = "run main" })

vim.keymap.set("n", "<leader>2", function()
	vim.cmd("w")
	local result = vim.fn.system("gcc main.c -o main -g")
	if vim.v.shell_error ~= 0 then
		vim.notify("Compile failed:\n" .. result, vim.log.levels.ERROR)
		return
	end
	require("dap").run({
		name = "Launch (gdb)",
		type = "cppdbg",
		request = "launch",
		program = vim.fn.getcwd() .. "/main",
		cwd = "${workspaceFolder}",
		stopAtEntry = true,
		MIMode = "gdb",
	})
end, { desc = "compile & debug main.c" })

vim.keymap.set("n", "<leader>3", function()
	vim.cmd("w")
	vim.cmd("!cargo test")
end, { desc = "cargo test" })

vim.keymap.set("n", "<leader>4", function()
	print("Moin Moin")
end, { desc = "Moin Moin" })

local cppcheck = require("custom.cppcheck")
vim.keymap.set("n", "<leader>5", function()
	cppcheck.check_project(vim.fn.getcwd() .. "/" .. build_dir .. "/compile_commands.json")
end, { desc = "cppcheck full project" })
