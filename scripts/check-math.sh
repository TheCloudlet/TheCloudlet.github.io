#!/bin/bash
# scripts/check-math.sh: Verify math rendering configuration.

CONTENT_DIR="content"
fail=0

log()  { printf "\n\033[1;34m==>\033[0m %s\n\n" "$*"; }
ok()   { printf "  \033[1;32m[OK]\033[0m  %s\n" "$*"; }
err()  { printf "  \033[1;31m[ERR]\033[0m %s\n" "$*"; fail=$((fail + 1)); }

# ponytail: delimiter heuristic; use format parsers if prose creates false positives.
contains_math() {
    awk '
        /^```/ { in_block = !in_block; next }
        /^#\+BEGIN_(SRC|EXAMPLE)/ { in_block = 1; next }
        /^#\+END_(SRC|EXAMPLE)/ { in_block = 0; next }
        !in_block {
            line = $0
            gsub(/`[^`]*`/, "", line)
            gsub(/~[^~]*~/, "", line)
            if (index(line, "\\(") || index(line, "\\[") ||
                index(line, "$$") || line ~ /\$[^$]+\$/) {
                found = 1
            }
        }
        END { exit !found }
    ' "$1"
}

log "Checking for math blocks without 'math = true' flag..."

# Find .md files with math delimiters
for md in $(find "$CONTENT_DIR" -name "*.md" | sort); do
    [[ "$md" == *"_index.md" ]] && continue

    if contains_math "$md"; then
        if ! grep -q "math = true" "$md"; then
            err "$md — contains math but missing 'math = true' in [extra]"
        else
            ok "$md"
        fi
    fi
done

log "Checking .org files for math but missing frontmatter..."

for org in $(find "$CONTENT_DIR" -name "*.org" | sort); do
    if contains_math "$org"; then
        if ! grep -q "math . t" "$org"; then
            err "$org — contains math but missing ':extra '((math . t)...)'"
        else
            ok "$org"
        fi
    fi
done

echo ""
if [ "$fail" -eq 0 ]; then
    printf "\033[1;32mMath check passed.\033[0m\n"
else
    printf "\033[1;31m%d error(s) found in math configuration.\033[0m\n" "$fail"
    exit 1
fi
