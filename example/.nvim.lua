-- Project-local keymaps
-- Copy this file to the root of your project and adjust to your needs.
-- Neovim will prompt you to trust it on first load (once per file change).
-- Use <leader>1 through <leader>9 for project-specific shortcuts.

-- Example: Rust / Cargo project
vim.keymap.set("n", "<leader>1", function()
	vim.cmd("w")
	vim.cmd("!cargo check")
end, { desc = "cargo check" })

vim.keymap.set("n", "<leader>2", function()
	vim.cmd("w")
	vim.cmd("!cargo run")
end, { desc = "cargo run" })

vim.keymap.set("n", "<leader>3", function()
	vim.cmd("w")
	vim.cmd("!cargo test")
end, { desc = "cargo test" })

vim.keymap.set("n", "<leader>4", function()
	print("Moin Moin")
end, { desc = "Moin Moin" })

-- Add more shortcuts here (<leader>5 .. <leader>9)
