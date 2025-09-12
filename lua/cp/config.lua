---@class cp.ContestConfig
---@field cpp_version number
---@field compile_flags string[]
---@field debug_flags string[]
---@field timeout_ms number

---@class cp.PartialContestConfig
---@field cpp_version? number
---@field compile_flags? string[]
---@field debug_flags? string[]
---@field timeout_ms? number

---@class cp.HooksConfig
---@field before_run? function
---@field before_debug? function

---@class cp.Config
---@field contests table<string, cp.ContestConfig>
---@field snippets table<string, any>
---@field hooks cp.HooksConfig

---@class cp.PartialConfig
---@field contests? table<string, cp.PartialContestConfig>
---@field snippets? table<string, any>
---@field hooks? cp.HooksConfig

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

---@param base_config cp.ContestConfig
---@param contest_config cp.PartialContestConfig
---@return cp.ContestConfig
local function extend_contest_config(base_config, contest_config)
	local result = vim.tbl_deep_extend("force", base_config, contest_config)

	local std_flag = ("-std=c++%d"):format(result.cpp_version)
	table.insert(result.compile_flags, 1, std_flag)
	table.insert(result.debug_flags, 1, std_flag)

	return result
end

---@param path string
---@param tbl table
---@return boolean is_valid
---@return string|nil error_message
local function validate_path(path, tbl)
	local ok, err = pcall(vim.validate, tbl)
	return ok, err and path .. "." .. err
end

---@param path string
---@param contest_config table|nil
---@return boolean is_valid
---@return string|nil error_message
local function validate_contest_config(path, contest_config)
	if not contest_config then
		return true, nil
	end

	return validate_path(path, {
		cpp_version = { contest_config.cpp_version, "number", true },
		compile_flags = { contest_config.compile_flags, "table", true },
		debug_flags = { contest_config.debug_flags, "table", true },
		timeout_ms = { contest_config.timeout_ms, "number", true },
	})
end

---@param user_config cp.PartialConfig|nil
---@return cp.Config
function M.setup(user_config)
	local ok, err = validate_path("config", {
		user_config = { user_config, { "table", "nil" }, true },
	})
	if not ok then
		error(err)
	end

	if user_config then
		ok, err = validate_path("config", {
			contests = { user_config.contests, { "table", "nil" }, true },
			snippets = { user_config.snippets, { "table", "nil" }, true },
			hooks = { user_config.hooks, { "table", "nil" }, true },
		})
		if not ok then
			error(err)
		end

		if user_config.hooks then
			ok, err = validate_path("config.hooks", {
				before_run = { user_config.hooks.before_run, { "function", "nil" }, true },
				before_debug = { user_config.hooks.before_debug, { "function", "nil" }, true },
			})
			if not ok then
				error(err)
			end
		end

		if user_config.contests then
			for contest_name, contest_config in pairs(user_config.contests) do
				ok, err = validate_contest_config("config.contests." .. contest_name, contest_config)
				if not ok then
					error(err)
				end
			end
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
