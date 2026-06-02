#!/bin/sh
# build-org.sh: Lint org files, export to md, then validate md output.
#
# Usage:
#   ./scripts/build-org.sh           # full pipeline (skip drafts)
#   ./scripts/build-org.sh --drafts  # full pipeline (include drafts)
#   ./scripts/build-org.sh --lint    # lint only
#   ./scripts/build-org.sh --export  # export only (skip drafts)
#   ./scripts/build-org.sh --check   # check md only

CONTENT_DIR="content"
EMACS="${EMACS:-emacs}"
fail=0
lint_fail=0
INCLUDE_DRAFTS=""

# parse flags
for arg in "$@"; do
    case "$arg" in
        --drafts) INCLUDE_DRAFTS=1 ;;
    esac
done

# ─── helpers ──────────────────────────────────────────────────────────────────

log()  { printf "\n\033[1;34m==>\033[0m %s\n\n" "$*"; }
ok()   { printf "  \033[1;32m[OK]\033[0m  %s\n" "$*"; }
err()      { printf "  \033[1;31m[ERR]\033[0m %s\n" "$*"; fail=$((fail + 1)); }
lint_err() { printf "  \033[1;31m[ERR]\033[0m %s\n" "$*"; fail=$((fail + 1)); lint_fail=$((lint_fail + 1)); }
warn() { printf "\033[1;33mWRN\033[0m  %s\n" "$*"; }

# ─── Step 0: Lint .org files ──────────────────────────────────────────────────

lint_org() {
    log "Step 1: Linting .org files"

    for org in $(find "$CONTENT_DIR" -name "*.org" | sort); do

        # skip draft files entirely
        grep -q "^#+ZOLA_DRAFT: true" "$org" 2>/dev/null && continue

        # Bare image links (no alt text → ox-zola emits Hugo figure shortcode)
        bare=$(grep -n "^\[\[/images/[^]]*\]\]$" "$org" 2>/dev/null || true)
        if [ -n "$bare" ]; then
            lint_err "$org — bare image link (add alt text: [[/path/img.png][alt]])"
            echo "$bare" | sed 's/^/     /'
        fi

        # @/ links (Org cannot resolve them — use [[file:other.org][text]])
        at=$(grep -n "\[\[@/" "$org" 2>/dev/null || true)
        if [ -n "$at" ]; then
            lint_err "$org — @/ link found (use [[file:other.org][text]] instead)"
            echo "$at" | sed 's/^/     /'
        fi
# Check for TITLE and DATE
actual_title=$(grep "^#+TITLE:" "$org" 2>/dev/null | head -1 | sed 's/^#+TITLE: *//')
if [ -z "$actual_title" ]; then
    lint_err "$org — missing #+TITLE:"
fi
actual_date=$(grep "^#+DATE:" "$org" 2>/dev/null | head -1 | sed 's/^#+DATE: *//')
if [ -z "$actual_date" ]; then
    lint_err "$org — missing #+DATE:"
fi

        # Check #+ZOLA_SECTION matches the file's directory (and is NOT "posts")
        if [ "$org" != "$CONTENT_DIR/about.org" ]; then
            expected_section=$(dirname "$org" | sed "s|^$CONTENT_DIR/||")
            actual_section=$(grep "^#+ZOLA_SECTION:" "$org" 2>/dev/null | head -1 | sed 's/^#+ZOLA_SECTION: *//')
            
            if [ -z "$actual_section" ]; then
                lint_err "$org — missing #+ZOLA_SECTION: (expected: $expected_section)"
            elif [ "$actual_section" = "posts" ]; then
                lint_err "$org — ZOLA_SECTION cannot be 'posts'. Please choose a real category."
            elif [ "$actual_section" != "$expected_section" ]; then
                lint_err "$org — ZOLA_SECTION mismatch (got: '$actual_section', expected: '$expected_section')"
            fi
        fi

# Skip draft content checks if it's a draft, but keep structural checks above
grep -q "^#+ZOLA_DRAFT: true" "$org" 2>/dev/null && continue

# Check for legacy TAXONOMIES keywords
if grep -q "ZOLA_TAXONOMIES_" "$org"; then
    lint_err "$org — legacy ZOLA_TAXONOMIES_ keyword (use ZOLA_TAGS/ZOLA_CATEGORIES)"
fi

# Check for unsupported EXTRA keywords
if grep -q "ZOLA_EXTRA_" "$org"; then
    lint_err "$org — unsupported ZOLA_EXTRA_ keyword (use ZOLA_CUSTOM_FRONT_MATTER)"
fi

        bad_links=$(grep -n "\[\[.*\.md\]" "$org" 2>/dev/null | grep -v "@/" || true)
        if [ -n "$bad_links" ]; then
            lint_err "$org — .md cross-reference link (use [[file:other.org][text]] instead)"
            echo "$bad_links" | sed 's/^/     /'
        fi

        # Indented headings (common copy-paste mistake)
        # Use awk to skip lines inside BEGIN_SRC / BEGIN_EXAMPLE blocks
        bad_head=$(awk '
            /^#\+BEGIN_(SRC|EXAMPLE|QUOTE|VERSE)/ { in_block=1 }
            /^#\+END_(SRC|EXAMPLE|QUOTE|VERSE)/   { in_block=0; next }
            !in_block && /^ +\*/ { print NR": "$0 }
        ' "$org" 2>/dev/null || true)
        if [ -n "$bad_head" ]; then
            lint_err "$org — indented heading(s)"
            echo "$bad_head" | sed 's/^/     /'
        fi

    done

    if [ "$lint_fail" -eq 0 ]; then
        printf "  \033[1;32m[OK]\033[0m  No lint errors found.\n"
    fi
}

# ─── Step 1: Export all .org → .md via Emacs batch ───────────────────────────

export_org() {
    log "Step 2: Exporting .org → .md"

    ORG_EXPORT_DRAFTS="$INCLUDE_DRAFTS" "$EMACS" --batch --load scripts/org-export.el \
        2>&1 | grep -v "^Loading\|^Wrote\|^org-babel\|\[ox-hugo\]\|\[ox-zola\]"
}

# ─── Step 2: Validate generated .md files ────────────────────────────────────

check_md() {
    log "Step 3: Checking generated .md files"

    # --- Integrity Check: No orphaned markdown or 'posts' directory ---
    for md in $(find "$CONTENT_DIR" -name "*.md" | sort); do
        [[ "$md" == *"_index.md" ]] && continue

        # Explicitly forbid 'posts' directory
        if [[ "$md" == *"/posts/"* ]]; then
            err "$md — forbidden directory 'posts'. All content must be categorized."
            continue
        fi

        org="${md%.md}.org"
        if [ ! -f "$org" ]; then
            err "$md — orphaned markdown (missing .org source)"
        fi
    done

    for org in $(find "$CONTENT_DIR" -name "*.org" | sort); do
        grep -q "^#+ZOLA_DRAFT: true" "$org" 2>/dev/null && continue

        md="${org%.org}.md"

        # md must exist
        if [ ! -f "$md" ]; then
            err "$md — not found (export failed?)"
            continue
        fi

        # md must be newer than org
        if [ "$org" -nt "$md" ]; then
            err "$md — stale (.org is newer, export may have failed)"
        else
            ok "$md"
        fi

        # No Hugo figure shortcodes
        figures=$(grep -n "{{ figure(" "$md" 2>/dev/null || true)
        if [ -n "$figures" ]; then
            err "$md — Hugo figure shortcode (fix bare image link in .org)"
            echo "$figures" | sed 's/^/     /'
        fi

        # No leftover @/ links as raw text
        at=$(grep -n "\[\[@/" "$md" 2>/dev/null || true)
        if [ -n "$at" ]; then
            err "$md — raw @/ link in output"
            echo "$at" | sed 's/^/     /'
        fi

    done
}

# ─── Main ─────────────────────────────────────────────────────────────────────

case "${1:-all}" in
    --lint)   lint_org ;;
    --export) export_org ;;
    --check)  check_md ;;
    all|*)
        lint_org
        if [ "$lint_fail" -gt 0 ]; then
            printf "\033[1;31m\n%d lint error(s) — fix before exporting.\033[0m\n" "$lint_fail"
            exit 1
        fi
        export_org
        check_md
        ;;
esac

echo ""
if [ "$fail" -eq 0 ]; then
    printf "\033[1;32mAll checks passed.\033[0m\n"
else
    printf "\033[1;31m%d error(s) found.\033[0m\n" "$fail"
    exit 1
fi
