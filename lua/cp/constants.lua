local M = {}

M.PLATFORMS = { "atcoder", "codeforces", "cses" }
M.ACTIONS = { "run", "debug", "test", "next", "prev" }

M.CPP = "cpp"
M.PYTHON = "python"

---@type table<string, string>
M.filetype_to_language = {
	cc = M.CPP,
	cxx = M.CPP,
	cpp = M.CPP,
	py = M.PYTHON,
	py3 = M.PYTHON,
}

---@type table<string, string>
M.canonical_filetypes = {
	[M.CPP] = "cpp",
	[M.PYTHON] = "python",
}

return M
