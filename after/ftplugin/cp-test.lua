vim.opt_local.number = false
vim.opt_local.relativenumber = false
vim.opt_local.statuscolumn = ""
vim.opt_local.signcolumn = "no"
vim.opt_local.wrap = false
vim.opt_local.linebreak = false
vim.opt_local.foldmethod = "marker"
vim.opt_local.foldmarker = "{{{,}}}"
vim.opt_local.foldlevel = 0
vim.opt_local.foldtext = ""

local function get_test_id_from_line()
	local line = vim.api.nvim_get_current_line()
	local test_id = line:match("%[.%] Test (%d+)")
	return test_id and tonumber(test_id)
end

local function toggle_test()
	local test_id = get_test_id_from_line()
	if not test_id then
		return
	end

	local cp = require("cp")
	cp.toggle_test(test_id)
end

local function run_single_test()
	local test_id = get_test_id_from_line()
	if not test_id then
		return
	end

	local cp = require("cp")
	cp.run_single_test(test_id)
end

local function run_all_enabled_tests()
	local cp = require("cp")
	cp.run_all_enabled_tests()
end

vim.keymap.set("n", "t", toggle_test, { buffer = true, desc = "Toggle test enabled/disabled" })
vim.keymap.set("n", "r", run_single_test, { buffer = true, desc = "Run single test" })
vim.keymap.set("n", "R", run_all_enabled_tests, { buffer = true, desc = "Run all enabled tests" })
