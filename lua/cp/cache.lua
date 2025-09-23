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
---@field cached_at number
---@field expires_at number

---@class ContestData
---@field problems Problem[]
---@field scraped_at string
---@field expires_at? number
---@field test_cases? CachedTestCase[]
---@field test_cases_cached_at? number
---@field timeout_ms? number
---@field memory_mb? number

---@class Problem
---@field id string
---@field name? string

---@class CachedTestCase
---@field index? number
---@field input string
---@field expected? string
---@field output? string

local M = {}

local cache_file = vim.fn.stdpath('data') .. '/cp-nvim.json'
local cache_data = {}
local loaded = false

local CONTEST_LIST_TTL = {
  cses = 7 * 24 * 60 * 60,
  codeforces = 24 * 60 * 60,
  atcoder = 24 * 60 * 60,
}

---@param contest_data ContestData
---@param platform string
---@return boolean
local function is_cache_valid(contest_data, platform)
  vim.validate({
    contest_data = { contest_data, 'table' },
    platform = { platform, 'string' },
  })

  if contest_data.expires_at and os.time() >= contest_data.expires_at then
    return false
  end

  return true
end

function M.load()
  if loaded then
    return
  end

  if vim.fn.filereadable(cache_file) == 0 then
    cache_data = {}
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
    cache_data = {}
  end
  loaded = true
end

function M.save()
  local ok, _ = pcall(vim.fn.mkdir, vim.fn.fnamemodify(cache_file, ':h'), 'p')
  if not ok then
    vim.schedule(function()
      vim.fn.mkdir(vim.fn.fnamemodify(cache_file, ':h'), 'p')
    end)
    return
  end

  local encoded = vim.json.encode(cache_data)
  local lines = vim.split(encoded, '\n')
  ok, err = pcall(vim.fn.writefile, lines, cache_file)
  if not ok then
    vim.schedule(function()
      vim.fn.writefile(lines, cache_file)
    end)
  end
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
  if not contest_data then
    return nil
  end

  if not is_cache_valid(contest_data, platform) then
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

  local ttl = CONTEST_LIST_TTL[platform] or (24 * 60 * 60)
  cache_data[platform][contest_id] = {
    problems = problems,
    scraped_at = os.date('%Y-%m-%d'),
    expires_at = os.time() + ttl,
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
function M.set_test_cases(platform, contest_id, problem_id, test_cases, timeout_ms, memory_mb)
  vim.validate({
    platform = { platform, 'string' },
    contest_id = { contest_id, 'string' },
    problem_id = { problem_id, { 'string', 'nil' }, true },
    test_cases = { test_cases, 'table' },
    timeout_ms = { timeout_ms, { 'number', 'nil' }, true },
    memory_mb = { memory_mb, { 'number', 'nil' }, true },
  })

  local problem_key = problem_id and (contest_id .. '_' .. problem_id) or contest_id
  if not cache_data[platform] then
    cache_data[platform] = {}
  end
  if not cache_data[platform][problem_key] then
    cache_data[platform][problem_key] = {}
  end

  cache_data[platform][problem_key].test_cases = test_cases
  cache_data[platform][problem_key].test_cases_cached_at = os.time()
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
  vim.validate({
    file_path = { file_path, 'string' },
  })

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
  vim.validate({
    file_path = { file_path, 'string' },
    platform = { platform, 'string' },
    contest_id = { contest_id, 'string' },
    problem_id = { problem_id, { 'string', 'nil' }, true },
    language = { language, { 'string', 'nil' }, true },
  })

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
  vim.validate({
    platform = { platform, 'string' },
  })

  if not cache_data.contest_lists or not cache_data.contest_lists[platform] then
    return nil
  end

  local contest_list_data = cache_data.contest_lists[platform]
  if os.time() >= contest_list_data.expires_at then
    return nil
  end

  return contest_list_data.contests
end

---@param platform string
---@param contests table[]
function M.set_contest_list(platform, contests)
  vim.validate({
    platform = { platform, 'string' },
    contests = { contests, 'table' },
  })

  if not cache_data.contest_lists then
    cache_data.contest_lists = {}
  end

  local ttl = CONTEST_LIST_TTL[platform] or (24 * 60 * 60)
  cache_data.contest_lists[platform] = {
    contests = contests,
    cached_at = os.time(),
    expires_at = os.time() + ttl,
  }

  M.save()
end

---@param platform string
function M.clear_contest_list(platform)
  vim.validate({
    platform = { platform, 'string' },
  })

  if cache_data.contest_lists and cache_data.contest_lists[platform] then
    cache_data.contest_lists[platform] = nil
    M.save()
  end
end

function M.clear_all()
  cache_data = {}
  M.save()
end

---@param platform string
function M.clear_platform(platform)
  vim.validate({
    platform = { platform, 'string' },
  })

  if cache_data[platform] then
    cache_data[platform] = nil
  end
  if cache_data.contest_lists and cache_data.contest_lists[platform] then
    cache_data.contest_lists[platform] = nil
  end
  M.save()
end

return M
