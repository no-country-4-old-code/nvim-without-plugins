-- Command built on the nested sidebar: the call tree of the function the cursor
-- is in -- the file tree's keys, but for calls.
--
--   down  (opens like this) every call made by the function, one row per call
--         site -- a function called on three lines shows three times.
--         l unfolds a row into the calls *that* function makes, and so on.
--   up    h on a top-level row with nothing left to fold: the tree re-opens
--         the other way round -- every place the root function is called from,
--         and l unfolds a caller into its own callers.
--
-- j / k move and the window next to the sidebar follows: it shows the call
-- site of the row (the line in the function one level up), the call marked.
-- <CR> / o jump there and close the tree, <Esc> closes it.
--
-- Rows painted red cannot be unfolded: the function calls nothing (down), is
-- called by nobody (up), or the server could not resolve it (a macro, a
-- function pointer, a library function known only by its prototype).
--
-- "Calls made" come from a plain text scan of the body for `name(` -- clangd
-- before 20 does not answer callHierarchy/outgoingCalls -- and the server
-- resolves each hit (definition, then prepareCallHierarchy there, so the item
-- covers the body and not a prototype in a header). "Called from" is the
-- server's callHierarchy/incomingCalls.

local sidebar = require("actions.gui.list_nested_sidebar")

local M = {}

local TIMEOUT = 1000 -- ms per server request
local NS = vim.api.nvim_create_namespace("call_tree")

-- symbol kinds that count as "a function" (LSP SymbolKind)
local KINDS = { [6] = true, [9] = true, [12] = true } -- method, constructor, function

-- `word(` that is no call
local KEYWORDS = {}
for _, k in ipairs({ "if", "for", "while", "switch", "return", "sizeof", "alignof",
	"decltype", "catch", "noexcept", "elif", "not", "and", "or", "in", "match",
	"function", "lambda", "defined" }) do
	KEYWORDS[k] = true
end

local function set_highlights()
	vim.api.nvim_set_hl(0, "CallTreeEnd", { fg = "#f7768e" }) -- tokyonight red
	vim.api.nvim_set_hl(0, "CallTreeCall", { bg = "#3d59a1" })
end

-- first answer of the servers attached to buf, nil when none has one
local function request(buf, method, params)
	local res = vim.lsp.buf_request_sync(buf, method, params, TIMEOUT)
	for _, r in pairs(res or {}) do
		if r.result and not vim.tbl_isempty(r.result) then return r.result end
	end
end

-- the file's buffer, loaded -- the server only answers for files it has open,
-- and loading one attaches it (FileType)
local function load(uri)
	local buf = vim.uri_to_bufnr(uri)
	vim.fn.bufload(buf)
	return buf
end

local function position(buf, line, col)
	return { textDocument = { uri = vim.uri_from_bufnr(buf) }, position = { line = line, character = col } }
end

-- call hierarchy item of the function named at line/col, nil if there is none
local function prepare(buf, line, col)
	local items = request(buf, "textDocument/prepareCallHierarchy", position(buf, line, col))
	return items and items[1]
end

-- the function called at line/col, as the item of its *definition*
local function resolve(buf, line, col)
	local loc = request(buf, "textDocument/definition", position(buf, line, col))
	loc = loc and (loc[1] or loc) -- Location | Location[] | LocationLink[]
	if loc and (loc.uri or loc.targetUri) then
		local r = loc.targetSelectionRange or loc.range
		return prepare(load(loc.uri or loc.targetUri), r.start.line, r.start.character)
	end
	return prepare(buf, line, col)
end

-- `name(` spots in the body of item (after its name, up to its end), skipping
-- comment lines and string contents: { line, col, name } 0-based
local function call_spots(item)
	local buf = load(item.uri)
	local from, to = item.selectionRange["end"], item.range["end"].line
	local spots = {}
	for i, text in ipairs(vim.api.nvim_buf_get_lines(buf, from.line, to + 1, false)) do
		local line = from.line + i - 1
		local skip = line == from.line and from.character or 0
		text = text:gsub("//.*$", "") -- trailing comment
		if not (text:match("^%s*/?%*") or text:match("^%s*#")) then
			for col, name in text:gmatch("()([%a_][%w_]*)%s*%(") do
				local quotes = select(2, text:sub(1, col - 1):gsub('"', ""))
				if col > skip and not KEYWORDS[name] and quotes % 2 == 0 then
					spots[#spots + 1] = { line = line, col = col - 1, name = name }
				end
			end
		end
	end
	return buf, spots
end

-- node = { item = hierarchy item of the row's function (nil: unresolved),
--          name, uri + range = the call site shown next to the tree, key }
local function node(parent, item, name, uri, range)
	return {
		item = item,
		name = name,
		uri = uri,
		range = range,
		key = ("%s/%s@%s:%d:%d"):format(parent.key, name, uri, range.start.line, range.start.character),
	}
end

-- down: the calls parent's function makes, in the order they appear
local function callees(parent)
	local buf, spots = call_spots(parent.item)
	local out = {}
	for _, s in ipairs(spots) do
		local range = {
			start = { line = s.line, character = s.col },
			["end"] = { line = s.line, character = s.col + #s.name },
		}
		out[#out + 1] = node(parent, resolve(buf, s.line, s.col), s.name, parent.item.uri, range)
	end
	return out
end

-- up: every call site of parent's function, by file and line
local function callers(parent)
	local calls = request(load(parent.item.uri), "callHierarchy/incomingCalls", { item = parent.item })
	local out = {}
	for _, call in ipairs(calls or {}) do
		for _, range in ipairs(call.fromRanges) do
			out[#out + 1] = node(parent, call.from, call.from.name, call.from.uri, range)
		end
	end
	table.sort(out, function(a, b)
		if a.uri ~= b.uri then return a.uri < b.uri end
		return a.range.start.line < b.range.start.line
	end)
	return out
end

-- item of the function the cursor is in (innermost one), else of the function
-- named under the cursor
local function current_function()
	local buf = vim.api.nvim_get_current_buf()
	local line, col = unpack(vim.api.nvim_win_get_cursor(0))
	line = line - 1
	local best
	local function walk(symbols)
		for _, s in ipairs(symbols or {}) do
			local r = s.range or (s.location or {}).range
			if r and r.start.line <= line and line <= r["end"].line then
				if KINDS[s.kind] then best = s.selectionRange or r end
				walk(s.children)
			end
		end
	end
	walk(request(buf, "textDocument/documentSymbol", { textDocument = { uri = vim.uri_from_bufnr(buf) } }))
	if best then return prepare(buf, best.start.line, best.start.character) end
	return prepare(buf, line, col)
end

-- mode = "down" | "up"
local function open_tree(root, mode)
	set_highlights()
	local kids, calls_any = {}, {} -- caches: render asks again on every fold
	local marked -- buffer holding the call mark
	local shown_win -- window the call site is shown in

	local function children(n)
		if not kids[n.key] then
			kids[n.key] = n.item and (mode == "down" and callees or callers)(n) or {}
		end
		return kids[n.key]
	end

	-- down only needs to know *whether* there are calls -- the cheap text scan,
	-- nothing resolved until the row is unfolded
	local function is_parent(n)
		if not n.item then return false end
		if mode == "up" then return #children(n) > 0 end
		if calls_any[n.key] == nil then
			calls_any[n.key] = #select(2, call_spots(n.item)) > 0
		end
		return calls_any[n.key]
	end

	local function unmark()
		if marked and vim.api.nvim_buf_is_valid(marked) then
			vim.api.nvim_buf_clear_namespace(marked, NS, 0, -1)
		end
		marked = nil
	end

	-- the call site in the window next to the tree, call marked, line centered
	local function show(n, win)
		shown_win = win
		unmark()
		vim.api.nvim_win_call(win, function()
			local buf = vim.uri_to_bufnr(n.uri)
			if vim.api.nvim_get_current_buf() ~= buf then
				pcall(vim.cmd, "edit " .. vim.fn.fnameescape(vim.uri_to_fname(n.uri)))
			end
			if vim.api.nvim_get_current_buf() ~= buf then return end
			local s, e = n.range.start, n.range["end"]
			pcall(vim.api.nvim_win_set_cursor, win, { s.line + 1, s.character })
			vim.cmd("normal! zz")
			marked = buf
			pcall(vim.api.nvim_buf_set_extmark, buf, NS, s.line, s.character, {
				end_row = e.line, end_col = e.character, hl_group = "CallTreeCall",
			})
		end)
	end

	local function jump(n, close)
		close()
		if shown_win and vim.api.nvim_win_is_valid(shown_win) then
			vim.api.nvim_set_current_win(shown_win)
		end
	end

	sidebar.open({
		filetype = "calltree",
		width = 35,
		root = { item = root, key = "" }, -- no row of its own
		key = function(n) return n.key end,
		label = function(n) return ("%s :%d"):format(n.name, n.range.start.line + 1) end,
		highlight = function(n) return is_parent(n) and "Function" or "CallTreeEnd" end,
		is_parent = is_parent,
		children = children,
		on_move = show,
		keys = { ["<CR>"] = jump, o = jump },
		-- h at the top: who calls it. not scheduled -- the server requests wait
		-- with vim.wait, which would run a second queued switch in the middle
		on_collapse_root = mode == "down" and function() open_tree(root, "up") end or nil,
	})

	-- the sidebar is the current window now
	vim.wo.winbar = (" %s %s"):format(mode == "down" and "calls in" or "callers of", root.name)
	vim.api.nvim_create_autocmd("BufWipeout", { buffer = 0, once = true, callback = unmark })
end

function M.open()
	local root = current_function()
	if not root then
		vim.notify("Call tree: no function here (language server running?)", vim.log.levels.WARN)
		return
	end
	vim.cmd("normal! m'") -- <CR> jumps away: CTRL-O comes back here
	open_tree(root, "down")
end

return M
