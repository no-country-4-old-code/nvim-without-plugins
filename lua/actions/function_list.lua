-- Command built on the nested sidebar: every function of the current file --
-- definitions and declarations (prototypes), in file order, one row each.
-- The cursor opens on the function it was in; j / k walk from function start
-- to function start and the window next to the sidebar follows. Declarations
-- are painted dimmer than definitions. <CR> / o jump there and close the list,
-- <Esc> closes it. u switches to the list of the paired header / source file
-- (foo.c <-> foo.h) and shows that file; u again switches back.
--
-- The functions come from the language server's document symbols (methods and
-- constructors of C++ classes included); without a server the bundled
-- treesitter parser is used instead, so plain C still works with no clangd.

local sidebar = require("actions.gui.list_nested_sidebar")

local M = {}

local TIMEOUT = 1000 -- ms to wait for the server's symbol list

-- symbol kinds that count as "a function" (LSP SymbolKind)
local KINDS = { [6] = true, [9] = true, [12] = true } -- method, constructor, function

-- a definition, not a prototype: its range ends on the body's closing brace,
-- a declaration's on its ";" (same rule as custom.goto-function)
local function has_body(buf, last_line)
	local last = vim.api.nvim_buf_get_lines(buf, last_line, last_line + 1, false)[1]
	return last ~= nil and last:find("}", 1, true) ~= nil
end

-- fn = { name, line + col = name position (0-based), first = first line, body }
local function from_lsp(buf)
	if #vim.lsp.get_clients({ bufnr = buf, method = "textDocument/documentSymbol" }) == 0 then
		return nil
	end
	local res = vim.lsp.buf_request_sync(buf, "textDocument/documentSymbol", {
		textDocument = vim.lsp.util.make_text_document_params(buf),
	}, TIMEOUT)
	if not res then return nil end

	local fns = {}
	local function walk(symbols)
		for _, sym in ipairs(symbols or {}) do
			-- SymbolInformation has no children and its range sits in "location"
			local extent = sym.range or (sym.location or {}).range
			local at = (sym.selectionRange or extent).start
			if KINDS[sym.kind] and extent then
				fns[#fns + 1] = {
					name = sym.name, line = at.line, col = at.character,
					first = extent.start.line,
					body = has_body(buf, extent["end"].line),
				}
			end
			walk(sym.children)
		end
	end
	for _, r in pairs(res) do
		walk(r.result)
	end
	return fns
end

-- same list from the buffer's treesitter tree (C grammar), nil without a parser
local function from_treesitter(buf)
	local ok, parser = pcall(vim.treesitter.get_parser, buf)
	if not ok or not parser then return nil end
	local ok_query, query = pcall(vim.treesitter.query.parse, parser:lang(),
		"(function_declarator declarator: (_) @name)")
	if not ok_query then return nil end

	local fns = {}
	for _, node in query:iter_captures(parser:parse()[1]:root(), buf) do
		local line, col = node:start()
		-- the whole definition / declaration around the declarator
		local outer = node:parent()
		while outer:parent() and outer:parent():type() ~= "translation_unit" do
			outer = outer:parent()
		end
		fns[#fns + 1] = {
			name = vim.treesitter.get_node_text(node, buf), line = line, col = col,
			first = (outer:start()),
			body = outer:type() == "function_definition",
		}
	end
	return fns
end

local HEADERS = { "h", "hpp", "hh", "hxx" }
local SOURCES = { "c", "cpp", "cc", "cxx" }

-- path of the header of a source file or the other way round, nil if none:
-- clangd knows (switchSourceHeader), else a same-named file in the same folder
local function paired_file(buf)
	for _, client in ipairs(vim.lsp.get_clients({ bufnr = buf, name = "clangd" })) do
		local res = client:request_sync("textDocument/switchSourceHeader",
			vim.lsp.util.make_text_document_params(buf), TIMEOUT, buf)
		if res and type(res.result) == "string" then return vim.uri_to_fname(res.result) end
	end
	local name = vim.api.nvim_buf_get_name(buf)
	local ext = vim.fn.fnamemodify(name, ":e")
	local stem = vim.fn.fnamemodify(name, ":r")
	local others = vim.tbl_contains(HEADERS, ext) and SOURCES
		or vim.tbl_contains(SOURCES, ext) and HEADERS or {}
	for _, e in ipairs(others) do
		if vim.fn.filereadable(stem .. "." .. e) == 1 then return stem .. "." .. e end
	end
end

-- the functions of buf in file order, nil when there are none
local function functions(buf)
	local fns = from_lsp(buf) or from_treesitter(buf)
	if not fns or #fns == 0 then return nil end
	table.sort(fns, function(a, b) return a.line < b.line end)
	return fns
end

-- the list of buf's functions, opened from win (showing buf)
local function open_list(buf, fns, win)
	-- open on the function the cursor is in, else the one above it: the last
	-- one starting at or before the cursor line
	local cur = vim.api.nvim_win_get_cursor(win)[1] - 1
	local here
	for _, fn in ipairs(fns) do
		if fn.first <= cur then here = fn end
	end

	local function key(fn) return fn.name .. ":" .. fn.line end
	local shown_win = win -- window the function is shown in

	local function show(fn, win)
		shown_win = win
		if vim.api.nvim_win_get_buf(win) ~= buf then vim.api.nvim_win_set_buf(win, buf) end
		pcall(vim.api.nvim_win_set_cursor, win, { fn.line + 1, fn.col })
		vim.api.nvim_win_call(win, function() vim.cmd("normal! zz") end)
	end

	local function jump(_, close)
		close()
		if shown_win and vim.api.nvim_win_is_valid(shown_win) then
			vim.api.nvim_set_current_win(shown_win)
		end
	end

	sidebar.open({
		filetype = "functionlist",
		width = 35,
		root = {}, -- no row of its own
		children = function() return fns end, -- rows are leaves: only the root asks
		key = key,
		label = function(fn) return fn.name end,
		highlight = function(fn) return fn.body and "Function" or "FunctionListDecl" end,
		reveal = here and { key(here) } or nil,
		on_move = show,
		on_open = show,
		keys = { ["<CR>"] = jump, o = jump, u = function(_, close)
			local name = vim.api.nvim_buf_get_name(buf)
			local path = paired_file(buf)
			if not path then
				vim.notify("No header / source for " .. vim.fn.fnamemodify(name, ":t"), vim.log.levels.WARN)
				return
			end
			local other = vim.fn.bufadd(path)
			vim.fn.bufload(other)
			vim.bo[other].buflisted = true
			local other_fns = functions(other)
			if not other_fns then
				vim.notify("No functions in " .. vim.fn.fnamemodify(path, ":t"), vim.log.levels.WARN)
				return
			end
			close()
			if not vim.api.nvim_win_is_valid(shown_win) then return end
			vim.api.nvim_set_current_win(shown_win)
			vim.api.nvim_win_set_buf(shown_win, other)
			open_list(other, other_fns, shown_win)
		end },
	})
	sidebar.set_title("Functions in " .. vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":t"))
end

function M.open()
	vim.api.nvim_set_hl(0, "FunctionListDecl", { link = "Comment" })

	local buf = vim.api.nvim_get_current_buf()
	local fns = functions(buf)
	if not fns then
		vim.notify("No functions found (language server running?)", vim.log.levels.WARN)
		return
	end
	vim.cmd("normal! m'") -- <CR> jumps away: CTRL-O comes back here
	open_list(buf, fns, vim.api.nvim_get_current_win())
end

return M
