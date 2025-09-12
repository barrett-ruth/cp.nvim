local M = {}

M.defaults = {
	contests = {
		default = {
			cpp_version = 20,
			compile_flags = { "-O2", "-DLOCAL", "-Wall", "-Wextra" },
			debug_flags = { "-g3", "-fsanitize=address,undefined", "-DLOCAL" },
			timeout_ms = 2000,
		},
		atcoder = {
			cpp_version = 23,
		},
		codeforces = {
			cpp_version = 23,
		},
		cses = {},
	},
	snippets = {},
}

local function extend_contest_config(base_config, contest_config)
	local result = vim.deepcopy(base_config)

	for key, value in pairs(contest_config) do
		if key == "compile_flags" or key == "debug_flags" then
			vim.list_extend(result[key], value)
		else
			result[key] = value
		end
	end

	local std_flag = ("-std=c++%d"):format(result.cpp_version)
	table.insert(result.compile_flags, 1, std_flag)
	table.insert(result.debug_flags, 1, std_flag)

	return result
end

function M.setup(user_config)
	local config = vim.tbl_deep_extend("force", M.defaults, user_config or {})

	local default_contest = config.contests.default
	for contest_name, contest_config in pairs(config.contests) do
		if contest_name ~= "default" then
			config.contests[contest_name] = extend_contest_config(default_contest, contest_config)
		end
	end

	return config
end

return M
