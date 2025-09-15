local M = {}
local logger = require("cp.log")

local filetype_to_language = {
	cpp = "cpp",
	cxx = "cpp",
	cc = "cpp",
	c = "cpp",
	py = "python",
	py3 = "python",
}

local function get_language_from_file(source_file)
	local extension = vim.fn.fnamemodify(source_file, ":e")
	local language = filetype_to_language[extension] or "cpp"
	logger.log(("detected language: %s (extension: %s)"):format(language, extension))
	return language
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
		logger.log("no compilation step required")
		return { code = 0, stderr = "" }
	end

	local compile_cmd = substitute_template(language_config.compile, substitutions)
	logger.log(("compiling: %s"):format(table.concat(compile_cmd, " ")))

	local start_time = vim.loop.hrtime()
	local result = vim.system(compile_cmd, { text = true }):wait()
	local compile_time = (vim.loop.hrtime() - start_time) / 1000000

	if result.code == 0 then
		logger.log(("compilation successful (%.1fms)"):format(compile_time))
	else
		logger.log(("compilation failed (%.1fms): %s"):format(compile_time, result.stderr), vim.log.levels.WARN)
	end

	return result
end

local function execute_command(cmd, input_data, timeout_ms)
	logger.log(("executing: %s"):format(table.concat(cmd, " ")))

	local start_time = vim.loop.hrtime()

	local result = vim.system(cmd, {
		stdin = input_data,
		timeout = timeout_ms,
		text = true,
	}):wait()

	local end_time = vim.loop.hrtime()
	local execution_time = (end_time - start_time) / 1000000

	local actual_code = result.code or 0

	if result.code == 124 then
		logger.log(("execution timed out after %.1fms"):format(execution_time), vim.log.levels.WARN)
	elseif actual_code ~= 0 then
		logger.log(("execution failed (exit code %d, %.1fms)"):format(actual_code, execution_time), vim.log.levels.WARN)
	else
		logger.log(("execution successful (%.1fms)"):format(execution_time))
	end

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

	local language = get_language_from_file(ctx.source_file)
	local language_config = contest_config[language]

	if not language_config then
		vim.fn.writefile({ "Error: No configuration for language: " .. language }, ctx.output_file)
		return
	end

	local substitutions = {
		source = ctx.source_file,
		binary = ctx.binary_file,
		version = tostring(language_config.version or ""),
	}

	local compile_cmd = is_debug and language_config.debug or language_config.compile
	if compile_cmd then
		local compile_result = compile_generic(language_config, substitutions)
		if compile_result.code ~= 0 then
			vim.fn.writefile({ compile_result.stderr }, ctx.output_file)
			return
		end
	end

	local input_data = ""
	if vim.fn.filereadable(ctx.input_file) == 1 then
		input_data = table.concat(vim.fn.readfile(ctx.input_file), "\n") .. "\n"
	end

	local run_cmd = build_command(language_config.run, language_config.executable, substitutions)
	local exec_result = execute_command(run_cmd, input_data, contest_config.timeout_ms)
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
