;;; lgit.el --- a little GIT mode, or lomew's GIT mode

;; Copyright (C) 2006 Bart Robinson <lomew@pobox.com>

;; Author: Bart Robinson <lomew@pobox.com>
;; Created: Sep 2006
;; Version: trunk ($Revision$)
(defconst lgit-version "trunk")
;; Date: the-date
;; Keywords: git

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 675 Mass Ave, Cambridge, MA 02139, USA.

;;; Commentary:

;; todo
;; - see git.el in contrib/emacs, similar to pcl-cvs
;; - can use git apply --cached --recount to apply individual hunks
;; - can leverage emacs' diff-mode hunk splitting, which seems more
;;   powerful than the 's' command in interactive add
;; - example rename output after git mv:
;;    R  global/cfg_spec.xml -> config/cfg_spec.xml
;;    R  global/dynamic_spec.xml -> config/dynamic_spec.xml
;;    R  global/securevault_spec.xml -> config/securevault_spec.xml
;;    R  global/protobuf_header.h -> valib/protobuf_header.h


;; blah blah blah
;; (setq lgit-commit-template "BugID: \nCC: \nApproved-by: \nReviewed-by: \n")


;; User vars.

(defvar lgit-git-command "git"
  "*How to call git.")

;; XXX/lomew todo
(defvar lgit-explain-each-line nil
  "*If non-nil lgit-mode will print a message in the echo area
describing the current line.  This info is always available with
the \\[lgit-explain-this-line] command.")

(defvar lgit-use-view-mode nil
  "*If non nil, lgit will use view-mode in log, status, etc, buffers.")

(defvar lgit-use-diff-mode t
  "*If non nil, lgit will put diff buffers into diff-mode (if available).")
;; XXX/lomew diff-cmd/args

(defvar lgit-commit-template nil
  "*If non nil, default text to put in commit buffers")

(defvar lgit-temp-file-directory
  (or (getenv "TMPDIR")
      (and (file-directory-p "/tmp") "/tmp")
      (and (file-directory-p "C:\\TEMP") "C:\\TEMP")
      (and (file-directory-p "C:\\") "C:\\")
      "/tmp")
  "*Name of a directory where lgit can put temporary files.")

(defvar lgit-discard-confirm t
  "*If non-nil, discarding unstaged changes will require confirmation.")

(defvar lgit-resolve-confirm t
  "*If non-nil, resolving files will require confirmation.")

(defvar lgit-commit-mode-hook nil
  "*Hook to run upon entry to `lgit-commit-mode'.")

;; XXX/lomew revisit all this font-lock crap for tty and dark
;; backgrounds.  Took some ideas from pgit.

(defgroup lgit-faces nil
  "lgit faces"
  :group 'lgit)

(defface lgit-marked-face
  '((((class color) (background light))
     (:background "yellow2" :weight bold :bold t))
    (((class color) (background dark))
     (:background "yellow4" :weight bold :bold t))
    (t
     (:weight bold :bold t)))
  "Face to highlight marked lines."
  :group 'lgit-faces)
;; Hack to work with FSF Emacs.
(defvar lgit-marked-face 'lgit-marked-face)

(defface lgit-conflicted-face
  '((((class color) (background light))
     (:foreground "darkred" :weight bold :bold t))
    (((class color) (background dark))
     (:foreground "lightred" :weight bold :bold t))
    (t
     (:weight bold :bold t)))
  "Face to highlight conflicted lines."
  :group 'lgit-faces)
;; Hack to work with FSF Emacs.
(defvar lgit-conflicted-face 'lgit-conflicted-face)

(defface lgit-outofdate-face
  '((((class color) (background light))
     (:foreground "green4" :weight bold :bold t))
    (((class color) (background dark))
     (:foreground "yellow" :weight bold :bold t))
    (t
     (:weight bold :bold t)))
  "Face to highlight out-of-date lines."
  :group 'lgit-faces)
;; Hack to work with FSF Emacs.
(defvar lgit-outofdate-face 'lgit-outofdate-face)

(defface lgit-modified-face
  '((((class color) (background light))
     (:foreground "royalblue" :weight bold :bold t))
    (((class color) (background dark))
     (:foreground "lightblue" :weight bold :bold t))
    (t
     (:weight bold :bold t)))
  "Face to highlight modified lines."
  :group 'lgit-faces)
;; Hack to work with FSF Emacs.
(defvar lgit-modified-face 'lgit-modified-face)

(defvar lgit-common-font-lock-keywords
  '(
    ("^[MDART].*"	. lgit-modified-face)
    ("^.[MT].*"		. lgit-modified-face)
    ("^C.*"		. lgit-conflicted-face)
    ("^.C.*"		. lgit-conflicted-face)
    ))
(defvar lgit-status-font-lock-keywords
  (append
   '(
     ("^..\\*.*"	. lgit-marked-face)
     )
   lgit-common-font-lock-keywords))
(defvar lgit-ustatus-font-lock-keywords	;XXX/lomew unuesd
  (append
   '(
     ("^....................?\\*.*" . lgit-marked-face)
     ("^........?\\*.*" . lgit-outofdate-face)
     )
   lgit-common-font-lock-keywords))


;; Internal Vars.

;; The version of the git program.  We figure this out when our mode
;; gets started.
(defconst lgit-git-major-version nil)
(defconst lgit-git-minor-version nil)
(make-variable-buffer-local 'lgit-major-git-version)
(make-variable-buffer-local 'lgit-minor-git-version)

;; Specifies what to search for when looking for the filename
;; in "git status" output.  Also takes into account the characters
;; we add for marked files.
;; The parens are assumed to enclose the state information.
(defconst lgit-status-linepat "^\\([ IMADRCUT?][ WMADRCUT?]\\)[ *]")

;; Line pattern appropriate for this buffer.
(defconst lgit-linepat nil)
(make-variable-buffer-local 'lgit-linepat)

;; A dummy line format we use to represent a directory.  We insert
;; this into the output so they can run log or diff on it and have it
;; apply to the dir.  The dir comes after this line.
(defconst lgit-status-dummy-line         "IW ")

;; Dummy line appropriate for this buffer.
(defconst lgit-dummy-line nil)
(make-variable-buffer-local 'lgit-dummy-line)

;; The last dir we examined/updated.
(defconst lgit-last-dir nil)

(defvar lgit-debug nil
  "If non-nil, put lgit into debug mode.")

(defconst lgit-mode-map
  (let ((map (make-sparse-keymap 'lgit-mode-map)))
    (define-key map "?" 'lgit-explain-this-line)
    (define-key map "n" 'lgit-next-line)
    (define-key map "p" 'lgit-prev-line)
    (define-key map "m" 'lgit-mark-file)
    (define-key map "u" 'lgit-unmark-file)
    (define-key map " " 'scroll-other-window)
;    (define-key map "U" 'lgit-update-some-files)
    (define-key map "R" 'lgit-discard)
;    (define-key map "V" 'lgit-resolve)
    (define-key map "C" 'lgit-commit)
    (define-key map "d" 'lgit-diff-base)
    (define-key map "D" 'lgit-diff-staged)
;    (define-key map "e" 'lcvs-ediff)
;    (define-key map "l" 'lgit-log-base) ***
;    (define-key map "L" 'lgit-log-head) ***
;    (define-key map "s" 'lcvs-show-status)
;    (define-key map "S" 'lgit-sort)
;    (define-key map "a" 'lcvs-annotate)
    (define-key map "g" 'lgit-refresh-buffer)
    (define-key map "G" 'lgit-status)
    (define-key map "f" 'lgit-find-file)
    (define-key map "\C-m" 'lgit-find-file)
    (define-key map "o" 'lgit-find-file-other-window)
    (define-key map "q" 'lgit-quit-just-bury)
    (define-key map "+" 'lgit-add)
    (define-key map "-" 'lgit-unstage)
    (define-key map "B" 'lgit-checkout-branch)
;    (define-key map "-" 'lcvs-remove-crap)
;    (define-key map "\C-k" 'lcvs-kill-region-or-line)
;    (define-key map "\C-w" 'lcvs-kill-region)
;    (define-key map "\C-xu" 'lcvs-undo)
;    (define-key map "\C-xc" 'lcvs-clean)
;    (condition-case ()
;	 ;; This is for XEmacs, will error in Emacs.
;	 (define-key map '(control /) 'lcvs-undo)
;      (error nil))
    (define-key map "\C-c\C-k" 'lgit-kill-process)
    map)
  "Keymap for `lgit-mode'")

(defconst lgit-view-mode-commands
  '("annotate" "log")
  "List of CVS commands that get their output put into view-mode.")

(defconst lgit-lots-of-dashes (make-string 72 ?-)
  "A long string of dashes.")

(defconst lgit-inserted-final-dashes nil
  "If we inserted the final dashes.")
(make-variable-buffer-local 'lgit-inserted-final-dashes)

(defconst lgit-marked-files nil
  "Alist of marked files.  It is in the form `\(file . status)'.")
(make-variable-buffer-local 'lgit-marked-files)

(defconst lgit-submode nil
  "The submode for `lgit-mode' for this buffer.")
(make-variable-buffer-local 'lgit-submode)

(defconst lgit-head-revision-markers nil
  "An alist of (marker . headrev) pairs.
This gives the ability to map a point to the appropriate HEAD revision
in ustatus mode.")
(make-variable-buffer-local 'lgit-head-revision-markers)


;; User functions.

(defun lgit-status (dir &optional show-updates want-fresh-buf)
  "Call \"git status\" in DIR and then call `lgit-mode' (which see).
Optional arg SHOW-UPDATES (interactive prefix arg) means to
pass \"-u/--show-updates\" and show updatable files.
Optional WANT-FRESH-BUF means don't reuse an existing buffer visiting
the same directory."
  (interactive (list (expand-file-name
		      (file-name-as-directory
		       (lgit-read-directory-name (concat "GIT status"
							 (if current-prefix-arg
							     " -u")
							 " for directory: ")
						 lgit-last-dir
						 lgit-last-dir t)))
		     current-prefix-arg))
  ;; Have to run it from the top of the repository.  Otherwise the paths
  ;; that come out of --porcelain are incorrect
  (if (not (file-directory-p (concat dir ".git")))
      (error "%s does not contain a git repository" dir))
  (setq lgit-last-dir dir)
  (let* ((basename (file-name-nondirectory (directory-file-name dir)))
	 (bufname (format "*GIT-status-%s*" basename))
	 (procname (format "git-status-%s" basename))
	 (buf (get-buffer bufname))
	 (cmd (if show-updates
		  (list "echo" "not implemented")
		;; XXX/lomew use -z to deal with filenames containing spaces
		;; would require hacking the output before display
		(list lgit-git-command "status" "--porcelain")))
	 proc)
    ;; Use an existing buffer if it is "visiting" the same dir.
    (if (and (not want-fresh-buf)
	     buf
	     (string-equal (save-excursion
			     (set-buffer buf)
			     default-directory)
			   dir))
	(pop-to-buffer buf)
      ;; Else make one.
      (setq buf (get-buffer-create bufname))
      (save-excursion
	;; Check for existing process.
	(if (and (get-buffer-process buf)
		 (eq (process-status (get-buffer-process buf)) 'run))
	    (error "%s process already running" procname))

	(set-buffer buf)
	(setq default-directory dir)

	;; Set up keybindings etc.
	(lgit-mode (if show-updates 'ustatus 'status))

	;; Prepare the buffer.
	;; lgit-mode makes the buffer read-only, so we have to take that
	;; into account here (and we might be called from lgit-refresh-buffer).
	(unwind-protect
	    (let ((info (lgit-info))
		  (buffer-read-only nil))
	      (buffer-disable-undo (current-buffer))
	      (erase-buffer)
	      (insert "In " dir "\n")
	      (insert "On branch " (lgit-current-branch) "\n")
	      (insert "\n")
	      (insert "$ " (mapconcat 'identity cmd " ") "\n")
	      (insert lgit-lots-of-dashes "\n")
	      ;; Insert a dummy line for the cwd they can run 'log' on.
	      (insert lgit-dummy-line ".\n"))
	  (buffer-enable-undo (current-buffer)))

	;; Make the buffer visible and start the process.
	(pop-to-buffer buf)
	(goto-char (point-min))
	(setq proc (apply 'start-process procname buf cmd))
	(set-process-filter proc (function lgit-filter))
	(set-process-sentinel proc (function lgit-sentinel))))))

(defun lgit-mode (submode)
  "Major mode for interacting with GIT.
The normal entry point is `lgit-status'.

The hook `lgit-mode-hook', if set, is run upon entry.

The following keys have meaning in an `lgit-mode' buffer:
\\{lgit-mode-map}
Some of the commands can work on marked files via a \\[universal-argument]
prefix; consult the individual documentation for each command
via `describe-key' on \\[describe-key]"
  ;; XXX/lomew completions would be nice, but are hassle since I have to
  ;; define a keymap
  (interactive "SSubmode (status or ustatus): ")
  (if (and (not (eq submode 'status))
	   (not (eq submode 'ustatus)))
      (error "Submode should be status or ustatus"))
  (kill-all-local-variables)
  (let ((ver (lgit-determine-git-version)))
    (setq lgit-git-major-version (car ver))
    (setq lgit-git-minor-version (cdr ver)))
  (setq lgit-linepat    lgit-status-linepat
	lgit-dummy-line lgit-status-dummy-line)
  (setq lgit-marked-files nil)
  (setq lgit-submode submode)
  (use-local-map lgit-mode-map)
  (setq major-mode 'lgit-mode
	mode-name "LGIT")
  (setq modeline-process '(":%s"))
  (setq buffer-read-only t)
  (make-variable-buffer-local 'font-lock-defaults)
  (if (eq submode 'status)
      (setq font-lock-defaults '(lgit-status-font-lock-keywords))
    (setq font-lock-defaults '(lgit-ustatus-font-lock-keywords)))
  (run-hooks 'lgit-mode-hook))

(defun lgit-explain-this-line ()
  "Explain what this line means.  If repeated then offer brief help.
Translates stuff like \"M foo/bar.c\" into something like \"this file has
been locally modified\"."
  (interactive)
  (if (eq last-command 'lgit-explain-this-line)
      (message "m/u mark | d/D(l/L) diff(log) base/head | C commit | R revert | U update | + add")
    (let* ((state (lgit-current-file-state))
	   (res (mapconcat 'symbol-name state ", ")))
      (if (memq 'out-of-date state)
	  (setq res (concat res (format ", BASE is %s"
					(lgit-current-file-base)))))
      (setq res (concat res (format ", HEAD is %s" (lgit-head-revision))))
      (message res))))

(defun lgit-next-line ()
  "Move cursor to the next file."
  (interactive)
  (if (re-search-forward lgit-linepat nil t)
      (if lgit-explain-each-line
	  (lgit-explain-this-line))
    (error "No more files")))

(defun lgit-prev-line ()
  "Move cursor to the previous file."
  (interactive)
  (let ((pt (point)))
    (beginning-of-line)
    (if (re-search-backward lgit-linepat nil t)
	(progn 
	  (goto-char (match-end 0))
	  (if lgit-explain-each-line
	      (lgit-explain-this-line)))
      (goto-char pt)
      (error "No more files"))))

(defun lgit-refresh-buffer (arg)
  "Re-get the status for this dir.
Prefix arg toggles showing updatable files."
  (interactive "P")
  (let ((want-status (if arg
			 (eq lgit-submode 'status)
		       (eq lgit-submode 'ustatus))))
    (lgit-status default-directory want-status 'fresh)))

(defun lgit-quit-just-bury ()
  "\"Quit\" lgit-mode by burying the buffer."
  (interactive)
  (bury-buffer))

(defun lgit-kill-process ()
  "Kill the git process, if there is one.
We assume the current buffer is the one that is supposed to be running
a git process."
  (interactive)
  (if (get-buffer-process (current-buffer))
      (interrupt-process (get-buffer-process (current-buffer)))
    (error "No git process running")))

(defun lgit-mark-file ()
  "Mark the file on this line for later processing."
  (interactive)
  (lgit-bitch-if-commit-in-progress)
  (let ((file (lgit-current-file))
	(state (lgit-current-file-state)))
    (if (or (string-match "\\.mine$" file)
	    (string-match "\\.r[0-9]+$" file))
	;; XXX/lomew this is kind of lame, but should not bother
	;; anyone.  It makes it easier in lgit-resolve to assume these
	;; aren't in the marked list.
	(error "Cannot mark conflict temporary files"))
    (if (assoc file lgit-marked-files)
	nil
      (lgit-set-mark-state t)
      (setq lgit-marked-files (cons (cons file state) lgit-marked-files))))
  ;; `lgit-next-line' can error if at the end of files.
  (condition-case nil
      (lgit-next-line)
    (error nil)))

(defun lgit-unmark-file ()
  "Remove the file on this line from the list of to-be-processed files.
See also `lgit-mark-file'."
  (interactive)
  (lgit-bitch-if-commit-in-progress)
  (let ((file (lgit-current-file)))
    (if (not (assoc file lgit-marked-files))
	nil
      (lgit-set-mark-state nil)
      (setq lgit-marked-files (lgit-remassoc file lgit-marked-files))))
  ;; `lgit-next-line' can error if at the end of files.
  (condition-case nil
      (lgit-next-line)
    (error nil)))

(defun lgit-diff-base (arg)
  "Diff some files against the BASE revision (what you originally checked out).
Use this when you have locally modified files and want to see what
you have done.  See also `lgit-diff-head'.
If given a prefix argument, use the marked files.  Otherwise use
the file on this line."
  (interactive "P")
  (message "Diffing...")
  (lgit-do-command "diff"
		   "No differences with the working tree"
		   (mapcar 'car (lgit-get-relevant-files arg)))
  (message "Diffing...done"))

(defun lgit-diff-staged (arg)
  "Diff some files against the index revision.
Use this when files have been checked in by someone else and you want
to see what has changed before you update your copies.  See also
`lgit-diff-base'.
If given a prefix argument, use the marked files.  Otherwise use
the file on this line."
  ;; XXX/lomew need to check that we aren't operating on multiple
  ;; externals or lgit-head-revision will not be what we want.
  (interactive "P")
  (message "Diffing...")
  (lgit-do-command "diff"
		   "No differences with the index"
		   (cons "--staged"
			 (mapcar 'car (lgit-get-relevant-files arg))))
  (message "Diffing...done"))

;; XXX/lomew work in -v and --stop-on-copy
;; XXX/lomew work in the repositioning stuff?
;;   this would assume we are logging from beyond BASE
(defun lgit-log-base ()
  "Show log for the current file.  Logs from BASE to the earliest revision."
  (interactive)
  (message "Logging...")
  (lgit-do-command "log"
		   "No output"
		   (list "--limit=100" "-v" (lgit-current-file)))
  (message "Logging...done"))

(defun lgit-log-head ()
  "Shows the log for revisions you would get if you updated this file."
  (interactive)
  (let ((base (lgit-current-file-base)))
    ;; If BASE == HEAD then say no changes.
    (if (and (numberp base)
	     (numberp (lgit-head-revision))
	     (= base (lgit-head-revision)))
	(with-output-to-temp-buffer "*GIT-log*"
	  (princ (format "No changes from %d to %d"
			 base (lgit-head-revision))))
      ;; Otherwise run log.  Note that we show them in reverse
      ;; chronological order.
      (message "Logging...")
      (lgit-do-command "log"
		       "No output"
		       (list "--limit=100" "-v"
			     (format "-r%s:%s"
				     (lgit-head-revision)
				     ;; Don't include BASE itself
				     ;; since we already have that and
				     ;; don't want to show it (in case
				     ;; this file was changed in
				     ;; BASE).
				     (if (numberp base) (1+ base) base))
			     (lgit-current-file)))
      (message "Logging...done"))))

(defun lgit-sort ()
  "Sort the GIT output in this buffer.
This is useful to get files with similar status together."
  (interactive)
  (save-excursion
    (goto-char (point-min))
    ;; Go thru each section bracketed by lgit-lots-of-dashes
    (while (re-search-forward "^----" nil t)
      (let (beg end)
	(forward-line)
	(setq beg (point))
	(if (re-search-forward "^----" nil t)
	    (progn
	      (setq end (match-beginning 0))
	      (forward-line))
	  (setq end (point-max)))
	(let ((buffer-read-only nil))
	  (sort-lines nil beg end))))))

(defun lgit-commit ()
  "Commit the index."
  ;; XXX/lomew maybe later let prefix arg mean commit only the file
  ;; under cursor, see git-commit(1) where it talks about listing
  ;; files to commit
  ;; XXX/lomew confusing error if index is empty
  (interactive)
  (lgit-bitch-if-commit-in-progress)
  (let ((this-buffer (current-buffer)))
    (pop-to-buffer (get-buffer-create "*GIT-commit-message*"))
    (lgit-commit-mode this-buffer)))

(defun lgit-find-file (&optional arg)
  "Find the file on this line, or the marked files if given a prefix arg."
  (interactive "P")
  (mapcar (function (lambda (pair)
		      (if (file-exists-p (car pair))
			  (save-excursion
			    (find-file (car pair))))))
	  (lgit-get-relevant-files arg)))

(defun lgit-find-file-other-window ()
  "Find the file on this line."
  (interactive)
  (let ((file (lgit-current-file)))
    (if (file-exists-p file)
	(find-file-other-window file)
      (error (format "%s not in working copy, probably a new file" file)))))

(defun lgit-add (arg)
  "Schedule unversioned files for addition.
If given a prefix argument, add the marked files.  Otherwise add
the file on this line.
The files won't be actually added to the repository until they are
formally committed."
  (interactive "P")
  (let ((files (lgit-get-relevant-files arg))
	status cur)
    ;; Check thru the files for addable ones.  These are only ?/unversioned ones
    (setq cur files)
    (while cur
      (setq state (cdr (car cur)))
      (setq cur (cdr cur))
      (cond
       ((or (memq 'i-modified state)
	    (memq 'w-modified state)
	    (memq 'untracked state)
	    (and (memq 'w-unmerged state)
		 (memq 'i-unmerged state)))
	nil)
;       ((memq 'deleted state)
;	;; XXX/lomew it would be nice to collect these and then do a git revert
;	;; for them in addition to the add
;	(error (substitute-command-keys
;		"Deleted files can't be added, use revert, on \\[lgit-revert]")))
       (t
	(error "Can only add modified files"))))
    (message "Adding...")
    (setq status (lgit-do-command-quietly "add" (mapcar 'car files)))
    (message "Adding...done")
    (if (zerop status)
	;; " M" -> "M "
	;; "??" -> "A "
	;; Update the diplayed state of the files to "M " from " M"
	;; XXX/lomew would be better to just run git status --porcelain on the individual files
	(let ((cur files)
	      pair file state)
	  (while cur
	    (setq pair (car cur))
	    (setq cur (cdr cur))
	    (setq file (car pair)
		  state (cdr pair))
	    (cond
	     ((memq 'untracked state)		; ?? -> A_
	      (lgit-change-file-index-state file 'i-added))
	     ((memq 'i-unmodified state)	; _x -> Mx
	      (lgit-change-file-index-state file 'i-modified))
	     ((and (memq 'w-unmerged state)     ; UU -> M_
		   (memq 'i-unmerged state))
	      (lgit-change-file-index-state file 'i-modified)))
	    (lgit-change-file-working-state file 'w-unmodified))) ; xx -> x_
      ;; Otherwise an error happened, bitch appropriately
      (pop-to-buffer "*GIT-add*")
      (goto-char (point-min))
      (insert "\n"
	      "*** The add was not completely successful.\n"
	      "*** Check this buffer closely to determine what is wrong.\n"
	      "\n")
      (error "Add failed, see *GIT-add* buffer for details."))))

(defun lgit-update-some-files (arg)
  "Update some files.
If given a prefix arg, update the working copy to HEAD,
otherwise just this file."
  (interactive "P")
  (let ((filename (if arg "." (lgit-current-file)))
	(nconflicts 0)
	update-msg status head-revision)
    (setq head-revision (if (string-equal filename ".")
			    (lgit-top-head-revision)
			  (lgit-head-revision)))
    (setq update-msg (format "Updating %s to %s"
			     (if (string-equal filename ".")
				 "working copy"
			       filename)
			     (if (numberp head-revision)
				 (format "HEAD (%d)" head-revision)
			       "HEAD")))
    (message (format "%s..." update-msg))
    (setq status (lgit-do-command-quietly
		  "update"
		  (list "--non-interactive"
			(format "-r%s" head-revision)
			filename)))
    (message (format "%s...done" update-msg))

;-    (if (zerop status)
;-	;; Go thru each line from the update output and update the
;-	;; status buffer.  
;-	(let ((cur (lgit-parse-update-buffer "*GIT-update*"))
;-	      item file newstate)
;-	  (while cur
;-	    (setq item (car cur))
;-	    (setq file (car item))
;-	    (setq newstate (cdr item))
;-	    (setq cur (cdr cur))
;-	    (if (or (memq 'added newstate)
;-		    (memq 'deleted newstate)
;-		    (memq 'updated newstate))
;-		     props...
;-		(lgit-remove-file-line file)
	      
    (pop-to-buffer "*GIT-update*")
    (goto-char (point-min))
    (insert "\n"
	    "*** XXX/lomew deal with this buffer\n"
	    "\n")))

(defun lgit-unstage (arg)
  "Unstage some files, removing them from the index.
By default unstages the file on this line.
If supplied with a prefix argument, unstage the marked files.
Does the equivalent of \"git reset HEAD file1 file2...\"."
  (interactive "P")
  (let ((files (lgit-get-relevant-files arg))
	status cur)

    ;; Check thru for unstageable ones.
    (setq cur files)
    (while cur
      (setq state (cdr (car cur)))
      (setq cur (cdr cur))
      (cond
       ;; XXX/lomew test other states, added, renamed, etc
       ((or (memq 'i-modified state)
	    (memq 'i-typechange state)
	    (memq 'i-deleted state))
	nil)
       (t
	(error "Can only unstage modified files"))))
    
    (message "Unstaging...")
    (setq status (lgit-do-command-quietly "reset" (append '("-q" "HEAD")
							  (mapcar 'car files))))
    (message "Unstaging...done")

    (if (zerop status)
	;; Update the diplayed state of the files.
	;; "M." -> " M"
	(let ((cur files)
	      pair file)
	  (while cur
	    (setq pair (car cur))
	    (setq cur (cdr cur))
	    (setq file (car pair)
		  state (cdr pair))
	    (lgit-change-file-index-state file 'i-unmodified)
	    (cond ((memq 'i-typechange state)
		   (lgit-change-file-working-state file 'w-typechange))
		  ((memq 'i-modified state)
		   (lgit-change-file-working-state file 'w-modified))
		  ((memq 'i-deleted state)
		   (lgit-change-file-working-state file 'w-deleted)))))
      ;; Otherwise an error happened, bitch appropriately
      (pop-to-buffer "*GIT-reset*")
      (goto-char (point-min))
      (insert "\n"
	      "*** The unstage was not completely successful.\n"
	      "*** Check this buffer closely to determine what is wrong.\n"
	      "\n")
      (error "Add failed, see *GIT-reset* buffer for details."))))

(defun lgit-discard (arg)
  "Discard unstaged changes from some files.
By default affects the file on this line.
If supplied with a prefix argument, affect the marked files.
By default this command requires confirmation.  To
disable the confirmation, you can set `lgit-discard-confirm' to nil.
Does the equivalent of \"git checkout -- file1 file2...\"."
  (interactive "P")
  (let* ((files (lgit-get-relevant-files arg))
	 (multiple-p (cdr files))
	 status)
    (if (and lgit-discard-confirm
	     (not (yes-or-no-p (format "Discard unstaged changes to %s? "
				       (if multiple-p
					   "the marked files"
					 (car (car files)))))))
	(message "Discard cancelled")
      (message "Discarding...")
      (setq status (lgit-do-command-quietly "checkout" (cons "--" (mapcar 'car files))))
      (message "Discarding...done")
      (if (zerop status)
	  ;; Revert some buffers and update the displayed status.
	  ;; "xM" -> "x "
	  (let ((cur files)
		pair file state)
	    (while cur
	      (setq pair (car cur))
	      (setq cur (cdr cur))
	      (setq file (car pair)
		    state (cdr pair))
	      (if (memq 'i-unmodified state)
		  ;; No index changes, remove the line.
		  (lgit-remove-file-line file)
		;; Otherwise just update the state
		(lgit-change-file-working-state file 'w-unmodified))
	      (lgit-revert-buffers-visiting-file file)))
      ;; Otherwise an error happened, bitch appropriately
      (pop-to-buffer "*GIT-checkout*")
      (goto-char (point-min))
      (insert "\n"
	      "*** The discard/checkout was not completely successful.\n"
	      "*** Check this buffer closely to determine what is wrong.\n"
	      "\n")
      (error "Revert failed, see *GIT-checkout* buffer for details.")))))

(defun lgit-resolve (arg)
  "Mark some conflicted files as resolved.
By default applies to the file on this line.
If supplied with a prefix argument, resolve the marked files.
By default this command requires confirmation to resolve the files.  To
disable the confirmation, you can set `lgit-resolve-confirm' to nil."
  (interactive "P")
  (let* ((files (lgit-get-relevant-files arg))
	 (multiple-p (cdr files))
	 status
	 cur state)
    ;; Can only resolve conflicted files.
    (setq cur files)
    (while cur
      (setq state (cdr (car cur)))
      (setq cur (cdr cur))
      (if (or (memq 'conflicted state)
;	      (memq 'tree-conflicted state) ;not tested
	      )
	  nil
	(error "Can only resolve conflicted or tree-conflicted files")))
    ;; Confirm intention.
    (if (and lgit-resolve-confirm
	     (not (yes-or-no-p (format "Resolve %s? "
				       (if multiple-p
					   "the marked files"
					 (car (car files)))))))
	(message "Resolve cancelled")
      (message "Resolving...")
      (setq status (lgit-do-command-quietly "resolved" (mapcar 'car files)))
      (message "Resolving...done")
      (if (zerop status)
	  ;; Update the diplayed state of the files to "M" from "C"
	  ;; XXX/lomew also need to remove the .mine/.rNNN lines
	  (let ((cur files)
		pair)
	    (while cur
	      (setq pair (car cur))
	      (setq cur (cdr cur))
	      (lgit-change-file-state (car pair) 'modified)
	      (lgit-remove-conflict-file-lines (car pair))))
	;; Otherwise an error happened, bitch appropriately
	(pop-to-buffer "*GIT-resolved*")
	(goto-char (point-min))
	(insert "\n"
		"*** The resolve was not completely successful.\n"
		"*** Check this buffer closely to determine what is wrong.\n"
		"\n")
	(error "Resolve, see *GIT-resolved* buffer for details.")))))

(defun lgit-checkout-branch (cmd)
  (interactive
   (list (if current-prefix-arg
	     (read-from-minibuffer "Run git checkout (like this): " "checkout -q ")
	   (concat "checkout -q "
		   (completing-read "Switch to branch: " (lgit-get-local-branches))))))
  (let (status)
    (message "Running git %s..." cmd)
    (setq status (lgit-do-shell-command-quietly cmd))
    (message "Running git %s...done" cmd)
    (if (zerop status)
	(progn
	  (lgit-refresh-buffer nil)
	  (kill-buffer "*GIT-shell*"))
      ;; Otherwise an error happened, bitch appropriately
      (pop-to-buffer "*GIT-shell*")
      (goto-char (point-min))
      (insert "\n"
	      "*** The checkout was not completely successful.\n"
	      "*** Check this buffer closely to determine what is wrong.\n"
	      "\n")
      (error "Checkout, see *GIT-shell* buffer for details."))))
      

;; The committing major mode

(defvar lgit-commit-msgs (make-ring 10)
  "Stores last few commit messages.")
(defvar lgit-commit-msgs-index nil)
(make-variable-buffer-local 'lgit-commit-msgs-index)

(defvar lgit-commit-initial-buffer-contents ""
"Contents of the commit buffer when we initially prepare it.
Used for the commit message ring.")
(make-variable-buffer-local 'lgit-commit-initial-buffer-contents)

(defvar lgit-commit-parent-buffer nil
  "The examine/update mode buffer.
For commit-mode buffers.")
(make-variable-buffer-local 'lgit-commit-parent-buffer)

(defvar lgit-commit-mode-map
  (let ((map (make-sparse-keymap 'lgit-commit-mode-map)))
    (define-key map "\C-c\C-c" 'lgit-commit-finish)
    (define-key map "\M-p" 'lgit-commit-insert-prev-commit-msg)
    (define-key map "\M-n" 'lgit-commit-insert-next-commit-msg)
    map)
  "Keymap for `lgit-commit-mode'")

(defun lgit-commit-mode (parent)
  "Major mode for providing a commit log message and committing the index.
This mode is not meant to be user invoked."
  (interactive)

  (setq lgit-commit-parent-buffer parent)

  (use-local-map lgit-commit-mode-map)
  (setq major-mode 'lgit-commit-mode)
  (setq mode-name "GIT-Commit")

  (setq lgit-commit-msgs-index nil)

  (lgit-prepare-commit-buffer)
  (setq lgit-commit-initial-buffer-contents (buffer-string))
  (goto-char (point-min))
  (if lgit-commit-template
      (insert lgit-commit-template))
  (set-buffer-modified-p nil)

  (message (substitute-command-keys "Type \\[lgit-commit-finish] when done."))
  (run-hooks 'lgit-commit-mode-hook)
  (run-hooks 'text-mode-hook))

;; Insert stuff to show them what files they're affecting.
;; Takes the output from commit --dry-run
(defun lgit-prepare-commit-buffer ()
  (insert "\n\n")
  (insert (substitute-command-keys
	   "# ** Type \\[lgit-commit-finish] when done **\n"))
  (insert "#\n")
  (let ((bufname "*GIT-commit*")
	status)
    ;; XXX/lomew note this assumes commit.status=true
    (setq status (lgit-do-command-quietly "commit" (list "--dry-run")))
    (if (zerop status)
	(progn
	  (save-excursion
	    ;; Go add # to each line if it isn't there already.  This
	    ;; used to be the default but changed in Git 1.8.5 when
	    ;; "status" and "commit --dry-run" stopped prefixing lines
	    ;; with #.
	    ;;
	    ;; This is a goofy implementation since $ can't be used
	    ;; within a grouping construct in emacs regexps, otherwise
	    ;; I'd search for "^\\([^#]\\|$\\)
	    (set-buffer bufname)
	    (goto-char (point-min))
	    (while (re-search-forward "^" nil t)
	      (if (looking-at "#")
		  (forward-char 1)
		(insert "# "))))
	  (insert-buffer-substring bufname))
      (pop-to-buffer bufname)
      (error "git \"commit --dry-run\" failed, see %s buffer for details"
	     bufname))))

(defun lgit-commit-finish ()
  ;; Finish up the commit by grabbing the commit string and calling git commit.
  ;; If the commit worked,
  ;; XXX/lomew punt clear out the affected files from the parent buffer.
  ;; Otherwise complain loudly and pop up the commit output.
  ;;
  ;; This is tricky since several buffers are involved, each with their own
  ;; local variables and such.  Watch out.
  (interactive)
  (let ((logbuf (get-buffer "*GIT-commit-message*"))
	(commit-bufname "*GIT-commit*")
	(parent lgit-commit-parent-buffer)
	msg files-file message-file status)
    ;; Make sure they specified some message.
    (if (string-equal (buffer-string) lgit-commit-initial-buffer-contents)
	(error "Please specify a commit message"))
    ;; Remove any crap from the buffer, extracting the commit message.
    (lgit-commit-tidy-up-buffer)
    (setq msg (buffer-string))
    ;; Check again for deadbeat messages, reinitialize the buffer if needed.
    (if (string-equal msg "")
	(progn
	  (goto-char (point-min))
	  (insert lgit-commit-initial-buffer-contents)
	  (error "Please specify a non-empty commit message")))
    ;; Store the commit message in a temp file to
    ;; avoid any limits on argv size.
    (setq message-file (make-temp-name (concat (file-name-as-directory
						lgit-temp-file-directory)
					       "lgitM")))
    (unwind-protect
	(progn
	  (with-temp-file message-file
	    (insert msg))
	  ;; Do the commit.  We make sure to do it in the parent buffer so
	  ;; CWD, etc is correct.
	  (pop-to-buffer parent)
	  (message "Committing...")
	  (ring-insert lgit-commit-msgs msg)
	  (setq status (lgit-do-command-quietly
			"commit"
			(list "-F" message-file)))
	  (message "Committing...done"))
      ;; Always clean up.
      (delete-file message-file))
    ;; Remove lines in parent buffer for files we successfully committed.
    ;; Complain loudly if the commit failed.
    (if (zerop status)
	(progn
	  (pop-to-buffer parent)
	  (lgit-commit-update-index-display)
	  ;; Only chuck buffer when all is good.
	  (kill-buffer logbuf))
      ;; Commit failed.
      (pop-to-buffer commit-bufname)
      (goto-char (point-min))
      (insert "\n"
	      "*** The commit was not completely successful.\n"
	      "*** Check this buffer closely to determine what is wrong.\n"
	      "*** The commit message is in " (buffer-name logbuf) ".\n"
	      "\n")
      (error "Commit failed, see %s buffer for details." commit-bufname))))

(defun lgit-commit-update-index-display ()
  ;; Update the display post-commit for files that were in the index.
  ;; XXX/lomew svn/cvs ones revert the buffers for the files, prob for $Id$ crap.
  (save-excursion
    (goto-char (point-min))
    (while (re-search-forward lgit-linepat nil t)
      (let ((state (lgit-current-file-state)))
	(if (or (memq 'i-modified state)
		(memq 'i-added state)
		(memq 'i-deleted state)
		(memq 'i-renamed state)
		(memq 'i-copied state))
	    (progn
	      (lgit-change-this-file-index-state 'i-unmodified)
	      (if (memq 'w-unmodified state)
		  ;; Nothing to display for this file, remove the line.
		  (lgit-remove-file-line (lgit-current-file)))))))))
	    
(defun lgit-commit-tidy-up-buffer ()
  (save-excursion
    ;; Remove leading blank lines.
    (goto-char (point-min))
    (if (and (re-search-forward "\\S-" nil t)
	     (/= (point) (point-min)))
	(progn
	  (forward-char -1)
	  (delete-region (point-min) (point))))
    ;; Remove lines starting with # (although git will probably do this for us)
    (flush-lines "^#")
    ;; Trim trailing blank lines
    (goto-char (point-max))
    (if (and (re-search-backward "\\S-" nil t)
	     (/= (point) (point-max)))
	(progn
	  (forward-char 1)
	  (delete-region (point) (point-max))))))

(defun lgit-commit-insert-prev-commit-msg (arg)
  "Cycle backwards thru commit message history."
  (interactive "*p")
  (let ((len (ring-length lgit-commit-msgs)))
    (if (= len 0)
	(error "Empty commit message string")
      (erase-buffer)
      ;; Initialize the index on the first use of this command
      ;; so that the first M-p gets index 0, and the first M-n gets
      ;; index -1.
      (if (null lgit-commit-msgs-index)
	  (setq lgit-commit-msgs-index
		(if (> arg 0) -1
		  (if (< arg 0) 1 0))))
      (setq lgit-commit-msgs-index
	    (mod (+ lgit-commit-msgs-index arg) len))
      (message "Commit Msg %d" (1+ lgit-commit-msgs-index))
      (insert (ring-ref lgit-commit-msgs lgit-commit-msgs-index))
      (insert lgit-commit-initial-buffer-contents))))

(defun lgit-commit-insert-next-commit-msg (arg)
  "Cycle forwards thru commit message history."
  (interactive "*p")
  (lgit-commit-insert-prev-commit-msg (- arg)))


;; Internal functions.

(defun lgit-filepat (file)
  (concat lgit-linepat "\\(.+ -> \\)?" (regexp-quote file) "$"))

(defun lgit-current-file ()
  (save-excursion
    (beginning-of-line)
    (if (looking-at lgit-linepat)
	(let ((file-part (buffer-substring (match-end 0)
					   (progn (end-of-line) (point)))))
	  ;; handle the output from "git mv" files foo -> bar, take bar.
	  (if (string-match "\\(.+\\) -> \\(.+\\)" file-part)
	      (match-string 2 file-part)
	    file-part))
      (error "No file on this line"))))

(defun lgit-current-file-state ()
  (save-excursion
    (beginning-of-line)
    (if (looking-at lgit-linepat)
	(lgit-parse-state-string (match-string 1))
      (error "No file on this line"))))

(defun lgit-current-file-base ()
  ;; Parse the current line for the base revision info.
  ;; Only makes sense in ustatus mode.  If we can't parse it out
  ;; return "BASE"
  (save-excursion
    (beginning-of-line)
    (if (looking-at lgit-linepat)
	(progn
	  (if (>= (lgit-git-version-compare 1 6) 0)
	      (forward-char 9)
	    (forward-char 8))
	  (if (looking-at " +\\([0-9]+\\) ")
	      (string-to-number (match-string 1))
	    "BASE"))
      (error "No file on this line"))))

(defun lgit-set-mark-state (on)
  (save-excursion
    (beginning-of-line)
    (if (not (looking-at lgit-linepat))
	(error "No file on this line")
      (let ((buffer-read-only nil))
	(replace-match (concat (match-string 1) (if on "*" " ")))))))

(defun lgit-parse-state-string (str)
  ;; Parse the state portion of status output and return a list of
  ;; symbols
  (let (state)
    ;; 1st column - index
    (if (string-match "^ " str) (setq state (cons 'i-unmodified state)))
    (if (string-match "^M" str) (setq state (cons 'i-modified state)))
    (if (string-match "^A" str) (setq state (cons 'i-added state)))
    (if (string-match "^D" str) (setq state (cons 'i-deleted state)))
    (if (string-match "^R" str) (setq state (cons 'i-renamed state)))
    (if (string-match "^C" str) (setq state (cons 'i-copied state)))
    (if (string-match "^U" str) (setq state (cons 'i-unmerged state)))
    (if (string-match "^T" str) (setq state (cons 'i-typechange state)))
    (if (string-match "^\\?" str) (setq state (cons 'untracked state)))
    ;; 2nd column - work tree
    (if (string-match "^. " str) (setq state (cons 'w-unmodified state)))
    (if (string-match "^.M" str) (setq state (cons 'w-modified state)))
    (if (string-match "^.A" str) (setq state (cons 'w-added state)))
    (if (string-match "^.D" str) (setq state (cons 'w-deleted state)))
		      ; .R - shouldn't happen
		      ; .C - shouldn't happen
    (if (string-match "^.U" str) (setq state (cons 'w-unmerged state)))
    (if (string-match "^.T" str) (setq state (cons 'w-typechange state)))
    (if (string-match "^.\\?" str) (setq state (cons 'untracked state)))
    state))

;; commitable-p
;; updated-p
;; conflicted-p

(defun lgit-read-directory-name (prompt
				 &optional dir default must-match
				 initial-contents)
  ;; Older Emacs doesn't have this handy XEmacsism
  (if (fboundp 'read-directory-name)
      (read-directory-name prompt dir default must-match initial-contents)
    (let ((dir (read-file-name prompt dir default must-match
			       initial-contents)))
      (cond ((file-directory-p dir)
	     dir)
	    ((or (string-equal dir buffer-file-name)
		 (string-equal (expand-file-name dir) buffer-file-name))
	     ;; Undo that lame "default to current buffer" crap.
	     (file-name-directory dir))
	    (t
	     (error "%s is not a directory" dir))))))

(defun lgit-redraw-modeline (&optional all)
  ;; Older Emacs doesn't have this XEmacsism.
  (if (fboundp 'redraw-modeline)
      (redraw-modeline all)
    nil))

(defun lgit-bitch-if-commit-in-progress ()
  ;; If a commit is in progress, go to the commit-message buffer and
  ;; tell them what to do.
  ;; XXX/lomew should tie the commit buffer to the status buffer
  ;; and only enforce one commit per status
  (let ((buf (get-buffer "*GIT-commit-message*")))
    (if buf
	(progn
	  (pop-to-buffer buf)
	  (error "Please finish or abort this commit first")))))

;; Too bad Emacs doesn't have this XEmacs feature.
(defun lgit-remassoc (key list)
  "Delete by side effect any elements of LIST whose car is `equal' to KEY.
The modified LIST is returned.  If the first member of LIST has a car
that is `equal' to KEY, there is no way to remove it by side effect;
therefore, write `(setq foo (remassoc key foo))' to be sure of changing
the value of `foo'."
  (if (fboundp 'remassoc)
      (remassoc key list)
    ;; Roll our own...
    (let ((prev list)
	  (cur (cdr list)))
      ;; Check elems 2...end
      (while cur
	(if (equal (car (car cur)) key)
	    (setcdr prev (cdr cur))
	  (setq prev cur))
	(setq cur (cdr cur)))
      ;; Check the head
      (if (equal (car (car list)) key)
	  (cdr list)
	list))))

(defun lgit-get-relevant-files (use-marks &optional noerror)
  ;; Return a list of files in the form of `lgit-marked-files'
  ;; If USE-MARKS is non-nil then use the marked file list,
  ;; otherwise use the current file.
  ;; Optionaly NOERROR means return nil instead of throwing an error
  ;; when no files are marked.
  (if use-marks
      (if lgit-marked-files
	  ;; sort modifies
	  (sort (copy-sequence lgit-marked-files)
		(function (lambda (a b)
			    (string-lessp (car a) (car b)))))
	(if noerror
	    nil
	  (error "No marked files")))
    (list (cons (lgit-current-file)
		(lgit-current-file-state)))))

(defun lgit-do-command (cmd default-output &optional opts)
  ;; Do the git command `cmd' and print the result in buffer *GIT-`cmd'*.
  ;; If there is no output, insert some default text.
  ;; Returns the command exit status.
  (let ((args (cons cmd opts))
	(bufname (concat "*GIT-" cmd "*"))
	(cwd default-directory)
	status)
    ;; We override `temp-buffer-show-function' so we can insert some
    ;; default text if the command had no output.
    (let ((temp-buffer-show-function
	   (lambda (buf)
	     (save-excursion
	       (set-buffer buf)
	       (setq default-directory cwd)
               ;; Handle no output
	       (if (zerop (lgit-buffer-size buf))
		   (insert default-output))
               ;; Maybe turn on diff-mode.  We make it read only
               ;; so n/p, etc, can be used rather than M-n/M-p,
               ;; but we also want undo available in case we
               ;; start changing stuff around.
	       (if (and lgit-use-diff-mode
			(string-equal cmd "diff")
			(fboundp 'diff-mode))
		   (progn
		     (diff-mode)
		     (buffer-enable-undo)
		     (setq buffer-read-only t)
                     ;; Make revert-buffer work (bound to g in
		     ;; diff-mode).  Since elisp lacks closures I do
		     ;; something hacky with a local variable.  I used
		     ;; to use `lexical-let' but it is obsolete in
		     ;; emacs 24, which has lexical binding and true
		     ;; closures.  But it is confusing how to support
		     ;; emacs 23 and 24.
		     (set (make-local-variable 'lgit-revert-cmd-args)
			  (list cmd default-output opts))
                     (set (make-local-variable 'revert-buffer-function)
			  (lambda (ignore-auto noconfirm)
			    (apply 'lgit-do-command lgit-revert-cmd-args))))))
	     (let ((win (display-buffer buf t)))
               ;; Maybe turn on view-mode
	       (if (member cmd lgit-view-mode-commands)
		   (lgit-set-view-mode win buf))))))
      (with-output-to-temp-buffer bufname
	(setq status (apply 'call-process lgit-git-command
			    nil standard-output
			    nil args))))
    status))

(defun lgit-do-command-quietly (cmd &optional opts)
  ;; Do the git command `cmd' and print the result in buffer *GIT-`cmd'*.
  ;; Returns the command exit status.
  (let ((args (cons cmd opts))
	(bufname (concat "*GIT-" cmd "*"))
	(cwd default-directory)
	status buf)
    (setq buf (get-buffer-create bufname))
    (save-excursion
      (set-buffer buf)
      (setq default-directory cwd)
      (setq buffer-read-only nil)
      (erase-buffer))
    (setq status (apply 'call-process lgit-git-command
			nil buf nil
			args))
    status))

(defun lgit-do-shell-command-quietly (cmd)
  ;; Do the git command `cmd' and print the result in buffer *GIT-shell*.
  ;; Returns the command exit status.
  ;;
  ;; Like lgit-do-command-quietly but takes the whole command as a
  ;; string, like "status -q" rather than a list of ("status" "-q").
  (let ((command (concat lgit-git-command " " cmd))
	(bufname "*GIT-shell*")
	(cwd default-directory)
	status buf)
    (setq buf (get-buffer-create bufname))
    (save-excursion
      (set-buffer buf)
      (setq default-directory cwd)
      (setq buffer-read-only nil)
      (erase-buffer))
    (setq status (apply 'call-process-shell-command command
			nil buf nil))
    status))

(defun lgit-set-view-mode (win buf)
  ;; Turn view-mode on for BUF in window WIN, making sure quitting it
  ;; will get us back somewhere sane.
  (if (not lgit-use-view-mode)
      nil
    (let ((prevwin (selected-window))
	  (prevbuf (current-buffer)))
      (save-excursion
	(set-buffer buf)
	(condition-case nil
	    (view-mode prevbuf 'kill-buffer) ;XEmacs
	  (error
	   (view-mode-enter (list win prevwin) 'kill-buffer)
	   (setq buffer-read-only t))))))) ;Emacs

(defun lgit-buffer-size (&optional buffer)
  ;; `buffer-size' in Emacs doesn't take an arg like XEmacs.
  (condition-case nil
      (buffer-size buffer)
    (error (save-excursion
	     (if buffer
		 (set-buffer buffer))
	     (buffer-size)))))

(defun lgit-ensure-saved (files)
  ;; Check for any buffers visiting any of the FILES and offer to save
  ;; them.
  (save-excursion
    (map-y-or-n-p
     (function (lambda (buf)
		 (if (and buf (buffer-modified-p buf))
		     (format "Save file %s? " (buffer-file-name buf)))))
     (function (lambda (buf)
		 (set-buffer buf)
		 (condition-case ()
		     (save-buffer)
		   (error nil))))
     (mapcar 'get-file-buffer files)
     '("file" "files" "save"))))

(defun lgit-revert-buffers-visiting-file (file)
  ;; Revert any buffers visiting FILE.
  ;; FILE can be relative if the current directory of the caller is correct.
  (let ((buf (get-file-buffer file)))
    (if (and buf
	     (file-exists-p file)
	     (not (verify-visited-file-modtime buf))
	     (not (buffer-modified-p buf)))
	(save-excursion
	  (set-buffer buf)
	  (revert-buffer nil t)))))

(defun lgit-remove-file-line (file)
  ;; Delete lines in the (readonly) status buffer that match a filename.
  ;; Removes from marked files too.
  (save-excursion
    (goto-char (point-min))
    ;; Remove the line.
    (let ((buffer-read-only nil))
      (delete-matching-lines (lgit-filepat file)))
    ;; Update marked files.
    (if (assoc file lgit-marked-files)
	(setq lgit-marked-files (lgit-remassoc file lgit-marked-files)))))

(defun lgit-change-this-file-index-state (newstate)
  ;; Change the displayed index state of the file on this line.
  ;; If the file in in the marked list, update that too.
  ;; Only deals with the index file state, first column
  (let ((newstatechar (cond ((eq newstate 'i-unmodified) ? )
			    ((eq newstate 'i-modified)	 ?M)
			    ((eq newstate 'i-added)	 ?A)
			    ((eq newstate 'i-deleted)    ?D)
			    ((eq newstate 'i-renamed)    ?R)
			    ((eq newstate 'i-copied)     ?C)
			    ((eq newstate 'i-unmerged)   ?U)
			    ((eq newstate 'i-typechange) ?T)
			    ((eq newstate 'i-untracked)  ??)
			    (t (error "Illegal new file state")))))
    ;; Rewrite the first column of the line.
    (beginning-of-line)
    (let ((buffer-read-only nil))
      (subst-char-in-region (point) (1+ (point)) (char-after)
			    newstatechar 'noundo))

    ;; Update the marked files
    (let ((file (lgit-current-file))
	  (curstate (lgit-current-file-state)))
      (if (assoc file lgit-marked-files)
	  (setq lgit-marked-files
		(cons (cons file curstate)
		      (lgit-remassoc file lgit-marked-files)))))))

(defun lgit-change-this-file-working-state (newstate)
  ;; Change the displayed working-tree state of the file on this line.
  ;; If the file in in the marked list, update that too.
  ;; Only deals with the index file state, second column
  (let ((newstatechar (cond ((eq newstate 'w-unmodified) ? )
			    ((eq newstate 'w-modified)	 ?M)
			    ((eq newstate 'w-added)	 ?A)
			    ((eq newstate 'w-deleted)    ?D)
			    ((eq newstate 'w-unmerged)   ?U)
			    ((eq newstate 'w-typechange) ?T)
			    ((eq newstate 'w-untracked)  ??)
			    (t (error "Illegal new file state")))))
    ;; Rewrite the first column of the line.
    (beginning-of-line)
    (let ((buffer-read-only nil))
      (forward-char 1)
      (subst-char-in-region (point) (1+ (point)) (char-after)
			    newstatechar 'noundo))

    ;; Update the marked files
    (let ((file (lgit-current-file))
	  (curstate (lgit-current-file-state)))
      (if (assoc file lgit-marked-files)
	  (setq lgit-marked-files
		(cons (cons file curstate)
		      (lgit-remassoc file lgit-marked-files)))))))

(defun lgit-change-file-index-state (file newstate)
  ;; Change the displayed index state of a file.
  (save-excursion
    (goto-char (point-min))
    (if (re-search-forward (lgit-filepat file) nil t)
	(lgit-change-this-file-index-state newstate))))

(defun lgit-change-file-working-state (file newstate)
  ;; Change the displayed working-tree state of a file.
  (save-excursion
    (goto-char (point-min))
    (if (re-search-forward (lgit-filepat file) nil t)
	(lgit-change-this-file-working-state newstate))))

(defun lgit-info ()
  ;; Call git info and parse the result into an alist suitable for use with
  ;; the lgit-info-get function.
  nil
;-  (let ((bufname "*GIT-info*")
;-	status)
;-    (setq status (lgit-do-command-quietly "info"))
;-    (if (zerop status)
;-	(lgit-parse-info-buffer bufname)
;-      (pop-to-buffer bufname)
;-      (error "git \"info\" failed, see %s buffer for details" bufname)))
  )

(defun lgit-parse-info-buffer (buf)
  ;; Parse git info output into an alist.
  (let (result)
    (save-excursion
      (set-buffer buf)
      (goto-char (point-min))
      (while (re-search-forward "^\\([^:]+\\)\\s-*:\\s-*\\(.*\\)" nil t)
	(setq result (cons (cons (buffer-substring (match-beginning 1)
						   (match-end 1))
				 (buffer-substring (match-beginning 2)
						   (match-end 2)))
			   result))))
    result))

(defun lgit-info-get (info str)
  ;; Retrieve the value, if any, of the field corresponding to STR in
  ;; alist INFO, which is presumed to have come from `lgit-info'.
  (cdr (assoc str info)))

(defun lgit-parse-update-buffer (buf)
  ;; Parse git update output in BUF into an
  ;; alist like ((file state ...) (file state ...) ...)
  (let (result)
    (save-excursion
      (set-buffer buf)
      (goto-char (point-min))
      (while (re-search-forward "^\\([ADUCG ][ADUCG ][B ]  \\)\\(.*\\)" nil t)
	(let ((str (match-string 1))
	      (file (match-string 2))
	      state)
	  (if (string-match "^A" str) (setq state (cons 'added state)))
	  (if (string-match "^D" str) (setq state (cons 'deleted state)))
	  (if (string-match "^U" str) (setq state (cons 'updated state)))
	  (if (string-match "^C" str) (setq state (cons 'conflicted state)))
	  (if (string-match "^G" str) (setq state (cons 'merged state)))

	  (if (string-match "^.A" str) (setq state (cons 'padded state)))
	  (if (string-match "^.D" str) (setq state (cons 'pdeleted state)))
	  (if (string-match "^.U" str) (setq state (cons 'pupdated state)))
	  (if (string-match "^.C" str) (setq state (cons 'pconflicted state)))
	  (if (string-match "^.G" str) (setq state (cons 'pmerged state)))

	  (setq result (cons (cons file state) result)))))
    result))

(defun lgit-head-revision ()
  ;; Figure out what our HEAD revision would be at (point).  For plain
  ;; "status" output it should be HEAD, but for "ustatus" buffers it
  ;; comes from the "Status against revision:" line.
  ;;
  ;; Search thru the markers list and find the first one after us.
  (let ((markers lgit-head-revision-markers)
	(head "HEAD") cur found)
    (while (and markers (not found))
      (setq cur (car markers)
	    markers (cdr markers))
      (if (> (marker-position (car cur)) (point))
	  (setq head (cdr cur)
		found t)))
    head))

(defun lgit-top-head-revision ()
  ;; Return the HEAD revision for the top-level non-external
  ;; repository.  This will be the first element of our list.
  (cdr (car lgit-head-revision-markers)))

(defun lgit-determine-git-version ()
  ;; Figure out the version of git.
  ;; Call git --version and return (major . minor) tuple.
  (let ((bufname "*GIT---version*")	
	status start)
    (setq status (lgit-do-command-quietly "--version"))
    (if (zerop status)
	(save-excursion
	  (set-buffer bufname)
	  (goto-char (point-min))
	  (if (looking-at "^git version \\([0-9]+\\)\.\\([0-9]+\\)")
	      (cons (string-to-number (match-string 1))
		    (string-to-number (match-string 2)))
	    (pop-to-buffer bufname)
	    (error "cannot parse git --version output")))
      (pop-to-buffer bufname)
      (error "git --version failed, see %s buffer for details" bufname))))

;; Returns -1,0,1 if the git version is <,=,> maj.min
(defun lgit-git-version-compare (maj min)
  (cond ((> lgit-git-major-version maj) 1)
	((< lgit-git-major-version maj) -1)
	;; majors are equal, check minor
	(t (cond ((> lgit-git-minor-version min) 1)
		 ((< lgit-git-minor-version min) -1)
		 ;; minors are equal too
		 (t 0)))))

(defun lgit-current-branch ()
  ;; Figure out which branch we are on.
  (let ((status (lgit-do-command-quietly "symbolic-ref" '("-q" "HEAD")))
	(bufname "*GIT-symbolic-ref*"))
    (unwind-protect
	(cond ((zerop status)
	       (save-excursion
		 (set-buffer bufname)
		 (goto-char (point-min))
		 ;; Something like refs/heads/master.  Note the branch
		 ;; name may contain slashes.
		 (if (re-search-forward "refs/heads/\\(.*\\)" nil t)
		     (match-string 1)
		   (error "cannot find active branch in \"git symbolic-ref\" output"))))
	      ((= status 1)
	       "(detached head)")
	      (t
	       (error "cannot determine current branch")))
      (kill-buffer bufname))))

(defun lgit-get-local-branches ()
  ;; Return the list of local branches
  (let ((status (lgit-do-command-quietly "branch"))
	(bufname "*GIT-branch*")
	branches)
    (if (zerop status)
	(save-excursion
	  (set-buffer bufname)
	  (goto-char (point-min))
	  (while (re-search-forward "^[ *] \\(.+\\)" nil t)
	    (let ((b (match-string 1)))
	      (if (string-match "\\(.+\\) -> \\(.+\\)" b)
		  (setq b (match-string 1 b)))
	      (setq branches (cons b branches))))))
    (kill-buffer bufname)
    branches))


;; Process-related stuff.

(defun lgit-filter (proc string)
  ;; This is called when there is new input.  The input can be
  ;; any size and may have partial lines.  See the Elisp manual
  ;; where it describes process filters for an explanation of the
  ;; marker magic here.
  (with-current-buffer (process-buffer proc)
    (let ((moving (= (point) (process-mark proc)))
	  (buffer-read-only nil)
	  beg)
      (save-excursion
	;; Insert the text, advancing the process marker and fixing lines.
	(goto-char (process-mark proc))
	(setq beg (point))
	(insert string)
	(set-marker (process-mark proc) (point))
	(lgit-parse-output beg))
      (if moving (goto-char (process-mark proc))))))

(defun lgit-parse-output (beg)
  ;; Scan the output, noting and maybe rewriting some things.
;-  (goto-char beg)
;-  (beginning-of-line)			; in case last insert had partial line
;-  (let ((stuff-to-do t)
;-	prev-point dont-move)
;-    (while stuff-to-do
;-      (setq dont-move nil)
;-
;-      (cond
;-       ;; Note the reported HEAD revision for this section (note that
;-       ;; there may be externals with their own HEAD).
;-       ((looking-at "^Status against revision:[ \t]+\\([0-9]+\\)\n")
;-	;; Set a marker and save an association with the revision.
;-	;; Note these are kept in the same order as in the buffer.
;-	(setq lgit-head-revision-markers
;-	      (nconc lgit-head-revision-markers
;-		     (list (cons (copy-marker (match-beginning 0))
;-				 (string-to-number (match-string 1))))))
;-	;; Put in the ending dashes
;-	(beginning-of-line)
;-	(insert lgit-lots-of-dashes "\n")
;-	(setq lgit-inserted-final-dashes t))
;-       ((looking-at "^Performing status on external item at '\\(.*\\)'")
;-	(let ((ext (match-string 1)))
;-	  (end-of-line)
;-	  (insert "\n" lgit-lots-of-dashes)
;-	  (insert "\n" lgit-dummy-line ext))))
;-
;-      ;; Move forward.  If point changes we have more stuff to do.
;-      (if dont-move
;-	  nil
;-	(setq prev-point (point))
;-	(forward-line)
;-	(setq stuff-to-do (> (point) prev-point)))))
  )

(defun lgit-sentinel (proc msg)
  ;; Tell the user the process is done.
  (let* ((buf (process-buffer proc))
	 (buffer-is-visible (get-buffer-window buf 'visible))
	 (msg-long (format "%s process %s" (process-name proc) msg)))
    (if (memq (process-status proc) '(signal exit))
	;; Process is dead.
	(progn
	  ;; Don't tell them when the buffer is visible.
	  (or buffer-is-visible
	      (message msg-long))
	  (if (null (buffer-name buf))
	      ;; Buffer was killed.
	      (set-process-buffer proc nil)
	    ;; Else process died some other way.
	    (set-buffer buf)

	    ;; Hack the modeline.
	    (setq modeline-process
		  (concat ":"
			  (symbol-name (process-status proc))
			  (if (zerop (process-exit-status proc))
			      " OK"
			    (format " [exit-status %d]"
				    (process-exit-status proc)))))
	    (lgit-redraw-modeline)

	    ;; Indicate status in buffer too.  Remember that lcvs-mode
	    ;; makes the buffer read-only.
	    (save-excursion
	      (goto-char (point-max))
	      (setq buffer-read-only nil)
	      (if (not lgit-inserted-final-dashes)
		  (insert lgit-lots-of-dashes "\n"))
	      (insert "\n" msg-long)
	      (forward-char -1)		;back up over the \n to insert the time
	      (insert " at " (substring (current-time-string) 0 19))
	      (forward-char 1)		;and step over it
	      (setq buffer-read-only t))

	    ;; Go to the first file, if there is one, unless the user
	    ;; has already moved.  lgit-next-line will print stuff
	    ;; unless lgit-explain-each-line is nil.  We make it nil
	    ;; if BUF is not visible.  Also, lgit-next-line will error
	    ;; if no files.
	     (if (= (point) (point-min))
		 (let ((lgit-explain-each-line
			(and lgit-explain-each-line
			     (get-buffer-window buf 'visible))))
		   (condition-case nil
		       (lgit-next-line)
		     (error nil)))))))))
