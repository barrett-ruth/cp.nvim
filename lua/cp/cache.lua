---@class FileState
---@field platform string
---@field contest_id string
---@field problem_id? string
---@field language? string

---@class ContestData
---@field problems Problem[]
---@field test_cases? CachedTestCase[]
---@field timeout_ms? number
---@field memory_mb? number
---@field interactive? boolean

---@class ContestSummary
---@field display_name string
---@field name string
---@field id string

---@class CacheData
---@field [string] table<string, ContestData>
---@field file_states? table<string, FileState>
---@field contest_lists? table<string, ContestListData>

---@class ContestListData
---@field contests table[]

---@class Problem
---@field id string
---@field name? string

---@class CachedTestCase
---@field index? number
---@field input string
---@field expected? string
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
---@return ContestData?
function M.get_contest_data(platform, contest_id)
  vim.validate({
    platform = { platform, 'string' },
    contest_id = { contest_id, 'string' },
  })

  if not cache_data[platform] then
    return nil
  end

  local contest_data = cache_data[platform][contest_id]
  if not contest_data or vim.tbl_isempty(contest_data) then
    return nil
  end

  return contest_data
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
  local existing = cache_data[platform][contest_id] or {}

  local existing_by_id = {}
  if existing.problems then
    for _, p in ipairs(existing.problems) do
      existing_by_id[p.id] = p
    end
  end

  local merged = {}
  for _, p in ipairs(problems) do
    local prev = existing_by_id[p.id] or {}
    local merged_p = {
      id = p.id,
      name = p.name or prev.name,
      test_cases = prev.test_cases,
      timeout_ms = prev.timeout_ms,
      memory_mb = prev.memory_mb,
      interactive = prev.interactive,
    }
    table.insert(merged, merged_p)
  end

  existing.problems = merged
  existing.index_map = {}
  for i, p in ipairs(merged) do
    existing.index_map[p.id] = i
  end

  cache_data[platform][contest_id] = existing
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
---@return CachedTestCase[]?
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
    print('bad, failing')
    return nil
  end

  local index = cache_data[platform][contest_id].index_map[problem_id]
  return cache_data[platform][contest_id].problems[index].test_cases
end

---@param platform string
---@param contest_id string
---@param problem_id string
---@param test_cases CachedTestCase[]
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
---@param language? string
function M.set_file_state(file_path, platform, contest_id, problem_id, language)
  if not cache_data.file_states then
    cache_data.file_states = {}
  end

  cache_data.file_states[file_path] = {
    platform = platform,
    contest_id = contest_id,
    problem_id = problem_id,
    language = language,
  }

  M.save()
end

---@param platform string
---@return table[ContestSummary]
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
---@param contests table[ContestSummary]
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
