local M = {}

-- === Foreword
-- There are many ways you can config your keymaps.
-- I started with doing stuff like "<leader>gs" for git status (g: git , s: status).
-- This is very easy readable... but given the fact that you are the only user of your keymap, this is kind of senseless
-- Now I move actions which I use more often closer to "h,j,k,l".
-- E.g. I really enjoy to navigate to the file tree using only one hand.
-- This being said - feel free to choose your own keymaps

function M.setup()
	local git = require("core.git")
	local windows = require("core.windows")
	local dbg = require("core.debug")
	local history = require("custom.cursor-history") 
	local signs = require("behaviour.git-signs")

	-- help & health -----------------------------------------------------------------
	vim.keymap.set("n", "<leader>?", require("actions.show_keymaps").open, { desc = "Show keymaps" })
	vim.keymap.set("n", "<leader>=", require("actions.health_screen").open, { desc = "Health : LSP status / indexing / log + checkhealth (new tab)" })
	
	-- tabs -------------------------------------------------------------------
	vim.keymap.set("n", "<leader>tn", "<cmd>tabnew<CR>", { desc = "Tabs : New empty tab (tabs)" })
	vim.keymap.set("n", "<leader>ts", "<cmd>tab split<CR>", { desc = "Tabs : Open current file in new tab (tabs)" })
	vim.keymap.set("n", "<leader>tx", "<cmd>tabclose<CR>", { desc = "Tabs : Close current tab (tabs)" })

	-- git ----------------------------------------------------------------------
	vim.keymap.set("n", "<leader>g", require("actions.git_status").open, { desc = "Git : Browse every changed block (git status)" })
   
    -- navigation -----------------------------------------------------------
	vim.keymap.set("n", "<leader>l", require("actions.file_tree").open, { desc = "Navigation : Project file tree (nested sidebar)" })
	vim.keymap.set("n", "<leader>j", require("actions.jump_list").open, { desc = "Navigation : Browse jump history (sidebar, j/k walks it)" })
	vim.keymap.set("n", "<leader>f", require("actions.find_files").open, { desc = "Navigation : Search by file name" })
	vim.keymap.set("n", "<leader>K", require("actions.rip_grep").open, { desc = "Navigation : Rip grep file contents (list overlay)" })
	vim.keymap.set("n", "<leader>k", function() require("actions.rip_grep").open(vim.fn.expand("<cword>")) end, { desc = "Navigation : Rip grep word under cursor (list overlay, prefilled)" })
	vim.keymap.set("n", "<leader>r", require("custom.yank-ring").open, { desc = "Navigation : Yank ring (last 10 yanks, 0-9 pastes, <Esc> closes)" })
	vim.keymap.set("n", "f", function() signs.goto_hunk(1) end, { desc = "Navigation : Next modified block (git)" })
	vim.keymap.set("n", "F", function() signs.goto_hunk(-1) end, { desc = "Navigation : Previous modified block (git)" })
	vim.keymap.set("n", "<leader>w", windows.pick_window_to_jump, { desc = "Navigation : Pick window to jump to" })
	vim.keymap.set("n", "<leader>n", history.back, { desc = "Navigation : Go back to previous position" })
	vim.keymap.set("n", "<leader>b", history.forward, { desc = "Navigation : Go forward again" })
	vim.keymap.set({ "n", "o", "x" }, ",", "^", { desc = "Navigation : Set cursor to start of line" })
	vim.keymap.set({ "n", "o", "x" }, ".", "$", { desc = "Navigation : Set cursor to end of line" })

	-- code navigation (lsp) --------------------------------------------------
	vim.keymap.set("n", "<leader>h", vim.lsp.buf.definition, { desc = "LSP : Go to definition" })
	vim.keymap.set("n", "<leader>u", vim.lsp.buf.references, { desc = "LSP : Find usages / references" })
	vim.keymap.set("n", "<leader>t", require("actions.call_tree").open, { desc = "LSP : Call tree of current function (nested sidebar, h = callers)" })
	vim.keymap.set("n", "<leader>i", require("actions.function_list").open, { desc = "LSP : Functions of current file (nested sidebar, j/k walks them)" })
	vim.keymap.set("n", "<leader>z", vim.lsp.buf.hover, { desc = "LSP : Hover docs of var" })
	vim.keymap.set("n", "<leader>cl", require("actions.diagnostic_list").open, { desc = "LSP : Browse diagnostics (sidebar, j/k walks them)" })
	vim.keymap.set("n", "<leader>cr", vim.lsp.buf.rename, { desc = "LSP : Rename symbol" })
	vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, { desc = "LSP : Code actions" })

    -- other --------------------------------------------------------------
	vim.keymap.set("n", "<leader>y", require("custom.copy-mode").toggle, { desc = "Copy mode : Clipboard y/p, no line numbers (<Esc> leaves)" })

end

return M
