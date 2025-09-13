if exists("b:current_syntax")
  finish
endif

syntax match cpOutputCode /^\[code\]:/
syntax match cpOutputTime /^\[time\]:/
syntax match cpOutputDebug /^\[debug\]:/
syntax match cpOutputMatchesTrue /^\[matches\]:\ze true$/
syntax match cpOutputMatchesFalse /^\[matches\]:\ze false$/

highlight default link cpOutputCode DiagnosticInfo
highlight default link cpOutputTime Comment
highlight default link cpOutputDebug Comment
highlight default link cpOutputMatchesTrue DiffAdd
highlight default link cpOutputMatchesFalse DiffDelete

let b:current_syntax = "cp"