local M = {}

M.defaults = {
	contests = {
		atcoder = { cpp_version = 23 },
		codeforces = { cpp_version = 23 },
		cses = { cpp_version = 20 },
	},
	snippets = {},
}

function M.setup(user_config)
	return vim.tbl_deep_extend("force", M.defaults, user_config or {})
end

return M
