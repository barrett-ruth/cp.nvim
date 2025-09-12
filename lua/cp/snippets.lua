local M = {}

function M.setup(config)
	local has_luasnip, luasnip = pcall(require, "luasnip")
	if not has_luasnip then
		return
	end

	local snippets = {}

	for _, snippet in pairs(config.snippets or {}) do
		table.insert(snippets, snippet)
	end

	if #snippets > 0 then
		luasnip.add_snippets("cpp", snippets)
	end
end

return M
