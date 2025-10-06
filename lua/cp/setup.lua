local M = {}

local cache = require('cp.cache')
local config_module = require('cp.config')
local constants = require('cp.constants')
local logger = require('cp.log')
local scraper = require('cp.scraper')
local state = require('cp.state')

---@class TestCaseLite
---@field input string
---@field expected string

---@class ScrapeEvent
---@field problem_id string
---@field tests TestCaseLite[]|nil
---@field timeout_ms integer|nil
---@field memory_mb integer|nil
---@field interactive boolean|nil
---@field error string|nil
---@field done boolean|nil
---@field succeeded integer|nil
---@field failed integer|nil

---@param cd table|nil
---@return boolean
local function is_metadata_ready(cd)
  return cd
    and type(cd.problems) == 'table'
    and #cd.problems > 0
    and type(cd.index_map) == 'table'
    and next(cd.index_map) ~= nil
end

---@param platform string
---@param contest_id string
---@param problems table
local function start_tests(platform, contest_id, problems)
  local cached_len = #vim.tbl_filter(function(p)
    return not vim.tbl_isempty(cache.get_test_cases(platform, contest_id, p.id))
  end, problems)
  if cached_len ~= #problems then
    logger.log(('Fetching test cases... (%d/%d)'):format(cached_len, #problems))
    scraper.scrape_all_tests(platform, contest_id, function(ev)
      local cached_tests = {}
      if not ev.interactive and vim.tbl_isempty(ev.tests) then
        logger.log(("No tests found for problem '%s'."):format(ev.problem_id), vim.log.levels.WARN)
      end
      for i, t in ipairs(ev.tests) do
        cached_tests[i] = { index = i, input = t.input, expected = t.expected }
      end
      cache.set_test_cases(
        platform,
        contest_id,
        ev.problem_id,
        cached_tests,
        ev.timeout_ms or 0,
        ev.memory_mb or 0,
        ev.interactive
      )
    end)
  end
end

---@param platform string
---@param contest_id string
---@param problem_id? string
---@param language? string
function M.setup_contest(platform, contest_id, problem_id, language)
  state.set_platform(platform)
  state.set_contest_id(contest_id)
  cache.load()

  local function proceed(contest_data)
    local problems = contest_data.problems
    local pid = problem_id and problem_id or problems[1].id
    M.setup_problem(pid, language)
    start_tests(platform, contest_id, problems)
  end

  local contest_data = cache.get_contest_data(platform, contest_id)
  if not is_metadata_ready(contest_data) then
    local cfg = config_module.get_config()
    local lang = language or (cfg.platforms[platform] and cfg.platforms[platform].default_language)

    vim.cmd.only({ mods = { silent = true } })
    local bufnr = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_win_set_buf(0, bufnr)
    if lang then
      vim.bo[bufnr].filetype = lang
    end
    vim.bo[bufnr].buftype = ''

    local ext = cfg.runtime
      and cfg.runtime.effective[platform]
      and cfg.runtime.effective[platform][lang]
      and cfg.runtime.effective[platform][lang].extension
    local provisional_name = nil
    if ext then
      provisional_name = (config_module.default_filename(contest_id) .. '.' .. ext)
      vim.api.nvim_buf_set_name(bufnr, provisional_name)
    end

    if cfg.hooks and cfg.hooks.setup_code and not vim.b[bufnr].cp_setup_done then
      local ok = pcall(cfg.hooks.setup_code, state)
      if ok then
        vim.b[bufnr].cp_setup_done = true
      end
    end

    if provisional_name then
      cache.set_file_state(
        vim.fn.fnamemodify(provisional_name, ':p'),
        platform,
        contest_id,
        '',
        lang
      )
    end

    state.set_provisional({
      bufnr = bufnr,
      platform = platform,
      contest_id = contest_id,
      language = lang,
      requested_problem_id = problem_id,
      token = vim.loop.hrtime(),
    })

    logger.log('Fetching contests problems...', vim.log.levels.INFO, true)
    scraper.scrape_contest_metadata(
      platform,
      contest_id,
      vim.schedule_wrap(function(result)
        local problems = result.problems or {}
        cache.set_contest_data(platform, contest_id, problems)
        local prov = state.get_provisional()
        if not prov or prov.platform ~= platform or prov.contest_id ~= contest_id then
          return
        end
        local cd = cache.get_contest_data(platform, contest_id)
        if not is_metadata_ready(cd) then
          return
        end
        local pid = prov.requested_problem_id
        if not pid or not cd.index_map or not cd.index_map[pid] then
          pid = cd.problems[1] and cd.problems[1].id or nil
        end
        if not pid then
          return
        end
        M.setup_problem(pid, prov.language)
        start_tests(platform, contest_id, cd.problems)
      end)
    )
    return
  end

  proceed(contest_data)
end

---@param problem_id string
---@param language? string
function M.setup_problem(problem_id, language)
  local platform = state.get_platform()
  if not platform then
    return
  end

  state.set_problem_id(problem_id)
  local config = config_module.get_config()
  local lang = language
    or (config.platforms[platform] and config.platforms[platform].default_language)
  local source_file = state.get_source_file(lang)
  if not source_file then
    return
  end

  local prov = state.get_provisional()
  if prov and prov.platform == platform and prov.contest_id == (state.get_contest_id() or '') then
    if vim.api.nvim_buf_is_valid(prov.bufnr) then
      local old = vim.api.nvim_buf_get_name(prov.bufnr)
      local new = source_file
      if old ~= '' and old ~= new then
        local st = vim.loop.fs_stat(old)
        if st and st.type == 'file' then
          pcall(vim.loop.fs_rename, old, new)
        end
      end
      vim.api.nvim_buf_set_name(prov.bufnr, new)
      if config.hooks and config.hooks.setup_code and not vim.b[prov.bufnr].cp_setup_done then
        local ok = pcall(config.hooks.setup_code, state)
        if ok then
          vim.b[prov.bufnr].cp_setup_done = true
        end
      end
      cache.set_file_state(
        vim.fn.fnamemodify(new, ':p'),
        platform,
        state.get_contest_id() or '',
        state.get_problem_id() or '',
        lang
      )
    end
    state.set_provisional(nil)
    return
  end

  vim.schedule(function()
    vim.cmd.only({ mods = { silent = true } })
    vim.cmd.e(source_file)
    local bufnr = vim.api.nvim_get_current_buf()
    if config.hooks and config.hooks.setup_code and not vim.b[bufnr].cp_setup_done then
      local ok = pcall(config.hooks.setup_code, state)
      if ok then
        vim.b[bufnr].cp_setup_done = true
      end
    end
    cache.set_file_state(
      vim.fn.expand('%:p'),
      platform,
      state.get_contest_id() or '',
      state.get_problem_id() or '',
      lang
    )
  end)
end

---@param direction integer
function M.navigate_problem(direction)
  if direction == 0 then
    return
  end
  direction = direction > 0 and 1 or -1

  local platform = state.get_platform()
  local contest_id = state.get_contest_id()
  local current_problem_id = state.get_problem_id()
  if not platform or not contest_id or not current_problem_id then
    logger.log('No platform configured.', vim.log.levels.ERROR)
    return
  end

  cache.load()
  local contest_data = cache.get_contest_data(platform, contest_id)
  if not is_metadata_ready(contest_data) then
    logger.log(
      ('No data available for %s contest %s.'):format(
        constants.PLATFORM_DISPLAY_NAMES[platform],
        contest_id
      ),
      vim.log.levels.ERROR
    )
    return
  end

  local problems = contest_data.problems
  local index = contest_data.index_map[current_problem_id]
  local new_index = index + direction
  if new_index < 1 or new_index > #problems then
    return
  end

  require('cp.ui.panel').disable()
  M.setup_contest(platform, contest_id, problems[new_index].id)
end

return M
