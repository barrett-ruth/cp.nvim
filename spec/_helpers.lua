local M = {}

function M.capture_system(map)
  local orig = vim.system
  local calls = {}
  vim.system = function(args, opts, on_exit)
    local key = type(args) == 'table' and table.concat(args, ' ') or tostring(args)
    calls[#calls + 1] = { args = args, opts = opts }
    local r = map[key] or {}
    local result = {
      code = r.code or 0,
      signal = r.signal or 0,
      stdout = r.stdout or '',
      stderr = r.stderr or '',
    }
    local obj = {
      result = function()
        return result
      end,
      wait = function()
        return result.code, result.signal
      end,
      kill = function() end,
      pid = 4242,
    }
    if on_exit then
      vim.schedule(function()
        on_exit(result.code, result.signal)
      end)
    end
    return obj
  end
  return function()
    vim.system = orig
    return calls
  end
end

return M
