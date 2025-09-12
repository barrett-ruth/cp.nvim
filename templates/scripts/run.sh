#!/bin/sh

. ./scripts/utils.sh

SRC="$1"
BASE=$(basename "$SRC" .cc)
INPUT="${BASE}.in"
OUTPUT="${BASE}.out"
RUN_BIN="${BASE}.run"

test -d build || mkdir -p build
test -d io || mkdir -p io

test -f "$INPUT" && test ! -f "io/$INPUT" && mv "$INPUT" "io/"
test -f "$OUTPUT" && test ! -f "io/$OUTPUT" && mv "$OUTPUT" "io/"

test -f "io/$INPUT" || touch "io/$INPUT"
test -f "io/$OUTPUT" || touch "io/$OUTPUT"

INPUT="io/$INPUT"
OUTPUT="io/$OUTPUT"
RUN_BIN="build/$RUN_BIN"

compile_source "$SRC" "$RUN_BIN" "$OUTPUT" ""
CODE=$?
test $CODE -gt 0 && exit $CODE

execute_binary "$RUN_BIN" "$INPUT" "$OUTPUT"
exit $?
