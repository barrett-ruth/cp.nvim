local M = {}

local constants = require('cp.constants')
local logger = require('cp.log')
local state = require('cp.state')

local platforms = constants.PLATFORMS
local actions = constants.ACTIONS

local function parse_command(args)
  if #args == 0 then
    return {
      type = 'restore_from_file',
    }
  end

  local language = nil
  local debug = false

  for i, arg in ipairs(args) do
    local lang_match = arg:match('^--lang=(.+)$')
    if lang_match then
      language = lang_match
    elseif arg == '--lang' then
      if i + 1 <= #args then
        language = args[i + 1]
      else
        return { type = 'error', message = '--lang requires a value' }
      end
    elseif arg == '--debug' then
      debug = true
    end
  end

  local filtered_args = vim.tbl_filter(function(arg)
    return not (arg:match('^--lang') or arg == language or arg == '--debug')
  end, args)

  local first = filtered_args[1]

  if vim.tbl_contains(actions, first) then
    if first == 'cache' then
      local subcommand = filtered_args[2]
      if not subcommand then
        return { type = 'error', message = 'cache command requires subcommand: clear' }
      end
      if subcommand == 'clear' then
        local platform = filtered_args[3]
        return {
          type = 'cache',
          subcommand = 'clear',
          platform = platform,
        }
      else
        return { type = 'error', message = 'unknown cache subcommand: ' .. subcommand }
      end
    else
      return { type = 'action', action = first, language = language, debug = debug }
    end
  end

  if vim.tbl_contains(platforms, first) then
    if #filtered_args == 1 then
      return {
        type = 'platform_only',
        platform = first,
        language = language,
      }
    elseif #filtered_args == 2 then
      return {
        type = 'contest_setup',
        platform = first,
        contest = filtered_args[2],
        language = language,
      }
    elseif #filtered_args == 3 then
      return {
        type = 'full_setup',
        platform = first,
        contest = filtered_args[2],
        problem = filtered_args[3],
        language = language,
      }
    else
      return { type = 'error', message = 'Too many arguments' }
    end
  end

  if state.get_platform() and state.get_contest_id() then
    local cache = require('cp.cache')
    cache.load()
    local contest_data =
      cache.get_contest_data(state.get_platform() or '', state.get_contest_id() or '')
    if contest_data and contest_data.problems then
      local problem_ids = vim.tbl_map(function(prob)
        return prob.id
      end, contest_data.problems)
      if vim.tbl_contains(problem_ids, first) then
        return { type = 'problem_switch', problem = first, language = language }
      end
    end
    return {
      type = 'error',
      message = ("invalid subcommand '%s'"):format(first),
    }
  end

  return { type = 'error', message = 'Unknown command or no contest context' }
end

function M.handle_command(opts)
  logger.log(('command received: %s'):format(vim.inspect(opts.fargs)))
  local cmd = parse_command(opts.fargs)
  logger.log(('parsed command: %s'):format(vim.inspect(cmd)))

  if cmd.type == 'error' then
    logger.log(cmd.message, vim.log.levels.ERROR)
    return
  end

  if cmd.type == 'restore_from_file' then
    local restore = require('cp.restore')
    restore.restore_from_current_file()
    return
  end

  if cmd.type == 'action' then
    logger.log(('handling action: %s'):format(cmd.action))
    local setup = require('cp.setup')
    local ui = require('cp.ui.panel')

    if cmd.action == 'run' then
      print('running')
      logger.log('calling toggle_run_panel')
      ui.toggle_run_panel(cmd.debug)
    elseif cmd.action == 'next' then
      logger.log('calling navigate_problem(1)')
      setup.navigate_problem(1, cmd.language)
    elseif cmd.action == 'prev' then
      logger.log('calling navigate_problem(-1)')
      setup.navigate_problem(-1, cmd.language)
    elseif cmd.action == 'pick' then
      local picker = require('cp.commands.picker')
      picker.handle_pick_action()
    end
    return
  end

  if cmd.type == 'cache' then
    local cache_commands = require('cp.commands.cache')
    cache_commands.handle_cache_command(cmd)
    return
  end

  if cmd.type == 'platform_only' then
    local setup = require('cp.setup')
    setup.set_platform(cmd.platform)
    return
  end

  if cmd.type == 'contest_setup' then
    local setup = require('cp.setup')
    if setup.set_platform(cmd.platform) then
      setup.setup_contest(cmd.platform, cmd.contest, nil, cmd.language)
    end
    return
  end

  if cmd.type == 'full_setup' then
    local setup = require('cp.setup')
    if setup.set_platform(cmd.platform) then
      setup.setup_contest(cmd.platform, cmd.contest, cmd.problem, cmd.language)
    end
    return
  end

  if cmd.type == 'problem_switch' then
    local setup = require('cp.setup')
    setup.setup_problem(state.get_contest_id() or '', cmd.problem, cmd.language)
    return
  end
end

return M
