-- Command built on the nested sidebar: every changed block of the repo, one
-- folder per changed file, one row per block ("  110  + 2 lines": where it
-- starts, + added / ~ changed / - removed, how many lines -- in the colour of
-- the matching gutter sign).
-- j / k walk the blocks and the window next to the sidebar follows: it shows
-- the file itself (highlighted code, not a diff) centered on the block, every
-- block of the file marked -- green for added lines, the focus highlight for
-- changed ones, and -- since removed text has no line of its own left -- red
-- "ghost lines" (virtual lines: no number, not part of the buffer) for a
-- deletion. l / h fold a file, <CR> / o jump to the block and close the list,
-- <Esc> closes it.
--
-- The list comes from `git diff --unified=0` so that neighbouring changes stay
-- separate rows -- the same blocks the gutter signs mark.
--
-- The repo is the one the current file lives in (core.git-ref.root), so calling
-- this from a file outside the working directory shows *its* checkout's changes.
--
-- Compared against the commit the branch started from, else HEAD
-- (see core.git-ref). Untracked, deleted and binary files are single rows.

local sidebar = require("actions.gui.list_nested_sidebar")
local git_ref = require("core.git-ref")

local M = {}

local NS = vim.api.nvim_create_namespace("git_status")

-- tokyonight diff colours
local function set_highlights()
	vim.api.nvim_set_hl(0, "GitStatusAdd", { bg = "#20303b" })
	vim.api.nvim_set_hl(0, "GitStatusChange", { link = "Visual", default = true })
	vim.api.nvim_set_hl(0, "GitStatusDelete", { fg = "#f7768e", bg = "#37222c" })
	-- background only: whole lines that are shown as deleted keep their syntax colours
	vim.api.nvim_set_hl(0, "GitStatusDeleteLine", { bg = "#37222c" })
	vim.api.nvim_set_hl(0, "GitStatusGone", { fg = "#f7768e" }) -- row of a deleted file
	-- the gutter's colours (behaviour.git-signs), should it not be set up
	vim.api.nvim_set_hl(0, "GitSignAdd", { fg = "#9ece6a", default = true })
	vim.api.nvim_set_hl(0, "GitSignChange", { fg = "#73daca", default = true })
	vim.api.nvim_set_hl(0, "GitSignDelete", { fg = "#914c54", default = true })
end

local BLOCK_HL = { add = "GitStatusAdd", change = "GitStatusChange" }
local ROW = { -- sign + colour of a block's row
	add = { "+", "GitSignAdd" }, change = { "~", "GitSignChange" }, delete = { "-", "GitSignDelete" },
}

-- new-side line range a "@@ -a,b +c,d @@" header covers (d == 0: a pure
-- deletion, which sits right after line c)
local function hunk_range(header)
	local start, count = header:match("^@@ %-%S+ %+(%d+),?(%d*)")
	start = math.max(tonumber(start) or 1, 1)
	count = tonumber(count) or 1 -- "+12" without a count means one line
	return start, count == 0 and start or start + count - 1
end

-- the body of a `--unified=0` hunk: its removed lines (text only) and how many
-- lines it added. Runs to the next header ("@@" / "diff --git"); the
-- "\ No newline at end of file" marker can sit between the two halves, so it is
-- skipped rather than treated as the end.
local function hunk_body(diff, header)
	local removed, added = {}, 0
	for i = header + 1, #diff do
		local c = diff[i]:sub(1, 1)
		if c == "-" then
			removed[#removed + 1] = diff[i]:sub(2)
		elseif c == "+" then
			added = added + 1
		elseif c ~= "\\" then
			break
		end
	end
	return removed, added
end

--- cut a `git diff` into per-file sections, each with the rows of its hunk headers
local function split_files(diff)
	local order, cur = {}, nil
	for i, line in ipairs(diff) do
		if line:sub(1, 11) == "diff --git " then
			cur = {
				-- "a/<path> b/<path>" -- renames name the new path second
				path = line:match("^diff %-%-git a/.* b/(.*)$") or line:sub(12),
				hunks = {},
			}
			order[#order + 1] = cur
		elseif cur and line:sub(1, 2) == "@@" then
			cur.hunks[#cur.hunks + 1] = i
		elseif cur and line:sub(1, 13) == "Binary files " then
			cur.binary = true
		elseif cur and line:sub(1, 18) == "deleted file mode " then
			cur.deleted = true
		end
	end
	return order
end

--- the changed files, each with its blocks: every block, even ones a context
--- diff would merge into a single hunk
--- @return table[] files -- { path, note = string|nil (single-row file),
---   deleted, blocks = { { file, lnum, count, kind = "add"|"change"|"delete",
---   first, last = the block's lines in the working tree (add/change),
---   after, removed = anchor line + the lost text (delete) } } }
local function collect(root, rev)
	local diff = vim.fn.systemlist({ "git", "-C", root, "diff", "--unified=0", rev })
	local files = {}

	for _, sec in ipairs(split_files(diff)) do
		local file = { path = sec.path, blocks = {}, deleted = sec.deleted }
		files[#files + 1] = file
		if sec.deleted then
			file.note = "(deleted)"
		elseif #sec.hunks == 0 then -- binary file, rename without edits, mode change
			file.note = sec.binary and "(binary)" or "(no line changes)"
		else
			for _, header in ipairs(sec.hunks) do
				local first, last = hunk_range(diff[header])
				local removed, added = hunk_body(diff, header)
				file.blocks[#file.blocks + 1] = {
					file = file, lnum = first,
					count = added > 0 and added or #removed, -- lines it holds now, else lost
					kind = (added == 0 and "delete") or (#removed == 0 and "add") or "change",
					first = first, last = last,
					-- a deletion is written as "+c,0": the text sat after new-side line
					-- c, and c == 0 means it sat above the first line
					after = tonumber(diff[header]:match("%+(%d+)")) or 0,
					removed = removed,
				}
			end
		end
	end

	for _, path in ipairs(vim.fn.systemlist({ "git", "-C", root, "ls-files", "--others", "--exclude-standard" })) do
		-- nothing of it is in the ref: the whole file is one added block
		local file = { path = path, note = "(untracked)", blocks = {} }
		file.whole = { file = file, lnum = 1, kind = "add", first = 1, last = math.huge }
		files[#files + 1] = file
	end

	return files
end

--- mark `block` in buf
local function mark(buf, block)
	local count = vim.api.nvim_buf_line_count(buf)
	if block.kind == "delete" then
		-- the removed text has no line in the file: show it as virtual lines,
		-- below its anchor -- or above line 1 when it was cut from the top
		local virt = {}
		for _, line in ipairs(block.removed) do
			virt[#virt + 1] = { { line == "" and " " or line, "GitStatusDelete" } }
		end
		pcall(vim.api.nvim_buf_set_extmark, buf, NS, math.min(math.max(block.after, 1), count) - 1, 0, {
			virt_lines = virt, virt_lines_above = block.after == 0,
		})
	else
		for line = block.first, math.min(block.last, count) do
			pcall(vim.api.nvim_buf_set_extmark, buf, NS, line - 1, 0, { line_hl_group = BLOCK_HL[block.kind] })
		end
	end
end

function M.open()
	local root = git_ref.root()
	if not root then
		vim.notify("Not a git repo", vim.log.levels.WARN)
		return
	end
	local base, branch = git_ref.get(root)
	local rev = base or "HEAD"
	local label = base and string.format("%s (%s)", base:sub(1, 8), branch) or rev
	local files = collect(root, rev)
	if #files == 0 then
		vim.notify("No changes vs " .. label, vim.log.levels.INFO)
		return
	end
	set_highlights()

	local marked -- buffer holding the block marks
	local shown_win -- window the block is shown in

	local function unmark()
		if marked and vim.api.nvim_buf_is_valid(marked) then
			vim.api.nvim_buf_clear_namespace(marked, NS, 0, -1)
		end
		marked = nil
	end

	-- the file in the window next to the sidebar, all its blocks marked, the
	-- row's block centered (a file row: its first block)
	local function show(node, win)
		shown_win = win
		unmark()
		local file = node.file or node
		local block = node.file and node or file.blocks[1] or file.whole
		local abs = root .. "/" .. file.path

		local buf
		if file.deleted then
			-- gone from the working tree: show the version it was deleted from --
			-- every line of it is lost, so the whole buffer is marked deleted
			local gone = vim.fn.systemlist({ "git", "-C", root, "show", rev .. ":" .. file.path })
			if vim.v.shell_error ~= 0 then return end
			buf = vim.api.nvim_create_buf(false, true)
			vim.bo[buf].bufhidden = "wipe"
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, gone)
			vim.bo[buf].modifiable = false
			vim.bo[buf].filetype = vim.filetype.match({ filename = file.path }) or ""
			vim.api.nvim_win_set_buf(win, buf)
			for line = 1, #gone do
				vim.api.nvim_buf_set_extmark(buf, NS, line - 1, 0, { line_hl_group = "GitStatusDeleteLine" })
			end
		else
			buf = vim.fn.bufadd(abs)
			if vim.api.nvim_win_get_buf(win) ~= buf then
				vim.api.nvim_win_call(win, function()
					pcall(vim.cmd, "edit " .. vim.fn.fnameescape(abs))
				end)
			end
			if vim.api.nvim_win_get_buf(win) ~= buf then return end -- edit refused
			for _, b in ipairs(file.whole and { file.whole } or file.blocks) do
				mark(buf, b)
			end
		end
		marked = buf

		if block then
			local count = vim.api.nvim_buf_line_count(buf)
			local line = block.kind == "delete" and block.after or block.lnum
			pcall(vim.api.nvim_win_set_cursor, win, { math.min(math.max(line, 1), count), 0 })
		end
		vim.api.nvim_win_call(win, function() vim.cmd("normal! zz") end)
	end

	-- open on the first block
	local first = files[1]
	local reveal = { first.path }
	if #first.blocks > 0 then
		reveal[2] = first.path .. ":" .. first.blocks[1].lnum
	end

	sidebar.open({
		filetype = "gitstatus",
		width = 40,
		root = {}, -- no row of its own
		children = function(node) return node.path and node.blocks or files end,
		is_parent = function(node) return node.path ~= nil and #node.blocks > 0 end,
		key = function(node)
			return node.file and (node.file.path .. ":" .. node.lnum) or node.path
		end,
		label = function(node)
			if node.file then
				local n = node.count
				return string.format("%d  %s %d line%s", node.lnum, ROW[node.kind][1], n, n == 1 and "" or "s")
			end
			return node.note and (node.path .. "  " .. node.note) or node.path
		end,
		highlight = function(node)
			if node.file then return ROW[node.kind][2] end
			if node.deleted then return "GitStatusGone" end
			return node.note and "Comment" or "Directory"
		end,
		reveal = reveal,
		on_move = show,
		on_open = show,
	})

	-- the sidebar is the current window now; name the repo too: it is not
	-- necessarily the one of the cwd
	sidebar.set_title(string.format("Changes vs %s  [%s]", label, vim.fs.basename(root)))
	vim.api.nvim_create_autocmd("BufWipeout", { buffer = 0, once = true, callback = unmark })
end

return M
