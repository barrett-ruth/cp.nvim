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

---@param ctx ProblemContext
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
			error = "Python environment setup failed",
		}
	end

	local plugin_path = get_plugin_path()
	local scraper_path = plugin_path .. "/scrapers/" .. ctx.contest .. ".py"

	local args
	if ctx.contest == "cses" then
		args = { "uv", "run", scraper_path, ctx.problem_id }
	else
		args = { "uv", "run", scraper_path, ctx.problem_id, ctx.problem_letter }
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

		vim.fn.writefile(all_inputs, ctx.input_file)
		vim.fn.writefile(all_outputs, ctx.expected_file)
	end

	return {
		success = true,
		problem_id = ctx.problem_name,
		test_count = #data.test_cases,
		url = data.url,
	}
end

return M
