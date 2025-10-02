---@class FileState
---@field platform string
---@field contest_id string
---@field problem_id? string
---@field language? string

---@class CacheData
---@field [string] table<string, ContestData>
---@field file_states? table<string, FileState>
---@field contest_lists? table<string, ContestListData>

---@class ContestListData
---@field contests table[]

---@class ContestData
---@field problems Problem[]
---@field test_cases? CachedTestCase[]
---@field timeout_ms? number
---@field memory_mb? number
---@field interactive? boolean

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

  if not cache_data[platform] then
    cache_data[platform] = {}
  end

  cache_data[platform][contest_id] = {
    problems = problems,
  }

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

  local problem_key = problem_id and (contest_id .. '_' .. problem_id) or contest_id
  if not cache_data[platform] or not cache_data[platform][problem_key] then
    return nil
  end
  return cache_data[platform][problem_key].test_cases
end

---@param platform string
---@param contest_id string
---@param problem_id? string
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

  local problem_key = problem_id and (contest_id .. '_' .. problem_id) or contest_id
  if not cache_data[platform] then
    cache_data[platform] = {}
  end
  if not cache_data[platform][problem_key] then
    cache_data[platform][problem_key] = {}
  end

  cache_data[platform][problem_key].test_cases = test_cases
  if timeout_ms then
    cache_data[platform][problem_key].timeout_ms = timeout_ms
  end
  if memory_mb then
    cache_data[platform][problem_key].memory_mb = memory_mb
  end
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

  local problem_key = problem_id and (contest_id .. '_' .. problem_id) or contest_id
  if not cache_data[platform] or not cache_data[platform][problem_key] then
    return nil, nil
  end

  local problem_data = cache_data[platform][problem_key]
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
---@return table[]?
function M.get_contest_list(platform)
  if not cache_data.contest_lists or not cache_data.contest_lists[platform] then
    return nil
  end

  return cache_data.contest_lists[platform].contests
end

---@param platform string
---@param contests table[]
function M.set_contest_list(platform, contests)
  if not cache_data.contest_lists then
    cache_data.contest_lists = {}
  end

  cache_data.contest_lists[platform] = {
    contests = contests,
  }

  M.save()
end

---@param platform string
function M.clear_contest_list(platform)
  if cache_data.contest_lists and cache_data.contest_lists[platform] then
    cache_data.contest_lists[platform] = nil
    M.save()
  end
end

function M.clear_all()
  cache_data = {
    file_states = {},
    contest_lists = {},
  }
  M.save()
end

---@param platform string
function M.clear_platform(platform)
  if cache_data[platform] then
    cache_data[platform] = nil
  end
  if cache_data.contest_lists and cache_data.contest_lists[platform] then
    cache_data.contest_lists[platform] = nil
  end
  M.save()
end

return M
