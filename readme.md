# cp.nvim

neovim plugin for competitive programming.

> NOTE: sample test data from [codeforces](https://codeforces.com) is scraped via [cloudscraper](https://github.com/VeNoMouS/cloudscraper).
> Use at your own risk.

## Features

- Support for multiple online judges (AtCoder, Codeforces, CSES)
- Automatic problem scraping and test case management
- Integrated build, run, and debug commands
- Diff mode for comparing output with expected results
- LuaSnip integration for contest-specific snippets

## Requirements

- Neovim 0.9+
- `make`
-  [uv](https://docs.astral.sh/uv/): problem scraping (optional)
- [LuaSnip](https://github.com/L3MON4D3/LuaSnip): contest-specific snippets (optional)

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
    "barrett-ruth/cp.nvim",
    cmd = "CP",
    dependencies = {
        "L3MON4D3/LuaSnip",
    }
}
```

## Documentation

```vim
:help cp.nvim
```

## TODO

- remove vim-zoom dependency
- vimdocs
- example video
- more flexible setup (more of a question of philosophy)
- USACO support
