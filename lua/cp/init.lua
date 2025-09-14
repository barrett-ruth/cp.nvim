local config_module = require("cp.config")
local snippets = require("cp.snippets")
local execute = require("cp.execute")
local scrape = require("cp.scrape")
local window = require("cp.window")
local logger = require("cp.log")
local problem = require("cp.problem")
local cache = require("cp.cache")

local M = {}
local config = {}

if not vim.fn.has("nvim-0.10.0") then
	logger.log("cp.nvim requires nvim-0.10.0+", vim.log.levels.ERROR)
	return M
end

local platforms = { "atcoder", "codeforces", "cses" }
local actions = { "run", "debug", "diff", "next", "prev" }

local function set_platform(platform)
	if not vim.tbl_contains(platforms, platform) then
		logger.log(("unknown platform. Available: [%s]"):format(table.concat(platforms, ", ")), vim.log.levels.ERROR)
		return false
	end

	vim.g.cp = vim.g.cp or {}
	vim.g.cp.platform = platform
	vim.fn.mkdir("build", "p")
	vim.fn.mkdir("io", "p")
	return true
end

---@param contest_id string
---@param problem_id? string
local function setup_problem(contest_id, problem_id)
	if not vim.g.cp or not vim.g.cp.platform then
		logger.log("no platform set. run :CP <platform> <contest> first", vim.log.levels.ERROR)
		return
	end

	local metadata_result = scrape.scrape_contest_metadata(vim.g.cp.platform, contest_id)
	if not metadata_result.success then
		logger.log("failed to load contest metadata: " .. (metadata_result.error or "unknown error"), vim.log.levels.WARN)
	end

	if vim.g.cp and vim.g.cp.diff_mode then
		vim.cmd.diffoff()
		if vim.g.cp.saved_session then
			vim.fn.delete(vim.g.cp.saved_session)
			vim.g.cp.saved_session = nil
		end
		if vim.g.cp.temp_output then
			vim.fn.delete(vim.g.cp.temp_output)
			vim.g.cp.temp_output = nil
		end
		vim.g.cp.diff_mode = false
	end

	vim.cmd("silent only")

	vim.g.cp.contest_id = contest_id
	vim.g.cp.problem_id = problem_id

	local ctx = problem.create_context(vim.g.cp.platform, contest_id, problem_id, config)

	local scrape_result = scrape.scrape_problem(ctx)

	if not scrape_result.success then
		logger.log("scraping failed: " .. (scrape_result.error or "unknown error"), vim.log.levels.WARN)
		logger.log("you can manually add test cases to io/ directory", vim.log.levels.INFO)
	else
		local test_count = scrape_result.test_count or 0
		logger.log(("scraped %d test case(s) for %s"):format(test_count, scrape_result.problem_id))
	end

	vim.cmd.e(ctx.source_file)

	if vim.api.nvim_buf_get_lines(0, 0, -1, true)[1] == "" then
		local has_luasnip, luasnip = pcall(require, "luasnip")
		if has_luasnip then
			vim.api.nvim_buf_set_lines(0, 0, -1, false, { vim.g.cp.platform })
			vim.api.nvim_win_set_cursor(0, { 1, #vim.g.cp.platform })
			vim.cmd.startinsert({ bang = true })

			vim.schedule(function()
				if luasnip.expandable() then
					luasnip.expand()
				end
				vim.cmd.stopinsert()
			end)
		else
			vim.api.nvim_input(("i%s<c-space><esc>"):format(vim.g.cp.platform))
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

	if config.hooks and config.hooks.before_run then
		config.hooks.before_run(problem_id)
	end

	if not vim.g.cp or not vim.g.cp.platform then
		logger.log("no platform set", vim.log.levels.ERROR)
		return
	end

	local contest_config = config.contests[vim.g.cp.platform]

	vim.schedule(function()
		local ctx = problem.create_context(vim.g.cp.platform, vim.g.cp.contest_id, vim.g.cp.problem_id, config)
		execute.run_problem(ctx, contest_config, false)
		vim.cmd.checktime()
	end)
end

local function debug_problem()
	local problem_id = get_current_problem()
	if not problem_id then
		return
	end

	if config.hooks and config.hooks.before_debug then
		config.hooks.before_debug(problem_id)
	end

	if not vim.g.cp or not vim.g.cp.platform then
		logger.log("no platform set", vim.log.levels.ERROR)
		return
	end

	local contest_config = config.contests[vim.g.cp.platform]

	vim.schedule(function()
		local ctx = problem.create_context(vim.g.cp.platform, vim.g.cp.contest_id, vim.g.cp.problem_id, config)
		execute.run_problem(ctx, contest_config, true)
		vim.cmd.checktime()
	end)
end

local function diff_problem()
	if vim.g.cp and vim.g.cp.diff_mode then
		local tile_fn = config.tile or window.default_tile
		window.restore_layout(vim.g.cp.saved_layout, tile_fn)
		vim.g.cp.diff_mode = false
		vim.g.cp.saved_layout = nil
		logger.log("exited diff mode")
	else
		local problem_id = get_current_problem()
		if not problem_id then
			return
		end

		local ctx = problem.create_context(vim.g.cp.platform, vim.g.cp.contest_id, vim.g.cp.problem_id, config)

		if vim.fn.filereadable(ctx.expected_file) == 0 then
			logger.log(("No expected output file found: %s"):format(ctx.expected_file), vim.log.levels.ERROR)
			return
		end

		vim.g.cp = vim.g.cp or {}
		vim.g.cp.saved_layout = window.save_layout()

		local result = vim.system({ "awk", "/^\\[[^]]*\\]:/ {exit} {print}", ctx.output_file }, { text = true }):wait()
		local actual_output = result.stdout

		window.setup_diff_layout(actual_output, ctx.expected_file, ctx.input_file)

		vim.g.cp.diff_mode = true
		logger.log("entered diff mode")
	end
end

---@param delta number 1 for next, -1 for prev
local function navigate_problem(delta)
	if not vim.g.cp or not vim.g.cp.platform or not vim.g.cp.contest_id then
		logger.log("no contest set. run :CP <platform> <contest> first", vim.log.levels.ERROR)
		return
	end

	cache.load()
	local contest_data = cache.get_contest_data(vim.g.cp.platform, vim.g.cp.contest_id)
	if not contest_data or not contest_data.problems then
		logger.log("no contest metadata found. set up a problem first to cache contest data", vim.log.levels.ERROR)
		return
	end

	local problems = contest_data.problems
	local current_problem_id

	if vim.g.cp.platform == "cses" then
		current_problem_id = vim.g.cp.contest_id
	else
		current_problem_id = vim.g.cp.problem_id
	end

	if not current_problem_id then
		logger.log("no current problem set", vim.log.levels.ERROR)
		return
	end

	local current_index = nil
	for i, problem in ipairs(problems) do
		if problem.id == current_problem_id then
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

	if vim.g.cp.platform == "cses" then
		setup_problem(new_problem.id)
	else
		setup_problem(vim.g.cp.contest_id, new_problem.id)
	end
end

local initialized = false

function M.is_initialized()
	return initialized
end

function M.setup(user_config)
	if initialized and not user_config then
		return
	end

	config = config_module.setup(user_config)
	logger.set_config(config)
	snippets.setup(config)
	initialized = true
end

local function parse_command(args)
	if #args == 0 then
		return { type = "error", message = "Usage: :CP <platform> <contest> [problem] | :CP <action> | :CP <problem>" }
	end

	local first = args[1]

	if vim.tbl_contains(actions, first) then
		return { type = "action", action = first }
	end

	if vim.tbl_contains(platforms, first) then
		if #args == 1 then
			return { type = "platform_only", platform = first }
		elseif #args == 2 then
			return { type = "contest_setup", platform = first, contest = args[2] }
		elseif #args == 3 then
			return { type = "full_setup", platform = first, contest = args[2], problem = args[3] }
		else
			return { type = "error", message = "Too many arguments" }
		end
	end

	if vim.g.cp and vim.g.cp.platform and vim.g.cp.contest_id then
		return { type = "problem_switch", problem = first }
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
			vim.g.cp.contest_id = cmd.contest
			local metadata_result = scrape.scrape_contest_metadata(cmd.platform, cmd.contest)
			if not metadata_result.success then
				logger.log("failed to load contest metadata: " .. (metadata_result.error or "unknown error"), vim.log.levels.WARN)
			else
				logger.log(("loaded %d problems for %s %s"):format(#metadata_result.problems, cmd.platform, cmd.contest))
			end
		end
		return
	end

	if cmd.type == "full_setup" then
		if set_platform(cmd.platform) then
			vim.g.cp.contest_id = cmd.contest
			setup_problem(cmd.contest, cmd.problem)
		end
		return
	end

	if cmd.type == "problem_switch" then
		if vim.g.cp.platform == "cses" then
			setup_problem(cmd.problem)
		else
			setup_problem(vim.g.cp.contest_id, cmd.problem)
		end
		return
	end
end

return M
