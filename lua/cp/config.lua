---@class cp.Config
---@field contests table
---@field snippets table
---@field hooks table
---@field debug boolean
---@field tile? fun(source_buf: number, input_buf: number, output_buf: number)
---@field filename? fun(contest: string, problem_id: string, problem_letter?: string): string

local M = {}

---@type cp.Config
M.defaults = {
	contests = {
		default = {
			cpp = {
				compile = {
					"g++",
					"-std=c++{version}",
					"-O2",
					"-DLOCAL",
					"-Wall",
					"-Wextra",
					"{source}",
					"-o",
					"{binary}",
				},
				run = { "{binary}" },
				debug = {
					"g++",
					"-std=c++{version}",
					"-g3",
					"-fsanitize=address,undefined",
					"-DLOCAL",
					"{source}",
					"-o",
					"{binary}",
				},
				executable = nil,
				version = 20,
			},
			python = {
				compile = nil,
				run = { "{source}" },
				debug = { "{source}" },
				executable = "python3",
			},
			timeout_ms = 2000,
		},
		atcoder = {
			cpp = { version = 23 },
		},
		codeforces = {
			cpp = { version = 23 },
		},
		cses = {
			cpp = { version = 20 },
		},
	},
	snippets = {},
	hooks = {
		before_run = nil,
		before_debug = nil,
	},
	debug = false,
	tile = nil,
	filename = nil,
}

---@param base_config table
---@param contest_config table
---@return table
local function extend_contest_config(base_config, contest_config)
	local result = vim.tbl_deep_extend("force", base_config, contest_config)
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
			debug = { user_config.debug, { "boolean", "nil" }, true },
			tile = { user_config.tile, { "function", "nil" }, true },
			filename = { user_config.filename, { "function", "nil" }, true },
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

local function default_filename(contest, contest_id, problem_id)
	local full_problem_id = contest_id:lower()
	if contest == "atcoder" or contest == "codeforces" then
		if problem_id then
			full_problem_id = full_problem_id .. problem_id:lower()
		end
	end
	return full_problem_id .. ".cc"
end

M.default_filename = default_filename

return M
