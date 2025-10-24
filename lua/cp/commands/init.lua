local M = {}

local constants = require('cp.constants')
local logger = require('cp.log')
local state = require('cp.state')

local platforms = constants.PLATFORMS
local actions = constants.ACTIONS

---@class ParsedCommand
---@field type string
---@field error string?
---@field action? string
---@field message? string
---@field contest? string
---@field platform? string
---@field problem_id? string
---@field interactor_cmd? string
---@field test_index? integer
---@field debug? boolean

--- Turn raw args into normalized structure to later dispatch
---@param args string[] The raw command-line mode args
---@return ParsedCommand
local function parse_command(args)
  if vim.tbl_isempty(args) then
    return {
      type = 'restore_from_file',
    }
  end

  local first = args[1]

  if vim.tbl_contains(actions, first) then
    if first == 'cache' then
      local subcommand = args[2]
      if not subcommand then
        return { type = 'error', message = 'cache command requires subcommand' }
      end
      if vim.tbl_contains({ 'clear', 'read' }, subcommand) then
        local platform = args[3]
        return {
          type = 'cache',
          subcommand = subcommand,
          platform = platform,
        }
      else
        return { type = 'error', message = 'unknown cache subcommand: ' .. subcommand }
      end
    elseif first == 'interact' then
      local inter = args[2]
      if inter and inter ~= '' then
        return { type = 'action', action = 'interact', interactor_cmd = inter }
      else
        return { type = 'action', action = 'interact' }
      end
    elseif first == 'run' or first == 'panel' then
      local debug = false
      local test_index = nil

      for i = 2, #args do
        local arg = args[i]
        if arg == '--debug' then
          debug = true
        else
          local idx = tonumber(arg)
          if not idx then
            return {
              type = 'error',
              message = ("Invalid argument '%s': expected test number or --debug"):format(arg),
            }
          end
          if idx < 1 or idx ~= math.floor(idx) then
            return { type = 'error', message = ("'%s' is not a valid test index"):format(idx) }
          end
          test_index = idx
        end
      end

      return { type = 'action', action = first, test_index = test_index, debug = debug }
    else
      return { type = 'action', action = first }
    end
  end

  if vim.tbl_contains(platforms, first) then
    if #args == 1 then
      return {
        type = 'error',
        message = 'Too few arguments - specify a contest.',
      }
    elseif #args == 2 then
      return {
        type = 'contest_setup',
        platform = first,
        contest = args[2],
      }
    elseif #args == 3 then
      return {
        type = 'error',
        message = 'Setup contests with :CP <platform> <contest_id>.',
      }
    else
      return { type = 'error', message = 'Too many arguments' }
    end
  end

  if #args == 1 then
    return {
      type = 'problem_jump',
      problem_id = first,
    }
  end

  return { type = 'error', message = 'Unknown command or no contest context.' }
end

--- Core logic for handling `:CP ...` commands
---@return nil
function M.handle_command(opts)
  local cmd = parse_command(opts.fargs)

  if cmd.type == 'error' then
    logger.log(cmd.message, vim.log.levels.ERROR)
    return
  end

  if cmd.type == 'restore_from_file' then
    local restore = require('cp.restore')
    restore.restore_from_current_file()
  elseif cmd.type == 'action' then
    local setup = require('cp.setup')
    local ui = require('cp.ui.panel')

    if cmd.action == 'interact' then
      ui.toggle_interactive(cmd.interactor_cmd)
    elseif cmd.action == 'run' then
      ui.run_io_view(cmd.test_index, cmd.debug)
    elseif cmd.action == 'panel' then
      ui.toggle_panel({ debug = cmd.debug, test_index = cmd.test_index })
    elseif cmd.action == 'next' then
      setup.navigate_problem(1)
    elseif cmd.action == 'prev' then
      setup.navigate_problem(-1)
    elseif cmd.action == 'pick' then
      local picker = require('cp.commands.picker')
      picker.handle_pick_action()
    end
  elseif cmd.type == 'problem_jump' then
    local platform = state.get_platform()
    local contest_id = state.get_contest_id()
    local problem_id = cmd.problem_id

    if not (platform and contest_id) then
      logger.log('No contest is currently active.', vim.log.levels.ERROR)
      return
    end

    local cache = require('cp.cache')
    cache.load()
    local contest_data = cache.get_contest_data(platform, contest_id)

    if not (contest_data and contest_data.index_map and contest_data.index_map[problem_id]) then
      logger.log(
        ("%s contest '%s' has no problem '%s'."):format(
          constants.PLATFORM_DISPLAY_NAMES[platform],
          contest_id,
          problem_id
        ),
        vim.log.levels.ERROR
      )
      return
    end

    local setup = require('cp.setup')
    setup.setup_contest(platform, contest_id, problem_id)
  elseif cmd.type == 'cache' then
    local cache_commands = require('cp.commands.cache')
    cache_commands.handle_cache_command(cmd)
  elseif cmd.type == 'contest_setup' then
    local setup = require('cp.setup')
    setup.setup_contest(cmd.platform, cmd.contest, nil)
    return
  end
end

return M
