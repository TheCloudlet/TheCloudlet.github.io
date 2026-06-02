;; org-export.el — batch export all .org files to .md via ox-zola
;; Usage: emacs --batch --load scripts/org-export.el

(let ((straight-build (expand-file-name "~/.config/emacs/.local/straight/build-30.2")))
  (dolist (dir (directory-files straight-build t "^[^.]"))
    (when (file-directory-p dir)
      (add-to-list 'load-path dir))))

(require 'ox-hugo)
(require 'ox-zola)

(unless (fboundp 'ox-zola-export-to-md)
  (message "FATAL: ox-zola-export-to-md not found after loading")
  (kill-emacs 1))

(setq org-export-use-babel nil
      org-export-with-broken-links t
      ox-zola-base-dir (expand-file-name default-directory))

(dolist (org (directory-files-recursively "content" "\\.org$"))
  (with-current-buffer (find-file-noselect (expand-file-name org))
    (if (save-excursion
          (goto-char (point-min))
          (re-search-forward "^#\\+ZOLA_DRAFT: true" nil t))
        (message "  \033[1;33m[SKIP]\033[0m %s (draft)" org)
      (condition-case e
          (progn
            (ox-zola-export-to-md)
            (message "  \033[1;32m[OK]\033[0m  %s" org))
        (error
         (message "  \033[1;31m[ERR]\033[0m %s\n       %s" org e))))))
