local config_module = require("cp.config")
local snippets = require("cp.snippets")

local M = {}
local config = {}

local function log(msg, level)
	vim.notify(("[cp.nvim]: %s"):format(msg), level or vim.log.levels.INFO)
end

local function clearcol()
	vim.api.nvim_set_option_value("number", false, { scope = "local" })
	vim.api.nvim_set_option_value("relativenumber", false, { scope = "local" })
	vim.api.nvim_set_option_value("statuscolumn", "", { scope = "local" })
	vim.api.nvim_set_option_value("signcolumn", "no", { scope = "local" })
	vim.api.nvim_set_option_value("equalalways", false, { scope = "global" })
end

local function get_plugin_path()
	local plugin_path = debug.getinfo(1, "S").source:sub(2)
	return vim.fn.fnamemodify(plugin_path, ":h:h:h")
end

local function setup_python_env()
	local plugin_path = get_plugin_path()
	local venv_dir = plugin_path .. "/.venv"

	if vim.fn.executable("uv") == 0 then
		log(
			"uv is not installed. Install it to enable problem scraping: https://docs.astral.sh/uv/",
			vim.log.levels.WARN
		)
		return false
	end

	if vim.fn.isdirectory(venv_dir) == 0 then
		log("setting up Python environment for scrapers...")
		local result = vim.fn.system(("cd %s && uv sync"):format(vim.fn.shellescape(plugin_path)))
		if vim.v.shell_error ~= 0 then
			log("failed to setup Python environment: " .. result, vim.log.levels.ERROR)
			return false
		end
		log("python environment setup complete")
	end

	return true
end

local competition_types = { "atcoder", "codeforces", "cses" }

local function setup_contest(contest_type)
	if not vim.tbl_contains(competition_types, contest_type) then
		log(
			("unknown contest type. Available: [%s]"):format(table.concat(competition_types, ", ")),
			vim.log.levels.ERROR
		)
		return
	end

	vim.g.cp_contest = contest_type
	vim.fn.system(("cp -fr %s/* ."):format(config.template_dir))
	vim.fn.system(("make setup VERSION=%s"):format(config.contests[contest_type].cpp_version))
	log(("set up %s contest environment"):format(contest_type))
end

local function setup_problem(problem_id, problem_letter)
	if not vim.g.cp_contest then
		log("no contest mode set. run :CP <contest> first", vim.log.levels.ERROR)
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

	vim.cmd.only()

	local filename, full_problem_id
	if (vim.g.cp_contest == "atcoder" or vim.g.cp_contest == "codeforces") and problem_letter then
		full_problem_id = problem_id .. problem_letter
		filename = full_problem_id .. ".cc"
		vim.fn.system(("make scrape %s %s %s"):format(vim.g.cp_contest, problem_id, problem_letter))
	else
		full_problem_id = problem_id
		filename = problem_id .. ".cc"
		vim.fn.system(("make scrape %s %s"):format(vim.g.cp_contest, problem_id))
	end

	vim.cmd.e(filename)

	if vim.api.nvim_buf_get_lines(0, 0, -1, true)[1] == "" then
		vim.api.nvim_input(("i%s<c-space><esc>"):format(vim.g.cp_contest))
	end

	vim.api.nvim_set_option_value("winbar", "", { scope = "local" })
	vim.api.nvim_set_option_value("foldlevel", 0, { scope = "local" })
	vim.api.nvim_set_option_value("foldmethod", "marker", { scope = "local" })
	vim.api.nvim_set_option_value("foldmarker", "{{{,}}}", { scope = "local" })
	vim.api.nvim_set_option_value("foldtext", "", { scope = "local" })

	vim.diagnostic.enable(false)

	local base_fp = vim.fn.fnamemodify(filename, ":p:h")
	local input = ("%s/io/%s.in"):format(base_fp, full_problem_id)
	local output = ("%s/io/%s.out"):format(base_fp, full_problem_id)

	vim.cmd.vsplit(output)
	vim.cmd.w()
	clearcol()
	vim.cmd(("vertical resize %d"):format(math.floor(vim.o.columns * 0.3)))
	vim.cmd.split(input)
	vim.cmd.w()
	clearcol()
	vim.cmd.wincmd("h")

	log(("switched to problem %s"):format(full_problem_id))
end

local function get_current_problem()
	local filename = vim.fn.expand("%:t:r")
	if filename == "" then
		log("no file open", vim.log.levels.ERROR)
		return nil
	end
	return filename
end

local function run_problem()
	local problem_id = get_current_problem()
	if not problem_id then
		return
	end

	local has_lsp, lsp = pcall(require, "lsp")
	if has_lsp and lsp.lsp_format then
		lsp.lsp_format({ async = true })
	end

	vim.system({ "make", "run", vim.fn.expand("%:t") }, {}, function()
		vim.schedule(function()
			vim.cmd.checktime()
		end)
	end)
end

local function debug_problem()
	local problem_id = get_current_problem()
	if not problem_id then
		return
	end

	local has_lsp, lsp = pcall(require, "lsp")
	if has_lsp and lsp.lsp_format then
		lsp.lsp_format({ async = true })
	end

	vim.system({ "make", "debug", vim.fn.expand("%:t") }, {}, function()
		vim.schedule(function()
			vim.cmd.checktime()
		end)
	end)
end

local function diff_problem()
	if vim.g.cp_diff_mode then
		vim.cmd.diffoff()
		if vim.g.cp_saved_session then
			vim.cmd(("silent! source %s"):format(vim.g.cp_saved_session))
			vim.fn.delete(vim.g.cp_saved_session)
			vim.g.cp_saved_session = nil
		end
		vim.g.cp_diff_mode = false
		log("exited diff mode")
	else
		local problem_id = get_current_problem()
		if not problem_id then
			return
		end

		local base_fp = vim.fn.getcwd()
		local output = ("%s/io/%s.out"):format(base_fp, problem_id)
		local expected = ("%s/io/%s.expected"):format(base_fp, problem_id)
		local input = ("%s/io/%s.in"):format(base_fp, problem_id)

		if vim.fn.filereadable(expected) == 0 then
			log(("No expected output file found: %s"):format(expected), vim.log.levels.ERROR)
			return
		end

		local temp_output = vim.fn.tempname()
		vim.fn.system(("awk '/^\\[[^]]*\\]:/ {exit} {print}' %s > %s"):format(vim.fn.shellescape(output), temp_output))

		local session_file = vim.fn.tempname() .. ".vim"
		vim.cmd(("silent! mksession! %s"):format(session_file))
		vim.g.cp_saved_session = session_file

		vim.cmd.diffoff()
		vim.cmd.only()

		vim.cmd.edit(temp_output)
		vim.cmd.diffthis()
		clearcol()

		vim.cmd.vsplit(expected)
		vim.cmd.diffthis()
		clearcol()

		vim.cmd(("botright split %s"):format(input))
		clearcol()
		vim.cmd.wincmd("k")

		vim.g.cp_diff_mode = true
		vim.g.cp_temp_output = temp_output
		log("entered diff mode")
	end
end

local initialized = false

function M.setup(user_config)
	if initialized and not user_config then
		return
	end

	config = config_module.setup(user_config)

	local plugin_path = get_plugin_path()
	config.template_dir = plugin_path .. "/templates"
	config.snippets.path = plugin_path .. "/templates/snippets"

	snippets.setup(config)

	if initialized then
		return
	end
	initialized = true

	setup_python_env()

	vim.api.nvim_create_user_command("CP", function(opts)
		local args = opts.fargs
		if #args == 0 then
			log("Usage: :CP <contest|problem_id|run|debug|diff>", vim.log.levels.ERROR)
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
		else
			if vim.g.cp_contest then
				if (vim.g.cp_contest == "atcoder" or vim.g.cp_contest == "codeforces") and args[2] then
					setup_problem(cmd, args[2])
				else
					setup_problem(cmd)
				end
			else
				log("no contest mode set. run :CP <contest> first or use full command", vim.log.levels.ERROR)
			end
		end
	end, {
		nargs = "*",
		complete = function(ArgLead, CmdLine, ...)
			local commands = vim.list_extend(vim.deepcopy(competition_types), { "run", "debug", "diff" })
			return vim.tbl_filter(function(cmd)
				return cmd:find(ArgLead, 1, true) == 1
			end, commands)
		end,
	})
end

return M
