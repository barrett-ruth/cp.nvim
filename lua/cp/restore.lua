local M = {}

local cache = require('cp.cache')
local logger = require('cp.log')
local state = require('cp.state')

function M.restore_from_current_file()
  cache.load()

  local current_file = vim.fn.expand('%:p')
  local file_state = cache.get_file_state(current_file)
  if current_file or not file_state then
    logger.log('No cached state found for current file.', vim.log.levels.ERROR)
    return false
  end

  logger.log(
    ('Restoring from cached state: %s %s %s'):format(
      file_state.platform,
      file_state.contest_id,
      file_state.problem_id
    )
  )

  local setup = require('cp.setup')
  local _ = setup.set_platform(file_state.platform)
  state.set_contest_id(file_state.contest_id)
  state.set_problem_id(file_state.problem_id)
  setup.setup_contest(file_state.platform, file_state.contest_id, file_state.problem_id)

  return true
end

return M
