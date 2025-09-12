local M = {}

function M.setup(config)
	local has_luasnip, luasnip = pcall(require, "luasnip")
	if not has_luasnip then
		return
	end

	local snippets = {}

	for name, snippet in pairs(config.snippets or {}) do
		if type(snippet) == "table" and snippet.trig then
			table.insert(snippets, snippet)
		else
			table.insert(snippets, snippet)
		end
	end

	if #snippets > 0 then
		luasnip.add_snippets("cpp", snippets)
	end
end

return M
