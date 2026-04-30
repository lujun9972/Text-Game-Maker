;;; test-helper.el --- Shared test utilities for Text-Game-Maker -*- lexical-binding: t; -*-

(add-to-list 'load-path (expand-file-name ".." (file-name-directory (or load-file-name buffer-file-name))))

(require 'ert)
(require 'thingatpt)
(require 'eieio)

;; Save and restore global variables around test body
(defmacro test-with-globals-saved (globals &rest body)
  "Save GLOBALS, execute BODY, then restore GLOBALS."
  (declare (indent 1))
  (let ((saved-vars (cl-gensym "saved-")))
    `(let ((,saved-vars (list ,@(mapcar (lambda (v) `(cons ',v (symbol-value ',v))) globals))))
       (unwind-protect
           (progn ,@body)
         ,@(mapcar (lambda (v)
                     `(set ',v (cdr (assq ',v ,saved-vars))))
                   globals)))))

;; Create a temp file with CONTENT, call CALLBACK with the file path, then delete
(defmacro test-with-temp-file (content &rest body)
  "Create a temp file with CONTENT, execute BODY with `temp-file' bound, then cleanup."
  (declare (indent 1))
  `(let ((temp-file (make-temp-file "tg-test-" nil ".el")))
     (unwind-protect
         (progn
           (write-region ,content nil temp-file)
           ,@body)
       (delete-file temp-file))))

;; Create test Room instance
(defun test-make-room (&rest plist)
  "Create a Room instance for testing. PLIST keys: :symbol :description :inventory :creature."
  (apply #'make-instance 'Room plist))

;; Create test Inventory instance
(defun test-make-inventory (&rest plist)
  "Create an Inventory instance for testing. PLIST keys: :symbol :description :type :effects."
  (apply #'make-instance 'Inventory plist))

;; Create test Creature instance
(defun test-make-creature (&rest plist)
  "Create a Creature instance for testing. PLIST keys: :symbol :description :attr :inventory :equipment."
  (apply #'make-instance 'Creature plist))

(provide 'test-helper)
