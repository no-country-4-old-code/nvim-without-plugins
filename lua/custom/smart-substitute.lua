-- :S/old/new -- substitute that keeps the case shape of every match
-- (replaces abolish.vim's :Subvert/:S). Matching is case-insensitive,
-- the replacement adopts the case of the text it replaces:
--   memory -> mem     Memory -> Mem     MEMORY -> MEM
-- Partial words are matched too: memory_miau -> mem_miau.
-- Live preview while typing works like :%s (see 'inccommand'): matches are
-- highlighted while the pattern is typed, replacements once /new follows.

local M = {}

local function plural(n, word)
	return n .. " " .. word .. (n == 1 and "" or "s")
end

local function capitalize(s)
	return s:sub(1, 1):upper() .. s:sub(2)
end

-- shape `rep` like the matched text
local function reshape(match, rep)
	if match == match:lower() then return rep end
	if match == match:upper() and #match > 1 then return rep:upper() end
	if match:sub(2) == match:sub(2):lower() then return capitalize(rep) end
	return rep
end

-- split "/old/new" (any delimiter, trailing one optional); while the command
-- is still being typed there may be no replacement yet
local function parse(args)
	local delim = args:sub(1, 1)
	if delim == "" or delim:match("[%w\\|\"]") then return nil end
	local parts = vim.split(args:sub(2), delim, { plain = true })
	if parts[1] == "" then return nil end
	return parts[1], parts[2]
end

-- byte ranges of every match in `line`
local function find(line, re)
	local spans, from = {}, 0
	while true do
		local s, e = re:match_str(line:sub(from + 1))
		if not s or e == s then break end
		spans[#spans + 1] = { from + s, from + e }
		from = from + e
	end
	return spans
end

-- returns the new line and the byte ranges the replacements occupy in it
local function substitute(line, re, rep)
	local spans = find(line, re)
	if #spans == 0 then return nil end
	local out, new_spans, last, shift = {}, {}, 0, 0
	for _, span in ipairs(spans) do
		local new = reshape(line:sub(span[1] + 1, span[2]), rep)
		out[#out + 1] = line:sub(last + 1, span[1])
		out[#out + 1] = new
		new_spans[#new_spans + 1] = { span[1] + shift, span[1] + shift + #new }
		shift = shift + #new - (span[2] - span[1])
		last = span[2]
	end
	out[#out + 1] = line:sub(last + 1)
	return table.concat(out), #spans, new_spans
end

-- applies the substitution to opts' range; when `ns` is given nothing is
-- reported but the touched text is highlighted (used for the live preview).
-- Without a replacement only the matches are highlighted, like :s/pattern.
local function apply(opts, ns)
	local pat, rep = parse(opts.args)
	if not pat then return nil, "expected :S/old/new" end
	local ok, re = pcall(vim.regex, "\\c" .. pat)
	if not ok then return nil, "bad pattern: " .. pat end
	local buf = vim.api.nvim_get_current_buf()
	local lines = vim.api.nvim_buf_get_lines(buf, opts.line1 - 1, opts.line2, false)
	local cursor = ns and vim.api.nvim_win_get_cursor(0)
	local total, changed, at_cursor = 0, 0, false
	for i, line in ipairs(lines) do
		local lnum = opts.line1 + i - 2
		local spans
		if rep then
			local new, count, moved = substitute(line, re, rep)
			if new then
				vim.api.nvim_buf_set_lines(buf, lnum, lnum + 1, false, { new })
				total, changed, spans = total + count, changed + 1, moved
			end
		else
			spans = find(line, re)
			total, changed = total + #spans, changed + math.min(#spans, 1)
		end
		for _, span in ipairs(ns and spans or {}) do
			local hl = "Substitute"
			if not rep then -- pattern only: look like incsearch
				hl = "Search"
				if not at_cursor and (lnum > cursor[1] - 1 or (lnum == cursor[1] - 1 and span[2] > cursor[2])) then
					hl, at_cursor = "IncSearch", true
				end
			end
			vim.api.nvim_buf_set_extmark(buf, ns, lnum, span[1], { end_col = span[2], hl_group = hl })
		end
	end
	return total, changed, pat, rep
end

function M.setup()
	vim.api.nvim_create_user_command("S", function(opts)
		local total, changed, pat, rep = apply(opts)
		if not total then
			vim.notify("S: " .. changed, vim.log.levels.ERROR)
		elseif not rep then
			vim.notify("S: expected :S/old/new", vim.log.levels.ERROR)
		elseif total == 0 then
			vim.notify("S: pattern not found: " .. pat, vim.log.levels.WARN)
		else
			vim.notify(plural(total, "substitution") .. " on " .. plural(changed, "line"))
		end
	end, {
		nargs = "+",
		range = "%",
		desc = "Case-preserving substitute: :S/old/new",
		preview = function(opts, ns, _)
			local total = apply(opts, ns)
			return (total and total > 0) and 1 or 0
		end,
	})
end

return M
