#!/bin/sh

execute_binary() {
  binary="$1"
  input="$2"
  output="$3"
  is_debug="$4"

  start=$(date '+%s.%N')
  if [ -n "$is_debug" ]; then
    asan="$(ldconfig -p | grep libasan.so | head -n1 | awk '{print $4}')"
    LD_PRELOAD="$asan" timeout 2s ./"$binary" <"$input" >"$output" 2>&1
  else
    timeout 2s ./"$binary" <"$input" >"$output" 2>&1
  fi
  CODE=$?
  end=$(date '+%s.%N')
  truncate -s "$(head -n 1000 "$output" | wc -c)" "$output"

  if [ $CODE -ge 124 ]; then
    MSG=''
    case $CODE in
    124) MSG='TIMEOUT' ;;
    128) MSG='SIGILL' ;;
    130) MSG='SIGABRT' ;;
    131) MSG='SIGBUS' ;;
    136) MSG='SIGFPE' ;;
    135) MSG='SIGSEGV' ;;
    137) MSG='SIGPIPE' ;;
    139) MSG='SIGTERM' ;;
    esac
    [ $CODE -ne 124 ] && sed -i '$d' "$output"
    test -n "$MSG" && printf '\n[code]: %s (%s)' "$CODE" "$MSG" >>"$output"
  else
    printf '\n[code]: %s' "$CODE" >>"$output"
  fi

  printf '\n[time]: %s ms' "$(awk "BEGIN {print ($end - $start) * 1000}")" >>$output
  test -n "$is_debug" && is_debug_string=true || is_debug_string=false
  printf '\n[debug]: %s' "$is_debug_string" >>$output
  
  expected_file="${output%.out}.expected"
  if [ -f "$expected_file" ] && [ $CODE -eq 0 ]; then
    awk '/^\[[^]]*\]:/ {exit} {print}' "$output" > /tmp/program_output
    if cmp -s /tmp/program_output "$expected_file"; then
      printf '\n[matches]: true' >>"$output"
    else
      printf '\n[matches]: false' >>"$output"
    fi
    rm -f /tmp/program_output
  fi
  
  return $CODE
}

compile_source() {
  src="$1"
  bin="$2"
  output="$3"
  flags="$4"

  test -f "$bin" && rm "$bin" || true
  g++ @compile_flags.txt $flags "$src" -o "$bin" 2>"$output"
  CODE=$?

  if [ $CODE -gt 0 ]; then
    printf '\n[code]: %s' "$CODE" >>"$output"
    return $CODE
  else
    echo '' >"$output"
    return 0
  fi
}
