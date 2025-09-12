local M = {}

M.defaults = {
	template_dir = nil,
	contests = {
		atcoder = { cpp_version = 23 },
		codeforces = { cpp_version = 23 },
		cses = { cpp_version = 20 },
		icpc = { cpp_version = 20 },
		usaco = { cpp_version = 17 },
	},
	snippets = {},
}

function M.setup(user_config)
	return vim.tbl_deep_extend("force", M.defaults, user_config or {})
end

return M
