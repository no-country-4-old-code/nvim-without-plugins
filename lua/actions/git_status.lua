-- Command built on the list overlay: browse every changed block in the repo
-- like a rip-grep result -- one row per block, "path:line  first changed
-- line". The preview shows that file's diff with the block centered, <CR>
-- jumps to the block in the working tree, <Esc> closes.
--
-- The list comes from `git diff --unified=0` so that neighbouring changes stay
-- separate rows (the same blocks the gutter signs mark), while the preview uses
-- the normal diff, which has the context lines that make it readable.
--
-- Compared against HEAD, or against $NVIM_GIT_REF_BASE when that names a
-- branch / commit (see core.git-ref). Untracked files are listed as one entry.

local overlay = require("actions.gui.list_simple_overlay")

local M = {}

local function git_root()
	local out = vim.fn.systemlist({ "git", "rev-parse", "--show-toplevel" })
	if vim.v.shell_error ~= 0 then return nil end
	return out[1]
end

-- "path:lnum:text" -> its pieces (same shape as rg --vimgrep, on purpose)
local function parse(item)
	local path, lnum, text = item:match("^(.-):(%d+):(.*)$")
	return path, tonumber(lnum), text
end

-- new-side line range a "@@ -a,b +c,d @@" header covers (d == 0: a pure
-- deletion, which sits right after line c)
local function hunk_range(header)
	local start, count = header:match("^@@ %-%S+ %+(%d+),?(%d*)")
	start = math.max(tonumber(start) or 1, 1)
	count = tonumber(count) or 1 -- "+12" without a count means one line
	return start, count == 0 and start or start + count - 1
end

-- first changed line of a hunk: walk from its "@@" header over the leading
-- context, counting up from the hunk's start line in the new file. The label
-- prefers the "+" line of that block -- that is what the file holds now; only
-- a pure deletion falls back to the removed "-" line.
local function first_change(diff, header, start)
	local lnum, text, n = nil, "", start
	for i = header + 1, #diff do
		local c = diff[i]:sub(1, 1)
		if c == "+" or c == "-" then
			if not lnum then lnum, text = math.max(n, 1), diff[i] end
			if c == "+" then return lnum, vim.trim(diff[i]) end
		elseif c == " " then
			if lnum then break end -- past the first changed block of the hunk
			n = n + 1
		else
			break -- end of the hunk ("\ No newline...", next header, next file)
		end
	end
	return lnum or math.max(n, 1), vim.trim(text)
end

-- row of the block that starts at new-side line `lnum` inside `hunk`, so that a
-- hunk holding several blocks centers on the one that was picked. Walks the
-- hunk body, counting the new-side lines ("+" and context; "-" lines are gone
-- from the new file and stay on the position they were removed from).
local function block_row(lines, hunk, lnum)
	local n = hunk.first
	for row = hunk.row + 1, #lines do
		local c = lines[row]:sub(1, 1)
		if c == "+" or c == "-" then
			if n >= lnum then return row end
			if c == "+" then n = n + 1 end
		elseif c == " " or c == "" then
			if n > lnum then break end
			n = n + 1
		else
			break -- next hunk ("@@"), "\ No newline...", end of the section
		end
	end
	return hunk.row
end

--- cut a `git diff` into per-file sections, each with the rows of its hunk headers
local function split_files(diff)
	local order, cur = {}, nil
	for i, line in ipairs(diff) do
		if line:sub(1, 11) == "diff --git " then
			cur = {
				first = i,
				-- "a/<path> b/<path>" -- renames name the new path second
				path = line:match("^diff %-%-git a/.* b/(.*)$") or line:sub(12),
				hunks = {},
			}
			order[#order + 1] = cur
		elseif cur and line:sub(1, 2) == "@@" then
			cur.hunks[#cur.hunks + 1] = i
		elseif cur and line:sub(1, 13) == "Binary files " then
			cur.binary = true
		end
	end
	for n, sec in ipairs(order) do
		sec.last = order[n + 1] and order[n + 1].first - 1 or #diff
	end
	return order
end

--- one item per changed block + the per-file diff shown next to it
--- @return string[] items, table sections
---   -- path -> { lines, hunks[i] = { row, first, last } } of the context diff
local function collect(root, rev)
	local diff = vim.fn.systemlist({ "git", "-C", root, "diff", rev })
	local blocks = vim.fn.systemlist({ "git", "-C", root, "diff", "--unified=0", rev })
	local items, sections = {}, {}

	-- preview side: the readable diff, with each hunk's own line range
	for _, sec in ipairs(split_files(diff)) do
		sections[sec.path] = sec
		sec.lines = vim.list_slice(diff, sec.first, sec.last)
		for n, header in ipairs(sec.hunks) do
			local first, last = hunk_range(diff[header])
			sec.hunks[n] = { row = header - sec.first + 1, first = first, last = last }
		end
	end

	-- list side: every block, even ones the context diff merges into one hunk
	for _, sec in ipairs(split_files(blocks)) do
		if #sec.hunks == 0 then -- binary file, rename without edits, mode change
			items[#items + 1] = string.format("%s:1:%s", sec.path, sec.binary and "(binary)" or "(no line changes)")
		end
		for _, header in ipairs(sec.hunks) do
			local lnum, text = first_change(blocks, header, (hunk_range(blocks[header])))
			items[#items + 1] = string.format("%s:%d:%s", sec.path, lnum, text)
		end
	end

	for _, path in ipairs(vim.fn.systemlist({ "git", "-C", root, "ls-files", "--others", "--exclude-standard" })) do
		items[#items + 1] = string.format("%s:1:%s", path, "(untracked)")
	end

	return items, sections
end

function M.open()
	local root = git_root()
	if not root then
		vim.notify("Not a git repo", vim.log.levels.WARN)
		return
	end
	local rev = require("core.git-ref").get(root) or "HEAD"
	local items, sections = collect(root, rev)

	overlay.open({
		title = "Git changes vs " .. rev,
		start_on_list = true, -- focus starts on the list, not the filter box
		items = items,
		display = function(item)
			local path, lnum, text = parse(item)
			if not path then return item end
			return string.format("%s:%d  %s", path, lnum, text)
		end,
		preview = function(item)
			local path, lnum = parse(item)
			local sec = path and sections[path]
			if sec then -- the file's diff, centered on this block
				local found
				for _, hunk in ipairs(sec.hunks) do
					if hunk.first <= lnum then found = hunk end
					if hunk.last >= lnum then break end
				end
				return sec.lines, "diff", path, found and block_row(sec.lines, found, lnum)
			end
			if not path then return { "-- no diff --" } end
			return vim.fn.readfile(root .. "/" .. path, "", 500),
				vim.filetype.match({ filename = path }), path
		end,
		on_select = function(item)
			local path, lnum = parse(item)
			if not path then return end
			vim.cmd("edit " .. vim.fn.fnameescape(root .. "/" .. path))
			pcall(vim.api.nvim_win_set_cursor, 0, { lnum or 1, 0 })
		end,
	})
end

return M
