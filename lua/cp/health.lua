local M = {}

local function check_nvim_version()
	if vim.fn.has("nvim-0.10.0") == 1 then
		vim.health.ok("Neovim 0.10.0+ detected")
	else
		vim.health.error("cp.nvim requires Neovim 0.10.0+")
	end
end

local function check_uv()
	if vim.fn.executable("uv") == 1 then
		vim.health.ok("uv executable found")

		local result = vim.system({ "uv", "--version" }, { text = true }):wait()
		if result.code == 0 then
			vim.health.info("uv version: " .. result.stdout:gsub("\n", ""))
		end
	else
		vim.health.warn("uv not found - install from https://docs.astral.sh/uv/ for problem scraping")
	end
end

local function check_python_env()
	local plugin_path = debug.getinfo(1, "S").source:sub(2)
	plugin_path = vim.fn.fnamemodify(plugin_path, ":h:h:h")
	local venv_dir = plugin_path .. "/.venv"

	if vim.fn.isdirectory(venv_dir) == 1 then
		vim.health.ok("Python virtual environment found at " .. venv_dir)
	else
		vim.health.warn("Python virtual environment not set up - run :CP command to initialize")
	end
end

local function check_scrapers()
	local plugin_path = debug.getinfo(1, "S").source:sub(2)
	plugin_path = vim.fn.fnamemodify(plugin_path, ":h:h:h")

	local scrapers = { "atcoder.py", "codeforces.py", "cses.py" }
	for _, scraper in ipairs(scrapers) do
		local scraper_path = plugin_path .. "/scrapers/" .. scraper
		if vim.fn.filereadable(scraper_path) == 1 then
			vim.health.ok("Scraper found: " .. scraper)
		else
			vim.health.error("Missing scraper: " .. scraper)
		end
	end
end

local function check_luasnip()
	local has_luasnip, luasnip = pcall(require, "luasnip")
	if has_luasnip then
		vim.health.ok("LuaSnip integration available")
		local snippet_count = #luasnip.get_snippets("all")
		vim.health.info("LuaSnip snippets loaded: " .. snippet_count)
	else
		vim.health.info("LuaSnip not available - template expansion will be limited")
	end
end

local function check_config()
	local cp = require("cp")
	if cp.is_initialized() then
		vim.health.ok("Plugin initialized")

		if vim.g.cp_contest then
			vim.health.info("Current contest: " .. vim.g.cp_contest)
		else
			vim.health.info("No contest mode set")
		end
	else
		vim.health.warn("Plugin not initialized - configuration may be incomplete")
	end
end

function M.check()
	local version = require("cp.version")
	vim.health.start("cp.nvim health check")
	
	vim.health.info("Version: " .. version.version)
	if version.semver then
		vim.health.info("Semantic version: v" .. version.semver.full)
	end

	check_nvim_version()
	check_uv()
	check_python_env()
	check_scrapers()
	check_luasnip()
	check_config()
end

return M
