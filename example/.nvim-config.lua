-- Custom nvim settings. Fields are optional 
-- Copy it to your home directory ~/.nvim-config.lua

-- LSP
-- (currently clangd ; python & rust support in config will follow)
--
-- clangd (C/C++ LSP): where do the compile flags come from? Pick one.
--
--   "project"  A normal build creates compile_commands.json in
--              <cwd>/<build_dir> (CMake: -DCMAKE_EXPORT_COMPILE_COMMANDS=ON,
--              or `bear -- make`). Use this when the build can do it.
--              This needs "build_dir" to be set.
--
--   "farm"     Sometimes compile_commands.json can not be generated because the Makefile-structure
--              is a monster. To cover this, I have a "exotic" approach:
--              I create a symlink-farm (see README and script in tools folder).
--              One clangd then serves every repo;

local clangd_mode = "farm"

-- ===============
-- === "farm"-mode only. 
-- indexing   false: LSP in open files + go to declaration into every header.
--            true:  clangd also indexes every .c/.cpp in the background, so go
--                   to definition / references also reach files never opened.
--            Both read index/compile_commands.json, so C and C++ each get their
--            own -std (see link-farm.sh -f) and every .h its repo's language.
local farm_index = true 
-- cache dir
local farm_dir = vim.fn.expand("~/.cache/c-farm")
-- ===============

-- ===============
-- === "project" mode only. 
-- Directory which contains compile_commands.json for LSP like clangd or cppcheck
local build_dir = "build"
-- ===============


return {

	-- Search settings for the find-files && rip-grep
	-- Only apply while nvim's cwd is inside `root` 
	search = {
		-- As long as "root" is somewhere in parent path, every search starts from root.
        -- default value : "" --> disabled
		root = "",
		ignore_folders = { "build", "node_modules", ".venv" },
	},

	-- Run at the end of init.lua, after all modules are set up 
    -- so keymaps win over the built-in ones. Put anything that needs to *execute*
	-- in here: LSP tweaks, own keymaps, autocmds, ...
	setup = function()
		local clangd_cmd = {
			"clangd",
			-- system has a partial GCC 12 install without libstdc++ headers; make
			-- clangd take include paths from the real compiler instead of guessing
			"--query-driver=/usr/bin/c++,/usr/bin/cc",
			"--clang-tidy",
			"--background-index",
			"-j=4", -- threads for background indexing
			"--completion-style=detailed",
		}

		-- Indexing progress shows in the statusline; details, status and the LSP
		-- log (clangd errors) via <leader>= (actions.health_screen).

		if clangd_mode == "project" then
			table.insert(clangd_cmd, "--compile-commands-dir=" .. build_dir)
			vim.lsp.config("clangd", { cmd = clangd_cmd })
		elseif vim.fn.isdirectory(farm_dir) == 0 then
			vim.notify("clangd: no link farm at " .. farm_dir .. " -- run tools/c-link-farm/link-farm.sh build ROOT...",
				vim.log.levels.WARN)
		else
			table.insert(clangd_cmd, "--compile-commands-dir=" .. farm_dir .. "/index")
			-- clangd indexes by default and rejects the flag twice: replace it
			if not farm_index then
				clangd_cmd[vim.fn.index(clangd_cmd, "--background-index") + 1] = "--background-index=false"
			end
			-- one clangd for all repos, instead of one per .git root
			vim.lsp.config("clangd", { cmd = clangd_cmd, root_dir = farm_dir })

			-- go to declaration lands on the farm symlink; open the real file
			-- instead, so the path, git signs and tabs show the actual repo. This has
			-- to happen where the LSP turns a URI into a buffer: nvim matches buffers
			-- by inode, so a farm buffer can not be swapped for the real file later.
			local farm_prefix = vim.fn.resolve(farm_dir) .. "/"
			local uri_to_fname = vim.uri_to_fname
			vim.uri_to_fname = function(uri)
				local fname = uri_to_fname(uri)
				return vim.startswith(fname, farm_prefix) and vim.fn.resolve(fname) or fname
			end
			vim.uri_to_bufnr = function(uri) return vim.fn.bufadd(vim.uri_to_fname(uri)) end

			-- foo.h <-> foo.c / foo.cpp via the farm (header and source live in
			-- different folders, so clangd's own switch rarely finds them)
			vim.keymap.set("n", "<leader>6", function()
				local other = vim.fn.expand("%:e"):match("^h") and "/src/" or "/include/"
				local hits = vim.fn.glob(farm_dir .. other .. vim.fn.expand("%:t:r") .. ".*", false, true)
				if #hits == 0 then
					vim.notify("no header/source for " .. vim.fn.expand("%:t"))
					return
				end
				vim.cmd.edit(vim.fn.fnameescape(vim.fn.resolve(hits[1])))
			end, { desc = "switch header/source" })
		end

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
	end,
}
