local M = {}

local state = {
  platform = '',
  contest_id = '',
  problem_id = nil,
  test_cases = nil,
  run_panel_active = false,
  saved_session = nil,
}

function M.get_platform()
  return state.platform
end

function M.set_platform(platform)
  state.platform = platform
end

function M.get_contest_id()
  return state.contest_id
end

function M.set_contest_id(contest_id)
  state.contest_id = contest_id
end

function M.get_problem_id()
  return state.problem_id
end

function M.set_problem_id(problem_id)
  state.problem_id = problem_id
end

function M.get_test_cases()
  return state.test_cases
end

function M.set_test_cases(test_cases)
  state.test_cases = test_cases
end

function M.is_run_panel_active()
  return state.run_panel_active
end

function M.set_run_panel_active(active)
  state.run_panel_active = active
end

function M.get_saved_session()
  return state.saved_session
end

function M.set_saved_session(session)
  state.saved_session = session
end

function M.get_context()
  return {
    platform = state.platform,
    contest_id = state.contest_id,
    problem_id = state.problem_id,
  }
end

function M.has_context()
  return state.platform ~= '' and state.contest_id ~= ''
end

function M.reset()
  state.platform = ''
  state.contest_id = ''
  state.problem_id = nil
  state.test_cases = nil
  state.run_panel_active = false
  state.saved_session = nil
end

return M
