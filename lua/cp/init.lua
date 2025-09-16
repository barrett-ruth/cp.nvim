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
	saved_layout = nil,
	saved_session = nil,
	test_cases = nil,
	test_states = {},
	test_panel_active = false,
}

local constants = require("cp.constants")
local platforms = constants.PLATFORMS
local actions = constants.ACTIONS

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

	vim.cmd("silent only")

	state.contest_id = contest_id
	state.problem_id = problem_id

	local cached_test_cases = cache.get_test_cases(state.platform, contest_id, problem_id)
	if cached_test_cases then
		state.test_cases = cached_test_cases
	end

	local scrape_ctx = problem.create_context(state.platform, contest_id, problem_id, config, language)

	local scrape_result = scrape.scrape_problem(scrape_ctx)

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

	vim.cmd.e(scrape_ctx.source_file)
	local source_buf = vim.api.nvim_get_current_buf()

	if vim.api.nvim_buf_get_lines(source_buf, 0, -1, true)[1] == "" then
		local has_luasnip, luasnip = pcall(require, "luasnip")
		if has_luasnip then
			local filetype = vim.api.nvim_get_option_value("filetype", { buf = source_buf })
			local language_name = constants.filetype_to_language[filetype]
			local canonical_language = constants.canonical_filetypes[language_name] or language_name
			local prefixed_trigger = ("cp.nvim/%s.%s"):format(state.platform, canonical_language)

			vim.api.nvim_buf_set_lines(0, 0, -1, false, { prefixed_trigger })
			vim.api.nvim_win_set_cursor(0, { 1, #prefixed_trigger })
			vim.cmd.startinsert({ bang = true })

			vim.schedule(function()
				if luasnip.expandable() then
					luasnip.expand()
				else
					vim.api.nvim_buf_set_lines(0, 0, 1, false, { "" })
					vim.api.nvim_win_set_cursor(0, { 1, 0 })
				end
				vim.cmd.stopinsert()
			end)
		else
			vim.api.nvim_input(("i%s<c-space><esc>"):format(state.platform))
		end
	end

	local ctx = problem.create_context(state.platform, state.contest_id, state.problem_id, config, language)

	if config.hooks and config.hooks.setup_code then
		config.hooks.setup_code(ctx)
	end

	local src_buf = vim.api.nvim_get_current_buf()
	local input_buf = vim.fn.bufnr(ctx.input_file, true)
	local output_buf = vim.fn.bufnr(ctx.output_file, true)

	local tile_fn = config.tile or window.default_tile
	tile_fn(src_buf, input_buf, output_buf)

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
		logger.log(
			"No contest configured. Use :CP <platform> <contest> <problem> to set up first.",
			vim.log.levels.ERROR
		)
		return
	end

	local contest_config = config.contests[state.platform]
	local ctx = problem.create_context(state.platform, state.contest_id, state.problem_id, config)

	if config.hooks and config.hooks.before_run then
		config.hooks.before_run(ctx)
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
		config.hooks.before_debug(ctx)
	end

	vim.schedule(function()
		execute.run_problem(ctx, contest_config, true)
		vim.cmd.checktime()
	end)
end

local function toggle_test_panel()
	if state.test_panel_active then
		if state.saved_session then
			vim.cmd(("source %s"):format(state.saved_session))
			vim.fn.delete(state.saved_session)
			state.saved_session = nil
		end
		state.test_panel_active = false
		logger.log("test panel closed")
		return
	end

	if not state.platform then
		logger.log(
			"No contest configured. Use :CP <platform> <contest> <problem> to set up first.",
			vim.log.levels.ERROR
		)
		return
	end

	if state.platform == "codeforces" then
		logger.log("test panel not yet supported for codeforces", vim.log.levels.ERROR)
		return
	end

	local problem_id = get_current_problem()
	if not problem_id then
		return
	end

	local ctx = problem.create_context(state.platform, state.contest_id, state.problem_id, config)
	local test_module = require("cp.test")

	if not test_module.load_test_cases(ctx, state) then
		logger.log("no test cases found", vim.log.levels.WARN)
		return
	end

	state.saved_session = vim.fn.tempname()
	vim.cmd(("mksession! %s"):format(state.saved_session))

	vim.cmd("silent only")

	local tab_buf = vim.api.nvim_create_buf(false, true)
	local expected_buf = vim.api.nvim_create_buf(false, true)
	local actual_buf = vim.api.nvim_create_buf(false, true)

	vim.api.nvim_buf_set_option(tab_buf, "bufhidden", "wipe")
	vim.api.nvim_buf_set_option(expected_buf, "bufhidden", "wipe")
	vim.api.nvim_buf_set_option(actual_buf, "bufhidden", "wipe")

	local main_win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(main_win, tab_buf)
	vim.api.nvim_buf_set_option(tab_buf, "filetype", "cptest")

	vim.cmd("split")
	local content_win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(content_win, actual_buf)
	vim.api.nvim_buf_set_option(actual_buf, "filetype", "cptest")

	vim.cmd("vsplit")
	local expected_win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(expected_win, expected_buf)
	vim.api.nvim_buf_set_option(expected_buf, "filetype", "cptest")

	local test_windows = {
		tab_win = main_win,
		actual_win = content_win,
		expected_win = expected_win,
	}
	local test_buffers = {
		tab_buf = tab_buf,
		expected_buf = expected_buf,
		actual_buf = actual_buf,
	}

	local function render_test_tabs()
		local test_state = test_module.get_test_panel_state()
		local tab_lines = {}

		local max_status_width = 0
		local max_code_width = 0
		local max_time_width = 0

		for _, test_case in ipairs(test_state.test_cases) do
			local status_text = test_case.status == "pending" and "" or string.upper(test_case.status)
			max_status_width = math.max(max_status_width, #status_text)

			if test_case.code then
				max_code_width = math.max(max_code_width, #tostring(test_case.code))
			end

			if test_case.time_ms then
				local time_text = string.format("%.0fms", test_case.time_ms)
				max_time_width = math.max(max_time_width, #time_text)
			end
		end

		for i, test_case in ipairs(test_state.test_cases) do
			local prefix = i == test_state.current_index and "> " or "  "
			local tab = string.format("%s%d.", prefix, i)

			if test_case.code then
				tab = tab .. string.format(" [code:%-" .. max_code_width .. "s]", tostring(test_case.code))
			end

			if test_case.time_ms then
				local time_text = string.format("%.0fms", test_case.time_ms)
				tab = tab .. string.format(" [time:%-" .. max_time_width .. "s]", time_text)
			end

			if test_case.ok ~= nil then
				tab = tab .. string.format(" [ok:%-5s]", tostring(test_case.ok))
			end

			if test_case.signal then
				tab = tab .. string.format(" [%s]", test_case.signal)
			end

			table.insert(tab_lines, tab)
		end

		local current_test = test_state.test_cases[test_state.current_index]
		if current_test then
			table.insert(tab_lines, "")
			table.insert(tab_lines, "Input:")
			table.insert(tab_lines, "")
			for _, line in ipairs(vim.split(current_test.input, "\n", { plain = true, trimempty = true })) do
				table.insert(tab_lines, line)
			end
		end

		return tab_lines
	end


	local function update_expected_pane()
		local test_state = test_module.get_test_panel_state()
		local current_test = test_state.test_cases[test_state.current_index]

		if not current_test then
			return
		end

		local expected_lines = {}
		table.insert(expected_lines, "Expected:")
		table.insert(expected_lines, "")

		local expected_text = current_test.expected
		for _, line in ipairs(vim.split(expected_text, "\n", { plain = true, trimempty = true })) do
			table.insert(expected_lines, line)
		end

		vim.api.nvim_buf_set_lines(test_buffers.expected_buf, 0, -1, false, expected_lines)
	end

	local function update_actual_pane()
		local test_state = test_module.get_test_panel_state()
		local current_test = test_state.test_cases[test_state.current_index]

		if not current_test then
			return
		end

		local actual_lines = {}

		if current_test.actual then
			table.insert(actual_lines, "Actual:")
			table.insert(actual_lines, "")
			for _, line in ipairs(vim.split(current_test.actual, "\n", { plain = true, trimempty = true })) do
				table.insert(actual_lines, line)
			end

			if current_test.status == "fail" then
				vim.api.nvim_win_set_option(test_windows.expected_win, "diff", true)
				vim.api.nvim_win_set_option(test_windows.actual_win, "diff", true)
			else
				vim.api.nvim_win_set_option(test_windows.expected_win, "diff", false)
				vim.api.nvim_win_set_option(test_windows.actual_win, "diff", false)
			end
		else
			table.insert(actual_lines, "Actual:")
			table.insert(actual_lines, "(not run yet)")

			vim.api.nvim_win_set_option(test_windows.expected_win, "diff", false)
			vim.api.nvim_win_set_option(test_windows.actual_win, "diff", false)
		end

		vim.api.nvim_buf_set_lines(test_buffers.actual_buf, 0, -1, false, actual_lines)
	end

	local function refresh_test_panel()
		if not test_buffers.tab_buf or not vim.api.nvim_buf_is_valid(test_buffers.tab_buf) then
			return
		end

		local tab_lines = render_test_tabs()
		vim.api.nvim_buf_set_lines(test_buffers.tab_buf, 0, -1, false, tab_lines)

		update_expected_pane()
		update_actual_pane()
	end

	local function navigate_test_case(delta)
		local test_state = test_module.get_test_panel_state()
		if #test_state.test_cases == 0 then
			return
		end

		test_state.current_index = test_state.current_index + delta
		if test_state.current_index < 1 then
			test_state.current_index = #test_state.test_cases
		elseif test_state.current_index > #test_state.test_cases then
			test_state.current_index = 1
		end

		refresh_test_panel()
	end

	vim.keymap.set("n", "j", function()
		navigate_test_case(1)
	end, { buffer = test_buffers.tab_buf, silent = true })
	vim.keymap.set("n", "k", function()
		navigate_test_case(-1)
	end, { buffer = test_buffers.tab_buf, silent = true })

	for _, buf in pairs(test_buffers) do
		vim.keymap.set("n", "q", function()
			toggle_test_panel()
		end, { buffer = buf, silent = true })
	end

	local execute_module = require("cp.execute")
	local contest_config = config.contests[state.platform]
	if execute_module.compile_problem(ctx, contest_config) then
		test_module.run_all_test_cases(ctx, contest_config)
	end

	refresh_test_panel()

	vim.api.nvim_set_current_win(test_windows.tab_win)

	state.test_panel_active = true
	state.test_buffers = test_buffers
	state.test_windows = test_windows
	local test_state = test_module.get_test_panel_state()
	logger.log(string.format("test panel opened (%d test cases)", #test_state.test_cases))
end

---@param delta number 1 for next, -1 for prev
---@param language? string
local function navigate_problem(delta, language)
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
		setup_problem(new_problem.id, nil, language)
	else
		setup_problem(state.contest_id, new_problem.id, language)
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
		return { type = "action", action = first, language = language }
	end

	if vim.tbl_contains(platforms, first) then
		if #filtered_args == 1 then
			return {
				type = "platform_only",
				platform = first,
				language = language,
			}
		elseif #filtered_args == 2 then
			if first == "cses" then
				return {
					type = "cses_problem",
					platform = first,
					problem = filtered_args[2],
					language = language,
				}
			else
				return {
					type = "contest_setup",
					platform = first,
					contest = filtered_args[2],
					language = language,
				}
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
		elseif cmd.action == "test" then
			toggle_test_panel()
		elseif cmd.action == "next" then
			navigate_problem(1, cmd.language)
		elseif cmd.action == "prev" then
			navigate_problem(-1, cmd.language)
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
