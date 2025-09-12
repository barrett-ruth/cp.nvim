local M = {}

local signal_codes = {
	[128] = "SIGILL",
	[130] = "SIGABRT",
	[131] = "SIGBUS",
	[136] = "SIGFPE",
	[135] = "SIGSEGV",
	[137] = "SIGPIPE",
	[139] = "SIGTERM",
}

local function get_paths(problem_id)
	return {
		source = ("%s.cc"):format(problem_id),
		binary = ("build/%s"):format(problem_id),
		input = ("io/%s.in"):format(problem_id),
		output = ("io/%s.out"):format(problem_id),
		expected = ("io/%s.expected"):format(problem_id),
	}
end

local function ensure_directories()
	vim.system({ "mkdir", "-p", "build", "io" }):wait()
end

local function compile_cpp(source_path, binary_path, flags)
	local compile_cmd = { "g++", unpack(flags), source_path, "-o", binary_path }
	return vim.system(compile_cmd, { text = true }):wait()
end

local function execute_binary(binary_path, input_data, timeout_ms)
	local start_time = vim.loop.hrtime()

	local result = vim.system({ binary_path }, {
		stdin = input_data,
		timeout = timeout_ms,
		text = true,
	}):wait()

	local end_time = vim.loop.hrtime()
	local execution_time = (end_time - start_time) / 1000000

	return {
		stdout = result.stdout or "",
		stderr = result.stderr or "",
		code = result.code,
		time_ms = execution_time,
		timed_out = result.code == 124,
	}
end

local function format_output(exec_result, expected_file)
	local lines = { exec_result.stdout }

	if exec_result.timed_out then
		table.insert(lines, "\n[code]: 124 (TIMEOUT)")
	elseif exec_result.code >= 128 then
		local signal_name = signal_codes[exec_result.code] or "SIGNAL"
		table.insert(lines, ("\n[code]: %d (%s)"):format(exec_result.code, signal_name))
	else
		table.insert(lines, ("\n[code]: %d"):format(exec_result.code))
	end

	table.insert(lines, ("\n[time]: %.2f ms"):format(exec_result.time_ms))
	table.insert(lines, "\n[debug]: false")

	if vim.fn.filereadable(expected_file) == 1 and exec_result.code == 0 then
		local expected_content = vim.fn.readfile(expected_file)
		local actual_lines = vim.split(exec_result.stdout, "\n")

		local matches = #actual_lines == #expected_content
		if matches then
			for i, line in ipairs(actual_lines) do
				if line ~= expected_content[i] then
					matches = false
					break
				end
			end
		end

		table.insert(lines, ("\n[matches]: %s"):format(matches and "true" or "false"))
	end

	return table.concat(lines, "")
end

function M.run_problem(problem_id, contest_config, is_debug)
	ensure_directories()

	local paths = get_paths(problem_id)
	local flags = is_debug and contest_config.debug_flags or contest_config.compile_flags

	local compile_result = compile_cpp(paths.source, paths.binary, flags)
	if compile_result.code ~= 0 then
		vim.fn.writefile({ compile_result.stderr }, paths.output)
		return
	end

	local input_data = ""
	if vim.fn.filereadable(paths.input) == 1 then
		input_data = table.concat(vim.fn.readfile(paths.input), "\n") .. "\n"
	end

	local exec_result = execute_binary(paths.binary, input_data, contest_config.timeout_ms)
	local formatted_output = format_output(exec_result, paths.expected)

	vim.fn.writefile(vim.split(formatted_output, "\n"), paths.output)
end

return M
