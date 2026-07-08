-- Tokyonight "storm" colorscheme, reimplemented as a native colors/ file.
-- No plugin: a faithful subset of folke/tokyonight.nvim's storm palette and
-- highlight groups (editor UI + legacy syntax + treesitter + LSP/diagnostics).
-- Activated with `vim.cmd.colorscheme("tokyonight")`.

vim.cmd("highlight clear")
if vim.g.syntax_on then
	vim.cmd("syntax reset")
end
vim.o.termguicolors = true
vim.o.background = "dark"
vim.g.colors_name = "tokyonight"

-- storm palette
local c = {
	bg = "#24283b",
	bg_dark = "#1f2335",
	bg_highlight = "#292e42",
	bg_visual = "#2e3c64",
	bg_search = "#3d59a1",
	fg = "#c0caf5",
	fg_dark = "#a9b1d6",
	fg_gutter = "#3b4261",
	black = "#1d202f",
	border = "#1b1e2d",
	comment = "#565f89",
	dark3 = "#545c7e",
	dark5 = "#737aa2",
	terminal_black = "#414868",
	blue = "#7aa2f7",
	blue0 = "#3d59a1",
	blue1 = "#2ac3de",
	blue2 = "#0db9d7",
	blue5 = "#89ddff",
	blue6 = "#b4f9f8",
	blue7 = "#394b70",
	cyan = "#7dcfff",
	magenta = "#bb9af7",
	magenta2 = "#ff007c",
	purple = "#9d7cd8",
	orange = "#ff9e64",
	yellow = "#e0af68",
	green = "#9ece6a",
	green1 = "#73daca",
	green2 = "#41a6b5",
	teal = "#1abc9c",
	red = "#f7768e",
	red1 = "#db4b4b",
	git_add = "#449dab",
	git_change = "#6183bb",
	git_delete = "#914c54",
	diff_add = "#20303b",
	diff_change = "#1f2231",
	diff_delete = "#37222c",
	diff_text = "#394b70",
}

local groups = {
	-- editor ui
	Normal = { fg = c.fg, bg = c.bg },
	NormalNC = { fg = c.fg, bg = c.bg },
	NormalFloat = { fg = c.fg, bg = c.bg_dark },
	FloatBorder = { fg = c.blue, bg = c.bg_dark },
	FloatTitle = { fg = c.blue, bg = c.bg_dark, bold = true },
	ColorColumn = { bg = c.black },
	Cursor = { fg = c.bg, bg = c.fg },
	CursorLine = { bg = c.bg_highlight },
	CursorColumn = { bg = c.bg_highlight },
	CursorLineNr = { fg = c.orange, bold = true },
	LineNr = { fg = c.fg_gutter },
	LineNrAbove = { fg = c.fg_gutter },
	LineNrBelow = { fg = c.fg_gutter },
	SignColumn = { fg = c.fg_gutter, bg = c.bg },
	FoldColumn = { fg = c.comment, bg = c.bg },
	Folded = { fg = c.blue, bg = c.fg_gutter },
	VertSplit = { fg = c.border },
	WinSeparator = { fg = c.border, bold = true },
	MatchParen = { fg = c.orange, bold = true },
	Visual = { bg = c.bg_visual },
	VisualNOS = { bg = c.bg_visual },
	Search = { fg = c.fg, bg = c.bg_search },
	IncSearch = { fg = c.bg, bg = c.orange },
	CurSearch = { fg = c.bg, bg = c.orange },
	Substitute = { fg = c.bg, bg = c.red },
	Pmenu = { fg = c.fg, bg = c.bg_dark },
	PmenuSel = { bg = c.fg_gutter },
	PmenuSbar = { bg = c.bg_highlight },
	PmenuThumb = { bg = c.fg_gutter },
	WildMenu = { bg = c.bg_search },
	StatusLine = { fg = c.fg_dark, bg = c.bg_dark },
	StatusLineNC = { fg = c.fg_gutter, bg = c.bg_dark },
	TabLine = { fg = c.fg_gutter, bg = c.bg_dark },
	TabLineFill = { bg = c.black },
	TabLineSel = { fg = c.black, bg = c.blue },
	WinBar = { fg = c.fg_dark, bg = c.bg },
	WinBarNC = { fg = c.fg_gutter, bg = c.bg },
	Title = { fg = c.blue, bold = true },
	Directory = { fg = c.blue },
	ErrorMsg = { fg = c.red },
	WarningMsg = { fg = c.yellow },
	ModeMsg = { fg = c.fg_dark, bold = true },
	MoreMsg = { fg = c.blue },
	Question = { fg = c.blue },
	NonText = { fg = c.dark3 },
	Whitespace = { fg = c.fg_gutter },
	SpecialKey = { fg = c.fg_gutter },
	EndOfBuffer = { fg = c.bg },
	Conceal = { fg = c.dark5 },
	QuickFixLine = { bg = c.bg_visual, bold = true },
	SpellBad = { undercurl = true, sp = c.red },
	SpellCap = { undercurl = true, sp = c.yellow },
	SpellLocal = { undercurl = true, sp = c.blue1 },
	SpellRare = { undercurl = true, sp = c.magenta },

	-- legacy syntax
	Comment = { fg = c.comment, italic = true },
	Constant = { fg = c.orange },
	String = { fg = c.green },
	Character = { fg = c.green },
	Number = { fg = c.orange },
	Boolean = { fg = c.orange },
	Float = { fg = c.orange },
	Identifier = { fg = c.magenta },
	Function = { fg = c.blue },
	Statement = { fg = c.magenta },
	Conditional = { fg = c.magenta },
	Repeat = { fg = c.magenta },
	Label = { fg = c.magenta },
	Operator = { fg = c.blue5 },
	Keyword = { fg = c.magenta },
	Exception = { fg = c.magenta },
	PreProc = { fg = c.cyan },
	Include = { fg = c.cyan },
	Define = { fg = c.cyan },
	Macro = { fg = c.cyan },
	Type = { fg = c.blue1 },
	StorageClass = { fg = c.blue1 },
	Structure = { fg = c.blue1 },
	Typedef = { fg = c.blue1 },
	Special = { fg = c.blue1 },
	SpecialChar = { fg = c.magenta },
	Delimiter = { fg = c.blue5 },
	Todo = { fg = c.bg, bg = c.yellow, bold = true },
	Error = { fg = c.red },
	Underlined = { underline = true },
	Bold = { bold = true },
	Italic = { italic = true },

	-- treesitter
	["@variable"] = { fg = c.fg },
	["@variable.builtin"] = { fg = c.red },
	["@variable.parameter"] = { fg = c.yellow },
	["@variable.member"] = { fg = c.green1 },
	["@property"] = { fg = c.green1 },
	["@field"] = { fg = c.green1 },
	["@constant"] = { fg = c.orange },
	["@constant.builtin"] = { fg = c.orange },
	["@constant.macro"] = { fg = c.cyan },
	["@module"] = { fg = c.fg_dark },
	["@label"] = { fg = c.blue },
	["@string"] = { fg = c.green },
	["@string.regexp"] = { fg = c.blue6 },
	["@string.escape"] = { fg = c.magenta },
	["@string.special.symbol"] = { fg = c.green1 },
	["@character"] = { fg = c.green },
	["@character.special"] = { fg = c.magenta },
	["@boolean"] = { fg = c.orange },
	["@number"] = { fg = c.orange },
	["@number.float"] = { fg = c.orange },
	["@type"] = { fg = c.blue1 },
	["@type.builtin"] = { fg = c.blue2 },
	["@type.definition"] = { fg = c.blue1 },
	["@attribute"] = { fg = c.yellow },
	["@function"] = { fg = c.blue },
	["@function.builtin"] = { fg = c.cyan },
	["@function.macro"] = { fg = c.cyan },
	["@function.method"] = { fg = c.blue },
	["@function.call"] = { fg = c.blue },
	["@constructor"] = { fg = c.magenta },
	["@operator"] = { fg = c.blue5 },
	["@keyword"] = { fg = c.magenta },
	["@keyword.function"] = { fg = c.magenta },
	["@keyword.operator"] = { fg = c.magenta },
	["@keyword.return"] = { fg = c.magenta },
	["@keyword.import"] = { fg = c.cyan },
	["@keyword.exception"] = { fg = c.magenta },
	["@keyword.conditional"] = { fg = c.magenta },
	["@keyword.repeat"] = { fg = c.magenta },
	["@punctuation.delimiter"] = { fg = c.blue5 },
	["@punctuation.bracket"] = { fg = c.fg_dark },
	["@punctuation.special"] = { fg = c.blue5 },
	["@comment"] = { fg = c.comment, italic = true },
	["@comment.error"] = { fg = c.bg, bg = c.red },
	["@comment.warning"] = { fg = c.bg, bg = c.yellow },
	["@comment.todo"] = { fg = c.bg, bg = c.blue },
	["@tag"] = { fg = c.blue1 },
	["@tag.attribute"] = { fg = c.magenta },
	["@tag.delimiter"] = { fg = c.cyan },
	-- markup (markdown, help, ...)
	["@markup.heading"] = { fg = c.blue, bold = true },
	["@markup.strong"] = { fg = c.fg, bold = true },
	["@markup.italic"] = { fg = c.fg, italic = true },
	["@markup.raw"] = { fg = c.green1 },
	["@markup.link"] = { fg = c.blue },
	["@markup.link.url"] = { fg = c.comment, underline = true },
	["@markup.list"] = { fg = c.blue5 },

	-- diagnostics
	DiagnosticError = { fg = c.red },
	DiagnosticWarn = { fg = c.yellow },
	DiagnosticInfo = { fg = c.blue2 },
	DiagnosticHint = { fg = c.teal },
	DiagnosticUnnecessary = { fg = c.terminal_black },
	DiagnosticUnderlineError = { undercurl = true, sp = c.red },
	DiagnosticUnderlineWarn = { undercurl = true, sp = c.yellow },
	DiagnosticUnderlineInfo = { undercurl = true, sp = c.blue2 },
	DiagnosticUnderlineHint = { undercurl = true, sp = c.teal },

	-- lsp
	LspReferenceText = { bg = c.fg_gutter },
	LspReferenceRead = { bg = c.fg_gutter },
	LspReferenceWrite = { bg = c.fg_gutter },
	LspInlayHint = { fg = c.dark3, bg = c.bg_highlight },
	LspSignatureActiveParameter = { fg = c.orange, bold = true },
	LspCodeLens = { fg = c.comment },

	-- git / diff
	DiffAdd = { bg = c.diff_add },
	DiffChange = { bg = c.diff_change },
	DiffDelete = { bg = c.diff_delete },
	DiffText = { bg = c.diff_text },
	diffAdded = { fg = c.git_add },
	diffRemoved = { fg = c.git_delete },
	diffChanged = { fg = c.git_change },
	SignAdd = { fg = c.git_add },
	SignChange = { fg = c.git_change },
	SignDelete = { fg = c.git_delete },
}

for name, opts in pairs(groups) do
	vim.api.nvim_set_hl(0, name, opts)
end

-- :terminal ansi colors
vim.g.terminal_color_0 = c.terminal_black
vim.g.terminal_color_1 = c.red
vim.g.terminal_color_2 = c.green
vim.g.terminal_color_3 = c.yellow
vim.g.terminal_color_4 = c.blue
vim.g.terminal_color_5 = c.magenta
vim.g.terminal_color_6 = c.cyan
vim.g.terminal_color_7 = c.fg_dark
vim.g.terminal_color_8 = c.terminal_black
vim.g.terminal_color_9 = c.red
vim.g.terminal_color_10 = c.green
vim.g.terminal_color_11 = c.yellow
vim.g.terminal_color_12 = c.blue
vim.g.terminal_color_13 = c.magenta
vim.g.terminal_color_14 = c.cyan
vim.g.terminal_color_15 = c.fg
