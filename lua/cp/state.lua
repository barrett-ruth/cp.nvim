---@class cp.State
---@field get_platform fun(): string?
---@field set_platform fun(platform: string)
---@field get_contest_id fun(): string?
---@field set_contest_id fun(contest_id: string)
---@field get_problem_id fun(): string?
---@field set_problem_id fun(problem_id: string)
---@field get_active_panel fun(): string?
---@field set_active_panel fun(): string?
---@field get_base_name fun(): string?
---@field get_source_file fun(language?: string): string?
---@field get_binary_file fun(): string?
---@field get_input_file fun(): string?
---@field get_output_file fun(): string?
---@field get_expected_file fun(): string?

local M = {}

local state = {
  platform = nil,
  contest_id = nil,
  problem_id = nil,
  test_cases = nil,
  saved_session = nil,
  active_panel = nil,
}

function M.get_platform()
  return state.platform
end

function M.set_platform(platform)
  state.platform = platform
end

function M.get_contest_id()
  return state.contest_id
end

function M.set_contest_id(contest_id)
  state.contest_id = contest_id
end

function M.get_problem_id()
  return state.problem_id
end

function M.set_problem_id(problem_id)
  state.problem_id = problem_id
end

function M.get_base_name()
  local platform, contest_id, problem_id = M.get_platform(), M.get_contest_id(), M.get_problem_id()
  if not platform or not contest_id or not problem_id then
    return nil
  end

  local config_module = require('cp.config')
  local config = config_module.get_config()

  if config.filename then
    return config.filename(platform, contest_id, problem_id, config)
  else
    return config_module.default_filename(contest_id, problem_id)
  end
end

function M.get_source_file(language)
  local base_name = M.get_base_name()
  if not base_name or not M.get_platform() then
    return nil
  end

  local config = require('cp.config').get_config()
  local contest_config = config.platforms[M.get_platform()]
  if not contest_config then
    return nil
  end

  local target_language = language or contest_config.default_language
  local language_config = contest_config[target_language]
  if not language_config or not language_config.extension then
    return nil
  end

  return base_name .. '.' .. language_config.extension
end

function M.get_binary_file()
  local base_name = M.get_base_name()
  return base_name and ('build/%s.run'):format(base_name) or nil
end

function M.get_input_file()
  local base_name = M.get_base_name()
  return base_name and ('io/%s.cpin'):format(base_name) or nil
end

function M.get_output_file()
  local base_name = M.get_base_name()
  return base_name and ('io/%s.cpout'):format(base_name) or nil
end

function M.get_expected_file()
  local base_name = M.get_base_name()
  return base_name and ('io/%s.expected'):format(base_name) or nil
end

function M.get_active_panel()
  return state.active_panel
end

function M.set_active_panel(panel)
  state.active_panel = panel
end

M._state = state

return M
