local M = {}

M.CPP = "cpp"
M.PYTHON = "python"

---@type table<string, string>
M.filetype_to_language = {
	cc = M.CPP,
	cxx = M.CPP,
	cpp = M.CPP,
	c = M.CPP,
	py = M.PYTHON,
	py3 = M.PYTHON,
}

---@type string[]
M.all = { M.CPP, M.PYTHON }

return M