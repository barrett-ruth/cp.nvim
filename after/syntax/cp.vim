if exists("b:current_syntax")
  finish
endif

syntax match cpOutputCode /^\[code\]:/
syntax match cpOutputTime /^\[time\]:/
syntax match cpOutputDebug /^\[debug\]:/
syntax match cpOutputOkTrue /^\[ok\]:\ze true$/
syntax match cpOutputOkFalse /^\[ok\]:\ze false$/

highlight default link cpOutputCode DiagnosticInfo
highlight default link cpOutputTime Comment
highlight default link cpOutputDebug Comment
highlight default link cpOutputOkTrue DiffAdd
highlight default link cpOutputOkFalse DiffDelete

let b:current_syntax = "cp"
