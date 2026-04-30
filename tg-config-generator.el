;;; tg-config-generator.el --- Config file generator for Text-Game-Maker  -*- lexical-binding: t; -*-

(require 'cl-lib)

;; --- Buffer-local state ---

(defvar tg-config-type nil
  "Buffer-local: config type symbol (room, inventory, creature, map).")
(make-variable-buffer-local 'tg-config-type)

;; --- Major mode ---

(define-derived-mode tg-gen-config-mode text-mode "TG-Config"
  "Major mode for editing Text-Game-Maker config templates.
Press C-c C-c to submit and save."
  (local-set-key (kbd "C-c C-c") #'tg-gen-config-submit))

;; --- Buffer creation helper ---

(defun tg-gen-open-buffer (type header template)
  "Open config buffer for TYPE with HEADER comment and TEMPLATE text."
  (let ((buf (get-buffer-create (format "*TG Config: %s*" type))))
    (with-current-buffer buf
      (erase-buffer)
      (insert header)
      (insert template)
      (goto-char (point-min))
      (forward-line 3)
      (tg-gen-config-mode)
      (setq tg-config-type type))
    (switch-to-buffer buf)))

;; --- Parsing utilities ---

(defun tg-gen-parse-blocks (buffer-string)
  "Parse BUFFER-STRING into list of ((key . value) ...) blocks.
Blocks are delimited by lines starting with ##."
  (let* ((raw-blocks (split-string buffer-string "^## " t))
         results)
    (dolist (block raw-blocks)
      (let (fields)
        (dolist (line (split-string block "\n" t))
          (unless (or (string-prefix-p "#" line)
                      (string= "" line))
            (when (string-match "^\\([a-z-]+\\): \\(.*\\)" line)
              (push (cons (match-string 1 line)
                          (match-string 2 line))
                    fields))))
        (when fields
          (push (nreverse fields) results))))
    (nreverse results)))

(defun tg-gen-parse-value-as-list (value)
  "Parse VALUE as space-separated symbol list. Empty → nil."
  (if (or (null value) (string= value ""))
      nil
    (mapcar #'intern (split-string value))))

(defun tg-gen-parse-value-as-data (value)
  "Parse VALUE as Elisp alist data, e.g. (hp . 100) (attack . 10).
Wraps in parens and reads."
  (if (or (null value) (string= value ""))
      nil
    (car (read-from-string (format "(%s)" value)))))

;; --- Room config ---

(defconst tg-gen-room-template
  "# Room Configuration
# Fill in values, press C-c C-c to save

## Room 1
symbol:
description:
inventory:
creature:
"
  "Template for room configuration.")

(defun tg-gen-room-config ()
  "Open a buffer to generate room configuration."
  (interactive)
  (tg-gen-open-buffer 'room tg-gen-room-template ""))

(defun tg-gen-parse-room-config (buffer-string)
  "Parse room config BUFFER-STRING into room entity list."
  (let ((blocks (tg-gen-parse-blocks buffer-string)))
    (delq nil
          (mapcar (lambda (block)
                    (let ((sym (cdr (assoc "symbol" block))))
                      (when (and sym (not (string= sym "")))
                        (list (intern sym)
                              (or (cdr (assoc "description" block)) "")
                              (tg-gen-parse-value-as-list (cdr (assoc "inventory" block)))
                              (tg-gen-parse-value-as-list (cdr (assoc "creature" block)))))))
                  blocks))))

;; --- Inventory config ---

(defconst tg-gen-inventory-template
  "# Inventory Configuration
# Fill in values, press C-c C-c to save

## Item 1
symbol:
description:
type:
effects:
"
  "Template for inventory configuration.")

(defun tg-gen-inventory-config ()
  "Open a buffer to generate inventory configuration."
  (interactive)
  (tg-gen-open-buffer 'inventory tg-gen-inventory-template ""))

(defun tg-gen-parse-inventory-config (buffer-string)
  "Parse inventory config BUFFER-STRING into inventory entity list."
  (let ((blocks (tg-gen-parse-blocks buffer-string)))
    (delq nil
          (mapcar (lambda (block)
                    (let ((sym (cdr (assoc "symbol" block))))
                      (when (and sym (not (string= sym "")))
                        (list (intern sym)
                              (or (cdr (assoc "description" block)) "")
                              (let ((type-str (cdr (assoc "type" block))))
                                (if (or (null type-str) (string= type-str ""))
                                    nil
                                  (intern type-str)))
                              (tg-gen-parse-value-as-data (cdr (assoc "effects" block)))))))
                  blocks))))

;; --- Creature config ---

(defconst tg-gen-creature-template
  "# Creature Configuration
# Fill in values, press C-c C-c to save

## Creature 1
symbol:
description:
attr:
inventory:
equipment:
"
  "Template for creature configuration.")

(defun tg-gen-creature-config ()
  "Open a buffer to generate creature configuration."
  (interactive)
  (tg-gen-open-buffer 'creature tg-gen-creature-template ""))

(defun tg-gen-parse-creature-config (buffer-string)
  "Parse creature config BUFFER-STRING into creature entity list."
  (let ((blocks (tg-gen-parse-blocks buffer-string)))
    (delq nil
          (mapcar (lambda (block)
                    (let ((sym (cdr (assoc "symbol" block))))
                      (when (and sym (not (string= sym "")))
                        (list (intern sym)
                              (or (cdr (assoc "description" block)) "")
                              (tg-gen-parse-value-as-data (cdr (assoc "attr" block)))
                              (tg-gen-parse-value-as-list (cdr (assoc "inventory" block)))
                              (tg-gen-parse-value-as-list (cdr (assoc "equipment" block)))))))
                  blocks))))

;; --- Map config ---

(defconst tg-gen-map-template
  "# Map Configuration
# Fill in room symbols in grid layout, press C-c C-c to save

room1 room2
room3 room4
"
  "Template for map configuration.")

(defun tg-gen-map-config ()
  "Open a buffer to generate map configuration."
  (interactive)
  (tg-gen-open-buffer 'map tg-gen-map-template ""))

(defun tg-gen-parse-map-config (buffer-string)
  "Parse map config BUFFER-STRING into list of row lists."
  (let (rows)
    (dolist (line (split-string buffer-string "\n" t))
      (unless (or (string-prefix-p "#" line)
                  (string= "" line))
        (let ((symbols (mapcar #'intern (split-string line))))
          (when symbols
            (push symbols rows)))))
    (nreverse rows)))

;; --- Submit function ---

(defun tg-gen-config-submit ()
  "Parse current config buffer and save to file."
  (interactive)
  (let* ((content (buffer-substring-no-properties (point-min) (point-max)))
         (parsed (pcase tg-config-type
                   ('room (tg-gen-parse-room-config content))
                   ('inventory (tg-gen-parse-inventory-config content))
                   ('creature (tg-gen-parse-creature-config content))
                   ('map (tg-gen-parse-map-config content)))))
    (if (null parsed)
        (message "No valid data to save.")
      (let ((file (read-file-name "Save config to: ")))
        (with-temp-file file
          (if (eq tg-config-type 'map)
              (dolist (row parsed)
                (insert (mapconcat #'symbol-name row " "))
                (insert "\n"))
            (insert (prin1-to-string parsed))))
        (message "Config saved to %s" file)))))

(provide 'tg-config-generator)
