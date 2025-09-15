local M = {}
local logger = require("cp.log")

function M.setup(config)
	local ok, ls = pcall(require, "luasnip")
	if not ok then
		logger.log("LuaSnip not available - snippets disabled", vim.log.levels.INFO)
		return
	end

	local s, i, fmt = ls.snippet, ls.insert_node, require("luasnip.extras.fmt").fmt

	local languages = require("cp.languages")
	local filetype_to_language = languages.filetype_to_language

	local language_to_filetype = {}
	for ext, lang in pairs(filetype_to_language) do
		language_to_filetype[lang] = ext
	end


	for language, filetype in pairs(language_to_filetype) do
		local snippets = {}

		for _, snippet in ipairs(config.snippets or {}) do
			table.insert(snippets, snippet)
		end

		ls.add_snippets(filetype, snippets)
	end
end

return M
