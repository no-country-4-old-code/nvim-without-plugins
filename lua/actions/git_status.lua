-- Command built on the list overlay: browse every changed block in the repo
-- like a rip-grep result -- one row per block, "path:line  first changed
-- line". The preview shows the file itself (highlighted code, not a diff)
-- centered on that block, with the whole block marked: green for added lines,
-- the normal focus highlight for changed ones, and -- since removed text has
-- no line of its own left -- red "ghost lines" (virtual lines: no number, not
-- part of the buffer) for a deletion. <CR> jumps to the block in the working
-- tree, <Esc> closes.
--
-- The list comes from `git diff --unified=0` so that neighbouring changes stay
-- separate rows -- the same blocks the gutter signs mark.
--
-- The repo is the one the current file lives in (core.git-ref.root), so calling
-- this from a file outside the working directory shows *its* checkout's changes.
--
-- Compared against HEAD, or against `git.ref_base` when that names a
-- branch / commit (see core.git-ref). Untracked files are listed as one entry.

local overlay = require("actions.gui.list_simple_overlay")
local git_ref = require("core.git-ref")

local M = {}

local CONTEXT = 200 -- lines read past the block, so the preview can center it

-- tokyonight diff colours; the changed block keeps the overlay's own focus
-- highlight, so only "added" and "deleted" need a group of their own
local function set_highlights()
	vim.api.nvim_set_hl(0, "GitStatusPreviewAdd", { bg = "#20303b" })
	vim.api.nvim_set_hl(0, "GitStatusPreviewDelete", { fg = "#f7768e", bg = "#37222c" })
	-- background only: whole lines that are shown as deleted keep their syntax colours
	vim.api.nvim_set_hl(0, "GitStatusPreviewDeleteLine", { bg = "#37222c" })
end

local BLOCK_HL = { add = "GitStatusPreviewAdd", change = "ListOverlayMatch" }

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
		end
	end
	return order
end

--- one item per changed block: every block, even ones a context diff would
--- merge into a single hunk
--- @return string[] items, table blocks
---   -- "path:lnum" -> what the preview marks: { kind = "add"|"change"|"delete",
---   --   first, last = the block's lines in the working tree (add/change),
---   --   after, removed = anchor line + the lost text (delete) }
local function collect(root, rev)
	local diff = vim.fn.systemlist({ "git", "-C", root, "diff", "--unified=0", rev })
	local items, blocks = {}, {}

	for _, sec in ipairs(split_files(diff)) do
		if #sec.hunks == 0 then -- binary file, rename without edits, mode change
			items[#items + 1] = string.format("%s:1:%s", sec.path, sec.binary and "(binary)" or "(no line changes)")
		end
		for _, header in ipairs(sec.hunks) do
			local first, last = hunk_range(diff[header])
			local lnum, text = first_change(diff, header, first)
			local removed, added = hunk_body(diff, header)
			items[#items + 1] = string.format("%s:%d:%s", sec.path, lnum, text)
			blocks[string.format("%s:%d", sec.path, lnum)] = {
				kind = (added == 0 and "delete") or (#removed == 0 and "add") or "change",
				first = first, last = last,
				-- a deletion is written as "+c,0": the text sat after new-side line
				-- c, and c == 0 means it sat above the first line
				after = tonumber(diff[header]:match("%+(%d+)")) or 0,
				removed = removed,
			}
		end
	end

	for _, path in ipairs(vim.fn.systemlist({ "git", "-C", root, "ls-files", "--others", "--exclude-standard" })) do
		items[#items + 1] = string.format("%s:1:%s", path, "(untracked)")
		-- nothing of it is in the ref: the whole file is one added block
		blocks[path .. ":1"] = { kind = "add", first = 1, last = math.huge }
	end

	return items, blocks
end

--- extmarks that mark `block` in the previewed file (see the overlay's `preview`)
local function block_marks(block, count)
	local marks = {}
	if block.kind == "delete" then
		-- the removed text has no line in the file: show it as virtual lines,
		-- below its anchor -- or above line 1 when it was cut from the top
		local virt = {}
		for _, line in ipairs(block.removed) do
			virt[#virt + 1] = { { line == "" and " " or line, "GitStatusPreviewDelete" } }
		end
		marks[1] = {
			line = math.max(block.after, 1),
			opts = { virt_lines = virt, virt_lines_above = block.after == 0 },
		}
	else
		for line = block.first, math.min(block.last, count) do
			marks[#marks + 1] = { line = line, opts = { line_hl_group = BLOCK_HL[block.kind] } }
		end
	end
	return marks
end

function M.open()
	local root = git_ref.root()
	if not root then
		vim.notify("Not a git repo", vim.log.levels.WARN)
		return
	end
	local rev = git_ref.get(root) or "HEAD"
	local items, blocks = collect(root, rev)
	set_highlights()

	overlay.open({
		-- name the repo too: it is not necessarily the one of the cwd
		title = string.format("Git changes vs %s  [%s]", rev, vim.fs.basename(root)),
		start_on_list = true, -- focus starts on the list, not the filter box
		items = items,
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
				-- gone from the working tree: show the version it was deleted from --
				-- every line of it is lost, so the whole preview is marked deleted
				local gone = vim.fn.systemlist({ "git", "-C", root, "show", rev .. ":" .. path })
				if vim.v.shell_error ~= 0 then return { "-- not readable --" } end
				gone = vim.list_slice(gone, 1, (lnum or 1) + CONTEXT)
				local marks = {}
				for line = 1, #gone do
					marks[line] = { line = line, opts = { line_hl_group = "GitStatusPreviewDeleteLine" } }
				end
				return gone, ft, path .. "  (deleted)", lnum, marks
			end
			-- read past the block so it can be centered
			local lines = vim.fn.readfile(file, "", (lnum or 1) + CONTEXT)
			local block = blocks[string.format("%s:%d", path, lnum)]
			return lines, ft, path, lnum, block and block_marks(block, #lines)
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
