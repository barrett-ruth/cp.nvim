#!/bin/sh

CONTEST="$1"
PROBLEM="$2"
PROBLEM_LETTER="$3"

if [ -z "$CONTEST" ] ||  [ -z "$PROBLEM" ]; then
    echo "Usage: make scrape <contest> <problem_id> [problem_letter]"
    echo "Available contests: cses, atcoder, codeforces"
    echo "Examples:"
    echo "  make scrape cses 1068"
    echo "  make scrape atcoder abc042 a"
    echo "  make scrape codeforces 1234 A"
    exit
fi

test -d io && true || mkdir -p io
TMPFILE=$(mktemp)
ORIGDIR=$(pwd)

case "$CONTEST" in
    cses)
        cd "$(dirname "$0")/../.." && uv run scrapers/cses.py "$PROBLEM" > "$TMPFILE"
        if [ $? -eq 0 ]; then
            cd "$ORIGDIR"
            awk '/^---INPUT---$/ {getline; while ($0 != "---OUTPUT---") {print; getline}} END {}' "$TMPFILE" > "io/$PROBLEM.in"
            awk '/^---OUTPUT---$/ {getline; while ($0 != "---END---") {print; getline}} END {}' "$TMPFILE" > "io/$PROBLEM.expected"
            echo "Scraped problem $PROBLEM to io/$PROBLEM.in and io/$PROBLEM.expected"
        else
            echo "Failed to scrape problem $PROBLEM"
            cat "$TMPFILE"
            rm "$TMPFILE"
            exit
        fi
        ;;
    atcoder)
        if [ -z "$PROBLEM_LETTER" ]; then
            echo "AtCoder requires problem letter (e.g., make scrape atcoder abc042 a)"
            rm "$TMPFILE"
            exit
        fi
        FULL_PROBLEM_ID="${PROBLEM}${PROBLEM_LETTER}"
        cd "$(dirname "$0")/../.." && uv run scrapers/atcoder.py "$PROBLEM" "$PROBLEM_LETTER" > "$TMPFILE"
        if [ $? -eq 0 ]; then
            cd "$ORIGDIR"
            awk '/^---INPUT---$/ {getline; while ($0 != "---OUTPUT---") {print; getline}} END {}' "$TMPFILE" > "io/$FULL_PROBLEM_ID.in"
            awk '/^---OUTPUT---$/ {getline; while ($0 != "---END---") {print; getline}} END {}' "$TMPFILE" > "io/$FULL_PROBLEM_ID.expected"
            echo "Scraped problem $FULL_PROBLEM_ID to io/$FULL_PROBLEM_ID.in and io/$FULL_PROBLEM_ID.expected"
        else
            echo "Failed to scrape problem $FULL_PROBLEM_ID"
            cat "$TMPFILE"
            rm "$TMPFILE"
            exit
        fi
        ;;
    codeforces)
        if [ -z "$PROBLEM_LETTER" ]; then
            echo "Codeforces requires problem letter (e.g., make scrape codeforces 1234 A)"
            rm "$TMPFILE"
            exit
        fi
        FULL_PROBLEM_ID="${PROBLEM}${PROBLEM_LETTER}"
        cd "$(dirname "$0")/../.." && uv run scrapers/codeforces.py "$PROBLEM" "$PROBLEM_LETTER" > "$TMPFILE"
        if [ $? -eq 0 ]; then
            cd "$ORIGDIR"
            awk '/^---INPUT---$/ {getline; while ($0 != "---OUTPUT---") {print; getline}} END {}' "$TMPFILE" > "io/$FULL_PROBLEM_ID.in"
            awk '/^---OUTPUT---$/ {getline; while ($0 != "---END---") {print; getline}} END {}' "$TMPFILE" > "io/$FULL_PROBLEM_ID.expected"
            echo "Scraped problem $FULL_PROBLEM_ID to io/$FULL_PROBLEM_ID.in and io/$FULL_PROBLEM_ID.expected"
        else
            echo "Failed to scrape problem $FULL_PROBLEM_ID"
            echo "You can manually add test cases to io/$FULL_PROBLEM_ID.in and io/$FULL_PROBLEM_ID.expected"
            cat "$TMPFILE"
            rm "$TMPFILE"
            exit
        fi
        ;;
    *)
        echo "Unknown contest type: $CONTEST"
        echo "Available contests: cses, atcoder, codeforces"
        rm "$TMPFILE"
        exit
        ;;
esac

rm "$TMPFILE"
