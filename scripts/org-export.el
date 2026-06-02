;; org-export.el — batch export all .org files to .md via ox-zola
;; Usage: emacs --batch --load scripts/org-export.el

(let ((straight-build (expand-file-name "~/.config/emacs/.local/straight/build-30.2")))
  (dolist (dir (directory-files straight-build t "^[^.]"))
    (when (file-directory-p dir)
      (add-to-list 'load-path dir))))

(require 'ox-hugo)
(require 'ox-zola)

;; TOML Table Ordering: Zola requires all top-level key-value pairs (title, date, etc.)
;; to appear BEFORE any tables like [taxonomies] or [extra]. If a table is defined,
;; all subsequent keys are attributed to that table, causing parsing errors.
;; We enforce this by manually appending these tables to the end of the frontmatter alist.
(defun ox-zola--transform-frontmatter (data)
  "Transform DATA alist for Zola: taxonomies section, field renames.
Ensures that maps (tables) are at the end of the alist."
  (let ((result (copy-alist data)))
    ;; Rename lastmod → updated
    (when-let ((lastmod (alist-get 'lastmod result)))
      (setf (alist-get 'updated result) lastmod)
      (setq result (assq-delete-all 'lastmod result)))
    ;; Rename layout → template
    (when-let ((layout (alist-get 'layout result)))
      (setf (alist-get 'template result) layout)
      (setq result (assq-delete-all 'layout result)))
    ;; Remove Hugo-specific fields not used by Zola
    (dolist (key '(publishDate expiryDate blackfriday logbook menu resources
                   outputs headless isCJKLanguage markup series linkTitle
                   type url videos))
      (setq result (assq-delete-all key result)))
    ;; Build [taxonomies] section from tags/categories
    (let ((tags (alist-get 'tags result))
          (categories (alist-get 'categories result)))
      (when (or tags categories)
        (let ((taxonomies nil))
          (when categories
            (push (cons 'categories categories) taxonomies))
          (when tags
            (push (cons 'tags tags) taxonomies))
          (setq result (assq-delete-all 'tags result))
          (setq result (assq-delete-all 'categories result))
          ;; Add taxonomies to the end
          (setq result (append result (list (cons 'taxonomies taxonomies)))))))
    ;; Ensure 'extra is at the end
    (when-let ((extra (alist-get 'extra result)))
      (setq result (assq-delete-all 'extra result))
      (setq result (append result (list (cons 'extra extra)))))
    result))

(unless (fboundp 'ox-zola-export-to-md)
  (message "FATAL: ox-zola-export-to-md not found after loading")
  (kill-emacs 1))

(setq org-export-use-babel nil
      org-export-with-broken-links t
      ox-zola-base-dir (expand-file-name default-directory))

(let ((include-drafts (getenv "ORG_EXPORT_DRAFTS")))
  (dolist (org (directory-files-recursively "content" "\\.org$"))
    (with-current-buffer (find-file-noselect (expand-file-name org))
      (let ((is-draft (save-excursion
                        (goto-char (point-min))
                        (re-search-forward "^#\\+ZOLA_DRAFT: true" nil t))))
        (if (and is-draft (not include-drafts))
            (message "  \033[1;33m[SKIP]\033[0m %s (draft)" org)
          (condition-case e
              (progn
                (ox-zola-export-to-md)
                (message "  \033[1;32m[OK]\033[0m  %s%s" org (if is-draft " (draft)" "")))
            (error
             (message "  \033[1;31m[ERR]\033[0m %s\n       %s" org e))))))))
