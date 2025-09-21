local finders = require('telescope.finders')
local pickers = require('telescope.pickers')
local conf = require('telescope.config').values
local action_state = require('telescope.actions.state')
local actions = require('telescope.actions')

local picker_utils = require('cp.pickers')

local function problem_picker(opts, platform, contest_id)
  local constants = require('cp.constants')
  local platform_display_name = constants.PLATFORM_DISPLAY_NAMES[platform] or platform
  local problems = picker_utils.get_problems_for_contest(platform, contest_id)

  if #problems == 0 then
    vim.notify(
      ('No problems found for contest: %s %s'):format(platform_display_name, contest_id),
      vim.log.levels.WARN
    )
    return
  end

  pickers
    .new(opts, {
      prompt_title = ('Select Problem (%s %s)'):format(platform_display_name, contest_id),
      finder = finders.new_table({
        results = problems,
        entry_maker = function(entry)
          return {
            value = entry,
            display = entry.display_name,
            ordinal = entry.display_name,
          }
        end,
      }),
      sorter = conf.generic_sorter(opts),
      attach_mappings = function(prompt_bufnr)
        actions.select_default:replace(function()
          local selection = action_state.get_selected_entry()
          actions.close(prompt_bufnr)

          if selection then
            picker_utils.setup_problem(platform, contest_id, selection.value.id)
          end
        end)
        return true
      end,
    })
    :find()
end

local function contest_picker(opts, platform)
  local constants = require('cp.constants')
  local platform_display_name = constants.PLATFORM_DISPLAY_NAMES[platform] or platform
  local contests = picker_utils.get_contests_for_platform(platform)

  if #contests == 0 then
    vim.notify(
      ('No contests found for platform: %s'):format(platform_display_name),
      vim.log.levels.WARN
    )
    return
  end

  pickers
    .new(opts, {
      prompt_title = ('Select Contest (%s)'):format(platform_display_name),
      finder = finders.new_table({
        results = contests,
        entry_maker = function(entry)
          return {
            value = entry,
            display = entry.display_name,
            ordinal = entry.display_name,
          }
        end,
      }),
      sorter = conf.generic_sorter(opts),
      attach_mappings = function(prompt_bufnr)
        actions.select_default:replace(function()
          local selection = action_state.get_selected_entry()
          actions.close(prompt_bufnr)

          if selection then
            problem_picker(opts, platform, selection.value.id)
          end
        end)
        return true
      end,
    })
    :find()
end

local function platform_picker(opts)
  opts = opts or {}

  local platforms = picker_utils.get_platforms()

  pickers
    .new(opts, {
      prompt_title = 'Select Platform',
      finder = finders.new_table({
        results = platforms,
        entry_maker = function(entry)
          return {
            value = entry,
            display = entry.display_name,
            ordinal = entry.display_name,
          }
        end,
      }),
      sorter = conf.generic_sorter(opts),
      attach_mappings = function(prompt_bufnr)
        actions.select_default:replace(function()
          local selection = action_state.get_selected_entry()
          actions.close(prompt_bufnr)

          if selection then
            contest_picker(opts, selection.value.id)
          end
        end)
        return true
      end,
    })
    :find()
end

return {
  platform_picker = platform_picker,
}
