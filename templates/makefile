.PHONY: run debug clean setup init scrape

VERSION ?= 20

SRC = $(word 2,$(MAKECMDGOALS))

.SILENT:

run:
	sh scripts/run.sh $(SRC)

debug:
	sh scripts/debug.sh $(SRC)

clean:
	rm -rf build/*

setup:
	test -d build || mkdir -p build
	test -d io || mkdir -p io
	test -f compile_flags.txt && echo -std=c++$(VERSION) >>compile_flags.txt

init:
	make setup

scrape:
	sh scripts/scrape.sh $(word 2,$(MAKECMDGOALS)) $(word 3,$(MAKECMDGOALS)) $(word 4,$(MAKECMDGOALS))

%:
	@:
