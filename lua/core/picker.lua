-- Minimal fuzzy picker (telescope replacement, 0 plugins).
-- Blocking floating window, fuzzy matching via vim.fn.matchfuzzy.
-- Keys: type to filter | <CR> select | <Esc>/<C-c> cancel
--       <C-n>/<Down> next | <C-p>/<Up> previous | <BS> delete char

local M = {}

local KEY = {
	esc = vim.keycode("<Esc>"),
	cr = vim.keycode("<CR>"),
	nl = "\n",
	bs1 = vim.keycode("<BS>"),
	bs2 = "\8",
	c_c = vim.keycode("<C-c>"),
	c_n = vim.keycode("<C-n>"),
	c_p = vim.keycode("<C-p>"),
	down = vim.keycode("<Down>"),
	up = vim.keycode("<Up>"),
	c_u = vim.keycode("<C-u>"),
}

--- Open a fuzzy picker.
--- @param items table list of strings or tables
--- @param opts table { prompt = string, format = fn(item)->string, on_select = fn(item) }
function M.pick(items, opts)
	opts = opts or {}
	if not items or #items == 0 then
		vim.notify("Nothing to pick", vim.log.levels.INFO)
		return
	end

	local format = opts.format or function(it)
		return type(it) == "table" and (it.text or vim.inspect(it)) or tostring(it)
	end

	-- entries carry the original item + display text
	local all = {}
	for i, it in ipairs(items) do
		all[i] = { item = it, text = format(it) }
	end

	local width = math.min(math.max(60, math.floor(vim.o.columns * 0.6)), vim.o.columns - 4)
	local height = math.min(#all + 1, math.max(10, math.floor(vim.o.lines * 0.5)))
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].bufhidden = "wipe"
	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		width = width,
		height = height,
		row = math.floor((vim.o.lines - height) / 2) - 1,
		col = math.floor((vim.o.columns - width) / 2),
		style = "minimal",
		border = { "┏", "━", "┓", "┃", "┛", "━", "┗", "┃" },
		title = " " .. (opts.prompt or "Pick") .. " ",
		title_pos = "center",
	})
	vim.wo[win].cursorline = true
	vim.wo[win].scrolloff = 2

	local query = ""
	local filtered = all
	local sel = 1

	local function refilter()
		if query == "" then
			filtered = all
		else
			filtered = vim.fn.matchfuzzy(all, query, { key = "text" })
		end
		sel = 1
	end

	local function redraw()
		local lines = { "> " .. query }
		for _, e in ipairs(filtered) do
			lines[#lines + 1] = "  " .. e.text
		end
		vim.bo[buf].modifiable = true
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
		vim.bo[buf].modifiable = false
		if #filtered > 0 then
			vim.api.nvim_win_set_cursor(win, { sel + 1, 0 })
		else
			vim.api.nvim_win_set_cursor(win, { 1, 0 })
		end
		vim.cmd("redraw")
	end

	local function close()
		if vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_win_close(win, true)
		end
	end

	redraw()
	while true do
		local ok, key = pcall(vim.fn.getcharstr)
		if not ok or key == KEY.esc or key == KEY.c_c then
			close()
			return
		elseif key == KEY.cr or key == KEY.nl then
			local choice = filtered[sel]
			close()
			if choice and opts.on_select then
				opts.on_select(choice.item)
			end
			return
		elseif key == KEY.bs1 or key == KEY.bs2 then
			query = query:sub(1, -2)
			refilter()
		elseif key == KEY.c_u then
			query = ""
			refilter()
		elseif key == KEY.c_n or key == KEY.down then
			sel = math.min(sel + 1, math.max(#filtered, 1))
		elseif key == KEY.c_p or key == KEY.up then
			sel = math.max(sel - 1, 1)
		elseif #key >= 1 and key:byte(1) >= 32 and key:byte(1) < 128 then
			query = query .. key
			refilter()
		elseif key:byte(1) >= 128 and key:byte(1) ~= 0x80 then
			-- multibyte printable (utf-8)
			query = query .. key
			refilter()
		end
		redraw()
	end
end

return M
