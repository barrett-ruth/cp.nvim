local picker_utils = require('cp.pickers')

local M = {}

local function contest_picker(platform, refresh)
  local constants = require('cp.constants')
  local platform_display_name = constants.PLATFORM_DISPLAY_NAMES[platform]
  local fzf = require('fzf-lua')
  local contests = picker_utils.get_platform_contests(platform, refresh)

  if vim.tbl_isempty(contests) then
    vim.notify(
      ("No contests found for platform '%s'"):format(platform_display_name),
      vim.log.levels.WARN
    )
    return
  end

  local entries = vim.tbl_map(function(contest)
    return contest.display_name
  end, contests)

  return fzf.fzf_exec(entries, {
    prompt = ('Select Contest (%s)> '):format(platform_display_name),
    fzf_opts = {
      ['--header'] = 'ctrl-r: refresh',
    },
    actions = {
      ['default'] = function(selected)
        if vim.tbl_isempty(selected) then
          return
        end

        local selected_name = selected[1]
        local contest = nil
        for _, c in ipairs(contests) do
          if c.display_name == selected_name then
            contest = c
            break
          end
        end

        if contest then
          local cp = require('cp')
          cp.handle_command({ fargs = { platform, contest.id } })
        end
      end,
      ['ctrl-r'] = function()
        local cache = require('cp.cache')
        cache.clear_contest_list(platform)
        contest_picker(platform, true)
      end,
    },
  })
end

function M.pick()
  local fzf = require('fzf-lua')
  local platforms = picker_utils.get_platforms()
  local entries = vim.tbl_map(function(platform)
    return platform.display_name
  end, platforms)

  return fzf.fzf_exec(entries, {
    prompt = 'Select Platform> ',
    actions = {
      ['default'] = function(selected)
        if vim.tbl_isempty(selected) then
          return
        end

        local selected_name = selected[1]
        local platform = nil
        for _, p in ipairs(platforms) do
          if p.display_name == selected_name then
            platform = p
            break
          end
        end

        if platform then
          contest_picker(platform.id)
        end
      end,
    },
  })
end

return M
