-- Plugin-free git helpers.
-- Replaces the keymap targets of: diffview (working-tree diff, history),
-- telescope git pickers, fugitive checkout.
-- Hunk staging (gitsigns <leader>ga/gu) is intentionally NOT replicated;
-- use `git add -p` in a terminal instead.

local picker = require("core.picker")

local M = {}

local function sys(args, cwd)
	local out = vim.fn.systemlist(args)
	if vim.v.shell_error ~= 0 then
		return nil, table.concat(out or {}, "\n")
	end
	return out
end

local function git_root()
	local out = sys({ "git", "rev-parse", "--show-toplevel" })
	return out and out[1] or nil
end

local function relpath(abs, root)
	abs = vim.fn.fnamemodify(abs, ":p")
	if abs:sub(1, #root + 1) == root .. "/" then
		return abs:sub(#root + 2)
	end
	return abs
end

-- buffer-local hunk-navigation keys inside diff windows
-- (same speed keys 'f'/'t' as the old gitsigns/diffview setup)
local function set_diff_keymaps(bufs)
	for _, b in ipairs(bufs) do
		vim.keymap.set("n", "f", "]c", { buffer = b, desc = "Git-Diff : Jump to next hunk" })
		vim.keymap.set("n", "t", "[c", { buffer = b, desc = "Git-Diff : Jump to previous hunk" })
		vim.keymap.set("n", "<leader>gp", "<cmd>diffput<CR>", { buffer = b, desc = "Git-Diff : Push hunk to other panel" })
		vim.keymap.set("v", "<leader>gp", ":diffput<CR>", { buffer = b, desc = "Git-Diff : Push selected lines" })
		vim.keymap.set("n", "<leader>gl", "<cmd>diffget<CR>", { buffer = b, desc = "Git-Diff : Get hunk from other panel" })
		vim.keymap.set("v", "<leader>gl", ":diffget<CR>", { buffer = b, desc = "Git-Diff : Get selected lines" })
		vim.keymap.set("n", "q", function()
			vim.cmd("diffoff!")
			-- wipe scratch diff buffers
			for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
				local wb = vim.api.nvim_win_get_buf(w)
				if vim.bo[wb].buftype == "nofile" and vim.b[wb].is_git_scratch then
					vim.api.nvim_win_close(w, true)
				end
			end
		end, { buffer = b, desc = "Git-Diff : Close diff" })
	end
end

local function open_scratch(lines, ft, name)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].modifiable = false
	vim.b[buf].is_git_scratch = true
	if ft then vim.bo[buf].filetype = ft end
	if name then pcall(vim.api.nvim_buf_set_name, buf, name) end
	return buf
end

--- <leader>gs : diff current file against the git index (replaces DiffviewOpen for single files)
function M.diff_against_index()
	local file = vim.api.nvim_buf_get_name(0)
	local root = git_root()
	if not root or file == "" then
		vim.notify("Not a git file", vim.log.levels.WARN)
		return
	end
	local rel = relpath(file, root)
	local lines, err = sys({ "git", "-C", root, "show", ":0:" .. rel })
	if not lines then
		vim.notify("git show failed (file not tracked?):\n" .. (err or ""), vim.log.levels.WARN)
		return
	end
	local ft = vim.bo.filetype
	local cur_buf = vim.api.nvim_get_current_buf()
	vim.cmd("diffthis")
	vim.cmd("leftabove vsplit")
	local sbuf = open_scratch(lines, ft, "INDEX://" .. rel)
	vim.api.nvim_win_set_buf(0, sbuf)
	vim.cmd("diffthis")
	vim.cmd("wincmd p")
	set_diff_keymaps({ cur_buf, sbuf })
end

--- <leader>gq : git status picker; select opens the file and its diff
function M.status()
	local root = git_root()
	if not root then return vim.notify("Not a git repo", vim.log.levels.WARN) end
	local lines = sys({ "git", "-C", root, "status", "--porcelain" })
	if not lines or #lines == 0 then
		return vim.notify("Working tree clean", vim.log.levels.INFO)
	end
	picker.pick(lines, {
		prompt = "Git status  (<CR> open + diff)",
		on_select = function(line)
			local path = line:sub(4):gsub("^.* -> ", "") -- handle renames
			vim.cmd("edit " .. vim.fn.fnameescape(root .. "/" .. path))
			local status = line:sub(1, 2)
			if not status:match("%?") then -- untracked files have no index version
				M.diff_against_index()
			end
		end,
	})
end

--- <leader>gc : browse commits; select shows the full commit as a patch
function M.commits(path)
	local root = git_root()
	if not root then return vim.notify("Not a git repo", vim.log.levels.WARN) end
	local cmd = { "git", "-C", root, "log", "--oneline", "-300" }
	if path then
		table.insert(cmd, "--follow")
		table.insert(cmd, "--")
		table.insert(cmd, path)
	end
	local lines = sys(cmd)
	if not lines then return end
	picker.pick(lines, {
		prompt = path and ("History: " .. vim.fn.fnamemodify(path, ":t")) or "Git commits  (<CR> show patch)",
		on_select = function(line)
			local hash = line:match("^(%S+)")
			local show = { "git", "-C", root, "show", hash }
			if path then
				table.insert(show, "--")
				table.insert(show, path)
			end
			local patch = sys(show)
			if not patch then return end
			vim.cmd("tab split")
			vim.api.nvim_win_set_buf(0, open_scratch(patch, "git", "COMMIT://" .. hash))
			vim.keymap.set("n", "q", "<cmd>tabclose<CR>", { buffer = true, desc = "Close" })
		end,
	})
end

--- <leader>hf : history of current file
function M.file_history()
	local file = vim.api.nvim_buf_get_name(0)
	if file == "" then return end
	local root = git_root()
	if not root then return end
	M.commits(relpath(file, root))
end

--- <leader>gb : browse branches; select checks out
function M.branches()
	local root = git_root()
	if not root then return vim.notify("Not a git repo", vim.log.levels.WARN) end
	local lines = sys({ "git", "-C", root, "branch", "--all", "--format=%(refname:short)" })
	if not lines then return end
	picker.pick(lines, {
		prompt = "Git branches  (<CR> checkout)",
		on_select = function(branch)
			local out = vim.fn.systemlist({ "git", "-C", root, "checkout", branch })
			vim.notify(table.concat(out, "\n"), vim.v.shell_error == 0 and vim.log.levels.INFO or vim.log.levels.ERROR)
			vim.cmd("checktime")
		end,
	})
end

--- <leader>hd : diff between two picked commits
function M.diff_range()
	local root = git_root()
	if not root then return vim.notify("Not a git repo", vim.log.levels.WARN) end
	local lines = sys({ "git", "-C", root, "log", "--oneline", "-300" })
	if not lines then return end
	picker.pick(lines, {
		prompt = "Diff range: pick OLDER commit",
		on_select = function(older)
			local a = older:match("^(%S+)")
			picker.pick(lines, {
				prompt = "Diff range: pick NEWER commit",
				on_select = function(newer)
					local b = newer:match("^(%S+)")
					local patch = sys({ "git", "-C", root, "diff", a .. ".." .. b })
					if not patch then return end
					vim.cmd("tab split")
					vim.api.nvim_win_set_buf(0, open_scratch(patch, "git", "DIFF://" .. a .. ".." .. b))
					vim.keymap.set("n", "q", "<cmd>tabclose<CR>", { buffer = true, desc = "Close" })
				end,
			})
		end,
	})
end

--- <leader>hr : repo history as patch log in a scratch tab
function M.repo_history()
	local root = git_root()
	if not root then return vim.notify("Not a git repo", vim.log.levels.WARN) end
	local lines = sys({ "git", "-C", root, "log", "--stat", "-50" })
	if not lines then return end
	vim.cmd("tab split")
	vim.api.nvim_win_set_buf(0, open_scratch(lines, "git", "LOG://repo"))
	vim.keymap.set("n", "q", "<cmd>tabclose<CR>", { buffer = true, desc = "Close" })
end

return M
