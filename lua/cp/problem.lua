---@class ProblemContext
---@field contest string Contest name (e.g. "atcoder", "codeforces")
---@field contest_id string Contest ID (e.g. "abc123", "1933")
---@field problem_id? string Problem ID for AtCoder/Codeforces (e.g. "a", "b")
---@field source_file string Source filename (e.g. "abc123a.cpp")
---@field binary_file string Binary output path (e.g. "build/abc123a.run")
---@field input_file string Input test file path (e.g. "io/abc123a.in")
---@field output_file string Output file path (e.g. "io/abc123a.out")
---@field expected_file string Expected output path (e.g. "io/abc123a.expected")
---@field problem_name string Canonical problem identifier (e.g. "abc123a")

local M = {}

---@param contest string
---@param contest_id string
---@param problem_id? string
---@param config cp.Config
---@param language? string
---@return ProblemContext
function M.create_context(contest, contest_id, problem_id, config, language)
	vim.validate({
		contest = { contest, "string" },
		contest_id = { contest_id, "string" },
		problem_id = { problem_id, { "string", "nil" }, true },
		config = { config, "table" },
		language = { language, { "string", "nil" }, true },
	})

	local contest_config = config.contests[contest]
	if not contest_config then
		error(("No contest config found for '%s'"):format(contest))
	end

	local target_language = language or contest_config.default_language
	local language_config = contest_config[target_language]
	if not language_config then
		error(("No language config found for '%s' in contest '%s'"):format(target_language, contest))
	end
	if not language_config.extension then
		error(("No extension configured for language '%s' in contest '%s'"):format(target_language, contest))
	end

	local base_name
	if config.filename then
		local source_file = config.filename(contest, contest_id, problem_id, config, language)
		base_name = vim.fn.fnamemodify(source_file, ":t:r")
	else
		local default_filename = require("cp.config").default_filename
		base_name = default_filename(contest_id, problem_id)
	end

	local source_file = base_name .. "." .. language_config.extension

	return {
		contest = contest,
		contest_id = contest_id,
		problem_id = problem_id,
		source_file = source_file,
		binary_file = ("build/%s.run"):format(base_name),
		input_file = ("io/%s.cpin"):format(base_name),
		output_file = ("io/%s.cpout"):format(base_name),
		expected_file = ("io/%s.expected"):format(base_name),
		problem_name = base_name,
	}
end

return M
