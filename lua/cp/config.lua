---@class LanguageConfig
---@field compile? string[] Compile command template
---@field test string[] Test execution command template
---@field debug? string[] Debug command template
---@field executable? string Executable name
---@field version? number Language version
---@field extension? string File extension

---@class ContestConfig
---@field cpp LanguageConfig
---@field python LanguageConfig
---@field default_language? string

---@class Hooks
---@field before_run? fun(state: cp.State)
---@field before_debug? fun(state: cp.State)
---@field setup_code? fun(state: cp.State)

---@class RunPanelConfig
---@field ansi boolean Enable ANSI color parsing and highlighting
---@field diff_mode "none"|"vim"|"git" Diff backend to use
---@field next_test_key string Key to navigate to next test case
---@field prev_test_key string Key to navigate to previous test case
---@field max_output_lines number Maximum lines of test output to display

---@class DiffGitConfig
---@field args string[] Git diff arguments

---@class DiffConfig
---@field git DiffGitConfig

---@class cp.Config
---@field contests table<string, ContestConfig>
---@field snippets any[]
---@field hooks Hooks
---@field debug boolean
---@field scrapers string[]
---@field filename? fun(contest: string, contest_id: string, problem_id?: string, config: cp.Config, language?: string): string
---@field run_panel RunPanelConfig
---@field diff DiffConfig
---@field picker string|nil

---@class cp.PartialConfig
---@field contests? table<string, ContestConfig>
---@field snippets? any[]
---@field hooks? Hooks
---@field debug? boolean
---@field scrapers? string[]
---@field filename? fun(contest: string, contest_id: string, problem_id?: string, config: cp.Config, language?: string): string
---@field run_panel? RunPanelConfig
---@field diff? DiffConfig
---@field picker? string|nil

local M = {}

local constants = require('cp.constants')
local utils = require('cp.utils')

local default_contest_config = {
  cpp = {
    compile = { 'g++', '-std=c++17', '{source}', '-o', '{binary}' },
    debug = { 'g++', '-std=c++17', '-fsanitize=address,undefined', '{source}', '-o', '{binary}' },
    test = { '{binary}' },
  },
  python = {
    test = { '{source}' },
    debug = { '{source}' },
    executable = 'python',
    extension = 'py',
  },
  default_language = 'cpp',
}

---@type cp.Config
M.defaults = {
  contests = {
    codeforces = default_contest_config,
    atcoder = default_contest_config,
    cses = default_contest_config,
  },
  snippets = {},
  hooks = {
    before_run = nil,
    before_debug = nil,
    setup_code = nil,
  },
  debug = false,
  scrapers = constants.PLATFORMS,
  filename = nil,
  run_panel = {
    ansi = true,
    diff_mode = 'none',
    next_test_key = '<c-n>',
    prev_test_key = '<c-p>',
    max_output_lines = 50,
  },
  diff = {
    git = {
      args = { 'diff', '--no-index', '--word-diff=plain', '--word-diff-regex=.', '--no-prefix' },
    },
  },
  picker = nil,
}

---@param user_config cp.PartialConfig|nil
---@return cp.Config
function M.setup(user_config)
  vim.validate({
    user_config = { user_config, { 'table', 'nil' }, true },
  })

  if user_config then
    vim.validate({
      contests = { user_config.contests, { 'table', 'nil' }, true },
      snippets = { user_config.snippets, { 'table', 'nil' }, true },
      hooks = { user_config.hooks, { 'table', 'nil' }, true },
      debug = { user_config.debug, { 'boolean', 'nil' }, true },
      scrapers = { user_config.scrapers, { 'table', 'nil' }, true },
      filename = { user_config.filename, { 'function', 'nil' }, true },
      run_panel = { user_config.run_panel, { 'table', 'nil' }, true },
      diff = { user_config.diff, { 'table', 'nil' }, true },
      picker = { user_config.picker, { 'string', 'nil' }, true },
    })

    if user_config.contests then
      for contest_name, contest_config in pairs(user_config.contests) do
        vim.validate({
          [contest_name] = {
            contest_config,
            function(config)
              if type(config) ~= 'table' then
                return false
              end

              return true
            end,
            'contest configuration',
          },
        })
      end
    end

    if user_config.scrapers then
      for _, platform_name in ipairs(user_config.scrapers) do
        if type(platform_name) ~= 'string' then
          error(('Invalid scraper value type. Expected string, got %s'):format(type(platform_name)))
        end
        if not vim.tbl_contains(constants.PLATFORMS, platform_name) then
          error(
            ("Invalid platform '%s' in scrapers config. Valid platforms: %s"):format(
              platform_name,
              table.concat(constants.PLATFORMS, ', ')
            )
          )
        end
      end
    end

    if user_config.picker then
      if not vim.tbl_contains({ 'telescope', 'fzf-lua' }, user_config.picker) then
        error(("Invalid picker '%s'. Must be 'telescope' or 'fzf-lua'"):format(user_config.picker))
      end
    end
  end

  local config = vim.tbl_deep_extend('force', M.defaults, user_config or {})

  vim.validate({
    before_run = {
      config.hooks.before_run,
      { 'function', 'nil' },
      true,
    },
    before_debug = {
      config.hooks.before_debug,
      { 'function', 'nil' },
      true,
    },
    setup_code = {
      config.hooks.setup_code,
      { 'function', 'nil' },
      true,
    },
  })

  vim.validate({
    ansi = {
      config.run_panel.ansi,
      'boolean',
      'ansi color parsing must be enabled xor disabled',
    },
    diff_mode = {
      config.run_panel.diff_mode,
      function(value)
        return vim.tbl_contains({ 'none', 'vim', 'git' }, value)
      end,
      "diff_mode must be 'none', 'vim', or 'git'",
    },
    next_test_key = {
      config.run_panel.next_test_key,
      function(value)
        return type(value) == 'string' and value ~= ''
      end,
      'next_test_key must be a non-empty string',
    },
    prev_test_key = {
      config.run_panel.prev_test_key,
      function(value)
        return type(value) == 'string' and value ~= ''
      end,
      'prev_test_key must be a non-empty string',
    },
    max_output_lines = {
      config.run_panel.max_output_lines,
      function(value)
        return type(value) == 'number' and value > 0 and value == math.floor(value)
      end,
      'max_output_lines must be a positive integer',
    },
  })

  vim.validate({
    git = { config.diff.git, { 'table', 'nil' }, true },
  })

  for _, contest_config in pairs(config.contests) do
    for lang_name, lang_config in pairs(contest_config) do
      if type(lang_config) == 'table' and not lang_config.extension then
        if lang_name == 'cpp' then
          lang_config.extension = 'cpp'
        elseif lang_name == 'python' then
          lang_config.extension = 'py'
        end
      end
    end

    if not contest_config.default_language then
      local available_langs = {}
      for lang_name, lang_config in pairs(contest_config) do
        if type(lang_config) == 'table' and lang_name ~= 'default_language' then
          table.insert(available_langs, lang_name)
        end
      end

      if vim.tbl_isemtpy(available_langs) then
        error('No language configurations found')
      end

      table.sort(available_langs)
      contest_config.default_language = available_langs[1]
    end
  end

  local ok, err = utils.check_required_runtime()
  if not ok then
    error('[cp.nvim] ' .. err)
  end

  return config
end

---@param contest_id string
---@param problem_id? string
---@return string
local function default_filename(contest_id, problem_id)
  if problem_id then
    return (contest_id .. problem_id):lower()
  else
    return contest_id:lower()
  end
end

M.default_filename = default_filename

local current_config = nil

--- Set the config
---@return nil
function M.set_current_config(config)
  current_config = config
end

--- Get the config
---@return cp.Config
function M.get_config()
  return current_config or M.defaults
end

return M
