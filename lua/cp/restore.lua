local M = {}

local cache = require('cp.cache')
local logger = require('cp.log')
local state = require('cp.state')

function M.restore_from_current_file()
  local current_file = vim.fn.expand('%:p')
  if current_file == '' then
    logger.log('No file is currently open.', vim.log.levels.ERROR)
    return false
  end

  cache.load()
  local file_state = cache.get_file_state(current_file)
  if not file_state then
    logger.log(
      'No cached state found for current file. Use :CP <platform> <contest> <problem> [...] first.',
      vim.log.levels.ERROR
    )
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
  if not setup.set_platform(file_state.platform) then
    return false
  end

  state.set_contest_id(file_state.contest_id)
  state.set_problem_id(file_state.problem_id)

  setup.setup_problem(file_state.contest_id, file_state.problem_id, file_state.language)

  return true
end

return M
