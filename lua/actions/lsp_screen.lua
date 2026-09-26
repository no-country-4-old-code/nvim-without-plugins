-- LSP screens: what is the language server doing right now?
--
--   log()      the LSP log in a new tab, cursor at the end (servers like clangd
--              write their stderr there -- that is where indexing errors land)
--   errors()   only the error lines of that log (clangd: "E[12:34:56.789] ...")
--              in the quickfix list
--   status()   every running client: server version, root, cmd, attached
--              buffers, and whether the current buffer has a client at all
--   indexing() every progress task a server reported ($/progress -- clangd's
--              background index, rust-analyzer's cargo check, ...), running
--              and finished, with percent, elapsed time and a time-left guess.
--              Stays open and updates live; q / <Esc> closes.
--
-- Progress is only known from what the servers report, so setup() has to
-- listen from startup on (core.lsp calls it). A client without any task never
-- started one: indexing has not begun, or the server does not report it.
-- statusline() is the short form for the statusline: "clangd indexing 42%".

local M = {}

-- tasks[client_id][token] = { title, message, percentage, started, finished }
-- (times from vim.uv.now() in ms; `clock` = wall clock at begin/end for display)
local tasks = {}
local view = { buf = nil, render = nil } -- the open indexing() window, if any

local function fmt_duration(ms)
	local s = math.floor(ms / 1000)
	if s < 60 then return s .. "s" end
	if s < 3600 then return string.format("%dm%02ds", s / 60, s % 60) end
	return string.format("%dh%02dm", s / 3600, (s % 3600) / 60)
end

local function client_name(id)
	local c = vim.lsp.get_client_by_id(id)
	return c and c.name or ("client " .. id)
end

-- running tasks first (oldest start first), then finished ones, newest first
local function sorted(client_tasks)
	local list = vim.tbl_values(client_tasks)
	table.sort(list, function(a, b)
		if (a.finished == nil) ~= (b.finished == nil) then return a.finished == nil end
		if a.finished then return a.finished > b.finished end
		return a.started < b.started
	end)
	return list
end

local function describe(t, now)
	local pct = t.percentage and string.format("%3d%%", t.percentage) or "    "
	local text = t.title .. (t.message and t.message ~= "" and ("  " .. t.message) or "")
	if t.finished then
		return string.format("  ✓ %s  %s  -- done %s, took %s", pct, text,
			t.end_clock, fmt_duration(t.finished - t.started))
	end
	local elapsed = now - t.started
	local left = ""
	if t.percentage and t.percentage > 0 and t.percentage < 100 then
		left = ", ~" .. fmt_duration(elapsed * (100 - t.percentage) / t.percentage) .. " left"
	end
	return string.format("  ● %s  %s  -- since %s (%s%s)", pct, text,
		t.start_clock, fmt_duration(elapsed), left)
end

-- scratch float, q / <Esc> close it
local function float(lines, title)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].bufhidden = "wipe"
	local w = math.floor(vim.o.columns * 0.8)
	local h = math.floor(vim.o.lines * 0.6)
	vim.api.nvim_open_win(buf, true, {
		relative = "editor", style = "minimal",
		border = { "┏", "━", "┓", "┃", "┛", "━", "┗", "┃" },
		title = " " .. title .. " ", title_pos = "center",
		width = w, height = h,
		row = math.floor((vim.o.lines - h) / 2), col = math.floor((vim.o.columns - w) / 2),
	})
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].modifiable = false
	for _, lhs in ipairs({ "q", "<Esc>" }) do
		vim.keymap.set("n", lhs, "<cmd>close<CR>", { buffer = buf, nowait = true })
	end
	return buf
end

local function set_lines(buf, lines)
	vim.bo[buf].modifiable = true
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].modifiable = false
end

local function on_progress(ev)
	local id, params = ev.data.client_id, ev.data.params
	local value = params and params.value
	if type(value) ~= "table" or not value.kind then return end
	tasks[id] = tasks[id] or {}
	local token = tostring(params.token)
	local t = tasks[id][token]
	if value.kind == "begin" or not t then
		t = { title = value.title or token, started = vim.uv.now(), start_clock = os.date("%H:%M:%S") }
		tasks[id][token] = t
	end
	t.message = value.message or t.message
	t.percentage = value.percentage or t.percentage
	if value.kind == "end" then
		-- the last report ("1/2", 50%) is stale now; keep only the end message
		t.message = value.message
		t.percentage = t.percentage and 100
		t.finished = vim.uv.now()
		t.end_clock = os.date("%H:%M:%S")
	end
	vim.cmd.redrawstatus()
	if view.buf and vim.api.nvim_buf_is_valid(view.buf) then view.render() end
end

function M.setup()
	vim.api.nvim_create_autocmd("LspProgress", { callback = on_progress })
end

--- Running tasks as one short string for the statusline ("" when idle).
function M.statusline()
	local parts = {}
	for id, client_tasks in pairs(tasks) do
		for _, t in pairs(client_tasks) do
			if not t.finished then
				parts[#parts + 1] = string.format("%s %s%s", client_name(id), t.title,
					t.percentage and (" " .. t.percentage .. "%") or "")
			end
		end
	end
	return #parts > 0 and (" ⟳ " .. table.concat(parts, ", ")) or ""
end

function M.log()
	vim.cmd("tabedit +$ " .. vim.fn.fnameescape(vim.lsp.get_log_path()))
end

function M.errors()
	local ok = pcall(vim.cmd, "vimgrep /E\\[\\d\\d:/j " .. vim.fn.fnameescape(vim.lsp.get_log_path()))
	if ok then vim.cmd("copen") else vim.notify("no LSP errors in the log") end
end

function M.status()
	local cur = vim.api.nvim_get_current_buf()
	local lines = {}
	local clients = vim.lsp.get_clients()
	if #vim.lsp.get_clients({ bufnr = cur }) == 0 then
		lines[#lines + 1] = string.format("No LSP attached to this buffer (filetype '%s').", vim.bo[cur].filetype)
		lines[#lines + 1] = ""
	end
	if #clients == 0 then
		lines[#lines + 1] = "No LSP client running."
	end
	for _, c in ipairs(clients) do
		local info = c.server_info or {}
		local bufs = vim.tbl_keys(c.attached_buffers)
		local state = c:is_stopped() and "stopped" or (c.initialized and "running" or "starting")
		local running = 0
		for _, t in pairs(tasks[c.id] or {}) do
			if not t.finished then running = running + 1 end
		end
		vim.list_extend(lines, {
			string.format("%s  (id %d)  %s%s", c.name, c.id, state,
				c.attached_buffers[cur] and "  -- attached to this buffer" or ""),
			"  version  " .. (info.version or info.name or "?"),
			"  root     " .. (c.root_dir and vim.fn.fnamemodify(c.root_dir, ":~") or "-"),
			"  cmd      " .. (type(c.config.cmd) == "table" and table.concat(c.config.cmd, " ") or "<function>"),
			string.format("  buffers  %d attached", #bufs),
			string.format("  tasks    %d running (details: indexing screen)", running),
			"",
		})
	end
	vim.list_extend(lines, { "Log: " .. vim.fn.fnamemodify(vim.lsp.get_log_path(), ":~") })
	float(lines, "LSP status")
end

function M.indexing()
	local function lines()
		local out, now = {}, vim.uv.now()
		for _, c in ipairs(vim.lsp.get_clients()) do
			out[#out + 1] = c.name
			local list = sorted(tasks[c.id] or {})
			if #list == 0 then
				out[#out + 1] = "  no progress reported yet -- indexing not started"
					.. " (or this server does not report it)"
			end
			for _, t in ipairs(list) do out[#out + 1] = describe(t, now) end
			out[#out + 1] = ""
		end
		if #out == 0 then out[1] = "No LSP client running." end
		return out
	end
	view.buf = float(lines(), "LSP indexing / progress  (live, q closes)")
	local buf = view.buf
	view.render = function() set_lines(buf, lines()) end
	-- elapsed / time-left keep ticking even while the server is quiet
	local timer = vim.uv.new_timer()
	timer:start(1000, 1000, vim.schedule_wrap(function()
		if vim.api.nvim_buf_is_valid(buf) then view.render() end
	end))
	vim.api.nvim_create_autocmd("BufWipeout", {
		buffer = buf, once = true,
		callback = function()
			timer:stop()
			timer:close()
			if view.buf == buf then view.buf = nil end
		end,
	})
end

return M
