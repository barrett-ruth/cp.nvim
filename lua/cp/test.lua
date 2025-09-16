---@class TestCase
---@field index number
---@field input string
---@field expected string
---@field status "pending"|"pass"|"fail"|"running"|"timeout"
---@field actual string?
---@field time_ms number?
---@field error string?
---@field selected boolean
---@field code number?
---@field ok boolean?
---@field signal string?
---@field timed_out boolean?

---@class TestPanelState
---@field test_cases TestCase[]
---@field current_index number
---@field buffer number?
---@field namespace number?
---@field is_active boolean
---@field saved_layout table?

local M = {}
local logger = require("cp.log")
local constants = require("cp.constants")

---@type TestPanelState
local test_panel_state = {
	test_cases = {},
	current_index = 1,
	buffer = nil,
	namespace = nil,
	is_active = false,
	saved_layout = nil,
}

---@param index number
---@param input string
---@param expected string
---@return TestCase
local function create_test_case(index, input, expected)
	return {
		index = index,
		input = input,
		expected = expected,
		status = "pending",
		actual = nil,
		time_ms = nil,
		error = nil,
		selected = true,
	}
end

---@param platform string
---@param contest_id string
---@param problem_id string?
---@return TestCase[]
local function parse_test_cases_from_cache(platform, contest_id, problem_id)
	local cache = require("cp.cache")
	cache.load()
	local cached_test_cases = cache.get_test_cases(platform, contest_id, problem_id)

	if not cached_test_cases or #cached_test_cases == 0 then
		return {}
	end

	local test_cases = {}

	for i, test_case in ipairs(cached_test_cases) do
		local index = test_case.index or i
		table.insert(test_cases, create_test_case(index, test_case.input, test_case.output))
	end

	return test_cases
end

---@param input_file string
---@param expected_file string
---@return TestCase[]
local function parse_test_cases_from_files(input_file, expected_file)
	if vim.fn.filereadable(input_file) == 0 or vim.fn.filereadable(expected_file) == 0 then
		return {}
	end

	local base_name = vim.fn.fnamemodify(input_file, ":r")
	local test_cases = {}
	local i = 1

	while true do
		local individual_input_file = base_name .. "." .. i .. ".cpin"
		local individual_expected_file = base_name .. "." .. i .. ".cpout"

		if vim.fn.filereadable(individual_input_file) == 1 and vim.fn.filereadable(individual_expected_file) == 1 then
			local input_content = table.concat(vim.fn.readfile(individual_input_file), "\n")
			local expected_content = table.concat(vim.fn.readfile(individual_expected_file), "\n")

			table.insert(test_cases, create_test_case(i, input_content, expected_content))
			i = i + 1
		else
			break
		end
	end

	if #test_cases == 0 then
		local input_content = table.concat(vim.fn.readfile(input_file), "\n")
		local expected_content = table.concat(vim.fn.readfile(expected_file), "\n")
		return { create_test_case(1, input_content, expected_content) }
	end

	return test_cases
end

---@param ctx ProblemContext
---@param contest_config ContestConfig
---@param test_case TestCase
---@return table
local function run_single_test_case(ctx, contest_config, test_case)
	local language = vim.fn.fnamemodify(ctx.source_file, ":e")
	local language_name = constants.filetype_to_language[language] or contest_config.default_language
	local language_config = contest_config[language_name]

	if not language_config then
		return {
			status = "fail",
			actual = "",
			error = "No language configuration",
			time_ms = 0,
		}
	end

	local function substitute_template(cmd_template, substitutions)
		local result = {}
		for _, arg in ipairs(cmd_template) do
			local substituted = arg
			for key, value in pairs(substitutions) do
				substituted = substituted:gsub("{" .. key .. "}", value)
			end
			table.insert(result, substituted)
		end
		return result
	end

	local function build_command(cmd_template, executable, substitutions)
		local cmd = substitute_template(cmd_template, substitutions)
		if executable then
			table.insert(cmd, 1, executable)
		end
		return cmd
	end

	local substitutions = {
		source = ctx.source_file,
		binary = ctx.binary_file,
		version = tostring(language_config.version or ""),
	}

	if language_config.compile and vim.fn.filereadable(ctx.binary_file) == 0 then
		logger.log("binary not found, compiling first...")
		local compile_cmd = substitute_template(language_config.compile, substitutions)
		local compile_result = vim.system(compile_cmd, { text = true }):wait()
		if compile_result.code ~= 0 then
			return {
				status = "fail",
				actual = "",
				error = "Compilation failed: " .. (compile_result.stderr or "Unknown error"),
				time_ms = 0,
			}
		end
	end

	local run_cmd = build_command(language_config.run, language_config.executable, substitutions)

	local stdin_content = test_case.input .. "\n"
	if ctx.contest == "atcoder" then
		stdin_content = "1\n" .. stdin_content
	end

	local start_time = vim.uv.hrtime()
	local result = vim.system(run_cmd, {
		stdin = stdin_content,
		timeout = contest_config.timeout_ms or 2000,
		text = true,
	}):wait()
	local execution_time = (vim.uv.hrtime() - start_time) / 1000000

	local actual_output = (result.stdout or ""):gsub("\n$", "")
	local expected_output = test_case.expected:gsub("\n$", "")
	local ok = actual_output == expected_output

	local status
	local timed_out = result.code == 143 or result.code == 124
	if timed_out then
		status = "timeout"
	elseif result.code == 0 and ok then
		status = "pass"
	else
		status = "fail"
	end

	local signal = nil
	if result.code >= 128 then
		signal = constants.signal_codes[result.code]
	end

	return {
		status = status,
		actual = actual_output,
		error = result.code ~= 0 and result.stderr or nil,
		time_ms = execution_time,
		code = result.code,
		ok = ok,
		signal = signal,
		timed_out = timed_out,
	}
end

---@param ctx ProblemContext
---@param state table
---@return boolean
function M.load_test_cases(ctx, state)
	local test_cases = parse_test_cases_from_cache(state.platform, state.contest_id, state.problem_id)

	if #test_cases == 0 then
		test_cases = parse_test_cases_from_files(ctx.input_file, ctx.expected_file)
	end

	test_panel_state.test_cases = test_cases
	test_panel_state.current_index = 1

	logger.log(("loaded %d test case(s)"):format(#test_cases))
	return #test_cases > 0
end

---@param ctx ProblemContext
---@param contest_config ContestConfig
---@param index number
---@return boolean
function M.run_test_case(ctx, contest_config, index)
	local test_case = test_panel_state.test_cases[index]
	if not test_case then
		return false
	end

	logger.log(("running test case %d"):format(index))
	test_case.status = "running"

	local result = run_single_test_case(ctx, contest_config, test_case)

	test_case.status = result.status
	test_case.actual = result.actual
	test_case.error = result.error
	test_case.time_ms = result.time_ms
	test_case.code = result.code
	test_case.ok = result.ok
	test_case.signal = result.signal
	test_case.timed_out = result.timed_out

	return true
end

---@param ctx ProblemContext
---@param contest_config ContestConfig
---@return TestCase[]
function M.run_all_test_cases(ctx, contest_config)
	local results = {}
	for i, _ in ipairs(test_panel_state.test_cases) do
		M.run_test_case(ctx, contest_config, i)
		table.insert(results, test_panel_state.test_cases[i])
	end
	return results
end

---@return TestPanelState
function M.get_test_panel_state()
	return test_panel_state
end

return M
