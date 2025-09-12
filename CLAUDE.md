# CP.nvim Analysis & Modernization Plan

## Current Architecture Overview

### Plugin Structure
- **Main Logic**: `lua/cp/init.lua` (297 lines) - Core plugin functionality
- **Configuration**: `lua/cp/config.lua` (16 lines) - Contest settings and defaults
- **Snippets**: `lua/cp/snippets.lua` (21 lines) - LuaSnip integration
- **Entry Point**: `plugin/cp.lua` (7 lines) - Plugin initialization
- **Vim Integration**: `after/` directory with filetype detection, syntax highlighting, and buffer settings

### Current Build System (Make/Shell-Based)

#### Templates Structure
```
templates/
├── makefile                    # Build orchestration
├── compile_flags.txt          # Release flags: -O2, -DLOCAL
├── debug_flags.txt           # Debug flags: -g3, -fsanitize=address,undefined, -DLOCAL
├── .clang-format             # Code formatting rules (Google style)
├── scripts/
│   ├── run.sh               # Compilation + execution workflow
│   ├── debug.sh            # Debug compilation + execution
│   ├── scrape.sh           # Problem scraping orchestration
│   └── utils.sh            # Core build/execution utilities
├── scrapers/               # Python scrapers for each judge
│   ├── atcoder.py         # AtCoder problem scraping
│   ├── codeforces.py      # Codeforces problem scraping (with cloudscraper)
│   └── cses.py            # CSES problem scraping
└── io/                    # Input/output files directory
```

#### Build Workflow Analysis

**Compilation Process** (`utils.sh:compile_source`):
```bash
g++ @compile_flags.txt $flags "$src" -o "$bin" 2>"$output"
```

**Execution Process** (`utils.sh:execute_binary`):
- **Timeout**: 2-second hardcoded timeout using `timeout 2s`
- **Debug Mode**: LD_PRELOAD with AddressSanitizer when debugging
- **Output Processing**: 
  - Truncates to first 1000 lines
  - Appends metadata: `[code]`, `[time]`, `[debug]`, `[matches]`
  - Compares with `.expected` file if available
- **Signal Handling**: Maps exit codes to signal names (SIGSEGV, SIGFPE, etc.)

### Current Neovim Integration

#### Command System
- `:CP <contest>` - Setup contest environment
- `:CP <contest> <problem_id> [letter]` - Setup problem + scrape
- `:CP run` - Compile and execute current problem
- `:CP debug` - Compile with debug flags and execute
- `:CP diff` - Toggle diff mode between output and expected

#### Current vim.system Usage
```lua
-- Only used for async compilation in init.lua:148, 166
vim.system({ "make", "run", vim.fn.expand("%:t") }, {}, callback)
vim.system({ "make", "debug", vim.fn.expand("%:t") }, {}, callback)
```

#### Window Management
- **Current Layout**: Code editor | Output window + Input window (vsplit + split)
- **Diff Mode**: 
  - Uses `vim.cmd.diffthis()` and `vim.cmd.diffoff()`
  - Session saving with `mksession!` and restoration
  - Manual window arrangement with `vim.cmd.only()`, splits, and `wincmd`
  - **vim-zoom dependency**: Listed as optional for "better diff view" but not used in code

#### File Type Integration
- **Auto-detection**: `*/io/*.in` → `cpinput`, `*/io/*.out` → `cpoutput`
- **Buffer Settings**: Disables line numbers, signs, status column for I/O files
- **Syntax Highlighting**: Custom syntax for output metadata (`[code]`, `[time]`, etc.)

### Current Configuration System

#### Contest-Specific Settings
```lua
defaults = {
  contests = {
    atcoder = { cpp_version = 23 },
    codeforces = { cpp_version = 23 },
    cses = { cpp_version = 20 },
  },
  snippets = {},
}
```

#### File-Based Configuration Dependencies
- `compile_flags.txt` - Compiler flags for release builds
- `debug_flags.txt` - Debug-specific compiler flags
- `.clang-format` - Code formatting configuration
- **Missing**: `.clangd` file (referenced in makefile but doesn't exist)

---

## Proposed Modernization: Full Lua Migration

### 1. Replace Make/Shell System with vim.system

#### Benefits of Native Lua Implementation
- **Better Error Handling**: Lua error handling vs shell exit codes
- **Timeout Control**: `vim.system` supports timeout parameter directly
- **Streaming I/O**: Native stdin/stdout handling without temp files
- **Progress Reporting**: Real-time compilation/execution feedback
- **Cross-Platform**: Remove shell script dependencies

#### Proposed Build System
```lua
local function compile_cpp(src_path, output_path, flags, timeout_ms)
  local compile_cmd = { "g++", unpack(flags), src_path, "-o", output_path }
  return vim.system(compile_cmd, { timeout = timeout_ms or 10000 })
end

local function execute_with_timeout(binary_path, input_data, timeout_ms)
  return vim.system(
    { binary_path },
    {
      stdin = input_data,
      timeout = timeout_ms or 2000,
      stdout = true,
      stderr = true,
    }
  )
end
```

### 2. Configuration Migration to Pure Lua

#### Replace File-Based Config with Lua Tables
```lua
config = {
  contests = {
    atcoder = { 
      cpp_version = 23,
      compile_flags = { "-std=c++23", "-O2", "-DLOCAL", "-Wall", "-Wextra" },
      debug_flags = { "-std=c++23", "-g3", "-fsanitize=address,undefined", "-DLOCAL" },
      timeout_ms = 2000,
    },
    -- ... other contests
  },
  clangd_config = {
    CompileFlags = { Add = { "-std=c++23", "-DLOCAL" } },
    Diagnostics = { ClangTidy = { Add = { "readability-*" } } },
  },
  clang_format = {
    BasedOnStyle = "Google",
    AllowShortFunctionsOnASingleLine = false,
    -- ... other formatting options
  }
}
```

#### Dynamic File Generation
- Generate `.clangd` YAML from Lua config
- Generate `.clang-format` from Lua config
- Eliminate static template files

### 3. Enhanced Window Management (Remove vim-zoom Dependency)

#### Current Diff Implementation Issues
- Manual session management with temp files
- No proper view state restoration
- Hardcoded window arrangements

#### Proposed Native Window Management
```lua
local function save_window_state()
  return {
    layout = vim.fn.winrestcmd(),
    views = vim.tbl_map(function(win)
      return {
        winid = win,
        view = vim.fn.winsaveview(),
        bufnr = vim.api.nvim_win_get_buf(win)
      }
    end, vim.api.nvim_list_wins())
  }
end

local function restore_window_state(state)
  vim.cmd(state.layout)
  for _, view_state in ipairs(state.views) do
    if vim.api.nvim_win_is_valid(view_state.winid) then
      vim.api.nvim_win_call(view_state.winid, function()
        vim.fn.winrestview(view_state.view)
      end)
    end
  end
end
```

#### Improved Diff Mode
- Use `vim.diff()` API for programmatic diff generation
- Better window state management with `winsaveview`/`winrestview`
- Native zoom functionality without external dependency

### 4. Enhanced I/O and Timeout Management

#### Current Limitations
- Hardcoded 2-second timeout
- Shell-based timeout implementation
- Limited output processing

#### Proposed Improvements
```lua
local function execute_solution(config)
  local start_time = vim.loop.hrtime()
  
  local result = vim.system(
    { config.binary_path },
    {
      stdin = config.input_data,
      timeout = config.timeout_ms,
      stdout = true,
      stderr = true,
    }
  )
  
  local end_time = vim.loop.hrtime()
  local execution_time = (end_time - start_time) / 1000000 -- Convert to ms
  
  return {
    stdout = result.stdout,
    stderr = result.stderr,
    code = result.code,
    time_ms = execution_time,
    timed_out = result.code == 124,
  }
end
```

### 5. Integrated Problem Scraping

#### Current Python Integration
- Separate uv environment management
- Shell script orchestration for scraping
- External Python dependencies (requests, beautifulsoup4, cloudscraper)

#### Proposed Native Integration Options

**Option A: Keep Python, Improve Integration**
```lua
local function scrape_problem(contest, problem_id, problem_letter)
  local scraper_path = get_scraper_path(contest)
  local args = contest == "cses" and { problem_id } or { problem_id, problem_letter }
  
  return vim.system(
    { "uv", "run", scraper_path, unpack(args) },
    { cwd = plugin_path, timeout = 30000 }
  )
end
```

**Option B: Native Lua HTTP (Future)**
- Wait for Neovim native HTTP client
- Eliminate Python dependency entirely
- Pure Lua HTML parsing (challenging)

---

## Implementation Challenges & Considerations

### Technical Feasibility

#### ✅ **Definitely Possible**
- Replace makefile with vim.system calls
- Migrate configuration to pure Lua tables
- Implement native window state management
- Add configurable timeouts
- Remove vim-zoom dependency

#### ⚠️ **Requires Careful Implementation**
- **Signal Handling**: Shell scripts handle SIGSEGV, SIGFPE mapping - need Lua equivalent
- **AddressSanitizer Integration**: LD_PRELOAD handling in debug mode
- **Cross-Platform**: Shell scripts provide some cross-platform abstraction

#### 🤔 **Complex/Questionable**
- **Complete Python Elimination**: Would require native HTTP client + HTML parsing
- **Output Truncation Logic**: Currently truncates to 1000 lines efficiently in shell

### Migration Strategy

#### Phase 1: Core Build System
1. Replace `vim.system({ "make", ... })` with direct `vim.system({ "g++", ... })`
2. Migrate compile/debug flags from txt files to Lua config
3. Implement native timeout and execution management

#### Phase 2: Window Management
1. Implement native window state saving/restoration
2. Remove vim-zoom dependency mention
3. Enhance diff mode with better view management

#### Phase 3: Configuration Integration
1. Generate .clangd/.clang-format from Lua config
2. Consolidate all configuration in single config table
3. Add runtime configuration validation

#### Phase 4: Enhanced Features
1. Configurable timeouts per contest
2. Better error reporting and progress feedback
3. Enhanced output processing and metadata

### User Experience Impact

#### Advantages
- **Simpler Dependencies**: No external shell scripts or makefile
- **Better Error Messages**: Native Lua error handling
- **Configurable Timeouts**: Per-contest timeout settings
- **Improved Performance**: Direct system calls vs shell interpretation
- **Better Integration**: Native Neovim APIs throughout

#### Potential Concerns
- **Compatibility**: Users relying on current makefile system
- **Feature Parity**: Ensuring all current functionality is preserved
- **Debugging**: Shell scripts are easier to debug independently

---

## Recommendation

**Proceed with modernization** - The proposed changes align well with Neovim 0.9+ capabilities and would significantly improve the plugin's maintainability and user experience. The migration is technically feasible with the main complexity being in preserving exact feature parity during the transition.

**Priority Order**:
1. Build system migration (highest impact, lowest risk)
2. Window management improvements (removes external dependency)
3. Configuration consolidation (improves user experience)
4. Enhanced I/O and timeout management (adds new capabilities)

The plugin's current architecture is well-designed, making this modernization an enhancement rather than a rewrite.