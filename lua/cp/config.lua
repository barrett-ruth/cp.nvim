---@class cp.Config
---@field contests table
---@field snippets table
---@field hooks table

local M = {}

---@type cp.Config
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
		cses = {
			cpp_version = 20,
		},
	},
	snippets = {},
	hooks = {
		before_run = nil,
		before_debug = nil,
	},
}

---@param base_config table
---@param contest_config table
---@return table
local function extend_contest_config(base_config, contest_config)
	local result = vim.tbl_deep_extend("force", base_config, contest_config)

	local std_flag = ("-std=c++%d"):format(result.cpp_version)
	table.insert(result.compile_flags, 1, std_flag)
	table.insert(result.debug_flags, 1, std_flag)

	return result
end

---@param user_config table|nil
---@return table
function M.setup(user_config)
	vim.validate({
		user_config = { user_config, { "table", "nil" }, true },
	})

	if user_config then
		vim.validate({
			contests = { user_config.contests, { "table", "nil" }, true },
			snippets = { user_config.snippets, { "table", "nil" }, true },
			hooks = { user_config.hooks, { "table", "nil" }, true },
		})

		if user_config.hooks then
			vim.validate({
				before_run = { user_config.hooks.before_run, { "function", "nil" }, true },
				before_debug = { user_config.hooks.before_debug, { "function", "nil" }, true },
			})
		end
	end

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
