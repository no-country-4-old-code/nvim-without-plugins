-- Single user config file: ~/.nvim-config.lua
--
-- Replaces the former $NVIM_* environment variables. The file returns a table:
--
--   return {
--   	search = { root = "~/work/project", ignore_folders = { "build", ".venv" } },
--   	git    = { ref_base = "origin/main" },
--   	setup  = function() ... end,   -- own keymaps / vim.lsp.config / ...
--   }
--
-- Every key is optional. A missing file is fine -- nvim hints once at startup
-- and runs with the defaults below. See example/.nvim-config.lua.

local M = {}

local defaults = {
	search = {
		root = "",           -- "" -> search the directory nvim was started in
		ignore_folders = {}, -- list of folder names, or one "a,b c" string
	},
	git = {
		ref_base = "",       -- "" -> diff against the index / HEAD
	},
	setup = nil,             -- function, run at the end of init.lua
}

--- @return string absolute path of the user config file
function M.path()
	return vim.fn.fnamemodify(vim.fn.expand("~/.nvim-config.lua"), ":p")
end

-- "build, node_modules .venv" and { "build", ... } are both accepted for
-- search.ignore_folders -- normalize to a list of names without trailing slash
local function as_list(value)
	if type(value) == "table" then
		value = table.concat(value, ",")
	end
	local names = {}
	for name in tostring(value or ""):gmatch("[^,:%s]+") do
		table.insert(names, (name:gsub("/+$", "")))
	end
	return names
end

local loaded -- cache: the merged table, built on first access

--- The user config, merged over the defaults. Loads the file on first call.
--- @return table
function M.get()
	if loaded then
		return loaded
	end
	loaded = vim.deepcopy(defaults)

	local path = M.path()
	if vim.fn.filereadable(path) == 0 then
		loaded.missing = true
		return loaded
	end

	local chunk, err = loadfile(path)
	if not chunk then
		vim.schedule(function()
			vim.notify("~/.nvim-config.lua: " .. tostring(err), vim.log.levels.ERROR)
		end)
		return loaded
	end

	local ok, user = pcall(chunk)
	if not ok then
		vim.schedule(function()
			vim.notify("~/.nvim-config.lua: " .. tostring(user), vim.log.levels.ERROR)
		end)
		return loaded
	end
	if type(user) ~= "table" then
		vim.schedule(function()
			vim.notify("~/.nvim-config.lua: expected `return { ... }`", vim.log.levels.WARN)
		end)
		return loaded
	end

	loaded = vim.tbl_deep_extend("force", loaded, user)
	loaded.search.ignore_folders = as_list(loaded.search.ignore_folders)
	return loaded
end

--- Load the file, hint when it is not there, then run its `setup` function.
function M.setup()
	local cfg = M.get()

	if cfg.missing then
		vim.schedule(function()
			vim.notify(
				"no ~/.nvim-config.lua -- using defaults (see example/.nvim-config.lua)",
				vim.log.levels.WARN
			)
		end)
		return
	end

	if type(cfg.setup) == "function" then
		local ok, err = pcall(cfg.setup)
		if not ok then
			vim.schedule(function()
				vim.notify("~/.nvim-config.lua setup(): " .. tostring(err), vim.log.levels.ERROR)
			end)
		end
	end
end

return M
