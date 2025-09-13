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

local function format_output(exec_result, expected_file, is_debug)
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
	table.insert(lines, ("\n[debug]: %s"):format(is_debug and "true" or "false"))

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

return M
