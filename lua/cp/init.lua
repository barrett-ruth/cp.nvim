local config_module = require("cp.config")
local snippets = require("cp.snippets")
local execute = require("cp.execute")
local scrape = require("cp.scrape")
local window = require("cp.window")
local logger = require("cp.log")
local problem = require("cp.problem")

local M = {}
local config = {}

if not vim.fn.has("nvim-0.10.0") then
	logger.log("cp.nvim requires nvim-0.10.0+", vim.log.levels.ERROR)
	return M
end

local competition_types = { "atcoder", "codeforces", "cses" }

local function setup_contest(contest_type)
	if not vim.tbl_contains(competition_types, contest_type) then
		logger.log(
			("unknown contest type. Available: [%s]"):format(table.concat(competition_types, ", ")),
			vim.log.levels.ERROR
		)
		return
	end

	vim.g.cp_contest = contest_type
	vim.fn.mkdir("build", "p")
	vim.fn.mkdir("io", "p")
	logger.log(("set up %s contest environment"):format(contest_type))
end

local function setup_problem(contest_id, problem_id)
	if not vim.g.cp_contest then
		logger.log("no contest mode set. run :CP <contest> first", vim.log.levels.ERROR)
		return
	end

	if vim.g.cp_diff_mode then
		vim.cmd.diffoff()
		if vim.g.cp_saved_session then
			vim.fn.delete(vim.g.cp_saved_session)
			vim.g.cp_saved_session = nil
		end
		if vim.g.cp_temp_output then
			vim.fn.delete(vim.g.cp_temp_output)
			vim.g.cp_temp_output = nil
		end
		vim.g.cp_diff_mode = false
	end

	vim.cmd("silent only")

	vim.g.cp_contest_id = contest_id
	vim.g.cp_problem_id = problem_id

	local ctx = problem.create_context(vim.g.cp_contest, contest_id, problem_id, config)

	local scrape_result = scrape.scrape_problem(ctx)

	if not scrape_result.success then
		logger.log("scraping failed: " .. scrape_result.error, vim.log.levels.WARN)
		logger.log("you can manually add test cases to io/ directory", vim.log.levels.INFO)
	else
		logger.log(("scraped %d test case(s) for %s"):format(scrape_result.test_count, scrape_result.problem_id))
	end

	vim.cmd.e(ctx.source_file)

	if vim.api.nvim_buf_get_lines(0, 0, -1, true)[1] == "" then
		local has_luasnip, luasnip = pcall(require, "luasnip")
		if has_luasnip then
			vim.api.nvim_buf_set_lines(0, 0, -1, false, { vim.g.cp_contest })
			vim.api.nvim_win_set_cursor(0, { 1, #vim.g.cp_contest })
			vim.cmd.startinsert({ bang = true })

			vim.schedule(function()
				if luasnip.expandable() then
					luasnip.expand()
				end
				vim.cmd.stopinsert()
			end)
		else
			vim.api.nvim_input(("i%s<c-space><esc>"):format(vim.g.cp_contest))
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

	if not vim.g.cp_contest then
		logger.log("no contest mode set", vim.log.levels.ERROR)
		return
	end

	local contest_config = config.contests[vim.g.cp_contest]

	vim.schedule(function()
		local ctx = problem.create_context(vim.g.cp_contest, vim.g.cp_contest_id, vim.g.cp_problem_id, config)
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

	if not vim.g.cp_contest then
		logger.log("no contest mode set", vim.log.levels.ERROR)
		return
	end

	local contest_config = config.contests[vim.g.cp_contest]

	vim.schedule(function()
		local ctx = problem.create_context(vim.g.cp_contest, vim.g.cp_contest_id, vim.g.cp_problem_id, config)
		execute.run_problem(ctx, contest_config, true)
		vim.cmd.checktime()
	end)
end

local function diff_problem()
	if vim.g.cp_diff_mode then
		local tile_fn = config.tile or window.default_tile
		window.restore_layout(vim.g.cp_saved_layout, tile_fn)
		vim.g.cp_diff_mode = false
		vim.g.cp_saved_layout = nil
		logger.log("exited diff mode")
	else
		local problem_id = get_current_problem()
		if not problem_id then
			return
		end

		local ctx = problem.create_context(vim.g.cp_contest, vim.g.cp_contest_id, vim.g.cp_problem_id, config)

		if vim.fn.filereadable(ctx.expected_file) == 0 then
			logger.log(("No expected output file found: %s"):format(ctx.expected_file), vim.log.levels.ERROR)
			return
		end

		vim.g.cp_saved_layout = window.save_layout()

		local result = vim.system({ "awk", "/^\\[[^]]*\\]:/ {exit} {print}", ctx.output_file }, { text = true }):wait()
		local actual_output = result.stdout

		window.setup_diff_layout(actual_output, ctx.expected_file, ctx.input_file)

		vim.g.cp_diff_mode = true
		logger.log("entered diff mode")
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

function M.handle_command(opts)
	local args = opts.fargs
	if #args == 0 then
		logger.log("Usage: :CP <contest|problem_id|run|debug|diff>", vim.log.levels.ERROR)
		return
	end

	local cmd = args[1]

	if vim.tbl_contains(competition_types, cmd) then
		if args[2] then
			setup_contest(cmd)
			if (cmd == "atcoder" or cmd == "codeforces") and args[3] then
				setup_problem(args[2], args[3])
			else
				setup_problem(args[2])
			end
		else
			setup_contest(cmd)
		end
	elseif cmd == "run" then
		run_problem()
	elseif cmd == "debug" then
		debug_problem()
	elseif cmd == "diff" then
		diff_problem()
	elseif vim.g.cp_contest and not vim.tbl_contains(competition_types, cmd) then
		if (vim.g.cp_contest == "atcoder" or vim.g.cp_contest == "codeforces") and args[2] then
			setup_problem(cmd, args[2])
		else
			setup_problem(cmd)
		end
	else
		logger.log(
			("unknown contest type '%s'. Available: [%s]"):format(cmd, table.concat(competition_types, ", ")),
			vim.log.levels.ERROR
		)
	end
end

return M
