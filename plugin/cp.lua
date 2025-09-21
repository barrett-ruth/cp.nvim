if vim.g.loaded_cp then
  return
end
vim.g.loaded_cp = 1

vim.api.nvim_create_user_command('CP', function(opts)
  local cp = require('cp')
  cp.handle_command(opts)
end, {
  nargs = '*',
  desc = 'Competitive programming helper',
  complete = function(ArgLead, CmdLine, _)
    local constants = require('cp.constants')
    local platforms = constants.PLATFORMS
    local actions = constants.ACTIONS

    local args = vim.split(vim.trim(CmdLine), '%s+')
    local num_args = #args
    if CmdLine:sub(-1) == ' ' then
      num_args = num_args + 1
    end

    if num_args == 2 then
      local candidates = {}
      local cp = require('cp')
      local context = cp.get_current_context()
      if context.platform and context.contest_id then
        vim.list_extend(candidates, actions)
        local cache = require('cp.cache')
        cache.load()
        local contest_data = cache.get_contest_data(context.platform, context.contest_id)
        if contest_data and contest_data.problems then
          for _, problem in ipairs(contest_data.problems) do
            table.insert(candidates, problem.id)
          end
        end
      else
        vim.list_extend(candidates, platforms)
      end
      return vim.tbl_filter(function(cmd)
        return cmd:find(ArgLead, 1, true) == 1
      end, candidates)
    elseif num_args == 3 then
      if args[2] == 'cache' then
        return vim.tbl_filter(function(cmd)
          return cmd:find(ArgLead, 1, true) == 1
        end, { 'clear' })
      end
    elseif num_args == 4 then
      if args[2] == 'cache' and args[3] == 'clear' then
        return vim.tbl_filter(function(cmd)
          return cmd:find(ArgLead, 1, true) == 1
        end, platforms)
      elseif vim.tbl_contains(platforms, args[2]) then
        local cache = require('cp.cache')
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
