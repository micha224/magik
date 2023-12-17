;;; magik-utils.el --- programming utils for the Magik lisp.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;;

;;; Code:

(eval-when-compile
  (require 'sort))

(defvar magik-utils-original-process-environment (cl-copy-list process-environment)
  "Store the original `process-environment' at startup.
This is used by \\[gis-version-reset-emacs-environment] to reset an
Emacs session back to the original startup settings.
Note that any user defined Environment variables set via \\[setenv]
will be lost.")

(defvar magik-utils-original-exec-path (cl-copy-list exec-path)
  "Store the original `exec-path' at startup.
This is used by \\[gis-version-reset-emacs-environment] to reset an
Emacs session back to the original startup settings.")

(defun barf-if-no-gis (&optional buffer process)
  "Return process object of GIS process.
Signal an error if no gis is running."
  (setq buffer  (or buffer magik-session-buffer)
	process (or process (get-buffer-process buffer)))
  (or process
      (error "There is no GIS process running in buffer '%s'" buffer)))

(defun gsub (str from to)
  "return a string with any matches for the regexp, `from', replaced by `to'."
  (save-match-data
    (prog1
        (if (string-match from str)
            (concat (substring str 0 (match-beginning 0))
                    to
                    (gsub (substring str (match-end 0)) from to))
          str))))

(defun sub (str from to)
  "return a string with the first match for the regexp, `from', replaced by `to'."
  (save-match-data
    (prog1
        (if (string-match from str)
            (concat (substring str 0 (match-beginning 0))
                    to
                    (substring str (match-end 0)))
          str))))

(defun global-replace-regexp (regexp to-string)
  "Replace REGEXP with TO-STRING globally"
  (save-match-data
    (goto-char (point-min))
    (while
	(re-search-forward regexp nil t)
      (replace-match to-string nil nil))))

(defun magik-utils-find-files-up (path file &optional first)
  "Return list of FILEs found by looking up the directory PATH.
FILE may even be a relative path!
If FIRST is true just return the first one found."
  (let ((dir (file-name-as-directory path))
	parent
	dirs)
    (while dir
      (if (file-exists-p (concat dir file))
	  (setq dirs (cons (concat dir file) dirs)))
      (setq parent (file-name-directory (directory-file-name dir))
	    dir    (cond ((and first dirs) nil)
			 ((equal parent dir) nil)
			 ((equal parent "//") nil) ;; protect against UNC paths
			 (t parent))))
    dirs))

(defun magik-utils-curr-word ()
  "return the word (or part-word) before point as a string."
  (save-excursion
    (buffer-substring
     (point)
     (progn
       (skip-chars-backward "_!?a-zA-Z0-9")
       (point)))))

;; copied from emacs 18 because the emacs 19 find-tag-tag seems to be different.
(defun magik-utils-find-tag-tag (string)
  (let* ((default (magik-utils-find-tag-default))
	 (spec (read-string
		(if default
		    (format "%s (default %s) " string default)
		  string))))
    (list (if (equal spec "")
	      default
	    spec))))

;;also copied
(defun magik-utils-find-tag-default ()
  (save-excursion
    (while (looking-at "\\sw\\|\\s_")
      (forward-char 1))
    (if (re-search-backward "\\sw\\|\\s_" nil t)
	(progn (forward-char 1)
	       (buffer-substring (point)
				 (progn (forward-sexp -1)
					(while (looking-at "\\s'")
					  (forward-char 1))
					(point))))
      nil)))

(defun magik-utils-substitute-in-string (string)
  "Return STRING with environment variable references replaced."
  (let ((substr string)
	start)
    (while (or (string-match "\$\\(\\sw+\\)" substr start)
	       (string-match "\${\\(\\sw+\\)}" substr start)
	       (string-match "%\\(\\sw+\\)%" substr start))
      (let ((env-name (substring substr (match-beginning 1) (match-end 1))))
	(setq start (match-end 0)) ;increment start position irrespective of a match
	(and (getenv env-name)
	     (setq substr (replace-match (getenv env-name) t t substr 0)))))
    substr))

(defun which-file (filename &optional err path)
  "Return the full path when the given FILENAME name is in the PATH.
If PATH is not given then `load-path' is used.
nil is returned if no FILENAME found in PATH.

If ERROR string is given then output as an error, %s will be replced with FILENAME."
  (let ((path (or path load-path))
	file)
    (while (and path
		(not (file-exists-p
		      (setq file (concat (file-name-as-directory (car path)) filename)))))
      (setq path (cdr path)))
    (cond (path file)
	  (err  (error err filename))
	  (t    nil))))

(defun magik-utils-file-name-display (file maxlen &optional sep)
  "Return shortened file name suitable for display, retaining head and tail portions of path."
  (let ((sep (or sep "..."))
	(dirsep "\\")
	components head tail c)
    (if (< (length file) maxlen)
	file
      (setq components (reverse (split-string file "[\\/]+")))
      ;;collect last three parts of path
      (push (pop components) tail)
      (push (pop components) tail)
      (push (pop components) tail)
      (setq maxlen (- maxlen (apply '+ (mapcar 'length tail)) (length tail) (length sep))
	    components (reverse components))
      ;;now collect as many parts of the top of the path that we can.
      (while (and (setq c (car components)) (< (apply '+ (mapcar 'length head))
					       (- maxlen (length head) (length c))))
	(push c head)
	(setq components (cdr components)))

      (mapconcat 'identity (append (reverse head) (list sep) tail) dirsep))))

(defun magik-utils-buffer-mode-list-predicate-p (predicate)
  "Return t if predicate function or variable is true or predicate is nil."
  (cond ((null predicate) t) ;no predicate given
	((functionp predicate) (funcall predicate))
	((boundp predicate) (symbol-value predicate))
	(t t)))

(defun magik-utils-buffer-visible-list (mode &optional predicate)
  "Return list (BUFFER . THIS-FRAME) for given Major mode MODE.
MODE may also be a list of modes.
Optional PREDICATE is either a function or a variable which must not return nil."
  (save-excursion
    (cl-loop for b in (buffer-list)
	     do (set-buffer b)
	     if (get-buffer-window b 'visible)
	     if (member major-mode (if (listp mode) mode (list mode)))
	     if (magik-utils-buffer-mode-list-predicate-p predicate)
	     collect (cons (buffer-name)
			   (windowp (get-buffer-window b nil))))))

(defun magik-utils-buffer-mode-list (mode &optional predicate)
  "Return list of buffers with the given Major mode MODE.
MODE may also be a list of modes.
Optional PREDICATE is either a function or a variable which must not return nil."
  (save-excursion
    (cl-loop for b in (buffer-list)
	     do (set-buffer b)
	     if (member major-mode (if (listp mode) mode (list mode)))
	     if (magik-utils-buffer-mode-list-predicate-p predicate)
	     collect (buffer-name))))

(defun magik-utils-buffer-mode-list-sorted (mode &optional predicate sort-fn)
  "Return standardised sorted list of buffers with the given Major mode MODE.
Optional PREDICATE is either a function or a variable which must not return nil.
Optional SORT-FN overrides the default sort function, `string-lessp'.

This function is provided mainly for the standardised sorting of GIS buffers.
Since the introduction of having multiple GIS sessions with the 'key' being
the GIS buffer name, it is very useful to have a standardised sort of
GIS buffers."
  (sort (magik-utils-buffer-mode-list mode predicate)
	(or sort-fn 'string-lessp)))

(defun magik-utils-get-buffer-mode (buffer mode prompt default &optional prefix-fn initial predicate)
  "Generalised function to return a suitable major MODE buffer to use.

Used for determining a suitable BUFFER using the following interface:
1. If Prefix arg is given and is integer,
   then use the buffer returned from the PREFIX-FN.
   The buffer list is filtered according to PREDICATE if given.
2. If Prefix arg is given and is not an integer,
   then PROMPT user with completing list of known buffers
   (optionally provide an INITIAL value).
   The buffer list is filtered according to PREDICATE if given.
3. If BUFFER is given use that.
4. Use the buffer displayed in the current frame,
   only PROMPT if more than one buffer in current frame is displayed
   and only list those in the current frame.
5. Use the buffer displayed in the some other frame,
   only PROMPT if more than one buffer in the other frames are displayed
   and only list those that are displayed in the other frames.
6. Use DEFAULT value.
"
  (let* ((prefix-fn (or prefix-fn
			#'(lambda (arg mode predicate)
			    (nth (1- arg)
				 (reverse (magik-utils-buffer-mode-list-sorted mode predicate))))))
	 (prompt (concat prompt " "))
	 (visible-bufs (magik-utils-buffer-visible-list mode predicate))
	 bufs
	 (buffer (cond ((and (integerp current-prefix-arg)
			     (setq buffer (funcall prefix-fn current-prefix-arg mode predicate)))
			buffer)
		       (current-prefix-arg
			(completing-read prompt
					 (mapcar #'(lambda (b) (cons b b))
						 (magik-utils-buffer-mode-list mode predicate))
					 nil nil
					 initial))
		       (buffer buffer)
		       ((and
			 (setq bufs
			       (delete nil
				       (mapcar (function (lambda (b) (if (cdr b) b))) visible-bufs)))
			 ;;restrict list to those whose cdr is t.
			 (setq buffer
			       (if (= (length bufs) 1)
				   (caar bufs)
				 (completing-read prompt visible-bufs 'cdr t)))
			 (not (equal buffer "")))
			buffer)
		       ((and
			 visible-bufs
			 (setq buffer
			       (if (= (length visible-bufs) 1)
				   (caar visible-bufs)
				 (completing-read prompt visible-bufs nil t)))
			 (not (equal buffer "")))
			(select-frame-set-input-focus
			 (window-frame (get-buffer-window buffer 'visible)))
			buffer)
		       (t default))))
    buffer))

(defun magik-utils-delete-process-safely (process)
  "A safe `delete-process'.
This is to protect against Emacs 22.1.1 on Windows from hanging irretrievably
when the subprocess being killed does not terminate quickly enough."
  (if (and (eq system-type 'windows-nt)
	   (equal emacs-version "22.1.1"))
      (kill-process process)
    (delete-process process)))

(provide 'magik-utils)
;;; magik-utils.el ends here








(defun magik-forward-sexp (&optional arg)
  (cond
   ((looking-at ",\\s *") (goto-char (match-end 0)))
   ((looking-at (rx (or "\"" "{" "[" "("))) (goto-char (scan-sexps (point) arg)))
   ((looking-at (rx bol (or "_method" (group (or "" "_abstract" "_private" "_iter") space "_method"))))
	(re-search-forward (rx (or "_endmethod\n\\$" "_endmethod"))))
   ((looking-back "_endmethod")
	(re-search-forward "_endmethod"))
   ((or (looking-at (rx "$\n"))	(looking-back (rx "$\n")))
	(goto-char (match-end 0))
	(re-search-forward (rx "$\n")))
   ((looking-at (rx bol "_pragma(" (zero-or-more not-newline) ")" eol))
	(goto-char (match-end 0)))
   ((looking-at (rx (one-or-more word) "(" (zero-or-more anychar) ")"))
	(search-forward "(")
	(backward-char)
	(magik-forward-sexp 1)) ;; it will match on the (
   ((looking-at "_proc") (search-forward "_endproc")) ;;too simple check for same level proc
   ((looking-at "_for") (search-forward "_endloop"))
   ((looking-at "_loop") (search-forward "_endloop"))
   ((looking-at "_if") (search-forward "_endif"))
   ((looking-at (rx (or "_elif" "_else")))
	(goto-char (match-end 0))
	(re-search-forward (rx (or "_elif" "_else" "_endif")))
	(backward-word))
   ((looking-back "_then")
	(re-search-forward (rx (or "_elif" "_else" "_endif")))
	(backward-word))
   ((thing-at-point 'word) (skip-syntax-forward "w"))
   )
	)

(defun ruby-forward-sexp (&optional arg)
  "Move forward across one balanced expression (sexp).
With ARG, do it many times.  Negative ARG means move backward."
  (declare (obsolete forward-sexp "28.1"))
  ;; TODO: Document body
  (interactive "p")
  (cond
   (ruby-use-smie (forward-sexp arg))
   ((and (numberp arg) (< arg 0))
    (with-suppressed-warnings ((obsolete ruby-backward-sexp))
      (ruby-backward-sexp (- arg))))
   (t
    (let ((i (or arg 1)))
      (condition-case nil
          (while (> i 0)
            (skip-syntax-forward " ")
	    (if (looking-at ",\\s *") (goto-char (match-end 0)))
            (cond ((looking-at "\\?\\(\\\\[CM]-\\)*\\\\?\\S ")
                   (goto-char (match-end 0)))
                  ((progn
                     (skip-chars-forward "-,.:;|&^~=!?+*")
                     (looking-at "\\s("))
                   (goto-char (scan-sexps (point) 1)))
                  ((and (looking-at (concat "\\<\\(" ruby-block-beg-re
                                            "\\)\\>"))
                        (not (eq (char-before (point)) ?.))
                        (not (eq (char-before (point)) ?:)))
                   (ruby-end-of-block)
                   (forward-word-strictly 1))
                  ((looking-at "\\(\\$\\|@@?\\)?\\sw")
                   (while (progn
                            (while (progn (forward-word-strictly 1)
                                          (looking-at "_")))
                            (cond ((looking-at "::") (forward-char 2) t)
                                  ((> (skip-chars-forward ".") 0))
                                  ((looking-at "\\?\\|!\\(=[~=>]\\|[^~=]\\)")
                                   (forward-char 1) nil)))))
                  ((let (state expr)
                     (while
                         (progn
                           (setq expr (or expr (ruby-expr-beg)
                                          (looking-at "%\\sw?\\Sw\\|[\"'`/]")))
                           (nth 1 (setq state (apply #'ruby-parse-partial
                                                     nil state))))
                       (setq expr t)
                       (skip-chars-forward "<"))
                     (not expr))))
            (setq i (1- i)))
        ((error) (forward-word-strictly 1)))
      i))))
