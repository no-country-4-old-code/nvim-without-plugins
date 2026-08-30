-- Jump to the next / previous function definition in C and C++ files
-- (replaces treesitter-textobjects' ]f / [f moves).
--
-- The definition lines come from clangd's document symbols -- the only source
-- that understands C++ (methods, constructors, templates); nvim bundles a
-- treesitter parser for C but not for C++. Without a language server the
-- bundled C parser is used instead, so plain C still works with no clangd.
--
-- Keys are mapped per buffer in core.key-mappings (t / T).

local M = {}

local TIMEOUT = 500 -- ms to wait for the server's symbol list

-- symbol kinds that count as "a function definition" (LSP SymbolKind)
local KINDS = { [6] = true, [9] = true, [12] = true } -- method, constructor, function

-- a definition, not a prototype: the symbol's range ends on the body's closing
-- brace, while a declaration's ends on its ";"
local function has_body(buf, range)
	local last = vim.api.nvim_buf_get_lines(buf, range["end"].line, range["end"].line + 1, false)[1]
	return last ~= nil and last:find("}", 1, true) ~= nil
end

--- definition lines from the language server, nil when none can answer
--- @return table|nil { { line, col }, ... }
local function from_lsp(buf)
	if #vim.lsp.get_clients({ bufnr = buf, method = "textDocument/documentSymbol" }) == 0 then
		return nil
	end
	local res = vim.lsp.buf_request_sync(buf, "textDocument/documentSymbol", {
		textDocument = vim.lsp.util.make_text_document_params(buf),
	}, TIMEOUT)
	if not res then return nil end

	local spots = {}
	local function walk(symbols)
		for _, sym in ipairs(symbols or {}) do
			-- selectionRange is the name itself; SymbolInformation has no
			-- children and carries its range inside "location"
			local extent = sym.range or (sym.location or {}).range
			local name = sym.selectionRange or extent
			if KINDS[sym.kind] and extent and has_body(buf, extent) then
				spots[#spots + 1] = { name.start.line + 1, name.start.character }
			end
			walk(sym.children)
		end
	end
	for _, r in pairs(res) do
		walk(r.result)
	end
	return spots
end

--- same list from the buffer's treesitter tree (C grammar), nil without a parser
local function from_treesitter(buf)
	local ok, parser = pcall(vim.treesitter.get_parser, buf)
	if not ok or not parser then return nil end
	local ok_query, query = pcall(vim.treesitter.query.parse, parser:lang(), "(function_definition) @f")
	if not ok_query then return nil end

	local spots = {}
	for _, node in query:iter_captures(parser:parse()[1]:root(), buf) do
		local line, col = node:start()
		spots[#spots + 1] = { line + 1, col }
	end
	return spots
end

--- @param dir integer 1 = next definition, -1 = previous one
function M.jump(dir)
	local buf = vim.api.nvim_get_current_buf()
	local spots = from_lsp(buf) or from_treesitter(buf)
	if not spots or #spots == 0 then
		vim.notify("No function definitions found (clangd not running?)", vim.log.levels.WARN)
		return
	end
	table.sort(spots, function(a, b) return a[1] < b[1] end)

	local target
	for _ = 1, vim.v.count1 do -- 3t: three definitions further down
		local from = target and target[1] or vim.api.nvim_win_get_cursor(0)[1]
		local step = nil
		for _, spot in ipairs(spots) do -- sorted: keep the closest one past the cursor
			if dir > 0 and spot[1] > from then
				step = spot
				break
			elseif dir < 0 and spot[1] < from then
				step = spot
			end
		end
		if not step then break end
		target = step
	end
	if not target then return end -- nothing further in that direction: stay put

	vim.cmd("normal! m'") -- leave a jump behind, so CTRL-O comes back here
	vim.api.nvim_win_set_cursor(0, { target[1], target[2] })
end

return M
