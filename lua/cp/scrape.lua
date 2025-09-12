local M = {}

local function get_plugin_path()
	local plugin_path = debug.getinfo(1, "S").source:sub(2)
	return vim.fn.fnamemodify(plugin_path, ":h:h:h")
end

local function ensure_io_directory()
	vim.fn.mkdir("io", "p")
end

function M.scrape_problem(contest, problem_id, problem_letter)
	ensure_io_directory()

	local plugin_path = get_plugin_path()
	local scraper_path = plugin_path .. "/templates/scrapers/" .. contest .. ".py"

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

	local full_problem_id = data.problem_id
	local input_file = "io/" .. full_problem_id .. ".in"
	local expected_file = "io/" .. full_problem_id .. ".expected"

	if #data.test_cases > 0 then
		local first_test = data.test_cases[1]
		vim.fn.writefile(vim.split(first_test.input, "\n"), input_file)
		vim.fn.writefile(vim.split(first_test.output, "\n"), expected_file)
	end

	return {
		success = true,
		problem_id = full_problem_id,
		test_count = #data.test_cases,
		url = data.url,
	}
end

return M
