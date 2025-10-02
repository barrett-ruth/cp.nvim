local M = {}

local constants = require('cp.constants')
local logger = require('cp.log')
local state = require('cp.state')

local platforms = constants.PLATFORMS
local actions = constants.ACTIONS

local function parse_command(args)
  if vim.tbl_isempty(args) then
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
      if vim.tbl_contains({ 'clear', 'read' }, subcommand) then
        local platform = filtered_args[3]
        return {
          type = 'cache',
          subcommand = subcommand,
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
        type = 'error',
        message = 'Too few arguments - specify a contest.',
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
        type = 'error',
        message = 'Setup contests with :CP <platform> <contest_id> [--{lang=<lang>,debug}]',
      }
    else
      return { type = 'error', message = 'Too many arguments' }
    end
  end

  if state.get_platform() and state.get_contest_id() then
    local cache = require('cp.cache')
    cache.load()
    return {
      type = 'error',
      message = ("invalid subcommand '%s'"):format(first),
    }
  end

  return { type = 'error', message = 'Unknown command or no contest context' }
end

function M.handle_command(opts)
  local cmd = parse_command(opts.fargs)

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
    local setup = require('cp.setup')
    local ui = require('cp.ui.panel')

    if cmd.action == 'interact' then
      ui.toggle_interactive()
    elseif cmd.action == 'run' then
      ui.toggle_run_panel(cmd.debug)
    elseif cmd.action == 'next' then
      setup.navigate_problem(1, cmd.language)
    elseif cmd.action == 'prev' then
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

  if cmd.type == 'contest_setup' then
    local setup = require('cp.setup')
    if setup.set_platform(cmd.platform) then
      setup.setup_contest(cmd.platform, cmd.contest, cmd.language, nil)
    end
    return
  end
end

return M
