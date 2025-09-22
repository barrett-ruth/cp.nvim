local M = {}

local logger = require('cp.log')
local scrape = require('cp.scrape')
local state = require('cp.state')

function M.scrape_missing_problems(contest_id, missing_problems, config)
  vim.fn.mkdir('io', 'p')

  logger.log(('scraping %d uncached problems...'):format(#missing_problems))

  local results =
    scrape.scrape_problems_parallel(state.get_platform(), contest_id, missing_problems, config)

  local success_count = 0
  local failed_problems = {}
  for problem_id, result in pairs(results) do
    if result.success then
      success_count = success_count + 1
    else
      table.insert(failed_problems, problem_id)
    end
  end

  if #failed_problems > 0 then
    logger.log(
      ('scraping complete: %d/%d successful, failed: %s'):format(
        success_count,
        #missing_problems,
        table.concat(failed_problems, ', ')
      ),
      vim.log.levels.WARN
    )
  else
    logger.log(('scraping complete: %d/%d successful'):format(success_count, #missing_problems))
  end
end

return M
