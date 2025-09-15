# cp.nvim

neovim plugin for competitive programming.

https://private-user-images.githubusercontent.com/62671086/489116291-391976d1-c2f4-49e6-a79d-13ff05e9be86.mp4?jwt=eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJnaXRodWIuY29tIiwiYXVkIjoicmF3LmdpdGh1YnVzZXJjb250ZW50LmNvbSIsImtleSI6ImtleTUiLCJleHAiOjE3NTc3NDQ1ODEsIm5iZiI6MTc1Nzc0NDI4MSwicGF0aCI6Ii82MjY3MTA4Ni80ODkxMTYyOTEtMzkxOTc2ZDEtYzJmNC00OWU2LWE3OWQtMTNmZjA1ZTliZTg2Lm1wND9YLUFtei1BbGdvcml0aG09QVdTNC1ITUFDLVNIQTI1NiZYLUFtei1DcmVkZW50aWFsPUFLSUFWQ09EWUxTQTUzUFFLNFpBJTJGMjAyNTA5MTMlMkZ1cy1lYXN0LTElMkZzMyUyRmF3czRfcmVxdWVzdCZYLUFtei1EYXRlPTIwMjUwOTEzVDA2MTgwMVomWC1BbXotRXhwaXJlcz0zMDAmWC1BbXotU2lnbmF0dXJlPWI0Zjc0YmQzNWIzNGZkM2VjZjM3NGM0YmZmM2I3MmJkZGQ0YTczYjIxMTFiODc3MjQyMzY3ODc2ZTUxZDRkMzkmWC1BbXotU2lnbmVkSGVhZGVycz1ob3N0In0.MBK5q_Zxr0gWuzfjwmSbB7P7dtWrATrT5cDOosdPRuQ

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

- finer-tuned problem limits (i.e. per-problem codeforces time, memory)
- better highlighting
- test case management
- USACO support
- new video with functionality, notify discord members
- note that codeforces support is scuffed: https://codeforces.com/blog/entry/146423
- codeforces: use round number & api not the contest id
