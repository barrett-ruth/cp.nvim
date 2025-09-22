local M = {}

local cache = require('cp.cache')
local logger = require('cp.log')
local state = require('cp.state')

local function get_current_problem()
  local filename = vim.fn.expand('%:t:r')
  if filename == '' then
    logger.log('no file open', vim.log.levels.ERROR)
    return nil
  end
  return filename
end

function M.navigate_problem(delta, language)
  cache.load()
  local contest_data = cache.get_contest_data(state.get_platform(), state.get_contest_id())
  if not contest_data or not contest_data.problems then
    logger.log(
      'no contest metadata found. set up a problem first to cache contest data',
      vim.log.levels.ERROR
    )
    return
  end

  local problems = contest_data.problems
  local current_problem_id = state.get_problem_id()

  if not current_problem_id then
    logger.log('no current problem set', vim.log.levels.ERROR)
    return
  end

  local current_index = nil
  for i, prob in ipairs(problems) do
    if prob.id == current_problem_id then
      current_index = i
      break
    end
  end

  if not current_index then
    logger.log('current problem not found in contest', vim.log.levels.ERROR)
    return
  end

  local new_index = current_index + delta

  if new_index < 1 or new_index > #problems then
    local msg = delta > 0 and 'at last problem' or 'at first problem'
    logger.log(msg, vim.log.levels.WARN)
    return
  end

  local new_problem = problems[new_index]
  local setup = require('cp.setup')
  setup.setup_problem(state.get_contest_id(), new_problem.id, language)
end

M.get_current_problem = get_current_problem

return M
