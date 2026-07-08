-- Native LSP setup (nvim >= 0.11). Replaces nvim-lspconfig, mason, blink.cmp.
-- Requires the server binaries on $PATH (clangd, rust-analyzer, pyright, ...).

local M = {}

function M.setup()
	-- same diagnostic look as before
	vim.diagnostic.config({
		signs = false, -- I do not like if line-numbers move on the side
		underline = true,
		virtual_text = true,
	})

	local function set_lsp_float_highlights()
		vim.api.nvim_set_hl(0, "FloatBorder", { fg = "#ff69b4", bold = true })
		vim.api.nvim_set_hl(0, "NormalFloat", { bg = "NONE" })
	end
	set_lsp_float_highlights()
	vim.api.nvim_create_autocmd("ColorScheme", { callback = set_lsp_float_highlights })

	-- server definitions (what nvim-lspconfig used to provide)
	vim.lsp.config("clangd", {
		cmd = { "clangd" },
		filetypes = { "c", "cpp", "objc", "objcpp", "cuda" },
		root_markers = { "compile_commands.json", "compile_flags.txt", ".clangd", ".git" },
	})

	vim.lsp.config("rust_analyzer", {
		cmd = { "rust-analyzer" },
		filetypes = { "rust" },
		root_markers = { "Cargo.toml", ".git" },
		settings = {
			["rust-analyzer"] = {
				cargo = { allFeatures = true },
				checkOnSave = true,
				check = { command = "clippy" },
			},
		},
	})

	vim.lsp.config("pyright", {
		cmd = { "pyright-langserver", "--stdio" },
		filetypes = { "python" },
		root_markers = { "pyproject.toml", "setup.py", "requirements.txt", ".git" },
		settings = { python = { analysis = { autoSearchPaths = true } } },
	})

	vim.lsp.config("omnisharp", {
		cmd = { "omnisharp", "-lsp" },
		filetypes = { "cs" },
		root_markers = { "*.sln", "*.csproj", ".git" },
	})

	-- only enable servers whose binary actually exists
	for server, bin in pairs({
		clangd = "clangd",
		rust_analyzer = "rust-analyzer",
		pyright = "pyright-langserver",
		omnisharp = "omnisharp",
	}) do
		if vim.fn.executable(bin) == 1 then
			vim.lsp.enable(server)
		end
	end

	vim.api.nvim_create_autocmd("LspAttach", {
		callback = function(args)
			local client = vim.lsp.get_client_by_id(args.data.client_id)
			if not client then return end

			-- inlay hints (same as before)
			if client:supports_method("textDocument/inlayHint") then
				vim.lsp.inlay_hint.enable(true, { bufnr = args.buf })
			end

			-- built-in autocompletion (replaces blink.cmp)
			if client:supports_method("textDocument/completion") then
				vim.lsp.completion.enable(true, client.id, args.buf, { autotrigger = true })
			end

			-- format on demand via gq (replaces conform for LSP-backed filetypes)
			vim.bo[args.buf].formatexpr = "v:lua.vim.lsp.formatexpr()"
		end,
	})
end

return M
