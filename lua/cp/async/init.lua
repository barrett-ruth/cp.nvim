local M = {}

local active_operation = nil

function M.start_contest_operation(operation_name)
  if active_operation then
    error(
      ("Contest operation '%s' already active, cannot start '%s'"):format(
        active_operation,
        operation_name
      )
    )
  end
  active_operation = operation_name
end

function M.finish_contest_operation()
  active_operation = nil
end

function M.get_active_operation()
  return active_operation
end

return M
