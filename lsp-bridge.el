;;; lsp-bridge.el --- LSP bridge  -*- lexical-binding: t; -*-

;; Filename: lsp-bridge.el
;; Description: LSP bridge
;; Author: Andy Stewart <lazycat.manatee@gmail.com>
;; Maintainer: Andy Stewart <lazycat.manatee@gmail.com>
;; Copyright (C) 2018, Andy Stewart, all rights reserved.
;; Created: 2018-06-15 14:10:12
;; Version: 0.5
;; Last-Updated: Wed May 11 02:44:16 2022 (-0400)
;;           By: Mingde (Matthew) Zeng
;; URL: https://github.com/manateelazycat/lsp-bridge
;; Keywords:
;; Compatibility: emacs-version >= 27
;; Package-Requires: ((emacs "27"))
;;
;; Features that might be required by this library:
;;
;; Please check README
;;

;;; This file is NOT part of GNU Emacs

;;; License
;;
;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program; see the file COPYING.  If not, write to
;; the Free Software Foundation, Inc., 51 Franklin Street, Fifth
;; Floor, Boston, MA 02110-1301, USA.

;;; Commentary:
;;
;; Lsp-Bridge
;;

;;; Installation:
;;
;; Please check README
;;

;;; Customize:
;;
;;
;;
;; All of the above can customize by:
;;      M-x customize-group RET lsp-bridge RET
;;

;;; Change log:
;;
;;

;;; Acknowledgements:
;;
;;
;;

;;; TODO
;;
;;
;;

;;; Code:
(require 'cl-lib)
(require 'json)
(require 'map)
(require 'seq)
(require 'subr-x)
(require 'lsp-bridge-epc)
(require 'lsp-bridge-ref)
(require 'posframe)
(require 'markdown-mode)
(require 'xref)

(require 'corfu)
(require 'corfu-info)
(require 'corfu-doc)

(defgroup lsp-bridge nil
  "LSP-Bridge group."
  :group 'applications)


(defcustom lsp-bridge-completion-popup-predicates '(lsp-bridge-not-continue
                                                    lsp-bridge-not-empty-candidates
                                                    lsp-bridge-not-only-blank-before-cursor
                                                    lsp-bridge-not-match-hide-characters
                                                    lsp-bridge-not-match-completion-position
                                                    lsp-bridge-not-match-stop-commands
                                                    lsp-bridge-is-evil-insert-state)
  "A list of predicate functions with no argument to enable popup completion in callback."
  :type 'list
  :group 'lsp-bridge)

(defcustom lsp-bridge-flash-line-delay .3
  "How many seconds to flash `lsp-bridge-font-lock-flash' after navigation.

Setting this to nil or 0 will turn off the indicator."
  :type 'number
  :group 'lsp-bridge)

(defcustom lsp-bridge-completion-stop-commands
  '("corfu-complete" "corfu-insert"
    "undo-tree-undo" "undo-tree-redo"
    "kill-region" "delete-block-backward" "company-complete-selection")
  "If last command is match this option, stop popup completion ui."
  :type 'cons
  :group 'lsp-bridge)

(defcustom lsp-bridge-completion-hide-characters '(":" ";" "(" ")" "[" "]" "{" "}" "," "\"")
  "If character before match this option, stop popup completion ui."
  :type 'cons
  :group 'lsp-bridge)

(defcustom lsp-bridge-lookup-doc-tooltip " *lsp-bridge-hover*"
  "Buffer for display hover information."
  :type 'string
  :group 'lsp-bridge)

(defcustom lsp-bridge-lookup-doc-tooltip-text-scale 0.5
  "The text scale for lsp-bridge hover tooltip."
  :type 'float
  :group 'lsp-bridge)

(defcustom lsp-bridge-lookup-doc-tooltip-border-width 20
  "The border width of lsp-bridge hover tooltip, in pixels."
  :type 'integer
  :group 'lsp-bridge)

(defcustom lsp-bridge-lookup-doc-tooltip-max-width 150
  "The max width of lsp-bridge hover tooltip."
  :type 'integer
  :group 'lsp-bridge)

(defcustom lsp-bridge-lookup-doc-tooltip-max-height 20
  "The max width of lsp-bridge hover tooltip."
  :type 'integer
  :group 'lsp-bridge)

(defcustom lsp-bridge-enable-show-in-mode-line t
  "Whether to show up in mode-line."
  :type 'boolean
  :group 'lsp-bridge)

(defcustom lsp-bridge-enable-auto-import t
  "Whether to enable auto-import."
  :type 'boolean
  :group 'lsp-bridge)

(defcustom lsp-bridge-enable-candidate-doc-preview t
  "Whether to enable candidate documentation."
  :type 'boolean
  :group 'lsp-bridge)

(defcustom lsp-bridge-disable-backup t
  "Default disable backup feature, include `make-backup-files' `auto-save-default' and `create-lockfiles'."
  :type 'boolean
  :group 'lsp-bridge)

(defcustom lsp-bridge-enable-signature-help t
  "Whether to enable signature-help."
  :type 'boolean
  :group 'lsp-bridge)

(defcustom lsp-bridge-signature-help-fetch-idle 0.5
  "The idle seconds to fetch signature help.."
  :type 'float
  :group 'lsp-bridge)

(defcustom lsp-bridge-enable-diagnostics t
  "Whether to enable diagnostics."
  :type 'boolean
  :group 'lsp-bridge)

(defcustom lsp-bridge-candidates-max-number 1000
  "Maxium number of candidates returned by lsp-bridge."
  :type 'integer
  :group 'lsp-bridge)

(defface lsp-bridge-font-lock-flash
  '((t (:inherit highlight)))
  "Face to flash the current line."
  :group 'lsp-bridge)

(defvar lsp-bridge-last-change-command nil)
(defvar lsp-bridge-server nil
  "The LSP-Bridge Server.")

(defvar lsp-bridge-python-file (expand-file-name "lsp_bridge.py" (file-name-directory load-file-name)))

(defvar lsp-bridge-mark-ring nil
  "The list of saved lsp-bridge marks, most recent first.")

(defcustom lsp-bridge-mark-ring-max 16
  "Maximum size of lsp-bridge mark ring.  \
Start discarding off end if gets this big."
  :type 'integer)

(defvar lsp-bridge-server-port nil)

(defun lsp-bridge--start-epc-server ()
  "Function to start the EPC server."
  (unless (process-live-p lsp-bridge-server)
    (setq lsp-bridge-server
          (lsp-bridge-epc-server-start
           (lambda (mngr)
             (let ((mngr mngr))
               (lsp-bridge-epc-define-method mngr 'eval-in-emacs 'lsp-bridge--eval-in-emacs-func)
               (lsp-bridge-epc-define-method mngr 'get-emacs-var 'lsp-bridge--get-emacs-var-func)
               (lsp-bridge-epc-define-method mngr 'get-emacs-vars 'lsp-bridge--get-emacs-vars-func)
               (lsp-bridge-epc-define-method mngr 'get-lang-server 'lsp-bridge--get-lang-server-func)
               (lsp-bridge-epc-define-method mngr 'get-emacs-version 'emacs-version)
               (lsp-bridge-epc-define-method mngr 'is-snippet-support 'lsp-bridge--snippet-expansion-fn)
               (lsp-bridge-epc-define-method mngr 'get-project-root 'lsp-bridge-project-root)
               ))))
    (if lsp-bridge-server
        (setq lsp-bridge-server-port (process-contact lsp-bridge-server :service))
      (error "[LSP-Bridge] lsp-bridge-server failed to start")))
  lsp-bridge-server)

(defun lsp-bridge--eval-in-emacs-func (sexp-string)
  (eval (read sexp-string))
  nil)

(defun lsp-bridge--get-emacs-var-func (var-name)
  (let* ((var-symbol (intern var-name))
         (var-value (symbol-value var-symbol))
         ;; We need convert result of booleanp to string.
         ;; Otherwise, python-epc will convert all `nil' to [] at Python side.
         (var-is-bool (prin1-to-string (booleanp var-value))))
    (list var-value var-is-bool)))

(defun lsp-bridge--get-emacs-vars-func (&rest vars)
  (mapcar #'lsp-bridge--get-emacs-var-func vars))

(defvar lsp-bridge-epc-process nil)

(defvar lsp-bridge-internal-process nil)
(defvar lsp-bridge-internal-process-prog nil)
(defvar lsp-bridge-internal-process-args nil)

(defcustom lsp-bridge-name "*lsp-bridge*"
  "Name of LSP-Bridge buffer."
  :type 'string)

(defcustom lsp-bridge-python-command (if (memq system-type '(cygwin windows-nt ms-dos)) "python.exe" "python3")
  "The Python interpreter used to run lsp_bridge.py."
  :type 'string)

(defcustom lsp-bridge-enable-debug nil
  "If you got segfault error, please turn this option.
Then LSP-Bridge will start by gdb, please send new issue with `*lsp-bridge*' buffer content when next crash."
  :type 'boolean)

(defcustom lsp-bridge-enable-log nil
  "Enable this option to print log message in `*lsp-bridge*' buffer, default only print message header."
  :type 'boolean)

(defcustom lsp-bridge-lang-server-extension-list
  '(
    (("vue") . "volar")
    (("wxml") . "wxml-language-server")
    (("html") . "vscode-html-language-server")
    )
  "The lang server rule for file extension."
  :type 'cons)

(defcustom lsp-bridge-lang-server-mode-list
  '(
    ((c-mode c++-mode) . "clangd")
    (java-mode . "jdtls")
    (python-mode . "pyright")
    (ruby-mode . "solargraph")
    ((rust-mode rustic-mode) . "rust-analyzer")
    (elixir-mode . "elixirLS")
    (go-mode . "gopls")
    (haskell-mode . "hls")
    (lua-mode . "sumneko")
    (dart-mode . "dart-analysis-server")
    (scala-mode . "metals")
    ((js2-mode js-mode rjsx-mode) . "javascript")
    (typescript-tsx-mode . "typescriptreact")
    ((typescript-mode) . "typescript")
    (tuareg-mode . "ocamllsp")
    (erlang-mode . "erlang-ls")
    ((latex-mode Tex-latex-mode texmode context-mode texinfo-mode bibtex-mode) . "texlab")
    ((clojure-mode clojurec-mode clojurescript-mode clojurex-mode) . "clojure-lsp")
    ((sh-mode) . "bash-language-server")
    ((css-mode) . "vscode-css-language-server")
    (elm-mode . "elm-language-server")
    )
  "The lang server rule for file mode."
  :type 'cons)

(defcustom lsp-bridge-default-mode-hooks
  '(c-mode-hook
    c++-mode-hook
    java-mode-hook
    python-mode-hook
    ruby-mode-hook
    lua-mode-hook
    rust-mode-hook
    rustic-mode-hook
    elixir-mode-hook
    go-mode-hook
    haskell-mode-hook
    haskell-literate-mode-hook
    dart-mode-hook
    scala-mode-hook
    typescript-mode-hook
    typescript-tsx-mode-hook
    js2-mode-hook
    js-mode-hook
    rjsx-mode-hook
    tuareg-mode-hook
    latex-mode-hook
    Tex-latex-mode-hook
    texmode-hook
    context-mode-hook
    texinfo-mode-hook
    bibtex-mode-hook
    clojure-mode-hook
    clojurec-mode-hook
    clojurescript-mode-hook
    clojurex-mode-hook
    sh-mode-hook
    web-mode-hook
    css-mode-hook
    elm-mode-hook)
  "The default mode hook to enable lsp-bridge."
  :type 'list)

(defvar lsp-bridge-get-lang-server-by-project nil
  "Get lang server with project path and file path.")

(defmacro lsp-bridge--with-file-buffer (filepath &rest body)
  "Evaluate BODY in buffer with FILEPATH."
  (declare (indent 1))
  `(let ((buffer (lsp-bridge-get-match-buffer ,filepath)))
     (when buffer
       (with-current-buffer buffer
         ,@body))))

(defun lsp-bridge-get-match-buffer (filepath)
  (catch 'find-match
    (dolist (buffer (buffer-list))
      (if-let ((file-name (buffer-file-name buffer)))
          (when (or (string-equal file-name filepath)
                    (string-equal (file-truename file-name) filepath))
            (throw 'find-match buffer))))
    nil))

(defun lsp-bridge--get-lang-server-func (project-path filepath)
  "Get lang server with project path, file path or file extension."
  (let (lang-server-by-project
        lang-server-by-extension)
    ;; Step 1: Search lang server base on project rule provide by `lsp-bridge-get-lang-server-by-project'.
    (when lsp-bridge-get-lang-server-by-project
      (setq lang-server-by-project (funcall lsp-bridge-get-lang-server-by-project project-path filepath)))

    (if lang-server-by-project
        lang-server-by-project
      ;; Step 2: search lang server base on extension rule provide by `lsp-bridge-lang-server-extension-list'.
      (setq lang-server-by-extension (lsp-bridge-get-lang-server-by-extension filepath))
      (if lang-server-by-extension
          lang-server-by-extension
        ;; Step 3: search lang server base on mode rule provide by `lsp-bridge-lang-server-extension-list'.
        (lsp-bridge--with-file-buffer filepath
          (lsp-bridge-get-lang-server-by-mode))))))

(defun lsp-bridge-get-lang-server-by-extension (filepath)
  "Get lang server for file extension."
  (let* ((file-extension (file-name-extension filepath))
         (langserver-info (cl-find-if
                           (lambda (pair)
                             (let ((extension (car pair)))
                               (if (eq (type-of extension) 'string)
                                   (string-equal file-extension extension)
                                 (member file-extension extension))))
                           lsp-bridge-lang-server-extension-list)))
    (if langserver-info
        (cdr langserver-info)
      nil)))

(defun lsp-bridge-get-lang-server-by-mode ()
  "Get lang server for file mode."
  (let ((langserver-info (cl-find-if
                          (lambda (pair)
                            (let ((mode (car pair)))
                              (if (symbolp mode)
                                  (eq major-mode mode)
                                (member major-mode mode))))
                          lsp-bridge-lang-server-mode-list)))
    (if langserver-info
        (cdr langserver-info)
      nil)))

(defun lsp-bridge--auto-tick ()
  "Return the current tick/status of the buffer.
Auto completion is only performed if the tick did not change."
  (list (current-buffer) (buffer-chars-modified-tick) (point)))

(defun lsp-bridge-call-async (method &rest args)
  "Call Python EPC function METHOD and ARGS asynchronously."
  (lsp-bridge-deferred-chain
    (lsp-bridge-epc-call-deferred lsp-bridge-epc-process (read method) args)))

(defun lsp-bridge-call-sync (method &rest args)
  "Call Python EPC function METHOD and ARGS synchronously."
  (lsp-bridge-epc-call-sync lsp-bridge-epc-process (read method) args))

(defvar-local lsp-bridge-buffer-file-deleted nil)

(defun lsp-bridge-call-file-api (method &rest args)
  (unless (or (null lsp-bridge-filepath)
              (equal lsp-bridge-filepath ""))
    (if (file-exists-p lsp-bridge-filepath)
        (if lsp-bridge-buffer-file-deleted
            ;; If buffer's file create again (such as switch branch back), we need save buffer first,
            ;; send the LSP request after the file is changed next time.
            (progn
              (save-buffer)
              (setq-local lsp-bridge-buffer-file-deleted nil)
              (message "[LSP-Bridge] %s is back, will send the LSP request after the file is changed next time." lsp-bridge-filepath))
          (lsp-bridge-deferred-chain
            (lsp-bridge-epc-call-deferred lsp-bridge-epc-process (read method) (append (list lsp-bridge-filepath) args))))
      ;; We need send `closeFile' request to lsp server if we found buffer's file is not exist,
      ;; it is usually caused by switching branch or other tools to delete file.
      ;;
      ;; We won't send any lsp request until buffer's file create again.
      (unless lsp-bridge-buffer-file-deleted
        (lsp-bridge-close-buffer-file)
        (setq-local lsp-bridge-buffer-file-deleted t)
        (message "[LSP-Bridge] %s is not exist, stop send the LSP request until file create again." lsp-bridge-filepath)))))

(defvar lsp-bridge-is-starting nil)

(defun lsp-bridge-restart-process ()
  "Stop and restart LSP-Bridge process."
  (interactive)
  (setq lsp-bridge-is-starting nil)

  (lsp-bridge-kill-process)
  (lsp-bridge-start-process)
  (message "[LSP-Bridge] Process restarted."))

(defun lsp-bridge-start-process ()
  "Start LSP-Bridge process if it isn't started."
  (setq lsp-bridge-is-starting t)
  (unless (lsp-bridge-epc-live-p lsp-bridge-epc-process)
    ;; start epc server and set `lsp-bridge-server-port'
    (lsp-bridge--start-epc-server)
    (let* ((lsp-bridge-args (append
                             (list lsp-bridge-python-file)
                             (list (number-to-string lsp-bridge-server-port))
                             )))

      ;; Set process arguments.
      (if lsp-bridge-enable-debug
          (progn
            (setq lsp-bridge-internal-process-prog "gdb")
            (setq lsp-bridge-internal-process-args (append (list "-batch" "-ex" "run" "-ex" "bt" "--args" lsp-bridge-python-command) lsp-bridge-args)))
        (setq lsp-bridge-internal-process-prog lsp-bridge-python-command)
        (setq lsp-bridge-internal-process-args lsp-bridge-args))

      ;; Start python process.
      (let ((process-connection-type (not (lsp-bridge--called-from-wsl-on-windows-p))))
        (setq lsp-bridge-internal-process
              (apply 'start-process
                     lsp-bridge-name lsp-bridge-name
                     lsp-bridge-internal-process-prog lsp-bridge-internal-process-args)))
      (set-process-query-on-exit-flag lsp-bridge-internal-process nil))))

(defun lsp-bridge--called-from-wsl-on-windows-p ()
  "Check whether lsp-bridge is called by Emacs on WSL and is running on Windows."
  (and (eq system-type 'gnu/linux)
       (string-match-p ".exe" lsp-bridge-python-command)))

(defvar lsp-bridge-stop-process-hook nil)

(defun lsp-bridge-kill-process ()
  "Stop LSP-Bridge process and kill all LSP-Bridge buffers."
  (interactive)

  ;; Run stop process hooks.
  (run-hooks 'lsp-bridge-stop-process-hook)

  ;; Kill process after kill buffer, make application can save session data.
  (lsp-bridge--kill-python-process))

(add-hook 'kill-emacs-hook #'lsp-bridge-kill-process)

(defun lsp-bridge--kill-python-process ()
  "Kill LSP-Bridge background python process."
  (when (lsp-bridge-epc-live-p lsp-bridge-epc-process)
    ;; Cleanup before exit LSP-Bridge server process.
    (lsp-bridge-call-async "cleanup")
    ;; Delete LSP-Bridge server process.
    (lsp-bridge-epc-stop-epc lsp-bridge-epc-process)
    ;; Kill *lsp-bridge* buffer.
    (when (get-buffer lsp-bridge-name)
      (kill-buffer lsp-bridge-name))
    (setq lsp-bridge-epc-process nil)
    (message "[LSP-Bridge] Process terminated.")))

(defun lsp-bridge--first-start (lsp-bridge-epc-port)
  "Call `lsp-bridge--open-internal' upon receiving `start_finish' signal from server."
  ;; Make EPC process.
  (setq lsp-bridge-epc-process (make-lsp-bridge-epc-manager
                                :server-process lsp-bridge-internal-process
                                :commands (cons lsp-bridge-internal-process-prog lsp-bridge-internal-process-args)
                                :title (mapconcat 'identity (cons lsp-bridge-internal-process-prog lsp-bridge-internal-process-args) " ")
                                :port lsp-bridge-epc-port
                                :connection (lsp-bridge-epc-connect "localhost" lsp-bridge-epc-port)
                                ))
  (lsp-bridge-epc-init-epc-layer lsp-bridge-epc-process)
  (setq lsp-bridge-is-starting nil))

(defvar-local lsp-bridge-last-position 0)
(defvar-local lsp-bridge-completion-candidates nil)
(defvar-local lsp-bridge-completion-server-name nil)
(defvar-local lsp-bridge-completion-trigger-characters nil)
(defvar-local lsp-bridge-completion-resolve-provider nil)
(defvar-local lsp-bridge-completion-prefix nil)
(defvar-local lsp-bridge-completion-common nil)
(defvar-local lsp-bridge-completion-position nil)
(defvar-local lsp-bridge-filepath "")
(defvar-local lsp-bridge-prohibit-completion nil)
(defvar-local lsp-bridge-current-tick nil)
(defvar-local lsp-bridge-diagnostic-overlays '())

(defun lsp-bridge-char-before ()
  (let ((prev-char (char-before)))
    (if prev-char (char-to-string prev-char) "")))

(defun lsp-bridge-monitor-post-command ()
  (when (lsp-bridge-epc-live-p lsp-bridge-epc-process)
    (unless (equal (point) lsp-bridge-last-position)
      (lsp-bridge-call-file-api "change_cursor" (lsp-bridge--position))
      (setq-local lsp-bridge-last-position (point))))

  ;; Hide hover tooltip.
  (if (not (string-prefix-p "lsp-bridge-popup-documentation-scroll" (format "%s" this-command)))
      (lsp-bridge-hide-doc-tooltip))

  ;; Hide diagnostic tooltip.
  (unless (member (format "%s" this-command) '("lsp-bridge-jump-to-next-diagnostic"
                                               "lsp-bridge-jump-to-prev-diagnostic"))
    (lsp-bridge-hide-diagnostic-tooltip)))

(defun lsp-bridge-close-buffer-file ()
  (when (lsp-bridge-epc-live-p lsp-bridge-epc-process)
    (lsp-bridge-call-async "close_file" lsp-bridge-filepath)))

(defun lsp-bridge-is-empty-list (list)
  (or (and (eq (length list) 1)
           (string-empty-p (format "%s" (car list))))
      (and (eq (length list) 0))))

(defun lsp-bridge-add-candidate-item (label item)
  (if (gethash label lsp-bridge-completion-candidates)
      (lsp-bridge-add-candidate-item (format "%s " label) item)
    (puthash label item lsp-bridge-completion-candidates)))

(defun lsp-bridge-get-candidate-item (label)
  (gethash label lsp-bridge-completion-candidates))

(defun lsp-bridge-record-completion-items (filepath
                                           common items position
                                           server-name
                                           completion-trigger-characters
                                           completion-resolve-provider)
  (lsp-bridge--with-file-buffer filepath
    ;; Save completion items.
    (setq-local lsp-bridge-completion-common common)
    (setq-local lsp-bridge-completion-position position)
    (setq-local lsp-bridge-completion-server-name server-name)
    (setq-local lsp-bridge-completion-trigger-characters completion-trigger-characters)
    (setq-local lsp-bridge-completion-resolve-provider completion-resolve-provider)

    (setq-local lsp-bridge-completion-candidates (make-hash-table :test 'equal))
    (dolist (item items)
      (lsp-bridge-add-candidate-item (plist-get item :label) item))

    (if lsp-bridge-prohibit-completion
        (setq lsp-bridge-prohibit-completion nil)

      ;; Try popup completion frame.
      (when (cl-every (lambda (pred)
                        (if (functionp pred) (funcall pred) t))
                      lsp-bridge-completion-popup-predicates)
        (lsp-bridge-update-candidates)
        ))))

(defun lsp-bridge-update-candidates ()
  "Update corfu candidate manually."
  (ignore-errors
    (pcase (while-no-input ;; Interruptible capf query
             ;;  TODO: Is this expensive?
             (run-hook-wrapped 'completion-at-point-functions #'corfu--capf-wrapper))
      (`(,fun ,beg ,end ,table . ,plist)
       (let ((completion-in-region-mode-predicate
              (lambda () (eq beg (car-safe (funcall fun))))))
         (setq completion-in-region--data
               (list (if (markerp beg) beg (copy-marker beg))
                     (copy-marker end t)
                     table
                     (plist-get plist :predicate)))
         (setq completion-extra-properties plist)
         ;; (setq corfu--extra completion-extra-properties)
         (let ((corfu--input nil))
           (corfu--setup)
           (corfu--exhibit 'auto))
         )))))

(defun lsp-bridge-not-continue ()
  "Hide completion if completion continue."
  (not (corfu--continue-p)))

(defun lsp-bridge-not-empty-candidates ()
  "Hide completion if candidates list is empty."
  (not (lsp-bridge-is-empty-list (hash-table-keys lsp-bridge-completion-candidates))))

(defun lsp-bridge-not-match-completion-position ()
  "Hide completion if the position of cursor has changed."
  (equal lsp-bridge-current-tick (lsp-bridge--auto-tick)))

(defun lsp-bridge-not-match-stop-commands ()
  "Hide completion if `lsp-bridge-last-change-command' match commands in `lsp-bridge-completion-stop-commands'."
  (not (member lsp-bridge-last-change-command lsp-bridge-completion-stop-commands)))

(defun lsp-bridge-not-match-hide-characters ()
  "Hide completion if cursor after hide character match `lsp-bridge-completion-hide-characters'."
  (not (member (char-to-string (char-before)) lsp-bridge-completion-hide-characters)))

(defun lsp-bridge-not-only-blank-before-cursor ()
  "Hide completion if only blank before cursor."
  (split-string (buffer-substring-no-properties
                 (max (1- (point)) (line-beginning-position))
                 (point))))

(defun lsp-bridge-is-evil-insert-state ()
  "If `evil' mode is enable, only show completion when evil is in insert mode."
  (or (not (featurep 'evil)) (evil-insert-state-p)))

(defun lsp-bridge-capf (&optional interactive)
  "Capf function"
  (interactive (list t))
  (if interactive
      (let ((completion-at-point-functions (list 'lsp-bridge-capf)))
        (completion-at-point))
    (when (hash-table-p lsp-bridge-completion-candidates)
      (let* ((candidates (hash-table-keys lsp-bridge-completion-candidates))
             (bounds (bounds-of-thing-at-point 'symbol))
             (bounds-start (or (car bounds) (point)))
             (bounds-end (or (cdr bounds) (point))))
        (list
         bounds-start
         bounds-end
         candidates

         :company-cache
         t

         :annotation-function
         (lambda (candidate)
           (let* ((annotation (plist-get (lsp-bridge-get-candidate-item candidate) :annotation)))
             (setq lsp-bridge-completion-prefix (buffer-substring-no-properties bounds-start (point)))
             (when annotation
               (concat " " (propertize annotation 'face 'font-lock-doc-face)))))

         :company-kind
         (lambda (candidate)
           (when-let* ((kind (plist-get (lsp-bridge-get-candidate-item candidate) :kind)))
             (intern (downcase kind))))

         :company-deprecated
         (lambda (candidate)
           (seq-contains-p (plist-get (lsp-bridge-get-candidate-item candidate) :tags) 1))

         :exit-function
         (lambda (candidate status)

           (when (memq status '(finished exact))
             ;; Because lsp-bridge will push new candidates when company/lsp-bridge-ui completing.
             ;; We need extract newest candidates when insert, avoid insert old candidate content.
             (let* ((candidate-index (cl-find candidate candidates :test #'string=)))
               (with-current-buffer (if (minibufferp)
                                        (window-buffer (minibuffer-selected-window))
                                      (current-buffer))
                 (cond
                  ;; Don't expand candidate if the user enters all characters manually.
                  ;; ((and (member candidate candidates)
                  ;;       (eq this-command 'self-insert-command)))
                  ;; Just insert candidate if it has expired.
                  ((null candidate-index))
                  (t
                   (let* ((label (string-trim candidate)) ; we need trim candidate
                          (candidate-info (lsp-bridge-get-candidate-item candidate))
                          (insert-text (plist-get candidate-info :insertText))
                          (insert-text-format (plist-get candidate-info :insertTextFormat))
                          (text-edit (plist-get candidate-info :textEdit))
                          (new-text (plist-get text-edit :newText))
                          (additionalTextEdits (plist-get candidate-info :additionalTextEdits))
                          (kind (plist-get candidate-info :kind))
                          (snippet-fn (and (or (eql insert-text-format 2) (string= kind "Snippet")) (lsp-bridge--snippet-expansion-fn)))
                          (completion-start-pos (lsp-bridge--lsp-position-to-point lsp-bridge-completion-position))
                          (delete-start-pos (if text-edit
                                                (lsp-bridge--lsp-position-to-point (plist-get (plist-get text-edit :range) :start))
                                              bounds-start))
                          (range-end-pos (if text-edit
                                             (lsp-bridge--lsp-position-to-point (plist-get (plist-get text-edit :range) :end))
                                           completion-start-pos))
                          (delete-end-pos (+ (point) (- range-end-pos completion-start-pos)))
                          (insert-candidate (or new-text insert-text label)))

                     ;; Move bound start position forward one character, if the following situation is satisfied:
                     ;; 1. `textEdit' is not exist
                     ;; 2. bound-start character is `lsp-bridge-completion-trigger-characters'
                     ;; 3. `label' start with bound-start character
                     ;; 4. `insertText' is not start with bound-start character
                     (unless text-edit
                       (let* ((bound-start-char (save-excursion
                                                  (goto-char delete-start-pos)
                                                  (char-to-string (char-after)))))
                         (when (and (member bound-start-char lsp-bridge-completion-trigger-characters)
                                    (string-prefix-p bound-start-char label)
                                    (not (string-prefix-p bound-start-char insert-text)))
                           (setq delete-start-pos (1+ delete-start-pos)))))

                     ;; Delete region.
                     (delete-region delete-start-pos delete-end-pos)

                     ;; Insert candidate or expand snippet.
                     (funcall (or snippet-fn #'insert) insert-candidate)

                     ;; Do `additionalTextEdits' if return auto-imprt information.
                     (when (and lsp-bridge-enable-auto-import
                                (cl-plusp (length additionalTextEdits)))
                       (lsp-bridge--apply-text-edits additionalTextEdits))
                     )))))))
         )))))

(defun lsp-bridge--snippet-expansion-fn ()
  "Compute a function to expand snippets.
Doubles as an indicator of snippet support."
  (and (boundp 'yas-minor-mode)
       (symbol-value 'yas-minor-mode)
       'yas-expand-snippet))

(defun lsp-bridge--apply-text-edits (edits)
  (dolist (edit edits)
    (let* ((range (plist-get edit :range))
           (range-start-pos (lsp-bridge--lsp-position-to-point (plist-get range :start)))
           (range-end-pos (lsp-bridge--lsp-position-to-point (plist-get range :start))))
      (save-excursion
        (goto-char range-start-pos)
        (delete-region range-start-pos range-end-pos)
        (insert (plist-get edit :newText))))))

(defun lsp-bridge--lsp-position-to-point (pos-plist &optional marker)
  "Convert LSP position POS-PLIST to Emacs point.
If optional MARKER, return a marker instead"
  (save-excursion
    (save-restriction
      (widen)
      (goto-char (point-min))
      (forward-line (min most-positive-fixnum
                         (plist-get pos-plist :line)))
      (unless (eobp) ;; if line was excessive leave point at eob
        (let ((tab-width 1)
              (character (plist-get pos-plist :character)))
          (unless (wholenump character)
            (message
             "[LSP Bridge] Caution: LSP server sent invalid character position %s. Using 0 instead."
             character)
            (setq character 0))
          ;; We cannot use `move-to-column' here, because it moves to *visual*
          ;; columns, which can be different from LSP columns in case of
          ;; `whitespace-mode', `prettify-symbols-mode', etc.
          (goto-char (min (+ (line-beginning-position) character)
                          (line-end-position)))))
      (if marker (copy-marker (point-marker)) (point)))))

(defun lsp-bridge--point-position (pos)
  "Get position of POS."
  (save-excursion
    (goto-char pos)
    (lsp-bridge--position)))

(defun lsp-bridge--calculate-column ()
  "Calculate character offset of cursor in current line."
  (/ (- (length (encode-coding-region (line-beginning-position)
                                      (min (point) (point-max)) 'utf-16 t))
        2)
     2))

(defun lsp-bridge--position ()
  "Get position of cursor."
  (list :line (1- (line-number-at-pos)) :character (lsp-bridge--calculate-column)))

(defvar-local lsp-bridge--before-change-begin-pos nil)
(defvar-local lsp-bridge--before-change-end-pos nil)

(defun lsp-bridge-monitor-before-change (begin end)
  (setq lsp-bridge--before-change-begin-pos (lsp-bridge--point-position begin))
  (setq lsp-bridge--before-change-end-pos (lsp-bridge--point-position end)))

(defun lsp-bridge-monitor-after-change (begin end length)
  ;; Record last command to `lsp-bridge-last-change-command'.
  (setq lsp-bridge-last-change-command (format "%s" this-command))

  ;; Send change_file request.
  (setq-local lsp-bridge-current-tick (lsp-bridge--auto-tick))

  (when (lsp-bridge-epc-live-p lsp-bridge-epc-process)
    (lsp-bridge-call-file-api "change_file"
                              lsp-bridge--before-change-begin-pos
                              lsp-bridge--before-change-end-pos
                              length
                              (buffer-substring-no-properties begin end)
                              (lsp-bridge--position)
                              (lsp-bridge-char-before)
                              (buffer-substring-no-properties (line-beginning-position) (point))
                              (lsp-bridge-completion-ui-visible-p)
                              )))

(defun lsp-bridge-completion-ui-visible-p ()
  (and (frame-live-p corfu--frame)
       (frame-visible-p corfu--frame)))

(defun lsp-bridge-monitor-after-save ()
  (lsp-bridge-call-file-api "save_file"))

(defalias 'lsp-bridge-find-define #'lsp-bridge-find-def)

(defvar-local lsp-bridge-jump-to-def-in-other-window nil)

(defun lsp-bridge-find-def ()
  (interactive)
  (setq-local lsp-bridge-jump-to-def-in-other-window nil)
  (lsp-bridge-call-file-api "find_define" (lsp-bridge--position)))

(defun lsp-bridge-find-def-other-window ()
  (interactive)
  (setq-local lsp-bridge-jump-to-def-in-other-window t)
  (lsp-bridge-call-file-api "find_define" (lsp-bridge--position)))

(defun lsp-bridge-return-from-def ()
  "Pop off lsp-bridge-mark-ring and jump to the top location."
  (interactive)
  ;; Pop entries that refer to non-existent buffers.
  (while (and lsp-bridge-mark-ring (not (marker-buffer (car lsp-bridge-mark-ring))))
    (setq lsp-bridge-mark-ring (cdr lsp-bridge-mark-ring)))
  (or lsp-bridge-mark-ring
      (error "[LSP-Bridge] No lsp-bridge mark set"))
  (let* ((this-buffer (current-buffer))
         (marker (pop lsp-bridge-mark-ring))
         (buffer (marker-buffer marker))
         (position (marker-position marker)))
    (set-buffer buffer)
    (or (and (>= position (point-min))
             (<= position (point-max)))
        (if widen-automatically
            (widen)
          (error "[LSP-Bridge] mark position is outside accessible part of buffer %s"
                 (buffer-name buffer))))
    (goto-char position)
    (unless (equal buffer this-buffer)
      (switch-to-buffer buffer))))

(defun lsp-bridge-find-impl ()
  (interactive)
  (setq-local lsp-bridge-jump-to-def-in-other-window nil)
  (lsp-bridge-call-file-api "find_implementation" (lsp-bridge--position)))

(defun lsp-bridge-find-impl-other-window ()
  (interactive)
  (setq-local lsp-bridge-jump-to-def-in-other-window t)
  (lsp-bridge-call-file-api "find_implementation" (lsp-bridge--position)))

(defun lsp-bridge-find-references ()
  (interactive)
  (lsp-bridge-call-file-api "find_references" (lsp-bridge--position)))

(defun lsp-bridge-popup-references (references-content references-counter)
  (if lsp-bridge--xref-wait-for ;;  HACK: more situations should be considered
      (progn
        (setq lsp-bridge--xref-locations
              (and references-content
                   (lsp-bridge--xref-reference-content-to-mark references-content)))
        (setq lsp-bridge--xref-wait-for nil))
    (lsp-bridge-ref-popup references-content references-counter)
    (message "[LSP-Bridge] Found %s references" references-counter)))

(defun lsp-bridge-rename ()
  (interactive)
  (lsp-bridge-call-file-api "try_prepare_rename" (lsp-bridge--position))
  (let ((new-name (read-string "Rename to: " (thing-at-point 'symbol 'no-properties))))
    (lsp-bridge-call-file-api "rename" (lsp-bridge--position) new-name)))

(defun lsp-bridge-rename-highlight (filepath bound-start bound-end)
  (lsp-bridge--with-file-buffer filepath
    (require 'pulse)
    (let ((pulse-iterations 1)
          (pulse-delay lsp-bridge-flash-line-delay))
      (pulse-momentary-highlight-region
       (lsp-bridge--lsp-position-to-point bound-start)
       (lsp-bridge--lsp-position-to-point bound-end)
       'lsp-bridge-font-lock-flash))))

(defun lsp-bridge-lookup-documentation ()
  (interactive)
  (lsp-bridge-call-file-api "hover" (lsp-bridge--position)))

(defun lsp-bridge-signature-help-fetch ()
  (interactive)
  (if lsp-bridge-code-action-notify
      (setq-local lsp-bridge-code-action-notify nil)
    (unless (eq last-command 'mwheel-scroll)
      (lsp-bridge-call-file-api "signature_help" (lsp-bridge--position)))))

(defun lsp-bridge-rename-file (filepath edits)
  (find-file-noselect filepath)
  (lsp-bridge--with-file-buffer filepath
    (save-excursion
      (dolist (edit (reverse edits))
        (let* ((bound-start (nth 0 edit))
               (bound-end (nth 1 edit))
               (new-text (nth 2 edit))
               (replace-start-pos (lsp-bridge--lsp-position-to-point bound-start))
               (replace-end-pos (lsp-bridge--lsp-position-to-point bound-end)))
          (delete-region replace-start-pos replace-end-pos)
          (goto-char replace-start-pos)
          (insert new-text)))))
  (setq lsp-bridge-prohibit-completion t))

(defun lsp-bridge--jump-to-def (filepath position)
  ;; Record postion.
  (if lsp-bridge--xref-wait-for ;;  TODO: more situations should be considered
      (progn
        (setq lsp-bridge--xref-locations
              (and filepath
                   (list (list filepath
                               (1+ (plist-get position :line))
                               (plist-get position :character)))))
        (setq lsp-bridge--xref-wait-for nil))
    (set-marker (mark-marker) (point) (current-buffer))
    (add-to-history 'lsp-bridge-mark-ring (copy-marker (mark-marker)) lsp-bridge-mark-ring-max t)

    ;; Jump to define.
    ;; Show define in other window if `lsp-bridge-jump-to-def-in-other-window' is non-nil.
    (if lsp-bridge-jump-to-def-in-other-window
        (find-file-other-window filepath)
      (find-file filepath))

    (goto-char (lsp-bridge--lsp-position-to-point position))
    (recenter)

    ;; Flash define line.
    (require 'pulse)
    (let ((pulse-iterations 1)
          (pulse-delay lsp-bridge-flash-line-delay))
      (pulse-momentary-highlight-one-line (point) 'lsp-bridge-font-lock-flash))))

(defun lsp-bridge-insert-common-prefix ()
  (interactive)
  (if lsp-bridge-mode
      (if (and (> (length (hash-table-keys lsp-bridge-completion-candidates)) 0)
               lsp-bridge-completion-prefix
               lsp-bridge-completion-common
               (not (string-equal lsp-bridge-completion-common ""))
               (not (string-equal lsp-bridge-completion-common lsp-bridge-completion-prefix)))
          (insert (substring lsp-bridge-completion-common (length lsp-bridge-completion-prefix)))
        (message "Not found common part to insert."))
    (message "Only works for lsp-bridge mode.")))

(defun lsp-bridge-popup-documentation-scroll-up (&optional arg)
  (interactive)
  (posframe-funcall lsp-bridge-lookup-doc-tooltip
                    #'scroll-up-command arg))

(defun lsp-bridge-popup-documentation-scroll-down (&optional arg)
  (interactive)
  (posframe-funcall lsp-bridge-lookup-doc-tooltip
                    #'scroll-down-command arg))

(defun lsp-bridge-frame-background-color ()
  (let* ((theme-mode (format "%s" (frame-parameter nil 'background-mode))))
    (if (string-equal theme-mode "dark") "#191a1b" "#f0f0f0")))

(defun lsp-bridge-popup-documentation (kind name value)
  (with-current-buffer (get-buffer-create lsp-bridge-lookup-doc-tooltip)
    (erase-buffer)
    (text-scale-set lsp-bridge-lookup-doc-tooltip-text-scale)
    (setq-local markdown-fontify-code-blocks-natively t)
    (insert value)
    (lsp-bridge-render-markdown-content))
  (when (posframe-workable-p)
    (posframe-show lsp-bridge-lookup-doc-tooltip
                   :position (point)
                   :internal-border-width lsp-bridge-lookup-doc-tooltip-border-width
                   :background-color (lsp-bridge-frame-background-color)
                   :max-width lsp-bridge-lookup-doc-tooltip-max-width
                   :max-height lsp-bridge-lookup-doc-tooltip-max-height)))

(defun lsp-bridge-hide-doc-tooltip ()
  (posframe-hide lsp-bridge-lookup-doc-tooltip))

(defun lsp-bridge-hide-diagnostic-tooltip ()
  (posframe-hide lsp-bridge-diagnostic-tooltip))

(defun lsp-bridge-signature-help-update (help-infos help-index)
  (let ((index 0)
        (help ""))
    (dolist (help-info help-infos)
      (setq help (concat help
                         (propertize help-info 'face (if (equal index help-index) 'font-lock-function-name-face 'default))
                         (if (equal index (1- (length help-infos))) "" ", ")))
      (setq index (1+ index)))

    (let ((message-log-max nil))
      (message help)
      )))

(defvar lsp-bridge--last-buffer nil)

(defun lsp-bridge-monitor-window-buffer-change ()
  ;; Hide completion frame when buffer or window changed.
  (unless (eq (current-buffer)
              lsp-bridge--last-buffer)
    (lsp-bridge-hide-doc-tooltip)
    (lsp-bridge-hide-diagnostic-tooltip))

  (unless (or (minibufferp)
              (string-equal (buffer-name) "*Messages*"))
    (setq lsp-bridge--last-buffer (current-buffer))))

(add-hook 'post-command-hook 'lsp-bridge-monitor-window-buffer-change)

(defconst lsp-bridge--internal-hooks
  '((before-change-functions . lsp-bridge-monitor-before-change)
    (after-change-functions . lsp-bridge-monitor-after-change)
    (post-command-hook . lsp-bridge-monitor-post-command)
    (after-save-hook . lsp-bridge-monitor-after-save)
    (kill-buffer-hook . lsp-bridge-close-buffer-file)
    (completion-at-point-functions . lsp-bridge-capf)
    (before-revert-hook . lsp-bridge-close-buffer-file)
    ))

(defvar lsp-bridge-mode-map (make-sparse-keymap))

(defcustom lsp-bridge-org-babel-lang-list '("clojure" "latex" "python")
  "A list of org babel languages in which source code block lsp-bridge will be enabled."
  :type 'list
  :group 'lsp-bridge)

(defcustom lsp-bridge-diagnostics-fetch-idle 1
  "The idle seconds to fetch diagnostics."
  :type 'float
  :group 'lsp-bridge)

(defface lsp-bridge-diagnostics-error-face
  '((t (:underline (:style wave :color "Red1"))))
  "Face error diagnostic."
  :group 'lsp-bridge)

(defface lsp-bridge-diagnostics-warning-face
  '((t (:underline (:style wave :color "DarkOrange"))))
  "Face warning diagnostic."
  :group 'lsp-bridge)

(defface lsp-bridge-diagnostics-info-face
  '((t (:underline (:style wave :color "ForestGreen"))))
  "Face info diagnostic."
  :group 'lsp-bridge)

(defface lsp-bridge-diagnostics-hint-face
  '((t (:underline (:style wave :color "grey"))))
  "Face hint diagnostic."
  :group 'lsp-bridge)

(defcustom lsp-bridge-diagnostic-tooltip " *lsp-bridge-diagnostic*"
  "Buffer for display diagnostic information."
  :type 'string
  :group 'lsp-bridge)

(defcustom lsp-bridge-diagnostic-tooltip-border-width 20
  "The border width of lsp-bridge diagnostic tooltip, in pixels."
  :type 'integer
  :group 'lsp-bridge)

(defvar lsp-bridge-diagnostics-timer nil)

(defvar lsp-bridge-signature-help-timer nil)

;;;###autoload
(define-minor-mode lsp-bridge-mode
  "LSP Bridge mode."
  :keymap lsp-bridge-mode-map
  :init-value nil
  (if lsp-bridge-mode
      (lsp-bridge--enable)
    (lsp-bridge--disable)))

(defun lsp-bridge--enable ()
  "Enable LSP Bridge mode."
  (cond
   ((not buffer-file-name)
    (message "[LSP-Bridge] cannot be enabled in non-file buffers.")
    (setq lsp-bridge-mode nil))
   (t
    ;; Disable backup file.
    ;; Please use my another plugin `https://github.com/manateelazycat/auto-save' and use git for file version management.
    (when lsp-bridge-disable-backup
      (setq make-backup-files nil)
      (setq auto-save-default nil)
      (setq create-lockfiles nil))

    ;; When user open buffer by `ido-find-file', lsp-bridge will throw `FileNotFoundError' error.
    ;; So we need save buffer to disk before enable `lsp-bridge-mode'.
    (unless (file-exists-p (buffer-file-name))
      (save-buffer))

    (dolist (hook lsp-bridge--internal-hooks)
      (add-hook (car hook) (cdr hook) nil t))

    (setq lsp-bridge-filepath (file-truename buffer-file-name))
    (setq lsp-bridge-last-position 0)

    (remove-hook 'post-command-hook #'corfu--auto-post-command 'local)

    (advice-add #'corfu--popup-hide :after #'lsp-bridge--completion-hide-advisor)

    (corfu-doc-mode 1)

    ;; Flag `lsp-bridge-is-starting' make sure only call `lsp-bridge-start-process' once.
    (unless lsp-bridge-is-starting
      (lsp-bridge-start-process))

    (when (and lsp-bridge-enable-signature-help
               (null lsp-bridge-signature-help-timer))
      (setq lsp-bridge-signature-help-timer
            (run-with-idle-timer lsp-bridge-signature-help-fetch-idle t #'lsp-bridge-signature-help-fetch)))

    )))

(defun lsp-bridge--disable ()
  "Disable LSP Bridge mode."
  (kill-local-variable 'corfu-auto-prefix)
  (kill-local-variable 'corfu-auto)
  (kill-local-variable 'corfu-preview-current)

  (and corfu-auto (add-hook 'post-command-hook #'corfu--auto-post-command nil 'local))

  (advice-remove #'corfu--popup-hide #'lsp-bridge--completion-hide-advisor)

  (dolist (hook lsp-bridge--internal-hooks)
    (remove-hook (car hook) (cdr hook) t))

  (corfu-doc-mode -1))

(defun lsp-bridge-turn-off (filepath)
  (lsp-bridge--with-file-buffer filepath
    (lsp-bridge--disable)))

(defun lsp-bridge-diagnostics-fetch ()
  (when (and lsp-bridge-mode
             lsp-bridge-enable-diagnostics
             (process-live-p lsp-bridge-server)
             (not (lsp-bridge-completion-ui-visible-p))
             (buffer-file-name))
    (when (string-equal (file-truename (buffer-file-name)) lsp-bridge-filepath)
      (lsp-bridge-call-file-api "pull_diagnostics"))))

(defun lsp-bridge-diagnostics-render (filepath diagnostics)
  (lsp-bridge--with-file-buffer filepath
    (when lsp-bridge-diagnostic-overlays
      (dolist (diagnostic-overlay lsp-bridge-diagnostic-overlays)
        (delete-overlay diagnostic-overlay)))

    (setq lsp-bridge-diagnostic-overlays nil)

    (let ((diagnostic-index 0)
          (diagnostic-number (length diagnostics)))
      (dolist (diagnostic diagnostics)
        (let* ((diagnostic-start (lsp-bridge--lsp-position-to-point (plist-get (plist-get diagnostic :range) :start)))
               (diagnostic-end (lsp-bridge--lsp-position-to-point (plist-get (plist-get diagnostic :range) :end)))
               (overlay (if (eq diagnostic-start diagnostic-end)
                            ;; Adjust diagnostic end position if start and end is same position.
                            (make-overlay diagnostic-start (1+ diagnostic-start))
                          (make-overlay diagnostic-start diagnostic-end)))
               (severity (plist-get diagnostic :severity))
               (message (plist-get diagnostic :message))
               (overlay-face (cl-case severity
                               (1 'lsp-bridge-diagnostics-error-face)
                               (2 'lsp-bridge-diagnostics-warning-face)
                               (3 'lsp-bridge-diagnostics-info-face)
                               (4 'lsp-bridge-diagnostics-hint-face))))
          (overlay-put overlay 'face overlay-face)
          (overlay-put overlay
                       'help-echo
                       (if (> diagnostic-number 1)
                           (format "[%s:%s] %s" (1+ diagnostic-index) diagnostic-number message)
                         message))
          (push  overlay lsp-bridge-diagnostic-overlays))

        (setq diagnostic-index (1+ diagnostic-index))))
    (setq lsp-bridge-diagnostic-overlays (reverse lsp-bridge-diagnostic-overlays))))

(defvar lsp-bridge-diagnostic-frame nil)

(defun lsp-bridge-show-diagnostic-tooltip (diagnostic-overlay)
  (let* ((diagnostic-info (overlay-get diagnostic-overlay 'help-echo))
         (foreground-color (plist-get (face-attribute (overlay-get diagnostic-overlay 'face) :underline) :color)))
    (goto-char (overlay-start diagnostic-overlay))

    (with-current-buffer (get-buffer-create lsp-bridge-diagnostic-tooltip)
      (erase-buffer)
      (insert diagnostic-info))

    (when (posframe-workable-p)
      ;; Perform redisplay make sure posframe can poup to
      (redisplay 'force)
      (sleep-for 0.01)
      (setq lsp-bridge-diagnostic-frame
            (posframe-show lsp-bridge-diagnostic-tooltip
                           :position (point)
                           :internal-border-width lsp-bridge-diagnostic-tooltip-border-width
                           :background-color (lsp-bridge-frame-background-color)
                           :foreground-color foreground-color
                           )))))

(defun lsp-bridge-in-diagnostic-overlay-area-p (overlay)
  (and
   lsp-bridge-diagnostic-frame
   (not (frame-visible-p lsp-bridge-diagnostic-frame))
   (>= (point) (overlay-start overlay))
   (<= (point) (overlay-end overlay))))

(defun lsp-bridge-jump-to-next-diagnostic ()
  (interactive)
  (if (zerop (length lsp-bridge-diagnostic-overlays))
      (message "[LSP-Bridge] No diagnostics.")
    (if-let ((diagnostic-overlay (cl-find-if
                                  (lambda (overlay)
                                    (or (< (point) (overlay-start overlay))
                                        ;; Show diagnostic information around cursor if diagnostic frame is not visiable.
                                        (lsp-bridge-in-diagnostic-overlay-area-p overlay)))
                                  lsp-bridge-diagnostic-overlays)))
        (lsp-bridge-show-diagnostic-tooltip diagnostic-overlay)
      (message "[LSP-Bridge] Reach last diagnostic."))))

(defun lsp-bridge-jump-to-prev-diagnostic ()
  (interactive)
  (if (zerop (length lsp-bridge-diagnostic-overlays))
      (message "[LSP-Bridge] No diagnostics."))
  (if-let ((diagnostic-overlay (cl-find-if
                                (lambda (overlay)
                                  (or (> (point) (overlay-end overlay))
                                      ;; Show diagnostic information around cursor if diagnostic frame is not visiable.
                                      (lsp-bridge-in-diagnostic-overlay-area-p overlay)))
                                (reverse lsp-bridge-diagnostic-overlays))))
      (lsp-bridge-show-diagnostic-tooltip diagnostic-overlay)
    (message "[LSP-Bridge] Reach first diagnostic.")))

(defun lsp-bridge-update-completion-item-info (info)
  (let* ((filepath (plist-get info :filepath))
         (label (plist-get info :label))
         (additional-text-edits (plist-get info :additionalTextEdits))
         (documentation (plist-get info :documentation)))
    (lsp-bridge--with-file-buffer filepath
      ;; Update `documentation' and `additionalTextEdits'
      (when-let (item (lsp-bridge-get-candidate-item label))
        (when additional-text-edits
          (plist-put item :additionalTextEdits additional-text-edits))

        (unless (string-equal documentation "")
          (plist-put item :documentation documentation))

        (puthash label item lsp-bridge-completion-candidates))

      ;; Popup documentation window if same documentation window not exist.
      (unless (string-equal label lsp-bridge-completion-item-popup-doc-tick)
        (lsp-bridge-popup-completion-item-doc documentation))
      )))

(defun lsp-bridge-popup-completion-item-doc (documentation)
  (unless (string-equal documentation "")
    (unless (corfu--popup-support-p)
      (error "Corfu-doc requires child frames to display documentation."))
    (when (corfu-doc--should-show-popup) ;;  TODO: check if current index is the same for the documentation
      (when-let ((candidate (corfu-doc--get-candidate))
                 (cf-popup-edges (corfu-doc--get-cf-popup-edges)))
        (if (corfu-doc--should-refresh-popup candidate)
            (corfu-doc--refresh-popup)
          (corfu-doc--update-popup documentation)
          (with-current-buffer (get-buffer-create " *corfu-doc*")
            (lsp-bridge-render-markdown-content))
          (corfu-doc--set-vars
           candidate cf-popup-edges (selected-window))
          )))))

(defun lsp-bridge-render-markdown-content ()
  (let ((inhibit-message t))
    (if (fboundp 'gfm-view-mode)
        (gfm-view-mode)
      (gfm-mode)))
  (setq-local mode-line-format nil) ;; Hide mode-line for corfu-doc buffer.
  (display-line-numbers-mode -1)
  (read-only-mode 0)
  (font-lock-ensure))

;;;###autoload
(defun global-lsp-bridge-mode ()
  (interactive)

  (setq corfu-auto t)

  (dolist (hook lsp-bridge-default-mode-hooks)
    (add-hook hook (lambda ()
                     (corfu-mode 1)
                     (lsp-bridge-mode 1)
                     )))

  (when lsp-bridge-enable-diagnostics
    (setq lsp-bridge-diagnostics-timer
          (run-with-idle-timer lsp-bridge-diagnostics-fetch-idle t #'lsp-bridge-diagnostics-fetch)))

  (when lsp-bridge-enable-signature-help
    (setq lsp-bridge-signature-help-timer
          (run-with-idle-timer lsp-bridge-signature-help-fetch-idle t #'lsp-bridge-signature-help-fetch))))

(with-eval-after-load 'evil
  (evil-add-command-properties #'lsp-bridge-find-def :jump t)
  (evil-add-command-properties #'lsp-bridge-find-references :jump t)
  (evil-add-command-properties #'lsp-bridge-find-impl :jump t))

(defun lsp-bridge--rename-file-advisor (orig-fun &optional arg &rest args)
  (when lsp-bridge-mode
    (let ((new-name (expand-file-name (nth 0 args))))
      (lsp-bridge-call-file-api "rename_file" new-name)
      (lsp-bridge-call-async "close_file" lsp-bridge-filepath)
      (set-visited-file-name new-name t t)
      (setq lsp-bridge-filepath new-name)))
  (apply orig-fun arg args))
(advice-add #'rename-file :around #'lsp-bridge--rename-file-advisor)

(defun lsp-bridge--monitor-candidate-select-advisor (&rest args)
  (when (and lsp-bridge-mode
             lsp-bridge-enable-candidate-doc-preview
             lsp-bridge-completion-resolve-provider
             (not (null lsp-bridge-completion-candidates))
             (member (nth corfu--index corfu--candidates) (hash-table-keys lsp-bridge-completion-candidates))) ;; Check whether current candidate comes from lsp-bridge
    (lsp-bridge-completion-item-fetch (nth corfu--index corfu--candidates))))
(advice-add #'corfu--goto :after #'lsp-bridge--monitor-candidate-select-advisor)
(advice-add #'corfu--popup-show :after #'lsp-bridge--monitor-candidate-select-advisor)

(defvar-local lsp-bridge-completion-item-fetch-tick nil)
(defvar-local lsp-bridge-completion-item-popup-doc-tick nil)

(defun lsp-bridge-completion-item-fetch (label)
  (let* ((candidate-info (gethash label lsp-bridge-completion-candidates))
         (candidate (string-trim label))
         (kind (plist-get candidate-info :kind))
         (documentation (plist-get candidate-info :documentation)))

    ;; Popup candidate documentation directly if `documentation' is exist in candidate.
    (when documentation
      (setq-local lsp-bridge-completion-item-popup-doc-tick label)
      (lsp-bridge-popup-completion-item-doc documentation))

    ;; Try send `completionItem/resolve' request to fetch `documentation' and `additionalTextEdits' information.
    (unless (equal lsp-bridge-completion-item-fetch-tick (list lsp-bridge-filepath label kind))
      (lsp-bridge-call-async "fetch_completion_item_info" lsp-bridge-filepath label (format "%s,%s" candidate kind))
      (setq lsp-bridge-completion-item-fetch-tick (list lsp-bridge-filepath label kind)))))

(defun lsp-bridge--completion-hide-advisor (&rest args)
  (when lsp-bridge-mode
    ;; Hide completion ui.
    (lsp-bridge-call-file-api "completion_hide")

    ;; Clean completion item tick.
    (setq-local lsp-bridge-completion-item-fetch-tick nil)
    (setq-local lsp-bridge-completion-item-popup-doc-tick nil)
    ))

(defun lsp-bridge-list-workspace-symbols ()
  (interactive)
  (lsp-bridge-call-file-api "workspace_symbol" ""))

(defun lsp-bridge-show-workspace-symbols (info)
  (if (zerop (length info))
      (message "LSP server did not return any symbols.")
    (let* ((symbols (mapcar (lambda (i) (plist-get i :name)) info))
           match-symbol
           match-info)
      (setq match-symbol (completing-read "Workspace symbol: " symbols))
      (setq match-info (seq-filter (lambda (i) (string-equal match-symbol (plist-get i :name))) info))
      (when match-info
        (let* ((file-info (plist-get (car match-info) :location))
               (file-path (url-unhex-string (string-remove-prefix "file://" (format "%s" (plist-get file-info :uri)))))
               (file-range (plist-get file-info :range))
               (match-line (plist-get (plist-get file-range :start) :line))
               (match-column (plist-get (plist-get file-range :start) :character)))
          (find-file file-path)
          (lsp-bridge-ref-move-to-point (+ match-line 1) match-column)
          )))))

(defun lsp-bridge-code-action (&optional action-kind)
  (interactive)
  (lsp-bridge-call-file-api "code_action" (lsp-bridge-get-range-start) (lsp-bridge-get-range-end) action-kind))

(defvar-local lsp-bridge-code-action-notify nil)

(defun lsp-bridge-auto-format-code ()
  (unless (eq last-command 'mwheel-scroll)
    (lsp-bridge-code-format)))

(defun lsp-bridge-code-format ()
  (interactive)
  (when (and
         ;; Current buffer has LSP server.
         (lsp-bridge-has-lsp-server-p)
         ;; Completion menu not show.
         (not (lsp-bridge-completion-ui-visible-p))
         ;; Yasnippet not active.
         (or (not (boundp 'yas--active-snippets))
             (not yas--active-snippets))
         ;; Tempel not active.
         (or (not (boundp 'tempel--active))
             (not tempel--active)))
    (lsp-bridge-call-file-api "formatting" (symbol-value (lsp-bridge--get-indent-width major-mode)))))

(defun lsp-bridge-code-format-fix (filepath edits)
  (lsp-bridge-file-apply-edits filepath edits)
  (message "[LSP-BRIDGE] Complete code formatting."))

(defvar lsp-bridge-english-helper-dict nil)

(defun lsp-bridge-code-action-fix (actions action-kind)
  (let* ((menu-items
          (or
           (mapcar #'(lambda (action)
                       (when (or (not action-kind)
                                 (equal action-kind (plist-get action :kind)))
                         (cons (plist-get action :title) action)))
                   actions)
           (apply #'error
                  (if action-kind
                      (format "No '%s' code action here" action-kind)
                    "No code actions here"))))
         (preferred-action (cl-find-if
                            (lambda (menu-item)
                              (plist-get (cdr menu-item) :isPreferred))
                            menu-items))
         (default-action (car (or preferred-action (car menu-items))))
         (action (if (and action-kind (null (cadr menu-items)))
                     (cdr (car menu-items))
                   (cdr (assoc (completing-read
                                (format "[LSP-BRIDGE] Pick an action (default: %s): " default-action)
                                menu-items nil t nil nil default-action)
                               menu-items)))))

    (let* ((command (plist-get action :command))
           (edit (plist-get action :edit)))
      (cond (edit
             (lsp-bridge-workspace-apply-edit edit))
            (command
             (let (arguments)
               ;; Pick command and arguments.
               (cond ((consp command)
                      (setq arguments (plist-get command :arguments))
                      (setq command (plist-get command :command)))
                     ((stringp command)
                      (setq arguments (plist-get action :arguments))))

               (if (member command lsp-bridge-apply-edit-commands)
                   ;; Apply workspace edit if command match `lsp-bridge-apply-edit-commands'.
                   (dolist (argument arguments)
                     (lsp-bridge-workspace-apply-edit argument))
                 ;; Otherwise send `workspace/executeCommand' request to LSP server.
                 (lsp-bridge-call-file-api "execute_command" command)))))
      (message "[LSP-BRIDGE] Execute code action '%s'" (plist-get action :title)))))

(defun lsp-bridge-file-apply-edits (filepath edits &optional just-reverse)
  (if (string-match "^/[A-Za-z]:" filepath)
      (setq filepath (substring filepath 1)))
  (find-file-noselect filepath)
  (save-excursion
    (find-file filepath)
    (lsp-bridge--apply-text-edits edits))

  (setq-local lsp-bridge-prohibit-completion t))

(defun lsp-bridge-workspace-apply-edit (edit)
  (let (changes filepath edits)
    (cond ((plist-get edit :changes)
           (setq changes (plist-get edit :changes))
           (setq filepath (string-remove-prefix ":file://" (format "%s" (nth 0 changes))))
           (setq edits (nth 1 changes)))
          ((plist-get edit :documentChanges)
           (setq changes (plist-get edit :documentChanges))
           (setq filepath (string-remove-prefix "file://" (plist-get (plist-get (nth 0 changes) :textDocument) :uri)))
           (setq edits (plist-get (nth 0 changes) :edits))))
    (lsp-bridge-file-apply-edits filepath edits)))

(defun lsp-bridge-get-range-start ()
  (lsp-bridge--point-position
   (or (if (region-active-p)
           (region-beginning)
         (point))
       (point))))

(defun lsp-bridge-get-range-end ()
  (lsp-bridge--point-position
   (or (if (region-active-p)
           (region-end)
         (point))
       (point))))


;; https://tecosaur.github.io/emacs-config/config.html#lsp-support-src
(cl-defmacro lsp-org-babel-enable (lang)
  "Support LANG in org source code block."
  (cl-check-type lang stringp)
  (let* ((edit-pre (intern (format "org-babel-edit-prep:%s" lang)))
         (intern-pre (intern (format "lsp--%s" (symbol-name edit-pre)))))
    `(progn
       (defun ,intern-pre (info)
         (let ((file-name (->> info caddr (alist-get :file))))
           (unless file-name
             (setq file-name (make-temp-file "babel-lsp-")))
           (setq buffer-file-name file-name)
           (lsp-bridge-mode 1)))
       (put ',intern-pre 'function-documentation
            (format "Enable lsp-bridge-mode in the buffer of org source block (%s)."
                    (upcase ,lang)))
       (if (fboundp ',edit-pre)
           (advice-add ',edit-pre :after ',intern-pre)
         (progn
           (defun ,edit-pre (info)
             (,intern-pre info))
           (put ',edit-pre 'function-documentation
                (format "Prepare local buffer environment for org source block (%s)."
                        (upcase ,lang))))))))

(with-eval-after-load 'org
  (dolist (lang lsp-bridge-org-babel-lang-list)
    (eval `(lsp-org-babel-enable ,lang))))


;;; project
;; Currently only `project.el' is supported. PR about `projectile' or others are welcome.
(defun lsp-bridge-project-root (&optional dir)
  "Return the project root of DIR."
  (when-let* ((default-directory (or dir default-directory))
              (project (project-current)))
    (expand-file-name (if (fboundp 'project-root)
                          (project-root project)
                        (cdr project)))))

;;; xref

(defvar lsp-bridge--xref-wait-for nil
  "To judge whether we are waiting for the results.")
(defvar lsp-bridge--xref-locations nil
  "A list of (filename line column . content) for xref.")

;;;###autoload
(defun lsp-bridge-xref-backend ()
  "LSP Bridge backend for Xref."
  'lsp-bridge)

(cl-defmethod xref-backend-identifier-at-point ((_backend (eql lsp-bridge)))
  (symbol-name (symbol-at-point)))

(defun lsp-bridge--xref-do (action)
  "Call the actual asynchronous function according to ACTION and wait for the results."
  (setq lsp-bridge--xref-wait-for (lsp-bridge--position))
  (pcase action
    ('find-definitions
     (lsp-bridge-find-def))
    ('find-references
     (lsp-bridge-find-references)))
  (let ((sleep-time 0))
    (while (and lsp-bridge--xref-wait-for
                (< sleep-time 2)) ;;  HACK: wait for 2 seconds
      (sleep-for 0.05)
      (setq sleep-time (+ sleep-time 0.05))))
  (if lsp-bridge--xref-wait-for
      (setq lsp-bridge--xref-wait-for nil)
    (seq-map
     (lambda (candidate)
       (xref-make (if (> (length candidate) 3)
                      (nth 3 candidate)
                    'match)
                  (xref-make-file-location (nth 0 candidate)
                                           (nth 1 candidate)
                                           (nth 2 candidate))))
     lsp-bridge--xref-locations)))

(defun lsp-bridge--xref-highlight-references (content)
  "Remove unwanted substrings and add face for reference in CONTENT."
  (let ((loop t)
        (keys '("\033[94m" "\033[0m"))
        (index 0)
        (pos '())
        (content content))
    (while loop
      (setq current-pos (string-search (nth index keys) content))
      (if (null current-pos)
          (setq loop nil)
        (setq content
              (concat (substring content 0 current-pos)
                      (substring content (+ current-pos (length (nth index keys))))
                      ))
        (push current-pos pos)
        (unless (= index 0)
          (add-face-text-property (nth 0 pos) (nth 1 pos)
                                  'xref-match t content)
          (setq pos '()))
        (setq index (% (1+ index) 2))))
    content))

(defun lsp-bridge--xref-reference-content-to-mark (references-content)
  "Turn the REFERENCES-CONTENT of string into the list of (filename line column content)."
  (let* ((num 0)
         (content (split-string references-content "\n"))
         (len (length content))
         (current-file)
         (results '()))
    (while (< num len)
      (let ((str (nth num content)))
        (cond
         ((string-prefix-p "\033[95m" str)
          (setq current-file (substring str 5 (- (length str) 4))))
         ((and current-file str (> (length str) 0))
          (let* ((p1 (string-search ":" str))
                 (p2 (string-search ":" str (1+ p1)))
                 (line (substring str 0 p1))
                 (col (substring str (1+ p1) p2))
                 (content (substring str (1+ p2)))
                 (content (lsp-bridge--xref-highlight-references content)))
            (push (list current-file
                        (string-to-number line)
                        (string-to-number col)
                        content)
                  results)))))
      (setq num (1+ num)))
    results))

(cl-defmethod xref-backend-definitions ((_backend (eql lsp-bridge)) _)
  (lsp-bridge--xref-do 'find-definitions))

(cl-defmethod xref-backend-references ((_backend (eql lsp-bridge)) _)
  (lsp-bridge--xref-do 'find-references))

(cl-defmethod xref-backend-identifier-completion-table ((_backend (eql lsp-bridge)))
  nil)

;;; Mode-line
;;;

(defface lsp-bridge-alive-mode-line
  '((t (:inherit font-lock-constant-face :weight bold)))
  "Face for activity in LSP-bridge's mode line.")

(defface lsp-bridge-kill-mode-line
  '((t (:inherit font-lock-comment-face :weight bold)))
  "Face for kill process in LSP-bridge's mode line.")

(defvar lsp-bridge--mode-line-format `(:eval (lsp-bridge--mode-line-format)))

(put 'lsp-bridge--mode-line-format 'risky-local-variable t)

(defun lsp-bridge--mode-line-format ()
  "Compose the LSP-bridge's mode-line."
  (if (lsp-bridge-epc-live-p lsp-bridge-epc-process)
      (setq-local mode-face 'lsp-bridge-alive-mode-line)
    (setq-local mode-face 'lsp-bridge-kill-mode-line))
  (when lsp-bridge-server
    (propertize (format "lsp-bridge:%s" lsp-bridge-server-port) 'face mode-face)))

(when lsp-bridge-enable-show-in-mode-line
  (add-to-list 'mode-line-misc-info
               `(lsp-bridge-mode (" [" lsp-bridge--mode-line-format "] "))))


(provide 'lsp-bridge)

;;; lsp-bridge.el ends here
