local M = {}
local logger = require("cp.log")
local cache = require("cp.cache")

local function get_plugin_path()
	local plugin_path = debug.getinfo(1, "S").source:sub(2)
	return vim.fn.fnamemodify(plugin_path, ":h:h:h")
end

local function ensure_io_directory()
	vim.fn.mkdir("io", "p")
end

local function setup_python_env()
	local plugin_path = get_plugin_path()
	local venv_dir = plugin_path .. "/.venv"

	if vim.fn.executable("uv") == 0 then
		logger.log(
			"uv is not installed. Install it to enable problem scraping: https://docs.astral.sh/uv/",
			vim.log.levels.WARN
		)
		return false
	end

	if vim.fn.isdirectory(venv_dir) == 0 then
		logger.log("setting up Python environment for scrapers...")
		local result = vim.system({ "uv", "sync" }, { cwd = plugin_path, text = true }):wait()
		if result.code ~= 0 then
			logger.log("failed to setup Python environment: " .. result.stderr, vim.log.levels.ERROR)
			return false
		end
		logger.log("python environment setup complete")
	end

	return true
end

---@param contest_type string
---@param contest_id string
---@return {success: boolean, problems?: table[], error?: string}
function M.scrape_contest_metadata(contest_type, contest_id)
	cache.load()

	local cached_data = cache.get_contest_data(contest_type, contest_id)
	if cached_data then
		return {
			success = true,
			problems = cached_data.problems,
		}
	end

	if not setup_python_env() then
		return {
			success = false,
			error = "Python environment setup failed",
		}
	end

	local plugin_path = get_plugin_path()
	local scraper_path = plugin_path .. "/scrapers/" .. contest_type .. ".py"
	local args = { "uv", "run", scraper_path, "metadata", contest_id }

	local result = vim.system(args, {
		cwd = plugin_path,
		text = true,
		timeout = 30000,
	}):wait()

	if result.code ~= 0 then
		return {
			success = false,
			error = "Failed to run metadata scraper: " .. (result.stderr or "Unknown error"),
		}
	end

	local ok, data = pcall(vim.json.decode, result.stdout)
	if not ok then
		return {
			success = false,
			error = "Failed to parse metadata scraper output: " .. tostring(data),
		}
	end

	if not data.success then
		return data
	end

	local problems_list
	if contest_type == "cses" then
		problems_list = data.categories and data.categories["CSES Problem Set"] or {}
	else
		problems_list = data.problems or {}
	end

	cache.set_contest_data(contest_type, contest_id, problems_list)
	return {
		success = true,
		problems = problems_list,
	}
end

---@param ctx ProblemContext
---@return {success: boolean, problem_id: string, test_count?: number, url?: string, error?: string}
function M.scrape_problem(ctx)
	ensure_io_directory()

	if vim.fn.filereadable(ctx.input_file) == 1 and vim.fn.filereadable(ctx.expected_file) == 1 then
		return {
			success = true,
			problem_id = ctx.problem_name,
			test_count = 1,
		}
	end

	if not setup_python_env() then
		return {
			success = false,
			problem_id = ctx.problem_name,
			error = "Python environment setup failed",
		}
	end

	local plugin_path = get_plugin_path()
	local scraper_path = plugin_path .. "/scrapers/" .. ctx.contest .. ".py"

	local args
	if ctx.contest == "cses" then
		args = { "uv", "run", scraper_path, "tests", ctx.contest_id }
	else
		args = { "uv", "run", scraper_path, "tests", ctx.contest_id, ctx.problem_id }
	end

	local result = vim.system(args, {
		cwd = plugin_path,
		text = true,
		timeout = 30000,
	}):wait()

	if result.code ~= 0 then
		return {
			success = false,
			problem_id = ctx.problem_name,
			error = "Failed to run tests scraper: " .. (result.stderr or "Unknown error"),
		}
	end

	local ok, data = pcall(vim.json.decode, result.stdout)
	if not ok then
		return {
			success = false,
			problem_id = ctx.problem_name,
			error = "Failed to parse tests scraper output: " .. tostring(data),
		}
	end

	if not data.success then
		return data
	end

	if data.test_cases and #data.test_cases > 0 then
		local all_inputs = {}
		local all_outputs = {}

		for _, test_case in ipairs(data.test_cases) do
			local input_lines = vim.split(test_case.input:gsub("\r", ""):gsub("\n+$", ""), "\n")
			local output_lines = vim.split(test_case.output:gsub("\r", ""):gsub("\n+$", ""), "\n")

			for _, line in ipairs(input_lines) do
				table.insert(all_inputs, line)
			end

			for _, line in ipairs(output_lines) do
				table.insert(all_outputs, line)
			end
		end

		vim.fn.writefile(all_inputs, ctx.input_file)
		vim.fn.writefile(all_outputs, ctx.expected_file)
	end

	return {
		success = true,
		problem_id = ctx.problem_name,
		test_count = data.test_cases and #data.test_cases or 0,
		url = data.url,
	}
end

return M
