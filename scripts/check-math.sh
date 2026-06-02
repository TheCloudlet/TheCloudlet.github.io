#!/bin/bash
# scripts/check-math.sh: Verify math rendering configuration.

CONTENT_DIR="content"
fail=0

log()  { printf "\n\033[1;34m==>\033[0m %s\n\n" "$*"; }
ok()   { printf "  \033[1;32m[OK]\033[0m  %s\n" "$*"; }
err()  { printf "  \033[1;31m[ERR]\033[0m %s\n" "$*"; fail=$((fail + 1)); }

log "Checking for math blocks without 'math = true' flag..."

# Find .md files with math delimiters
for md in $(find "$CONTENT_DIR" -name "*.md" | sort); do
    [[ "$md" == *"_index.md" ]] && continue

    # Check for \\( or \\[ or $$
    if grep -qF "\\(" "$md" || grep -qF "\\[" "$md" || grep -qF "$$" "$md"; then
        if ! grep -q "math = true" "$md"; then
            err "$md — contains math but missing 'math = true' in [extra]"
        else
            ok "$md"
        fi
    fi
done

log "Checking .org files for math but missing frontmatter..."

for org in $(find "$CONTENT_DIR" -name "*.org" | sort); do
    # Search for $ or \( or \[ in .org
    if grep -qF "$" "$org" || grep -qF "\(" "$org" || grep -qF "\[" "$org"; then
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
