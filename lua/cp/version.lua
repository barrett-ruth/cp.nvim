local M = {}

local utils = require('cp.utils')

local function get_git_version()
  local plugin_root = utils.get_plugin_path()

  local result = vim
    .system({ 'git', 'describe', '--tags', '--always', '--dirty' }, {
      cwd = plugin_root,
      text = true,
    })
    :wait()

  if result.code == 0 then
    return result.stdout:gsub('\n', '')
  else
    return 'unknown'
  end
end

local function parse_semver(version_string)
  local semver = version_string:match('^v?(%d+%.%d+%.%d+)')
  if semver then
    local major, minor, patch = semver:match('(%d+)%.(%d+)%.(%d+)')
    return {
      full = semver,
      major = tonumber(major),
      minor = tonumber(minor),
      patch = tonumber(patch),
    }
  end
  return nil
end

M.version = get_git_version()
M.semver = parse_semver(M.version)

return M
