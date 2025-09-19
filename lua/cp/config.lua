---@class LanguageConfig
---@field compile? string[] Compile command template
---@field run string[] Run command template
---@field debug? string[] Debug command template
---@field executable? string Executable name
---@field version? number Language version
---@field extension string File extension

---@class PartialLanguageConfig
---@field compile? string[] Compile command template
---@field run? string[] Run command template
---@field debug? string[] Debug command template
---@field executable? string Executable name
---@field version? number Language version
---@field extension? string File extension

---@class ContestConfig
---@field cpp LanguageConfig
---@field python LanguageConfig
---@field default_language string
---@field timeout_ms number

---@class PartialContestConfig
---@field cpp? PartialLanguageConfig
---@field python? PartialLanguageConfig
---@field default_language? string
---@field timeout_ms? number

---@class Hooks
---@field before_run? fun(ctx: ProblemContext)
---@field before_debug? fun(ctx: ProblemContext)
---@field setup_code? fun(ctx: ProblemContext)

---@class cp.Config
---@field contests table<string, ContestConfig>
---@field snippets table[]
---@field hooks Hooks
---@field debug boolean
---@field scrapers table<string, boolean>
---@field filename? fun(contest: string, contest_id: string, problem_id?: string, config: cp.Config, language?: string): string

---@class cp.UserConfig
---@field contests? table<string, PartialContestConfig>
---@field snippets? table[]
---@field hooks? Hooks
---@field debug? boolean
---@field scrapers? table<string, boolean>
---@field filename? fun(contest: string, contest_id: string, problem_id?: string, config: cp.Config, language?: string): string

local M = {}
local constants = require('cp.constants')

---@type cp.Config
M.defaults = {
  contests = {},
  snippets = {},
  hooks = {
    before_run = nil,
    before_debug = nil,
    setup_code = nil,
  },
  debug = false,
  scrapers = constants.PLATFORMS,
  filename = nil,
}

---@param user_config cp.UserConfig|nil
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
    })

    if user_config.hooks then
      vim.validate({
        before_run = {
          user_config.hooks.before_run,
          { 'function', 'nil' },
          true,
        },
        before_debug = {
          user_config.hooks.before_debug,
          { 'function', 'nil' },
          true,
        },
        setup_code = {
          user_config.hooks.setup_code,
          { 'function', 'nil' },
          true,
        },
      })
    end

    if user_config.contests then
      for contest_name, contest_config in pairs(user_config.contests) do
        for lang_name, lang_config in pairs(contest_config) do
          if type(lang_config) == 'table' and lang_config.extension then
            if
              not vim.tbl_contains(
                vim.tbl_keys(constants.filetype_to_language),
                lang_config.extension
              )
            then
              error(
                ("Invalid extension '%s' for language '%s' in contest '%s'. Valid extensions: %s"):format(
                  lang_config.extension,
                  lang_name,
                  contest_name,
                  table.concat(vim.tbl_keys(constants.filetype_to_language), ', ')
                )
              )
            end
          end
        end
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
  end

  local config = vim.tbl_deep_extend('force', M.defaults, user_config or {})

  for contest_name, contest_config in pairs(config.contests) do
    for lang_name, lang_config in pairs(contest_config) do
      if type(lang_config) == 'table' and not lang_config.extension then
        if lang_name == 'cpp' then
          lang_config.extension = 'cpp'
        elseif lang_name == 'python' then
          lang_config.extension = 'py'
        end
      end
    end
  end

  return config
end

---@param contest_id string
---@param problem_id? string
---@return string
local function default_filename(contest_id, problem_id)
  vim.validate({
    contest_id = { contest_id, 'string' },
    problem_id = { problem_id, { 'string', 'nil' }, true },
  })

  if problem_id then
    return (contest_id .. problem_id):lower()
  else
    return contest_id:lower()
  end
end

M.default_filename = default_filename

return M
