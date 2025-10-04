---@class FileState
---@field platform string
---@field contest_id string
---@field problem_id? string
---@field language? string

---@class ContestData
---@field problems Problem[]
---@field index_map table<string, number>
---@field name string
---@field display_name string

---@class ContestSummary
---@field display_name string
---@field name string
---@field id string

---@class Problem
---@field id string
---@field name? string
---@field interactive? boolean
---@field memory_mb? number
---@field timeout_ms? number
---@field test_cases TestCase[]

---@class TestCase
---@field index? number
---@field expected? string
---@field input? string
---@field output? string

local M = {}

local logger = require('cp.log')
local cache_file = vim.fn.stdpath('data') .. '/cp-nvim.json'
local cache_data = {}
local loaded = false

--- Load the cache from disk if not done already
---@return nil
function M.load()
  if loaded then
    return
  end

  if vim.fn.filereadable(cache_file) == 0 then
    vim.fn.writefile({}, cache_file)
    loaded = true
    return
  end

  local content = vim.fn.readfile(cache_file)
  if #content == 0 then
    cache_data = {}
    loaded = true
    return
  end

  local ok, decoded = pcall(vim.json.decode, table.concat(content, '\n'))
  if ok then
    cache_data = decoded
  else
    logger.log('Could not decode json in cache file', vim.log.levels.ERROR)
  end
  loaded = true
end

--- Save the cache to disk, overwriting existing contents
---@return nil
function M.save()
  vim.schedule(function()
    vim.fn.mkdir(vim.fn.fnamemodify(cache_file, ':h'), 'p')

    local encoded = vim.json.encode(cache_data)
    local lines = vim.split(encoded, '\n')
    vim.fn.writefile(lines, cache_file)
  end)
end

---@param platform string
---@param contest_id string
---@return ContestData
function M.get_contest_data(platform, contest_id)
  vim.validate({
    platform = { platform, 'string' },
    contest_id = { contest_id, 'string' },
  })

  cache_data[platform] = cache_data[platform] or {}
  cache_data[platform][contest_id] = cache_data[platform][contest_id] or {}
  return cache_data[platform][contest_id]
end

---@param platform string
---@param contest_id string
---@param problems Problem[]
function M.set_contest_data(platform, contest_id, problems)
  vim.validate({
    platform = { platform, 'string' },
    contest_id = { contest_id, 'string' },
    problems = { problems, 'table' },
  })

  cache_data[platform] = cache_data[platform] or {}
  local prev = cache_data[platform][contest_id] or {}

  local out = {
    name = prev.name,
    display_name = prev.display_name,
    problems = problems,
    index_map = {},
  }
  for i, p in ipairs(out.problems) do
    out.index_map[p.id] = i
  end

  cache_data[platform][contest_id] = out
  M.save()
end

---@param platform string
---@param contest_id string
function M.clear_contest_data(platform, contest_id)
  vim.validate({
    platform = { platform, 'string' },
    contest_id = { contest_id, 'string' },
  })

  if cache_data[platform] and cache_data[platform][contest_id] then
    cache_data[platform][contest_id] = nil
    M.save()
  end
end

---@param platform string
---@param contest_id string
---@param problem_id? string
---@return TestCase[]
function M.get_test_cases(platform, contest_id, problem_id)
  vim.validate({
    platform = { platform, 'string' },
    contest_id = { contest_id, 'string' },
    problem_id = { problem_id, { 'string', 'nil' }, true },
  })

  if
    not cache_data[platform]
    or not cache_data[platform][contest_id]
    or not cache_data[platform][contest_id].problems
    or not cache_data[platform][contest_id].index_map
  then
    return {}
  end

  local index = cache_data[platform][contest_id].index_map[problem_id]
  return cache_data[platform][contest_id].problems[index].test_cases or {}
end

---@param platform string
---@param contest_id string
---@param problem_id string
---@param test_cases TestCase[]
---@param timeout_ms? number
---@param memory_mb? number
---@param interactive? boolean
function M.set_test_cases(
  platform,
  contest_id,
  problem_id,
  test_cases,
  timeout_ms,
  memory_mb,
  interactive
)
  vim.validate({
    platform = { platform, 'string' },
    contest_id = { contest_id, 'string' },
    problem_id = { problem_id, { 'string', 'nil' }, true },
    test_cases = { test_cases, 'table' },
    timeout_ms = { timeout_ms, { 'number', 'nil' }, true },
    memory_mb = { memory_mb, { 'number', 'nil' }, true },
    interactive = { interactive, { 'boolean', 'nil' }, true },
  })

  local index = cache_data[platform][contest_id].index_map[problem_id]

  cache_data[platform][contest_id].problems[index].test_cases = test_cases
  cache_data[platform][contest_id].problems[index].timeout_ms = timeout_ms or 0
  cache_data[platform][contest_id].problems[index].memory_mb = memory_mb or 0

  M.save()
end

---@param platform string
---@param contest_id string
---@param problem_id? string
---@return number?, number?
function M.get_constraints(platform, contest_id, problem_id)
  vim.validate({
    platform = { platform, 'string' },
    contest_id = { contest_id, 'string' },
    problem_id = { problem_id, { 'string', 'nil' }, true },
  })

  local index = cache_data[platform][contest_id].index_map[problem_id]

  local problem_data = cache_data[platform][contest_id].problems[index]
  return problem_data.timeout_ms, problem_data.memory_mb
end

---@param file_path string
---@return FileState?
function M.get_file_state(file_path)
  if not cache_data.file_states then
    return nil
  end

  return cache_data.file_states[file_path]
end

---@param file_path string
---@param platform string
---@param contest_id string
---@param problem_id? string
function M.set_file_state(file_path, platform, contest_id, problem_id)
  if not cache_data.file_states then
    cache_data.file_states = {}
  end

  cache_data.file_states[file_path] = {
    platform = platform,
    contest_id = contest_id,
    problem_id = problem_id,
  }

  M.save()
end

---@param platform string
---@return ContestSummary[]
function M.get_contest_summaries(platform)
  local contest_list = {}
  for contest_id, contest_data in pairs(cache_data[platform] or {}) do
    table.insert(contest_list, {
      id = contest_id,
      name = contest_data.name,
      display_name = contest_data.display_name,
    })
  end
  return contest_list
end

---@param platform string
---@param contests ContestSummary[]
function M.set_contest_summaries(platform, contests)
  cache_data[platform] = cache_data[platform] or {}
  for _, contest in ipairs(contests) do
    cache_data[platform][contest.id] = cache_data[platform][contest] or {}
    cache_data[platform][contest.id].display_name = contest.display_name
    cache_data[platform][contest.id].name = contest.name
  end

  M.save()
end

function M.clear_all()
  cache_data = {}
  M.save()
end

---@param platform string
function M.clear_platform(platform)
  if cache_data[platform] then
    cache_data[platform] = nil
  end

  M.save()
end

---@return string
function M.get_data_pretty()
  M.load()

  return vim.inspect(cache_data)
end

return M
