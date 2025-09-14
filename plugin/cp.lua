if vim.g.loaded_cp then
	return
end
vim.g.loaded_cp = 1

local platforms = { "atcoder", "codeforces", "cses" }
local actions = { "run", "debug", "diff", "next", "prev" }

vim.api.nvim_create_user_command("CP", function(opts)
	local cp = require("cp")
	if not cp.is_initialized() then
		cp.setup()
	end
	cp.handle_command(opts)
end, {
	nargs = "*",
	complete = function(ArgLead, CmdLine, CursorPos)
		local args = vim.split(vim.trim(CmdLine), "%s+")
		local num_args = #args
		if CmdLine:sub(-1) == " " then
			num_args = num_args + 1
		end

		if num_args == 2 then
			local candidates = {}
			vim.list_extend(candidates, platforms)
			vim.list_extend(candidates, actions)
			if vim.g.cp_platform and vim.g.cp_contest_id then
				local cache = require("cp.cache")
				cache.load()
				local contest_data = cache.get_contest_data(vim.g.cp_platform, vim.g.cp_contest_id)
				if contest_data and contest_data.problems then
					for _, problem in ipairs(contest_data.problems) do
						table.insert(candidates, problem.id)
					end
				end
			end
			return vim.tbl_filter(function(cmd)
				return cmd:find(ArgLead, 1, true) == 1
			end, candidates)
		elseif num_args == 4 then
			if vim.tbl_contains(platforms, args[2]) then
				local cache = require("cp.cache")
				cache.load()
				local contest_data = cache.get_contest_data(args[2], args[3])
				if contest_data and contest_data.problems then
					local candidates = {}
					for _, problem in ipairs(contest_data.problems) do
						table.insert(candidates, problem.id)
					end
					return vim.tbl_filter(function(cmd)
						return cmd:find(ArgLead, 1, true) == 1
					end, candidates)
				end
			end
		end
		return {}
	end,
})
