;;; forge-list.el --- Tabulated-list interface     -*- lexical-binding: t -*-

;; Copyright (C) 2018-2019  Jonas Bernoulli

;; Author: Jonas Bernoulli <jonas@bernoul.li>
;; Maintainer: Jonas Bernoulli <jonas@bernoul.li>

;; Forge is free software; you can redistribute it and/or modify it
;; under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.
;;
;; Forge is distributed in the hope that it will be useful, but WITHOUT
;; ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
;; or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public
;; License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with Forge.  If not, see http://www.gnu.org/licenses.

;;; Code:

(require 'forge)

;;; Options

(defcustom forge-topic-list-mode-hook '(hl-line-mode)
  "Hook run after entering Forge-Topic-List mode."
  :package-version '(forge . "0.1.0")
  :group 'forge
  :type 'hook
  :options '(hl-line-mode))

;;; Modes
;;;; Topic

(defvar forge-topic-list-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map tabulated-list-mode-map)
    (define-key map (kbd "'") 'forge-dispatch)
    (define-key map (kbd "?") 'magit-dispatch)
    map)
  "Local keymap for Forge-Topic-List mode buffers.")

(define-derived-mode forge-topic-list-mode tabulated-list-mode
  "Issues"
  "Major mode for browsing a list of topics."
  (setq-local x-stretch-cursor  nil)
  (setq tabulated-list-padding  0)
  (setq tabulated-list-sort-key (cons "#" nil))
  (setq tabulated-list-format   (vconcat (--map `(,@(-take 3 it)
                                                  ,@(-flatten (nth 3 it)))
                                                forge-topic-list-columns)))
  (tabulated-list-init-header))

;;;; Issue

(defvar forge-issue-list-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map forge-topic-list-mode-map)
    (define-key map (kbd "RET") 'forge-list-visit-issue)
    (define-key map [return]    'forge-list-visit-issue)
    (define-key map (kbd "o")   'forge-list-browse-issue)
    map)
  "Local keymap for Forge-Issue-List mode buffers.")

(define-derived-mode forge-issue-list-mode forge-topic-list-mode
  "Issues"
  "Major mode for browsing a list of issues.")

;;;; Pullreq

(defvar forge-pullreq-list-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map forge-topic-list-mode-map)
    (define-key map (kbd "RET") 'forge-list-visit-pullreq)
    (define-key map [return]    'forge-list-visit-pullreq)
    (define-key map (kbd "o")   'forge-list-browse-pullreq)
    map)
  "Local keymap for Forge-Pullreq-List mode buffers.")

(define-derived-mode forge-pullreq-list-mode forge-topic-list-mode
  "Pull-Requests"
  "Major mode for browsing a list of pull-requests.")

;;; Commands
;;;; Issue

;;;###autoload
(defun forge-list-issues (repo)
  "List issues in a separate buffer."
  (interactive (list (forge-get-repository t)))
  (forge--list-topics 'forge-issue-list-mode nil
    (forge-sql [:select $i1 :from issue :where (= repository $s2)]
               (forge--topic-list-columns-vector)
               (oref repo id))))

;;;###autoload
(defun forge-list-assigned-issues (repo)
  "List issues assigned to you in a separate buffer."
  (interactive (list (forge-get-repository t)))
  (forge--list-topics 'forge-issue-list-mode nil
    (forge-sql
     [:select $i1 :from [issue issue_assignee assignee]
      :where (and (= issue_assignee:issue issue:id)
                  (= issue_assignee:id    assignee:id)
                  (= issue:repository     $s2)
                  (= assignee:login       $s3)
                  (isnull issue:closed))
      :order-by [(desc updated)]]
     (forge--topic-list-columns-vector)
     (oref repo id)
     (ghub--username (ghub--host)))))

(defun forge-list-visit-issue ()
  "View the issue at point in a separate buffer."
  (interactive)
  (forge-visit-issue (forge-get-issue (tabulated-list-get-id))))

(defun forge-list-browse-issue ()
  "Visit the url corresponding to the issue at point in a browser."
  (interactive)
  (forge-browse-issue (forge-get-issue (tabulated-list-get-id))))

;;;; Pullreq

;;;###autoload
(defun forge-list-pullreqs (repo)
  "List pull-requests in a separate buffer."
  (interactive (list (forge-get-repository t)))
  (forge--list-topics 'forge-pullreq-list-mode nil
    (forge-sql [:select $i1 :from pullreq :where (= repository $s2)]
               (forge--topic-list-columns-vector)
               (oref repo id))))

;;;###autoload
(defun forge-list-assigned-pullreqs (repo)
  "List pull-requests assigned to you in a separate buffer."
  (interactive (list (forge-get-repository t)))
  (forge--list-topics 'forge-pullreq-list-mode nil
    (forge-sql
     [:select $i1 :from [pullreq pullreq_assignee assignee]
      :where (and (= pullreq_assignee:pullreq pullreq:id)
                  (= pullreq_assignee:id      assignee:id)
                  (= pullreq:repository       $s2)
                  (= assignee:login           $s3)
                  (isnull pullreq:closed))
      :order-by [(desc updated)]]
     (forge--topic-list-columns-vector)
     (oref repo id)
     (ghub--username (ghub--host)))))

(defun forge-list-visit-pullreq ()
  "View the pull-request at point in a separate buffer."
  (interactive)
  (forge-visit-pullreq (forge-get-pullreq (tabulated-list-get-id))))

(defun forge-list-browse-pullreq ()
  "Visit the url corresponding to the pull-request at point in a browser."
  (interactive)
  (forge-browse-pullreq (forge-get-pullreq (tabulated-list-get-id))))

;;; Internal

(defun forge--list-topics (mode buffer-name rows)
  (declare (indent 2))
  (let ((topdir (magit-toplevel)))
    (with-current-buffer
        (get-buffer-create
         (or buffer-name
             (let ((repo (forge-get-repository t)))
               (format "*%s: %s/%s*"
                       (substring (symbol-name mode) 0 -5)
                       (oref repo owner)
                       (oref repo name)))))
      (setq default-directory topdir)
      (funcall mode)
      (setq tabulated-list-entries
            (mapcar (lambda (row)
                      (list (car row)
                            (vconcat
                             (cl-mapcar (lambda (val col)
                                          (if-let ((pp (nth 5 col)))
                                              (funcall pp val)
                                            (if val (format "%s" val) "")))
                                        row forge-topic-list-columns))))
                    rows))
      (tabulated-list-print)
      (switch-to-buffer (current-buffer)))))

(defvar forge-topic-list-columns
  '(("#" 5
     (lambda (a b)
       (> (car a) (car b)))
     (:right-align t) number nil)
    ("Title" 35 t nil title  nil)
    ))

(defun forge--topic-list-columns-vector (&optional qualify)
  (let ((lst (--map (nth 4 it) forge-topic-list-columns)))
    (vconcat (if qualify (-replace 'name 'packages:name lst) lst))))

;;; _
(provide 'forge-list)
;;; forge-list.el ends here
