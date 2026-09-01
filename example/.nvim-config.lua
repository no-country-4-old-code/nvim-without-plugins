-- Example ~/.nvim-config.lua -- the single file this config reads for user
-- settings. Copy it to your home directory and adjust:
--
--   cp example/.nvim-config.lua ~/.nvim-config.lua
--
-- It replaces the former NVIM_* environment variables and the project-local
-- .nvim.lua. Every key is optional; without the file nvim hints once at
-- startup and runs with the defaults.

-- directory which contains compile_commands.json for LSP like clangd or cppcheck
local build_dir = "build"

return {

	-- Search settings for the find-files (<leader>ff) and rip-grep (<leader>fg)
	-- actions. They only apply while nvim's cwd is inside `root` -- started
	-- anywhere else, nvim searches its own cwd and hides nothing.
	search = {
		-- Pin searches to this folder. "" -> search the directory nvim was
		-- started in.
		root = "",

		-- Folder names to skip while searching. A list, or one string with
		-- , : or space as separator: "build node_modules .venv"
		ignore_folders = { "build", "node_modules", ".venv" },
	},

	git = {
		-- Branch or commit to treat as the review base. When set, the git signs
		-- in the gutter (f / F jump between changed blocks) and the `gs` change
		-- list compare against that ref instead of against the index / HEAD.
		-- "" -> compare against the index / HEAD. An unknown ref falls back to
		-- that default with a warning.
		ref_base = "",
	},

	-- Run at the end of init.lua, after all modules are set up -- so keymaps
	-- here win over the built-in ones. Put anything that needs to *execute*
	-- in here: LSP tweaks, own keymaps, autocmds, ...
	setup = function()
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

		-- Use <leader>1 through <leader>9 for your own shortcuts.
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
			-- built-in termdebug (see lua/core/debug.lua); gdb opens without running
			-- the program, so set breakpoints (<leader>db) and continue (<leader>dc)
			vim.cmd("Termdebug " .. vim.fn.getcwd() .. "/main")
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
	end,
}
