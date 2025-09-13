if vim.g.loaded_cp then
	return
end
vim.g.loaded_cp = 1

local competition_types = { "atcoder", "codeforces", "cses" }

vim.api.nvim_create_user_command("CP", function(opts)
	local cp = require("cp")
	if not cp.is_initialized() then
		cp.setup()
	end
	cp.handle_command(opts)
end, {
	nargs = "*",
	complete = function(ArgLead, _, _)
		local commands = vim.list_extend(vim.deepcopy(competition_types), { "run", "debug", "diff" })
		return vim.tbl_filter(function(cmd)
			return cmd:find(ArgLead, 1, true) == 1
		end, commands)
	end,
})
