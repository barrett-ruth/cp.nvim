#!/bin/sh

. ./scripts/utils.sh

SRC="$1"
BASE=$(basename "$SRC" .cc)
INPUT="${BASE}.in"
OUTPUT="${BASE}.out"
DBG_BIN="${BASE}.debug"

test -d build || mkdir -p build
test -d io || mkdir -p io

test -f "$INPUT" && test ! -f "io/$INPUT" && mv "$INPUT" "io/"
test -f "$OUTPUT" && test ! -f "io/$OUTPUT" && mv "$OUTPUT" "io/"

test -f "io/$INPUT" || touch "io/$INPUT"
test -f "io/$OUTPUT" || touch "io/$OUTPUT"

INPUT="io/$INPUT"
OUTPUT="io/$OUTPUT"
DBG_BIN="build/$DBG_BIN"

compile_source "$SRC" "$DBG_BIN" "$OUTPUT" @debug_flags.txt
CODE=$?
test $CODE -gt 0 && exit $CODE

execute_binary "$DBG_BIN" "$INPUT" "$OUTPUT" true
exit $?
