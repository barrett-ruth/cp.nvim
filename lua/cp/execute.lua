local M = {}

local filetype_to_language = {
	cpp = "cpp",
	cxx = "cpp",
	cc = "cpp",
	c = "cpp",
	py = "python",
	py3 = "python",
	rs = "rust",
	java = "java",
	js = "javascript",
	go = "go",
}

local function get_language_from_file(source_file)
	local extension = vim.fn.fnamemodify(source_file, ":e")
	return filetype_to_language[extension] or "cpp"
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

local signal_codes = {
	[128] = "SIGILL",
	[130] = "SIGINT",
	[131] = "SIGQUIT",
	[132] = "SIGILL",
	[133] = "SIGTRAP",
	[134] = "SIGABRT",
	[135] = "SIGBUS",
	[136] = "SIGFPE",
	[137] = "SIGKILL",
	[138] = "SIGUSR1",
	[139] = "SIGSEGV",
	[140] = "SIGUSR2",
	[141] = "SIGPIPE",
	[142] = "SIGALRM",
	[143] = "SIGTERM",
}

local function ensure_directories()
	vim.system({ "mkdir", "-p", "build", "io" }):wait()
end

local function compile_generic(language_config, substitutions)
	if not language_config.compile then
		return { code = 0, stderr = "" }
	end

	local compile_cmd = substitute_template(language_config.compile, substitutions)
	return vim.system(compile_cmd, { text = true }):wait()
end

local function execute_command(cmd, input_data, timeout_ms)
	local start_time = vim.loop.hrtime()

	local result = vim.system(cmd, {
		stdin = input_data,
		timeout = timeout_ms,
		text = true,
	}):wait()

	local end_time = vim.loop.hrtime()
	local execution_time = (end_time - start_time) / 1000000

	local actual_code = result.code or 0

	return {
		stdout = result.stdout or "",
		stderr = result.stderr or "",
		code = actual_code,
		time_ms = execution_time,
		timed_out = result.code == 124,
	}
end

local function format_output(exec_result, expected_file, is_debug)
	local output_lines = { exec_result.stdout }
	local metadata_lines = {}

	if exec_result.timed_out then
		table.insert(metadata_lines, "[code]: 124 (TIMEOUT)")
	elseif exec_result.code >= 128 then
		local signal_name = signal_codes[exec_result.code] or "SIGNAL"
		table.insert(metadata_lines, ("[code]: %d (%s)"):format(exec_result.code, signal_name))
	else
		table.insert(metadata_lines, ("[code]: %d"):format(exec_result.code))
	end

	table.insert(metadata_lines, ("[time]: %.2f ms"):format(exec_result.time_ms))
	table.insert(metadata_lines, ("[debug]: %s"):format(is_debug and "true" or "false"))

	if vim.fn.filereadable(expected_file) == 1 and exec_result.code == 0 then
		local expected_content = vim.fn.readfile(expected_file)
		local actual_lines = vim.split(exec_result.stdout, "\n")

		while #actual_lines > 0 and actual_lines[#actual_lines] == "" do
			table.remove(actual_lines)
		end

		local matches = #actual_lines == #expected_content
		if matches then
			for i, line in ipairs(actual_lines) do
				if line ~= expected_content[i] then
					matches = false
					break
				end
			end
		end

		table.insert(metadata_lines, ("[matches]: %s"):format(matches and "true" or "false"))
	end

	return table.concat(output_lines, "") .. "\n" .. table.concat(metadata_lines, "\n")
end

---@param ctx ProblemContext
---@param contest_config table
---@param is_debug boolean
function M.run_problem(ctx, contest_config, is_debug)
	ensure_directories()

	local flags = is_debug and contest_config.debug_flags or contest_config.compile_flags

	local compile_result = compile_cpp(ctx.source_file, ctx.binary_file, flags)
	if compile_result.code ~= 0 then
		vim.fn.writefile({ compile_result.stderr }, ctx.output_file)
		return
	end

	local input_data = ""
	if vim.fn.filereadable(ctx.input_file) == 1 then
		input_data = table.concat(vim.fn.readfile(ctx.input_file), "\n") .. "\n"
	end

	local exec_result = execute_binary(ctx.binary_file, input_data, contest_config.timeout_ms)
	local formatted_output = format_output(exec_result, ctx.expected_file, is_debug)

	local output_buf = vim.fn.bufnr(ctx.output_file)
	if output_buf ~= -1 then
		vim.api.nvim_buf_set_lines(output_buf, 0, -1, false, vim.split(formatted_output, "\n"))
		vim.api.nvim_buf_call(output_buf, function()
			vim.cmd.write()
		end)
	else
		vim.fn.writefile(vim.split(formatted_output, "\n"), ctx.output_file)
	end
end

function M.run_individual_tests(ctx, test_cases, contest_config, is_debug)
	ensure_directories()

	if not test_cases or #test_cases == 0 then
		return {}
	end

	local flags = is_debug and contest_config.debug_flags or contest_config.compile_flags
	local compile_result = compile_cpp(ctx.source_file, ctx.binary_file, flags)
	if compile_result.code ~= 0 then
		return {
			compile_error = compile_result.stderr,
			results = {},
		}
	end

	local results = {}
	for i, test_case in ipairs(test_cases) do
		local exec_result = execute_binary(ctx.binary_file, test_case.input, contest_config.timeout_ms)

		local actual_lines = vim.split(exec_result.stdout, "\n")
		while #actual_lines > 0 and actual_lines[#actual_lines] == "" do
			table.remove(actual_lines)
		end

		local expected_lines = vim.split(test_case.output, "\n")
		while #expected_lines > 0 and expected_lines[#expected_lines] == "" do
			table.remove(expected_lines)
		end

		local matches = #actual_lines == #expected_lines
		if matches then
			for j, line in ipairs(actual_lines) do
				if line ~= expected_lines[j] then
					matches = false
					break
				end
			end
		end

		table.insert(results, {
			id = i,
			status = exec_result.code == 0 and (matches and "PASS" or "FAIL") or "ERROR",
			time_ms = exec_result.time_ms,
			input = test_case.input,
			expected = test_case.output,
			actual = exec_result.stdout,
			exit_code = exec_result.code,
			timed_out = exec_result.timed_out,
			enabled = true,
		})
	end

	return {
		compile_error = nil,
		results = results,
	}
end

return M
