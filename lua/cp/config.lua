---@class LanguageConfig
---@field compile? string[] Compile command template
---@field run string[] Run command template
---@field debug? string[] Debug command template
---@field executable? string Executable name
---@field version? number Language version
---@field extension string File extension

---@class PartialLanguageConfig
---@field compile? string[] Compile command template
---@field run? string[] Run command template
---@field debug? string[] Debug command template
---@field executable? string Executable name
---@field version? number Language version
---@field extension? string File extension

---@class ContestConfig
---@field cpp LanguageConfig
---@field python LanguageConfig
---@field default_language string
---@field timeout_ms number

---@class PartialContestConfig
---@field cpp? PartialLanguageConfig
---@field python? PartialLanguageConfig
---@field default_language? string
---@field timeout_ms? number

---@class HookContext
---@field problem_id string
---@field platform string
---@field contest_id string
---@field source_file string
---@field input_file string
---@field output_file string
---@field expected_file string
---@field contest_config table

---@class Hooks
---@field before_run? fun(ctx: HookContext)
---@field before_debug? fun(ctx: HookContext)

---@class cp.Config
---@field contests table<string, ContestConfig>
---@field snippets table[]
---@field hooks Hooks
---@field debug boolean
---@field tile? fun(source_buf: number, input_buf: number, output_buf: number)
---@field filename? fun(contest: string, contest_id: string, problem_id?: string, config: cp.Config, language?: string): string

---@class cp.UserConfig
---@field contests? table<string, PartialContestConfig>
---@field snippets? table[]
---@field hooks? Hooks
---@field debug? boolean
---@field tile? fun(source_buf: number, input_buf: number, output_buf: number)
---@field filename? fun(contest: string, contest_id: string, problem_id?: string, config: cp.Config, language?: string): string

local M = {}

local filetype_to_language = {
	cc = "cpp",
	c = "cpp",
	py = "python",
	py3 = "python",
}

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
				extension = "cc",
			},
			python = {
				compile = nil,
				run = { "{source}" },
				debug = { "{source}" },
				executable = "python3",
				extension = "py",
			},
			default_language = "cpp",
			timeout_ms = 2000,
		},
		---@type PartialContestConfig
		atcoder = {
			---@type PartialLanguageConfig
			cpp = { version = 23 },
		},
		---@type PartialContestConfig
		codeforces = {
			---@type PartialLanguageConfig
			cpp = { version = 23 },
		},
		---@type PartialContestConfig
		cses = {
			---@type PartialLanguageConfig
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

---@param user_config cp.UserConfig|nil
---@return cp.Config
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

		if user_config.contests then
			for contest_name, contest_config in pairs(user_config.contests) do
				for lang_name, lang_config in pairs(contest_config) do
					if type(lang_config) == "table" and lang_config.extension then
						if not vim.tbl_contains(vim.tbl_keys(filetype_to_language), lang_config.extension) then
							error(
								("Invalid extension '%s' for language '%s' in contest '%s'. Valid extensions: %s"):format(
									lang_config.extension,
									lang_name,
									contest_name,
									table.concat(vim.tbl_keys(filetype_to_language), ", ")
								)
							)
						end
					end
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

---@param contest string
---@param contest_id string
---@param problem_id? string
---@param config cp.Config
---@param language? string
---@return string
local function default_filename(contest, contest_id, problem_id, config, language)
	vim.validate({
		contest = { contest, "string" },
		contest_id = { contest_id, "string" },
		problem_id = { problem_id, { "string", "nil" }, true },
		config = { config, "table" },
		language = { language, { "string", "nil" }, true },
	})

	local full_problem_id = contest_id:lower()
	if contest == "atcoder" or contest == "codeforces" then
		if problem_id then
			full_problem_id = full_problem_id .. problem_id:lower()
		end
	end

	local contest_config = config.contests[contest] or config.contests.default
	local target_language = language or contest_config.default_language
	local language_config = contest_config[target_language]
	return full_problem_id .. "." .. language_config.extension
end

M.default_filename = default_filename

return M
