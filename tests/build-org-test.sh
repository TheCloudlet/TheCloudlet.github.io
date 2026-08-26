#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT HUP INT TERM

mkdir -p "$fixture/content" "$fixture/scripts"
cp "$repo_dir/scripts/build-org.sh" "$fixture/scripts/build-org.sh"
cp "$repo_dir/scripts/org-export.el" "$fixture/scripts/org-export.el"
touch "$fixture/content/_index.md"

if ! output=$(cd "$fixture" && sh scripts/build-org.sh --check 2>&1); then
    printf '%s\n' "$output" >&2
    exit 1
fi

printf 'ok - check accepts Zola index files under POSIX sh\n'

status=0
output=$(cd "$fixture" && EMACS=false sh scripts/build-org.sh check 2>&1) || status=$?
if [ "$status" -ne 2 ]; then
    printf 'expected positional mode usage error, got exit %s:\n%s\n' "$status" "$output" >&2
    exit 1
fi

printf 'ok - positional modes are rejected\n'

status=0
output=$(cd "$fixture" && sh scripts/build-org.sh --help check 2>&1) || status=$?
if [ "$status" -ne 2 ]; then
    printf 'expected help plus positional mode usage error, got exit %s:\n%s\n' "$status" "$output" >&2
    exit 1
fi

printf 'ok - help does not mask invalid arguments\n'

status=0
output=$(cd "$fixture" && sh scripts/build-org.sh --lint --check 2>&1) || status=$?
if [ "$status" -ne 2 ]; then
    printf 'expected conflicting mode usage error, got exit %s:\n%s\n' "$status" "$output" >&2
    exit 1
fi

printf 'ok - conflicting modes are rejected\n'

if output=$(cd "$fixture" && EMACS=false sh scripts/build-org.sh --export 2>&1); then
    printf 'expected export failure, got success:\n%s\n' "$output" >&2
    exit 1
fi

printf 'ok - export propagates Emacs failures\n'

mkdir -p "$fixture/home/.config/emacs/.local/straight/build-30.2/fake"
cat > "$fixture/home/.config/emacs/.local/straight/build-30.2/fake/ox-hugo.el" <<'EOF'
(provide 'ox-hugo)
EOF
cat > "$fixture/home/.config/emacs/.local/straight/build-30.2/fake/ox-zola.el" <<'EOF'
(defun ox-zola-export-to-md ()
  (error "forced export failure"))
(provide 'ox-zola)
EOF
touch "$fixture/content/export-error.org"

if output=$(cd "$fixture" && HOME="$fixture/home" sh scripts/build-org.sh --export 2>&1); then
    printf 'expected per-file export failure, got success:\n%s\n' "$output" >&2
    exit 1
fi
case "$output" in
    *"forced export failure"*) ;;
    *)
        printf 'expected forced per-file failure, got:\n%s\n' "$output" >&2
        exit 1
        ;;
esac
rm "$fixture/content/export-error.org"

printf 'ok - export fails when any file fails\n'

cat > "$fixture/content/draft.org" <<'EOF'
#+ZOLA_DRAFT: true
EOF

if output=$(cd "$fixture" && sh scripts/build-org.sh --lint --drafts 2>&1); then
    printf 'expected draft lint failure, got success:\n%s\n' "$output" >&2
    exit 1
fi

printf 'ok - lint includes drafts when requested\n'

if output=$(cd "$fixture" && sh scripts/build-org.sh --check --drafts 2>&1); then
    printf 'expected missing draft output failure, got success:\n%s\n' "$output" >&2
    exit 1
fi

printf 'ok - check includes drafts when requested\n'

touch "$fixture/content/stale.org" "$fixture/content/stale.md"
touch -t 202001010000 "$fixture/content/stale.md"
touch -t 202001020000 "$fixture/content/stale.org"

if output=$(cd "$fixture" && sh scripts/build-org.sh --check 2>&1); then
    printf 'expected stale output failure, got success:\n%s\n' "$output" >&2
    exit 1
fi
rm "$fixture/content/stale.org" "$fixture/content/stale.md"

printf 'ok - check rejects stale Markdown\n'

mkdir -p "$fixture/content/posts"
touch "$fixture/content/posts/article.org" "$fixture/content/posts/article.md"

if output=$(cd "$fixture" && sh scripts/build-org.sh --check 2>&1); then
    printf 'expected forbidden posts failure, got success:\n%s\n' "$output" >&2
    exit 1
fi

printf 'ok - check rejects posts directory under POSIX sh\n'
