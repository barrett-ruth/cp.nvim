local M = {}

local config_module = require("cp.config")
local snippets = require("cp.snippets")
local execute = require("cp.execute")
local scrape = require("cp.scrape")
local window = require("cp.window")
local logger = require("cp.log")
local problem = require("cp.problem")
local cache = require("cp.cache")

if not vim.fn.has("nvim-0.10.0") then
	vim.notify("[cp.nvim]: requires nvim-0.10.0+", vim.log.levels.ERROR)
	return {}
end

local user_config = {}
local config = config_module.setup(user_config)
logger.set_config(config)
local snippets_initialized = false

local state = {
	platform = nil,
	contest_id = nil,
	problem_id = nil,
	diff_mode = false,
	saved_layout = nil,
	saved_session = nil,
	temp_output = nil,
	test_cases = nil,
	test_states = {},
}

local platforms = { "atcoder", "codeforces", "cses" }
local actions = { "run", "debug", "diff", "next", "prev" }

local function set_platform(platform)
	if not vim.tbl_contains(platforms, platform) then
		logger.log(("unknown platform. Available: [%s]"):format(table.concat(platforms, ", ")), vim.log.levels.ERROR)
		return false
	end

	state.platform = platform
	vim.fn.mkdir("build", "p")
	vim.fn.mkdir("io", "p")
	return true
end

---@param contest_id string
---@param problem_id? string
---@param language? string
local function setup_problem(contest_id, problem_id, language)
	if not state.platform then
		logger.log("no platform set. run :CP <platform> <contest> first", vim.log.levels.ERROR)
		return
	end

	local problem_name = state.platform == "cses" and contest_id or (contest_id .. (problem_id or ""))
	logger.log(("setting up problem: %s"):format(problem_name))

	local metadata_result = scrape.scrape_contest_metadata(state.platform, contest_id)
	if not metadata_result.success then
		logger.log(
			"failed to load contest metadata: " .. (metadata_result.error or "unknown error"),
			vim.log.levels.WARN
		)
	end

	if state.diff_mode then
		vim.cmd.diffoff()
		if state.saved_session then
			vim.fn.delete(state.saved_session)
			state.saved_session = nil
		end
		if state.temp_output then
			vim.fn.delete(state.temp_output)
			state.temp_output = nil
		end
		state.diff_mode = false
	end

	vim.cmd("silent only")

	state.contest_id = contest_id
	state.problem_id = problem_id

	local cached_test_cases = cache.get_test_cases(state.platform, contest_id, problem_id)
	if cached_test_cases then
		state.test_cases = cached_test_cases
	end

	local ctx = problem.create_context(state.platform, contest_id, problem_id, config, language)

	local scrape_result = scrape.scrape_problem(ctx)

	if not scrape_result.success then
		logger.log("scraping failed: " .. (scrape_result.error or "unknown error"), vim.log.levels.WARN)
		logger.log("you can manually add test cases to io/ directory", vim.log.levels.INFO)
		state.test_cases = nil
	else
		local test_count = scrape_result.test_count or 0
		logger.log(("scraped %d test case(s) for %s"):format(test_count, scrape_result.problem_id))
		state.test_cases = scrape_result.test_cases

		if scrape_result.test_cases then
			cache.set_test_cases(state.platform, contest_id, problem_id, scrape_result.test_cases)
		end
	end

	vim.cmd.e(ctx.source_file)

	if vim.api.nvim_buf_get_lines(0, 0, -1, true)[1] == "" then
		local has_luasnip, luasnip = pcall(require, "luasnip")
		if has_luasnip then
			vim.api.nvim_buf_set_lines(0, 0, -1, false, { state.platform })
			vim.api.nvim_win_set_cursor(0, { 1, #state.platform })
			vim.cmd.startinsert({ bang = true })

			vim.schedule(function()
				print("Debug: platform=" .. state.platform .. ", filetype=" .. vim.bo.filetype .. ", expandable=" .. tostring(luasnip.expandable()))
				if luasnip.expandable() then
					luasnip.expand()
				end
				vim.cmd.stopinsert()
			end)
		else
			vim.api.nvim_input(("i%s<c-space><esc>"):format(state.platform))
		end
	end

	vim.api.nvim_set_option_value("winbar", "", { scope = "local" })
	vim.api.nvim_set_option_value("foldlevel", 0, { scope = "local" })
	vim.api.nvim_set_option_value("foldmethod", "marker", { scope = "local" })
	vim.api.nvim_set_option_value("foldmarker", "{{{,}}}", { scope = "local" })
	vim.api.nvim_set_option_value("foldtext", "", { scope = "local" })

	vim.diagnostic.enable(false)

	local source_buf = vim.api.nvim_get_current_buf()
	local input_buf = vim.fn.bufnr(ctx.input_file, true)
	local output_buf = vim.fn.bufnr(ctx.output_file, true)

	local tile_fn = config.tile or window.default_tile
	tile_fn(source_buf, input_buf, output_buf)

	logger.log(("switched to problem %s"):format(ctx.problem_name))
end

local function get_current_problem()
	local filename = vim.fn.expand("%:t:r")
	if filename == "" then
		logger.log("no file open", vim.log.levels.ERROR)
		return nil
	end
	return filename
end

local function run_problem()
	local problem_id = get_current_problem()
	if not problem_id then
		return
	end

	logger.log(("running problem: %s"):format(problem_id))

	if not state.platform then
		logger.log("no platform set", vim.log.levels.ERROR)
		return
	end

	local contest_config = config.contests[state.platform]
	local ctx = problem.create_context(state.platform, state.contest_id, state.problem_id, config)

	if config.hooks and config.hooks.before_run then
		config.hooks.before_run({
			problem_id = problem_id,
			platform = state.platform,
			contest_id = state.contest_id,
			source_file = ctx.source_file,
			input_file = ctx.input_file,
			output_file = ctx.output_file,
			expected_file = ctx.expected_file,
			contest_config = contest_config,
		})
	end

	vim.schedule(function()
		execute.run_problem(ctx, contest_config, false)
		vim.cmd.checktime()
	end)
end

local function debug_problem()
	local problem_id = get_current_problem()
	if not problem_id then
		return
	end

	if not state.platform then
		logger.log("no platform set", vim.log.levels.ERROR)
		return
	end

	local contest_config = config.contests[state.platform]
	local ctx = problem.create_context(state.platform, state.contest_id, state.problem_id, config)

	if config.hooks and config.hooks.before_debug then
		config.hooks.before_debug({
			problem_id = problem_id,
			platform = state.platform,
			contest_id = state.contest_id,
			source_file = ctx.source_file,
			input_file = ctx.input_file,
			output_file = ctx.output_file,
			expected_file = ctx.expected_file,
			contest_config = contest_config,
		})
	end

	vim.schedule(function()
		execute.run_problem(ctx, contest_config, true)
		vim.cmd.checktime()
	end)
end

local function diff_problem()
	if state.diff_mode then
		vim.cmd.diffoff()
		if state.saved_session then
			vim.fn.delete(state.saved_session)
			state.saved_session = nil
		end
		if state.temp_output then
			vim.fn.delete(state.temp_output)
			state.temp_output = nil
		end
		state.diff_mode = false
		return
	end

	local problem_id = get_current_problem()
	if not problem_id then
		return
	end

	local ctx = problem.create_context(state.platform, state.contest_id, state.problem_id, config)

	if vim.fn.filereadable(ctx.expected_file) == 0 then
		logger.log("no expected output file found", vim.log.levels.WARN)
		return
	end

	if vim.fn.filereadable(ctx.output_file) == 0 then
		logger.log("no output file found. run the problem first", vim.log.levels.WARN)
		return
	end

	state.saved_session = vim.fn.tempname()
	vim.cmd(("mksession! %s"):format(state.saved_session))

	vim.cmd("silent only")
	vim.cmd(("edit %s"):format(ctx.expected_file))
	vim.cmd.diffthis()
	vim.cmd(("vertical diffsplit %s"):format(ctx.output_file))
	state.diff_mode = true
end

---@param delta number 1 for next, -1 for prev
local function navigate_problem(delta)
	if not state.platform or not state.contest_id then
		logger.log("no contest set. run :CP <platform> <contest> first", vim.log.levels.ERROR)
		return
	end

	cache.load()
	local contest_data = cache.get_contest_data(state.platform, state.contest_id)
	if not contest_data or not contest_data.problems then
		logger.log("no contest metadata found. set up a problem first to cache contest data", vim.log.levels.ERROR)
		return
	end

	local problems = contest_data.problems
	local current_problem_id

	if state.platform == "cses" then
		current_problem_id = state.contest_id
	else
		current_problem_id = state.problem_id
	end

	if not current_problem_id then
		logger.log("no current problem set", vim.log.levels.ERROR)
		return
	end

	local current_index = nil
	for i, prob in ipairs(problems) do
		if prob.id == current_problem_id then
			current_index = i
			break
		end
	end

	if not current_index then
		logger.log("current problem not found in contest", vim.log.levels.ERROR)
		return
	end

	local new_index = current_index + delta

	if new_index < 1 or new_index > #problems then
		local direction = delta > 0 and "next" or "previous"
		logger.log(("no %s problem available"):format(direction), vim.log.levels.INFO)
		return
	end

	local new_problem = problems[new_index]

	if state.platform == "cses" then
		setup_problem(new_problem.id)
	else
		setup_problem(state.contest_id, new_problem.id)
	end
end

local function parse_command(args)
	if #args == 0 then
		return {
			type = "error",
			message = "Usage: :CP <platform> <contest> [problem] [--lang=<language>] | :CP <action> | :CP <problem>",
		}
	end

	local language = nil

	for i, arg in ipairs(args) do
		local lang_match = arg:match("^--lang=(.+)$")
		if lang_match then
			language = lang_match
		elseif arg == "--lang" then
			if i + 1 <= #args then
				language = args[i + 1]
			else
				return { type = "error", message = "--lang requires a value" }
			end
		end
	end

	local filtered_args = vim.tbl_filter(function(arg)
		return not (arg:match("^--lang") or arg == language)
	end, args)

	local first = filtered_args[1]

	if vim.tbl_contains(actions, first) then
		return { type = "action", action = first }
	end

	if vim.tbl_contains(platforms, first) then
		if #filtered_args == 1 then
			return { type = "platform_only", platform = first, language = language }
		elseif #filtered_args == 2 then
			if first == "cses" then
				return { type = "cses_problem", platform = first, problem = filtered_args[2], language = language }
			else
				return { type = "contest_setup", platform = first, contest = filtered_args[2], language = language }
			end
		elseif #filtered_args == 3 then
			return {
				type = "full_setup",
				platform = first,
				contest = filtered_args[2],
				problem = filtered_args[3],
				language = language,
			}
		else
			return { type = "error", message = "Too many arguments" }
		end
	end

	if state.platform and state.contest_id then
		return { type = "problem_switch", problem = first, language = language }
	end

	return { type = "error", message = "Unknown command or no contest context" }
end

function M.handle_command(opts)
	local cmd = parse_command(opts.fargs)

	if cmd.type == "error" then
		logger.log(cmd.message, vim.log.levels.ERROR)
		return
	end

	if cmd.type == "action" then
		if cmd.action == "run" then
			run_problem()
		elseif cmd.action == "debug" then
			debug_problem()
		elseif cmd.action == "diff" then
			diff_problem()
		elseif cmd.action == "next" then
			navigate_problem(1)
		elseif cmd.action == "prev" then
			navigate_problem(-1)
		end
		return
	end

	if cmd.type == "platform_only" then
		set_platform(cmd.platform)
		return
	end

	if cmd.type == "contest_setup" then
		if set_platform(cmd.platform) then
			state.contest_id = cmd.contest
			local metadata_result = scrape.scrape_contest_metadata(cmd.platform, cmd.contest)
			if not metadata_result.success then
				logger.log(
					"failed to load contest metadata: " .. (metadata_result.error or "unknown error"),
					vim.log.levels.WARN
				)
			else
				logger.log(
					("loaded %d problems for %s %s"):format(#metadata_result.problems, cmd.platform, cmd.contest)
				)
			end
		end
		return
	end

	if cmd.type == "full_setup" then
		if set_platform(cmd.platform) then
			state.contest_id = cmd.contest
			local metadata_result = scrape.scrape_contest_metadata(cmd.platform, cmd.contest)
			if not metadata_result.success then
				logger.log(
					"failed to load contest metadata: " .. (metadata_result.error or "unknown error"),
					vim.log.levels.WARN
				)
			else
				logger.log(
					("loaded %d problems for %s %s"):format(#metadata_result.problems, cmd.platform, cmd.contest)
				)
			end

			setup_problem(cmd.contest, cmd.problem, cmd.language)
		end
		return
	end

	if cmd.type == "cses_problem" then
		if set_platform(cmd.platform) then
			local metadata_result = scrape.scrape_contest_metadata(cmd.platform, "")
			if not metadata_result.success then
				logger.log(
					"failed to load contest metadata: " .. (metadata_result.error or "unknown error"),
					vim.log.levels.WARN
				)
			end
			setup_problem(cmd.problem, nil, cmd.language)
		end
		return
	end

	if cmd.type == "problem_switch" then
		if state.platform == "cses" then
			setup_problem(cmd.problem, nil, cmd.language)
		else
			setup_problem(state.contest_id, cmd.problem, cmd.language)
		end
		return
	end
end

function M.setup(opts)
	opts = opts or {}
	user_config = opts
	config = config_module.setup(user_config)
	logger.set_config(config)
	if not snippets_initialized then
		snippets.setup(config)
		snippets_initialized = true
	end
end

function M.get_current_context()
	return {
		platform = state.platform,
		contest_id = state.contest_id,
		problem_id = state.problem_id,
	}
end

function M.is_initialized()
	return true
end

return M
