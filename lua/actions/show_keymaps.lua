-- Command built on the picker: every mapping that carries a description, as
-- "mode  lhs  desc", sorted. <CR> runs the selected mapping, <Esc> closes.
--
-- The description is the filter: the keymaps are written as "Navigation : ...",
-- "Git : ...", so typing a group name lists that group.

local M = {}

function M.open()
	local items = {}
	for _, mode in ipairs({ "n", "v", "x", "o", "i" }) do
		for _, km in ipairs(vim.api.nvim_get_keymap(mode)) do
			if km.desc and km.desc ~= "" then
				items[#items + 1] = {
					text = string.format("%s  %-14s %s", mode, km.lhs:gsub(" ", "<Space>"), km.desc),
					lhs = km.lhs,
					mode = mode,
				}
			end
		end
	end
	table.sort(items, function(a, b) return a.text < b.text end)
	require("core.picker").pick(items, { prompt = "Keymaps" })
end

return M
