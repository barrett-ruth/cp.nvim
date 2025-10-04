---@class PlatformLanguageConfig
---@field compile? string[] Compile command template
---@field test string[] Test execution command template
---@field debug? string[] Debug command template
---@field executable? string Executable name
---@field extension? string File extension

---@class PlatformConfig
---@field [string] PlatformLanguageConfig
---@field default_language? string

---@class Hooks
---@field before_run? fun(state: cp.State)
---@field before_debug? fun(state: cp.State)
---@field setup_code? fun(state: cp.State)

---@class RunPanelConfig
---@field ansi boolean Enable ANSI color parsing and highlighting
---@field diff_mode "none"|"vim"|"git" Diff backend to use
---@field max_output_lines number Maximum lines of test output to display

---@class DiffGitConfig
---@field args string[] Git diff arguments

---@class DiffConfig
---@field git DiffGitConfig

---@class cp.Config
---@field platforms table<string, PlatformConfig>
---@field snippets any[]
---@field hooks Hooks
---@field debug boolean
---@field filename? fun(contest: string, contest_id: string, problem_id?: string, config: cp.Config, language?: string): string
---@field run_panel RunPanelConfig
---@field diff DiffConfig
---@field picker string|nil

---@class cp.PartialConfig
---@field platforms? table<string, PlatformConfig>
---@field snippets? any[]
---@field hooks? Hooks
---@field debug? boolean
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
  },
  default_language = 'cpp',
}

---@type cp.Config
M.defaults = {
  platforms = {
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
      platforms = { user_config.platforms, { 'table', 'nil' }, true },
      snippets = { user_config.snippets, { 'table', 'nil' }, true },
      hooks = { user_config.hooks, { 'table', 'nil' }, true },
      debug = { user_config.debug, { 'boolean', 'nil' }, true },
      filename = { user_config.filename, { 'function', 'nil' }, true },
      run_panel = { user_config.run_panel, { 'table', 'nil' }, true },
      diff = { user_config.diff, { 'table', 'nil' }, true },
      picker = { user_config.picker, { 'string', 'nil' }, true },
    })

    if user_config.platforms then
      for platform_name, platform_config in pairs(user_config.platforms) do
        vim.validate({
          [platform_name] = {
            platform_config,
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

  for _, platform_config in pairs(config.platforms) do
    if not platform_config.default_language then
      -- arbitrarily choose a language
      platform_config.default_language = vim.tbl_keys(platform_config)[1]
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
