+++
title = "Migrating a Zola blog from Markdown to Org-mode — with a lint/export/check pipeline to keep them in sync"
author = ["Yi-Ping Pan (Cloudlet)"]
description = "How I migrated 15 articles from Markdown to Org-mode and built a lint/export/check pipeline to enforce sync between .org sources and generated .md files."
date = 2026-06-04
draft = false
[taxonomies]
  tags = ["emacs", "org-mode", "zola", "ox-zola", "blog-workflow"]
  categories = ["software-tooling"]
+++

For the first year, I wrote in Markdown. The reasons were practical: [Zola](https://www.getzola.org/) reads Markdown natively, and I was not sure I would keep writing long enough to justify setting up a more elaborate workflow.

Fifteen articles later, I am still writing. The friction of editing `.md` files in Emacs — jumping between Markdown conventions and Org muscle memory — became annoying enough to act on. So I migrated everything to Org-mode.

[ox-zola](https://github.com/gicrisf/ox-zola) bridges the syntax gap by exporting `.org` files to Zola-compatible Markdown. However, the architectural problem is state synchronization: ensuring the generated `.md` files continuously match the `.org` sources without manual intervention.

This note documents the linting and export pipeline built to enforce this synchronization.

---


## Why Org-mode Over Markdown {#why-org-mode-over-markdown}

I think Org-mode is easier to read for me than markdown in Emacs:


### 1. Outline Navigation {#1-dot-outline-navigation}

Markdown has no native outline. A long article looks like this as plain text:

```text
## Section One

...50 lines...

### Subsection

...50 lines...

## Section Two
```

In Org-mode, `TAB` on any heading collapses or expands it. `S-TAB` toggles the entire buffer. Jumping between sections in a 400-line article takes one keystroke instead of scrolling.


### 2. Code Block Delimiters {#2-dot-code-block-delimiters}

Markdown uses backtick fences that visually blend into surrounding text:

````text
Some prose here.

```cpp
int main() { return 0; }
```

More prose here.
````

Org uses `#+BEGIN_SRC` / `#+END_SRC` which stand out clearly in a monospace font:

````text
Some prose here.

#+BEGIN_SRC cpp
int main() { return 0; }
#+END_SRC

More prose here.
````

Once an article passes a few hundred lines, restructuring headers in Markdown means scrolling. In Org, folding makes it a non-issue.


### 3. Link Display Toggle {#3-dot-link-display-toggle}

In Markdown, a link always shows its full syntax:

````text
[some text](https://very-long-url-that-takes-up-space.com/path/to/page)
````

In Org-mode, links render the description by default. When you need to see or edit the URL, toggle with a small helper function:

````elisp
(defun cloudlet/org-toggle-link-display ()
  "Toggle the literal or descriptive display of links."
  (interactive)
  (if org-link-descriptive
      (progn (remove-from-invisibility-spec '(org-link))
             (org-restart-font-lock)
             (setq org-link-descriptive nil))
    (progn (add-to-invisibility-spec '(org-link))
           (org-restart-font-lock)
           (setq org-link-descriptive t))))
````

The URL stays hidden until I need it — which, when writing, is almost never.


## Setting Up ox-zola {#setting-up-ox-zola}

ox-zola is an Org exporter that outputs Zola-compatible Markdown, TOML frontmatter included. It builds on top of ox-hugo.

In Doom Emacs, add to `packages.el`:

````elisp
(package! ox-zola
  :recipe (:host github :repo "gicrisf/ox-zola"))
````

And in `config.el`:

````elisp
(use-package! ox-zola
  :after org
  :config
  (setq ox-zola-base-dir "~/path/to/your/site")
  (setq org-export-use-babel nil)
  (setq org-export-with-broken-links t))
````

`org-export-use-babel nil` prevents Emacs from trying to execute code blocks during export. `org-export-with-broken-links t` lets export continue even if some links cannot be resolved locally.


### Frontmatter Keywords {#frontmatter-keywords}

ox-zola reads `#+KEYWORD:` lines at the top of the file. The ones I use:

To automate frontmatter generation, use a yasnippet template at `$DOOMDIR/snippets/org-mode/zola`:

````text
# -*- mode: snippet -*-
# name: zola
# key: >zola
# --
#+TITLE: ${1:Title}
#+DESCRIPTION: ${2:Description}
#+AUTHOR: Yi-Ping Pan (Cloudlet)
#+DATE: `(format-time-string "%Y-%m-%d")`
#+ZOLA_DRAFT: ${3:true}
#+ZOLA_SECTION: ${4:technical/project}
#+ZOLA_CATEGORIES: ${5:category}
#+ZOLA_TAGS: ${6:tags}
#+ZOLA_CUSTOM_FRONT_MATTER: :extra '((math . ${7:nil}))

$0
````

Type `>zola` and press `TAB` to expand. Tab stops walk through title, description, section, and the rest.

````text
#+TITLE: Article Title
#+DESCRIPTION: One-line summary
#+AUTHOR: Yi-Ping Pan (Cloudlet)
#+DATE: 2026-06-04
#+ZOLA_DRAFT: true
#+ZOLA_SECTION: technical/project
#+ZOLA_CATEGORIES: systems-programming
#+ZOLA_TAGS: emacs org-mode
````

A few things I got wrong the first time:

-   `#+ZOLA_TAXONOMIES_CATEGORIES:` does not exist. The correct keyword is `#+ZOLA_CATEGORIES:`.
-   Tags are space-separated, not comma-separated.
-   `#+ZOLA_SECTION:` must match the actual directory path under `content/`, or ox-zola will output the file to `content/posts/` by default.
-   `#+ZOLA_EXTRA_MATH: true` does nothing. The `ZOLA_EXTRA_` namespace is not recognized by ox-zola. To enable KaTeX rendering, use `#+ZOLA_CUSTOM_FRONT_MATTER` instead:

<!--listend-->

````text
#+ZOLA_CUSTOM_FRONT_MATTER: :extra '((math . t))
````

Without this, `$...$` and `$$...$$` blocks export correctly as text but KaTeX never renders them in the browser.


### Cross-references Between Articles {#cross-references-between-articles}

Zola uses `@/section/article.md` for internal links. Org cannot resolve these at export time, which causes the export to abort.

The fix is to use `file:` links pointing to the `.org` source file. ox-zola will resolve the path relative to the `base-dir` and emit the correct `@/` syntax:

````org
[[file:emacs-01.org][Emacs Internal #01]]
````

Becomes:

````markdown
[Emacs Internal #01](@/technical/emacs/emacs-01.md)
````


### Images {#images}

Bare image links without alt text get converted to Hugo `figure` shortcodes, which Zola does not understand:

````org
;; Wrong — becomes {​{ figure(src="...") }​}
[[/images/screenshot.png]]

;; Correct — becomes ![alt](/images/screenshot.png)
[[/images/screenshot.png][Screenshot description]]
````

Always include alt text.

---


## The Pipeline: build-org.sh {#the-pipeline-build-org-dot-sh}

To enforce export consistency, `scripts/build-org.sh` wraps the export process in a strict lint-export-check sequence.


### Step 1: Lint {#step-1-lint}

Before exporting, check every `.org` file for common mistakes:

-   Bare image links (no alt text)
-   `@/` links that Org cannot resolve
-   `#+ZOLA_SECTION:` missing or not matching the file's directory
-   `.md` cross-reference links (should be `file:*.org` instead)
-   Indented headings inside code blocks (false positives filtered with awk)

Draft files (`#+ZOLA_DRAFT: true`) are skipped entirely.

If any lint check fails, the pipeline stops. Export only runs on clean files.


### Step 2: Export {#step-2-export}

Batch export using Emacs in `--batch` mode:

````bash
emacs --batch --load scripts/org-export.el
````

The `org-export.el` script loads the full straight.el build directory so ox-zola and ox-hugo are available without loading Doom's `init.el` (which does not work in batch mode).

Draft files are skipped by default. Pass `--drafts` to include them for local preview:

````bash
./scripts/build-org.sh --drafts
````


### Step 3: Check {#step-3-check}

After export, verify:

-   Every `.org` has a corresponding `.md` that is newer
-   No Hugo `figure` shortcodes leaked into the output
-   No raw `@/` links in the generated Markdown


### Git Hooks {#git-hooks}

A pre-commit hook blocks commits if any `.org` is newer than its `.md` (skipping drafts and `about.org`). A pre-push hook runs the full pipeline before pushing to origin.

````bash
# .git/hooks/pre-push
cd "$(git rev-parse --show-toplevel)"
./scripts/build-org.sh
````

---


## The File Structure {#the-file-structure}

````text
content/
  technical/
    emacs/
      emacs-01.org    ← source, edit this
      emacs-01.md     ← generated, do not edit manually
      emacs-02.org
      emacs-02.md
scripts/
  build-org.sh        ← lint + export + check
  org-export.el       ← batch export script
````

`.md` files are committed to the repository because Zola's GitHub Actions CI reads them directly. The `.org` files are the source of truth; the `.md` files are derived output.

---


## Result {#result}

The `.org` file is now the strict single source of truth. The `.md` file is treated entirely as a compiled build artifact.

By binding `scripts/build-org.sh` to the Git pre-push hook, the state synchronization problem is eliminated at the system level. If the pipeline returns 0, the Markdown artifacts are guaranteed to be in sync with the Org sources. `git push` simply acts as the deployment trigger for the clean artifacts.
