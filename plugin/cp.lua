if vim.g.loaded_cp then
	return
end
vim.g.loaded_cp = 1

local platforms = { "atcoder", "codeforces", "cses" }
local actions = { "run", "debug", "diff", "next", "prev" }

vim.api.nvim_create_user_command("CP", function(opts)
	local cp = require("cp")
	cp.handle_command(opts)
end, {
	nargs = "*",
	desc = "Competitive programming helper",
	complete = function(ArgLead, CmdLine, _)
		local filetype_to_language = {
			cc = "cpp",
			c = "cpp",
			py = "python",
			py3 = "python",
		}

		local languages = vim.tbl_keys(vim.tbl_add_reverse_lookup(filetype_to_language))

		if ArgLead:match("^--lang=") then
			local lang_completions = {}
			for _, lang in ipairs(languages) do
				table.insert(lang_completions, "--lang=" .. lang)
			end
			return vim.tbl_filter(function(completion)
				return completion:find(ArgLead, 1, true) == 1
			end, lang_completions)
		end

		if ArgLead == "--lang" then
			return { "--lang" }
		end

		local args = vim.split(vim.trim(CmdLine), "%s+")
		local num_args = #args
		if CmdLine:sub(-1) == " " then
			num_args = num_args + 1
		end

		local lang_flag_present = vim.tbl_contains(args, "--lang") or vim.iter(args):any(function(arg) return arg:match("^--lang=") end)

		if num_args == 2 then
			local candidates = { "--lang" }
			vim.list_extend(candidates, platforms)
			vim.list_extend(candidates, actions)
			local cp = require("cp")
			local context = cp.get_current_context()
			if context.platform and context.contest_id then
				local cache = require("cp.cache")
				cache.load()
				local contest_data = cache.get_contest_data(context.platform, context.contest_id)
				if contest_data and contest_data.problems then
					for _, problem in ipairs(contest_data.problems) do
						table.insert(candidates, problem.id)
					end
				end
			end
			return vim.tbl_filter(function(cmd)
				return cmd:find(ArgLead, 1, true) == 1
			end, candidates)
		elseif args[#args-1] == "--lang" then
			return vim.tbl_filter(function(lang)
				return lang:find(ArgLead, 1, true) == 1
			end, languages)
		elseif num_args == 4 and not lang_flag_present then
			if vim.tbl_contains(platforms, args[2]) then
				local cache = require("cp.cache")
				cache.load()
				local contest_data = cache.get_contest_data(args[2], args[3])
				if contest_data and contest_data.problems then
					local candidates = { "--lang" }
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
