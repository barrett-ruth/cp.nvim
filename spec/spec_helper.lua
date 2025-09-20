local M = {}

function M.setup()
  package.loaded['cp.log'] = {
    log = function() end,
    set_config = function() end,
  }
end

function M.teardown()
  package.loaded['cp.log'] = nil
end

return M
