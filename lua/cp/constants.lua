local M = {}

M.PLATFORMS = { 'atcoder', 'codeforces', 'cses' }
M.ACTIONS = { 'run', 'panel', 'debug', 'next', 'prev', 'pick', 'cache', 'interact' }

M.PLATFORM_DISPLAY_NAMES = {
  atcoder = 'AtCoder',
  codeforces = 'CodeForces',
  cses = 'CSES',
}

M.CPP = 'cpp'
M.PYTHON = 'python'

---@type table<string, string>
M.filetype_to_language = {
  python = M.PYTHON,
  cpp = M.CPP,
}

---@type table<string, string>
M.canonical_filetypes = {
  [M.CPP] = 'cpp',
  [M.PYTHON] = 'python',
}

---@type table<string, string>
M.canonical_filetype_to_extension = {
  [M.CPP] = 'cc',
  [M.PYTHON] = 'py',
}

---@type table<number, string>
M.signal_codes = {
  [128] = 'SIGILL',
  [130] = 'SIGINT',
  [131] = 'SIGQUIT',
  [132] = 'SIGILL',
  [133] = 'SIGTRAP',
  [134] = 'SIGABRT',
  [135] = 'SIGBUS',
  [136] = 'SIGFPE',
  [137] = 'SIGKILL',
  [138] = 'SIGUSR1',
  [139] = 'SIGSEGV',
  [140] = 'SIGUSR2',
  [141] = 'SIGPIPE',
  [142] = 'SIGALRM',
  [143] = 'SIGTERM',
}

return M
