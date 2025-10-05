-- lua/cp/config.lua
---@class CpLangCommands
---@field build? string[]
---@field run? string[]
---@field debug? string[]

---@class CpLanguage
---@field extension string
---@field commands CpLangCommands

---@class CpPlatformOverrides
---@field extension? string
---@field commands? CpLangCommands

---@class CpPlatform
---@field enabled_languages string[]
---@field default_language string
---@field overrides? table<string, CpPlatformOverrides>

---@class RunPanelConfig
---@field ansi boolean
---@field diff_mode "none"|"vim"|"git"
---@field max_output_lines integer

---@class DiffGitConfig
---@field args string[]

---@class DiffConfig
---@field git DiffGitConfig

---@class Hooks
---@field before_run? fun(state: cp.State)
---@field before_debug? fun(state: cp.State)
---@field setup_code? fun(state: cp.State)

---@class CpUI
---@field run_panel RunPanelConfig
---@field diff DiffConfig
---@field picker string|nil

---@class cp.Config
---@field languages table<string, CpLanguage>
---@field platforms table<string, CpPlatform>
---@field hooks Hooks
---@field debug boolean
---@field scrapers string[]
---@field filename? fun(contest: string, contest_id: string, problem_id?: string, config: cp.Config, language?: string): string
---@field ui CpUI
---@field runtime { effective: table<string, table<string, CpLanguage>> }  -- computed

---@class cp.PartialConfig: cp.Config

local M = {}

local constants = require('cp.constants')
local utils = require('cp.utils')

-- defaults per the new single schema
---@type cp.Config
M.defaults = {
  languages = {
    cpp = {
      extension = 'cc',
      commands = {
        build = { 'g++', '-std=c++17', '{source}', '-o', '{binary}' },
        run = { '{binary}' },
        debug = {
          'g++',
          '-std=c++17',
          '-fsanitize=address,undefined',
          '{source}',
          '-o',
          '{binary}',
        },
      },
    },
    python = {
      extension = 'py',
      commands = {
        run = { 'python', '{source}' },
        debug = { 'python', '{source}' },
      },
    },
  },
  platforms = {
    codeforces = {
      enabled_languages = { 'cpp', 'python' },
      default_language = 'cpp',
      overrides = {
        -- example override, safe to keep empty initially
      },
    },
    atcoder = {
      enabled_languages = { 'cpp', 'python' },
      default_language = 'cpp',
    },
    cses = {
      enabled_languages = { 'cpp', 'python' },
      default_language = 'cpp',
    },
  },
  hooks = { before_run = nil, before_debug = nil, setup_code = nil },
  debug = false,
  scrapers = constants.PLATFORMS,
  filename = nil,
  ui = {
    run_panel = { ansi = true, diff_mode = 'none', max_output_lines = 50 },
    diff = {
      git = {
        args = { 'diff', '--no-index', '--word-diff=plain', '--word-diff-regex=.', '--no-prefix' },
      },
    },
    picker = nil,
  },
  runtime = { effective = {} },
}

local function is_string_list(t)
  if type(t) ~= 'table' then
    return false
  end
  for _, v in ipairs(t) do
    if type(v) ~= 'string' then
      return false
    end
  end
  return true
end

local function has_tokens(cmd, required)
  if type(cmd) ~= 'table' then
    return false
  end
  local s = table.concat(cmd, ' ')
  for _, tok in ipairs(required) do
    if not s:find(vim.pesc(tok), 1, true) then
      return false
    end
  end
  return true
end

local function validate_language(id, lang)
  vim.validate({
    extension = { lang.extension, 'string' },
    commands = { lang.commands, { 'table' } },
  })
  if lang.commands.build ~= nil then
    vim.validate({ build = { lang.commands.build, { 'table' } } })
    if not has_tokens(lang.commands.build, { '{source}', '{binary}' }) then
      error(('[cp.nvim] languages.%s.commands.build must include {source} and {binary}'):format(id))
    end
    for _, k in ipairs({ 'run', 'debug' }) do
      if lang.commands[k] then
        if not has_tokens(lang.commands[k], { '{binary}' }) then
          error(('[cp.nvim] languages.%s.commands.%s must include {binary}'):format(id, k))
        end
      end
    end
  else
    for _, k in ipairs({ 'run', 'debug' }) do
      if lang.commands[k] then
        if not has_tokens(lang.commands[k], { '{source}' }) then
          error(('[cp.nvim] languages.%s.commands.%s must include {source}'):format(id, k))
        end
      end
    end
  end
end

local function merge_lang(base, ov)
  if not ov then
    return base
  end
  local out = vim.deepcopy(base)
  if ov.extension then
    out.extension = ov.extension
  end
  if ov.commands then
    out.commands = vim.tbl_deep_extend('force', out.commands or {}, ov.commands or {})
  end
  return out
end

---@param cfg cp.Config
local function build_runtime(cfg)
  cfg.runtime = cfg.runtime or { effective = {} }
  for plat, p in pairs(cfg.platforms) do
    vim.validate({
      enabled_languages = { p.enabled_languages, is_string_list, 'string[]' },
      default_language = { p.default_language, 'string' },
    })
    for _, lid in ipairs(p.enabled_languages) do
      if not cfg.languages[lid] then
        error(("[cp.nvim] platform %s references unknown language '%s'"):format(plat, lid))
      end
    end
    if not vim.tbl_contains(p.enabled_languages, p.default_language) then
      error(
        ("[cp.nvim] platform %s default_language '%s' not in enabled_languages"):format(
          plat,
          p.default_language
        )
      )
    end
    cfg.runtime.effective[plat] = {}
    for _, lid in ipairs(p.enabled_languages) do
      local base = cfg.languages[lid]
      validate_language(lid, base)
      local eff = merge_lang(base, p.overrides and p.overrides[lid] or nil)
      validate_language(lid, eff)
      cfg.runtime.effective[plat][lid] = eff
    end
  end
end

---@param user_config cp.PartialConfig|nil
---@return cp.Config
function M.setup(user_config)
  vim.validate({ user_config = { user_config, { 'table', 'nil' }, true } })
  local cfg = vim.tbl_deep_extend('force', vim.deepcopy(M.defaults), user_config or {})

  vim.validate({
    hooks = { cfg.hooks, { 'table' } },
    ui = { cfg.ui, { 'table' } },
  })

  vim.validate({
    before_run = { cfg.hooks.before_run, { 'function', 'nil' }, true },
    before_debug = { cfg.hooks.before_debug, { 'function', 'nil' }, true },
    setup_code = { cfg.hooks.setup_code, { 'function', 'nil' }, true },
  })

  vim.validate({
    ansi = { cfg.ui.run_panel.ansi, 'boolean' },
    diff_mode = {
      cfg.ui.run_panel.diff_mode,
      function(v)
        return vim.tbl_contains({ 'none', 'vim', 'git' }, v)
      end,
      "diff_mode must be 'none', 'vim', or 'git'",
    },
    max_output_lines = {
      cfg.ui.run_panel.max_output_lines,
      function(v)
        return type(v) == 'number' and v > 0 and v == math.floor(v)
      end,
      'positive integer',
    },
    git = { cfg.ui.diff.git, { 'table' } },
  })

  for id, lang in pairs(cfg.languages) do
    validate_language(id, lang)
  end

  build_runtime(cfg)

  local ok, err = utils.check_required_runtime()
  if not ok then
    error('[cp.nvim] ' .. err)
  end

  return cfg
end

local current_config = nil

function M.set_current_config(config)
  current_config = config
end

function M.get_config()
  return current_config or M.defaults
end

---@param contest_id string
---@param problem_id? string
---@return string
local function default_filename(contest_id, problem_id)
  if problem_id then
    return (contest_id .. problem_id):lower()
  end
  return contest_id:lower()
end
M.default_filename = default_filename

return M
