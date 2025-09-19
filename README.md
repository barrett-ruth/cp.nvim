# cp.nvim

neovim plugin for competitive programming.

https://github.com/user-attachments/assets/cb142535-fba0-4280-8f11-66ad1ca50ca9

[video config](https://github.com/barrett-ruth/dots/blob/main/nvim/lua/plugins/cp.lua)

> Sample test data from [codeforces](https://codeforces.com) is scraped via [cloudscraper](https://github.com/VeNoMouS/cloudscraper). Use at your own risk.

## Features

- Support for multiple online judges ([AtCoder](https://atcoder.jp/), [Codeforces](https://codeforces.com/), [CSES](https://cses.fi))
- Multi-language support (C++, Python)
- Automatic problem scraping and test case management
- Integrated build, run, and debug commands
- Enhanced test viewer with individual test case management
- LuaSnip integration for contest-specific snippets

## Requirements

- Neovim 0.10.0+
- [uv](https://docs.astral.sh/uv/): problem scraping (optional)
- [LuaSnip](https://github.com/L3MON4D3/LuaSnip): contest-specific snippets (optional)

## Documentation

```vim
:help cp.nvim
```

## Philosophy

This plugin is highly tuned to my workflow and may not fit for you. Personally,
I believe there are two aspects of a cp workflow:

- local work (i.e. coding, running test cases)
- site work (i.e. problem reading, submitting)

Namely, I do not like the idea of submitting problems locally - the experience
will never quite offer what the remote does. Therefore, cp.nvim works as
follows:

1. Find a problem

- Browse the remote and find it
- Read it on the remote

2. Set up your local environment with `:CP ...`

- test cases and expected output automatically scraped
- templates automatically configured

3. Solve the problem locally

- easy to run/debug
- easy to diff actual vs. expected output

4. Submit the problem (on the remote!)


## Similar Projects

- [competitest.nvim](https://github.com/xeluxee/competitest.nvim)
- [assistant.nvim](https://github.com/A7Lavinraj/assistant.nvim)

## TODO

- fzf/telescope integration (whichever available)
- autocomplete with --lang and --debug
- finer-tuned problem limits (i.e. per-problem codeforces time, memory)
- notify discord members
