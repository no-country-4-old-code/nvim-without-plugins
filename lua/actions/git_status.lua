-- Command built on the list overlay: browse every changed block in the repo
-- like a rip-grep result -- one row per block, "path:line  first changed
-- line". The preview shows the file itself (highlighted code, not a diff)
-- centered on that block, <CR> jumps to the block in the working tree,
-- <Esc> closes.
--
-- The list comes from `git diff --unified=0` so that neighbouring changes stay
-- separate rows -- the same blocks the gutter signs mark.
--
-- The repo is the one the current file lives in (core.git-ref.root), so calling
-- this from a file outside the working directory shows *its* checkout's changes.
--
-- Compared against HEAD, or against $NVIM_GIT_REF_BASE when that names a
-- branch / commit (see core.git-ref). Untracked files are listed as one entry.

local overlay = require("actions.gui.list_simple_overlay")
local git_ref = require("core.git-ref")

local M = {}

local CONTEXT = 200 -- lines read past the block, so the preview can center it

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
		end
	end
	return order
end

--- one item per changed block: every block, even ones a context diff would
--- merge into a single hunk
--- @return string[] items
local function collect(root, rev)
	local blocks = vim.fn.systemlist({ "git", "-C", root, "diff", "--unified=0", rev })
	local items = {}

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

	return items
end

function M.open()
	local root = git_ref.root()
	if not root then
		vim.notify("Not a git repo", vim.log.levels.WARN)
		return
	end
	local rev = git_ref.get(root) or "HEAD"

	overlay.open({
		-- name the repo too: it is not necessarily the one of the cwd
		title = string.format("Git changes vs %s  [%s]", rev, vim.fs.basename(root)),
		start_on_list = true, -- focus starts on the list, not the filter box
		items = collect(root, rev),
		display = function(item)
			local path, lnum, text = parse(item)
			if not path then return item end
			return string.format("%s:%d  %s", path, lnum, text)
		end,
		preview = function(item)
			local path, lnum, text = parse(item)
			if not path then return { "-- no file --" } end
			if text == "(binary)" then return { "-- binary file --" } end
			local file = root .. "/" .. path
			local ft = vim.filetype.match({ filename = path })
			if vim.fn.filereadable(file) == 0 then
				-- gone from the working tree: show the version it was deleted from
				local old = vim.fn.systemlist({ "git", "-C", root, "show", rev .. ":" .. path })
				if vim.v.shell_error ~= 0 then return { "-- not readable --" } end
				return old, ft, path .. "  (deleted)", lnum
			end
			-- read past the block so it can be centered
			return vim.fn.readfile(file, "", (lnum or 1) + CONTEXT), ft, path, lnum
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
