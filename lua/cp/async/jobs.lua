local M = {}

local current_jobs = {}

function M.start_job(job_id, args, opts, callback)
  opts = opts or {}

  if current_jobs[job_id] then
    current_jobs[job_id]:kill(9)
    current_jobs[job_id] = nil
  end

  local job = vim.system(args, opts, function(result)
    current_jobs[job_id] = nil
    callback(result)
  end)

  current_jobs[job_id] = job
  return job
end

function M.kill_job(job_id)
  if current_jobs[job_id] then
    current_jobs[job_id]:kill(9)
    current_jobs[job_id] = nil
  end
end

function M.kill_all_jobs()
  for _, job in pairs(current_jobs) do
    job:kill(9)
  end
  current_jobs = {}
end

function M.get_active_jobs()
  local active = {}
  for job_id, _ in pairs(current_jobs) do
    table.insert(active, job_id)
  end
  return active
end

return M
