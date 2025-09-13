local M = {}
local logger = require("cp.log")

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

function M.scrape_problem(contest, problem_id, problem_letter)
	ensure_io_directory()

	local cache_problem_id = problem_id:lower()
	if contest == "atcoder" or contest == "codeforces" then
		if problem_letter then
			cache_problem_id = cache_problem_id .. problem_letter:lower()
		end
	end

	local input_file = "io/" .. cache_problem_id .. ".in"
	local expected_file = "io/" .. cache_problem_id .. ".expected"

	if vim.fn.filereadable(input_file) == 1 and vim.fn.filereadable(expected_file) == 1 then
		return {
			success = true,
			problem_id = cache_problem_id,
			test_count = 1,
		}
	end

	if not setup_python_env() then
		return {
			success = false,
			error = "Python environment setup failed",
		}
	end

	local plugin_path = get_plugin_path()
	local scraper_path = plugin_path .. "/scrapers/" .. contest .. ".py"

	local args
	if contest == "cses" then
		args = { "uv", "run", scraper_path, problem_id }
	else
		args = { "uv", "run", scraper_path, problem_id, problem_letter }
	end

	local result = vim.system(args, {
		cwd = plugin_path,
		text = true,
		timeout = 30000,
	}):wait()

	if result.code ~= 0 then
		return {
			success = false,
			error = "Failed to run scraper: " .. (result.stderr or "Unknown error"),
		}
	end

	local ok, data = pcall(vim.json.decode, result.stdout)
	if not ok then
		return {
			success = false,
			error = "Failed to parse scraper output: " .. tostring(data),
		}
	end

	if not data.success then
		return data
	end

	local full_problem_id = data.problem_id:lower()
	input_file = "io/" .. full_problem_id .. ".in"
	expected_file = "io/" .. full_problem_id .. ".expected"

	if #data.test_cases > 0 then
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

		vim.fn.writefile(all_inputs, input_file)
		vim.fn.writefile(all_outputs, expected_file)
	end

	return {
		success = true,
		problem_id = full_problem_id,
		test_count = #data.test_cases,
		url = data.url,
	}
end

return M
