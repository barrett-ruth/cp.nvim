local picker_utils = require('cp.pickers')

local function contest_picker(platform)
  local constants = require('cp.constants')
  local platform_display_name = constants.PLATFORM_DISPLAY_NAMES[platform] or platform
  local fzf = require('fzf-lua')
  local contests = picker_utils.get_contests_for_platform(platform)

  if #contests == 0 then
    vim.notify(
      ('No contests found for platform: %s'):format(platform_display_name),
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
        if not selected or #selected == 0 then
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
          problem_picker(platform, contest.id)
        end
      end,
      ['ctrl-r'] = function()
        local cache = require('cp.cache')
        cache.clear_contest_list(platform)
        contest_picker(platform)
      end,
    },
  })
end

local function problem_picker(platform, contest_id)
  local constants = require('cp.constants')
  local platform_display_name = constants.PLATFORM_DISPLAY_NAMES[platform] or platform
  local fzf = require('fzf-lua')
  local problems = picker_utils.get_problems_for_contest(platform, contest_id)

  if #problems == 0 then
    vim.notify(
      ("Contest %s %s hasn't started yet or has no available problems"):format(
        platform_display_name,
        contest_id
      ),
      vim.log.levels.WARN
    )
    contest_picker(platform)
    return
  end

  local entries = vim.tbl_map(function(problem)
    return problem.display_name
  end, problems)

  return fzf.fzf_exec(entries, {
    prompt = ('Select Problem (%s %s)> '):format(platform_display_name, contest_id),
    actions = {
      ['default'] = function(selected)
        if not selected or #selected == 0 then
          return
        end

        local selected_name = selected[1]
        local problem = nil
        for _, p in ipairs(problems) do
          if p.display_name == selected_name then
            problem = p
            break
          end
        end

        if problem then
          local cp = require('cp')
          cp.handle_command({ fargs = { platform, contest_id, problem.id } })
        end
      end,
    },
  })
end

local function platform_picker()
  local fzf = require('fzf-lua')
  local platforms = picker_utils.get_platforms()
  local entries = vim.tbl_map(function(platform)
    return platform.display_name
  end, platforms)

  return fzf.fzf_exec(entries, {
    prompt = 'Select Platform> ',
    actions = {
      ['default'] = function(selected)
        if not selected or #selected == 0 then
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

return {
  platform_picker = platform_picker,
}
