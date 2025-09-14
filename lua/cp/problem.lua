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
---@return ProblemContext
function M.create_context(contest, contest_id, problem_id, config)
	local filename_fn = config.filename or require("cp.config").default_filename
	local source_file = filename_fn(contest, contest_id, problem_id)
	local base_name = vim.fn.fnamemodify(source_file, ":t:r")

	return {
		contest = contest,
		contest_id = contest_id,
		problem_id = problem_id,
		source_file = source_file,
		binary_file = ("build/%s.run"):format(base_name),
		input_file = ("io/%s.in"):format(base_name),
		output_file = ("io/%s.out"):format(base_name),
		expected_file = ("io/%s.expected"):format(base_name),
		problem_name = base_name,
	}
end

return M
