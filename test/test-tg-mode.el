;;; test-tg-mode.el --- Tests for tg-mode.el -*- lexical-binding: t; -*-

(require 'ert)
(require 'test-helper)
(require 'tg-mode)
(require 'text-game-maker)

;; --- tg-mprinc ---

(ert-deftest test-tg-mprinc-with-newline ()
  "tg-mprinc should insert string followed by newline."
  (with-temp-buffer
    (tg-mprinc "hello")
    (should (equal (buffer-string) "hello\n"))))

(ert-deftest test-tg-mprinc-no-newline ()
  "tg-mprinc with 'no-newline should not add newline."
  (with-temp-buffer
    (tg-mprinc "hello" 'no-newline)
    (should (equal (buffer-string) "hello"))))

(ert-deftest test-tg-mprinc-non-string ()
  "tg-mprinc should convert non-string to string via prin1-to-string."
  (with-temp-buffer
    (tg-mprinc 42)
    (should (equal (buffer-string) "42\n"))))

;; --- tg-mode ---

(ert-deftest test-tg-mode-is-major-mode ()
  "tg-mode should be a valid major mode derived from text-mode."
  (with-temp-buffer
    (tg-mode)
    (should (equal major-mode 'tg-mode))
    (should (derived-mode-p 'text-mode))))

;; --- tg-parse ---

(ert-deftest test-tg-parse-valid-command ()
  "tg-parse should execute a valid command and display result."
  (test-with-globals-saved (tg-valid-actions tg-over-p)
    (setq tg-valid-actions '(tg-help))
    (with-temp-buffer
      (tg-mode)
      (insert ">help\n")
      (goto-char (point-max))
      ;; Move to beginning of the line with ">help"
      (forward-line -1)
      (let ((output (catch 'exception (tg-parse 1))))
        ;; tg-help should have been called; check buffer has output
        nil))))

(ert-deftest test-tg-parse-unknown-command ()
  "tg-parse should display error for unknown command."
  (test-with-globals-saved (tg-valid-actions tg-over-p)
    (setq tg-valid-actions nil)
    (with-temp-buffer
      (tg-mode)
      (insert ">xyz\n")
      (goto-char (point-max))
      (forward-line -1)
      (tg-parse 1)
      (should (string-match-p "未知的命令" (buffer-string))))))

(ert-deftest test-tg-parse-empty-line ()
  "tg-parse should do nothing for empty lines."
  (test-with-globals-saved (tg-valid-actions tg-over-p)
    (setq tg-valid-actions nil)
    (with-temp-buffer
      (tg-mode)
      (insert "\n")
      (goto-char (point-max))
      (forward-line -1)
      (let ((before (buffer-string)))
        (tg-parse 1)
        ;; Should not error, buffer may have changed slightly but no crash
        t))))

(ert-deftest test-tg-parse-no-prompt ()
  "tg-parse should do nothing for lines without '>' prompt."
  (test-with-globals-saved (tg-valid-actions tg-over-p)
    (setq tg-valid-actions nil)
    (with-temp-buffer
      (tg-mode)
      (insert "hello world\n")
      (goto-char (point-max))
      (forward-line -1)
      (tg-parse 1)
      ;; Should not error
      t)))

;; --- tg-prompt-string ---

(ert-deftest test-tg-prompt-string-with-room ()
  "tg-prompt-string should return [symbol]> when current-room is set."
  (test-with-globals-saved (current-room)
    (setq current-room (make-Room :symbol 'living-room :description "A room"))
    (should (equal (tg-prompt-string) "[living-room]>"))))

(ert-deftest test-tg-prompt-string-without-room ()
  "tg-prompt-string should return > when current-room is nil."
  (test-with-globals-saved (current-room)
    (setq current-room nil)
    (should (equal (tg-prompt-string) ">"))))

(ert-deftest test-tg-parse-room-prompt ()
  "tg-parse should parse commands after [room]> prompt."
  (test-with-globals-saved (tg-valid-actions tg-over-p current-room rooms-alist room-map)
    (setq tg-valid-actions '(tg-help))
    (setq current-room (make-Room :symbol 'living-room :description "A room"))
    (setq rooms-alist (list (cons 'living-room current-room)))
    (setq room-map '((living-room)))
    (with-temp-buffer
      (tg-mode)
      (insert "[living-room]>help\n")
      (goto-char (point-max))
      (forward-line -1)
      (let ((output (catch 'exception (tg-parse 1))))
        (should-not (stringp output))))))

(ert-deftest test-tg-parse-plain-prompt-still-works ()
  "tg-parse should still parse commands after plain > prompt."
  (test-with-globals-saved (tg-valid-actions tg-over-p current-room)
    (setq tg-valid-actions '(tg-help))
    (setq current-room nil)
    (with-temp-buffer
      (tg-mode)
      (insert ">help\n")
      (goto-char (point-max))
      (forward-line -1)
      (let ((output (catch 'exception (tg-parse 1))))
        (should-not (stringp output))))))

;; --- tg-messages prompt read-only ---

(ert-deftest test-tg-messages-prompt-is-read-only ()
  "tg-messages should insert prompt with read-only text property."
  (test-with-globals-saved (tg-over-p)
    (setq tg-over-p nil)
    (with-temp-buffer
      (tg-mode)
      (tg-messages)
      (let ((prompt-start (point-min))
            (prompt-end (1- (point-max))))
        ;; The prompt text should have read-only property
        (should (get-text-property prompt-start 'read-only))))))

(ert-deftest test-tg-messages-room-prompt-is-read-only ()
  "tg-messages prompt should be read-only when current-room is set."
  (test-with-globals-saved (tg-over-p current-room rooms-alist room-map)
    (setq tg-over-p nil)
    (setq current-room (make-Room :symbol 'dungeon :description "A dark dungeon"))
    (setq rooms-alist (list (cons 'dungeon current-room)))
    (setq room-map '((dungeon)))
    (with-temp-buffer
      (tg-mode)
      (tg-messages)
      (let ((prompt-start (point-min)))
        (should (get-text-property prompt-start 'read-only))
        ;; Verify the prompt contains the room name
        (should (string-match-p "\\[dungeon\\]>" (buffer-string)))))))

(ert-deftest test-tg-messages-prompt-text-not-modifiable ()
  "Prompt text should not be modifiable (text-property test)."
  (test-with-globals-saved (tg-over-p)
    (setq tg-over-p nil)
    (with-temp-buffer
      (tg-mode)
      (tg-messages)
      ;; Verify prompt area has read-only
      (goto-char (point-min))
      (should (get-text-property (point) 'read-only))
      ;; All prompt chars up to point-max are read-only
      (should (get-text-property (1- (point-max)) 'read-only))
      ;; After user types (bypassing read-only), new text should NOT be read-only
      (goto-char (point-max))
      (let ((inhibit-read-only t))
        (insert "test input"))
      (should-not (get-text-property (1- (point)) 'read-only)))))

(ert-deftest test-tg-messages-game-over-switches-mode ()
  "tg-messages should switch to text-mode when game is over."
  (test-with-globals-saved (tg-over-p)
    (setq tg-over-p t)
    (with-temp-buffer
      (tg-mode)
      (tg-messages)
      (should (equal major-mode 'text-mode)))))

;; --- tg-display-fn ---

(ert-deftest test-tg-display-fn-is-tg-mprinc ()
  "tg-display-fn should be tg-mprinc, not message."
  (require 'text-game-maker)
  (should (eq tg-display-fn #'tg-mprinc)))

;; --- tg-eldoc-function ---

(ert-deftest test-tg-eldoc-exact-command ()
  "tg-eldoc-function should return docstring for exact command match."
  (test-with-globals-saved (tg-valid-actions)
    (setq tg-valid-actions '(tg-help))
    (with-temp-buffer
      (tg-mode)
      (insert ">help")
      (goto-char (point-max))
      (should (string= (tg-eldoc-function)
                       (documentation 'tg-help))))))

(ert-deftest test-tg-eldoc-prefix-match ()
  "tg-eldoc-function should return docstring for unique prefix match."
  (test-with-globals-saved (tg-valid-actions)
    (setq tg-valid-actions '(tg-help))
    (with-temp-buffer
      (tg-mode)
      (insert ">he")
      (goto-char (point-max))
      (should (string= (tg-eldoc-function)
                       (documentation 'tg-help))))))

(ert-deftest test-tg-eldoc-ambiguous-prefix ()
  "tg-eldoc-function should return nil for ambiguous prefix."
  (test-with-globals-saved (tg-valid-actions)
    (setq tg-valid-actions '(tg-help))
    ;; We need to manually add a second action starting with "he"
    ;; tg-defaction adds to tg-valid-actions, but we can just set the list
    (setq tg-valid-actions '(tg-help tg-hello))
    (with-temp-buffer
      (tg-mode)
      (insert ">he")
      (goto-char (point-max))
      (should-not (tg-eldoc-function)))))

(ert-deftest test-tg-eldoc-no-match ()
  "tg-eldoc-function should return nil for no match."
  (test-with-globals-saved (tg-valid-actions)
    (setq tg-valid-actions '(tg-help))
    (with-temp-buffer
      (tg-mode)
      (insert ">xyz")
      (goto-char (point-max))
      (should-not (tg-eldoc-function)))))

(ert-deftest test-tg-eldoc-no-prompt ()
  "tg-eldoc-function should return nil when no prompt on line."
  (test-with-globals-saved (tg-valid-actions)
    (setq tg-valid-actions '(tg-help))
    (with-temp-buffer
      (tg-mode)
      (insert "hello world")
      (goto-char (point-max))
      (should-not (tg-eldoc-function)))))

(ert-deftest test-tg-eldoc-room-prompt ()
  "tg-eldoc-function should work with [room]> prompt format."
  (test-with-globals-saved (tg-valid-actions current-room rooms-alist room-map)
    (setq tg-valid-actions '(tg-help))
    (setq current-room (make-Room :symbol 'living-room :description "A room"))
    (setq rooms-alist (list (cons 'living-room current-room)))
    (setq room-map '((living-room)))
    (with-temp-buffer
      (tg-mode)
      (insert "[living-room]>help")
      (goto-char (point-max))
      (should (string= (tg-eldoc-function)
                       (documentation 'tg-help))))))

;; --- prompt rear-nonsticky ---

(ert-deftest test-tg-messages-prompt-rear-nonsticky ()
  "Last char of prompt should have rear-nonsticky containing read-only."
  (test-with-globals-saved (tg-over-p)
    (setq tg-over-p nil)
    (with-temp-buffer
      (tg-mode)
      (tg-messages)
      (let ((last-pos (1- (point-max))))
        (should (member 'read-only (get-text-property last-pos 'rear-nonsticky)))))))

(ert-deftest test-tg-messages-can-type-after-prompt ()
  "User should be able to insert text after prompt without inhibit-read-only."
  (test-with-globals-saved (tg-over-p)
    (setq tg-over-p nil)
    (with-temp-buffer
      (tg-mode)
      (tg-messages)
      (goto-char (point-max))
      ;; This insert should NOT signal text-read-only
      (insert "hello")
      (should (equal (buffer-substring-no-properties (point-max) (- (point-max) 5)) "hello")))))

(ert-deftest test-tg-messages-consecutive-calls-preserve-read-only ()
  "Multiple tg-messages calls should keep all prompts read-only."
  (test-with-globals-saved (tg-over-p current-room rooms-alist room-map)
    (setq tg-over-p nil)
    (setq current-room (make-Room :symbol 'hall :description "A hall"))
    (setq rooms-alist (list (cons 'hall current-room)))
    (setq room-map '((hall)))
    (with-temp-buffer
      (tg-mode)
      (tg-messages)
      (goto-char (point-max))
      (insert "test")
      (tg-messages)
      ;; Both prompt areas should be read-only
      (should (get-text-property (point-min) 'read-only))
      ;; Find second prompt: search for the second "[hall]>"
      (goto-char (point-min))
      (search-forward "[hall]>" nil t 2)
      (should (get-text-property (match-beginning 0) 'read-only)))))

(ert-deftest test-tg-parse-new-prompt-is-read-only ()
  "After tg-parse processes a command, the new prompt should be read-only."
  (test-with-globals-saved (tg-valid-actions tg-over-p)
    (setq tg-valid-actions '(tg-help))
    (setq tg-over-p nil)
    (with-temp-buffer
      (tg-mode)
      (insert ">help\n")
      (goto-char (point-max))
      (forward-line -1)
      (tg-parse 1)
      ;; After parse, a new prompt should be inserted and read-only
      (goto-char (point-max))
      (let ((pos (1- (point))))
        ;; Find the last '>' which is the end of the new prompt
        (should (search-backward ">" nil t))
        (should (get-text-property (point) 'read-only))))))

;; --- action.el tg-display-fn ---

(ert-deftest test-action-el-not-redefining-tg-display-fn ()
  "action.el should not have its own defvar for tg-display-fn."
  (with-temp-buffer
    (insert-file-contents "action.el")
    (should-not (string-match-p "defvar tg-display-fn" (buffer-string)))))

;; --- Command history ---

(ert-deftest test-tg-history-prev-replaces-input ()
  "tg-history-prev should replace input with previous history entry."
  (test-with-globals-saved (tg-command-history tg-history-index tg-current-input)
    (setq tg-command-history '("attack rat" "move up"))
    (setq tg-history-index -1)
    (setq tg-current-input "")
    (with-temp-buffer
      (tg-mode)
      (insert ">test")
      (goto-char (point-max))
      (tg-history-prev)
      (should (string-match-p ">attack rat$" (buffer-string)))
      (should (equal tg-current-input "test"))
      (should (= tg-history-index 0)))))

(ert-deftest test-tg-history-prev-saves-current-input ()
  "tg-history-prev should save current input before entering history."
  (test-with-globals-saved (tg-command-history tg-history-index tg-current-input)
    (setq tg-command-history '("attack rat"))
    (setq tg-history-index -1)
    (setq tg-current-input "")
    (with-temp-buffer
      (tg-mode)
      (insert ">my input")
      (goto-char (point-max))
      (tg-history-prev)
      (should (equal tg-current-input "my input")))))

(ert-deftest test-tg-history-prev-no-history ()
  "tg-history-prev should do nothing when history is empty."
  (test-with-globals-saved (tg-command-history tg-history-index tg-current-input)
    (setq tg-command-history nil)
    (setq tg-history-index -1)
    (with-temp-buffer
      (tg-mode)
      (insert ">test")
      (goto-char (point-max))
      (let ((before (buffer-string)))
        (tg-history-prev)
        (should (equal (buffer-string) before))))))

(ert-deftest test-tg-history-prev-cycles-through ()
  "tg-history-prev should cycle through all history entries."
  (test-with-globals-saved (tg-command-history tg-history-index tg-current-input)
    (setq tg-command-history '("attack rat" "move up" "take sword"))
    (setq tg-history-index -1)
    (setq tg-current-input "")
    (with-temp-buffer
      (tg-mode)
      (insert ">")
      (goto-char (point-max))
      (tg-history-prev)
      (should (string-match-p ">attack rat$" (buffer-string)))
      (tg-history-prev)
      (should (string-match-p ">move up$" (buffer-string)))
      (tg-history-prev)
      (should (string-match-p ">take sword$" (buffer-string)))
      ;; At end of history, should stay on last entry
      (tg-history-prev)
      (should (string-match-p ">take sword$" (buffer-string))))))

(ert-deftest test-tg-history-next-restores-input ()
  "tg-history-next should restore saved input when returning to present."
  (test-with-globals-saved (tg-command-history tg-history-index tg-current-input)
    (setq tg-command-history '("attack rat" "move up"))
    (setq tg-history-index -1)
    (setq tg-current-input "")
    (with-temp-buffer
      (tg-mode)
      (insert ">my text")
      (goto-char (point-max))
      (tg-history-prev)
      (tg-history-prev)
      (should (= tg-history-index 1))
      (tg-history-next)
      (should (string-match-p ">attack rat$" (buffer-string)))
      (should (= tg-history-index 0))
      (tg-history-next)
      (should (string-match-p ">my text$" (buffer-string)))
      (should (= tg-history-index -1)))))

(ert-deftest test-tg-history-next-at-present ()
  "tg-history-next at present should do nothing."
  (test-with-globals-saved (tg-command-history tg-history-index tg-current-input)
    (setq tg-command-history '("attack rat"))
    (setq tg-history-index -1)
    (with-temp-buffer
      (tg-mode)
      (insert ">test")
      (goto-char (point-max))
      (let ((before (buffer-string)))
        (tg-history-next)
        (should (equal (buffer-string) before))))))

(ert-deftest test-tg-record-history-success ()
  "tg-record-history should add command to front of history."
  (test-with-globals-saved (tg-command-history tg-history-index)
    (setq tg-command-history nil)
    (setq tg-history-index -1)
    (tg-record-history "attack rat")
    (should (equal tg-command-history '("attack rat")))
    (tg-record-history "move up")
    (should (equal tg-command-history '("move up" "attack rat")))))

(ert-deftest test-tg-record-history-dedup ()
  "tg-record-history should skip duplicate of most recent entry."
  (test-with-globals-saved (tg-command-history)
    (setq tg-command-history '("attack rat"))
    (tg-record-history "attack rat")
    (should (equal tg-command-history '("attack rat")))))

(ert-deftest test-tg-record-history-empty ()
  "tg-record-history should not record empty strings."
  (test-with-globals-saved (tg-command-history)
    (setq tg-command-history nil)
    (tg-record-history "")
    (should (equal tg-command-history nil))))

(ert-deftest test-tg-record-history-max ()
  "tg-record-history should trim history beyond max size."
  (test-with-globals-saved (tg-command-history tg-command-history-max)
    (setq tg-command-history-max 3)
    (setq tg-command-history nil)
    (tg-record-history "a")
    (tg-record-history "b")
    (tg-record-history "c")
    (tg-record-history "d")
    (should (= (length tg-command-history) 3))
    (should (equal (car tg-command-history) "d"))))

;; --- Tab completion ---

(ert-deftest test-tg-complete-unique-prefix ()
  "tg-complete-command should complete unique prefix."
  (test-with-globals-saved (tg-valid-actions)
    (setq tg-valid-actions '(tg-attack tg-move tg-help))
    (with-temp-buffer
      (tg-mode)
      (insert ">at")
      (goto-char (point-max))
      (tg-complete-command)
      (should (string-match-p ">attack$" (buffer-string))))))

(ert-deftest test-tg-complete-no-match ()
  "tg-complete-command should do nothing with no match."
  (test-with-globals-saved (tg-valid-actions)
    (setq tg-valid-actions '(tg-attack tg-move))
    (with-temp-buffer
      (tg-mode)
      (insert ">xyz")
      (goto-char (point-max))
      (let ((before (buffer-string)))
        (tg-complete-command)
        (should (equal (buffer-string) before))))))

(ert-deftest test-tg-complete-already-complete ()
  "tg-complete-command should do nothing when already complete."
  (test-with-globals-saved (tg-valid-actions)
    (setq tg-valid-actions '(tg-attack tg-move))
    (with-temp-buffer
      (tg-mode)
      (insert ">attack")
      (goto-char (point-max))
      (let ((before (buffer-string)))
        (tg-complete-command)
        (should (equal (buffer-string) before))))))

(ert-deftest test-tg-complete-ambiguous-shows-candidates ()
  "tg-complete-command on ambiguous prefix should show candidates via tg-display."
  (test-with-globals-saved (tg-valid-actions tg-display-fn)
    (setq tg-valid-actions '(tg-talk tg-take))
    (let (output)
      (setq tg-display-fn (lambda (&rest args) (push args output)))
      (with-temp-buffer
        (tg-mode)
        (insert ">ta")
        (goto-char (point-max))
        (tg-complete-command)
        (should (cl-some (lambda (s) (string-match-p "talk" s)) (mapcar #'car output)))
        (should (cl-some (lambda (s) (string-match-p "take" s)) (mapcar #'car output)))))))

;; --- tg-parse returns action result (not "t") ---

(ert-deftest test-tg-parse-action-result-not-t ()
  "tg-parse should display the action's return value, not symbol t."
  (test-with-globals-saved (tg-valid-actions tg-over-p current-room rooms-alist room-map)
    (setq tg-valid-actions '(tg-watch))
    (setq current-room (make-Room :symbol 'test-room :description "A test room"))
    (setq rooms-alist (list (cons 'test-room current-room)))
    (setq room-map '((test-room)))
    (with-temp-buffer
      (tg-mode)
      (insert ">watch\n")
      (goto-char (point-max))
      (forward-line -1)
      (tg-parse 1)
      (let ((buf (buffer-string)))
        (should-not (string-match-p "^t$" buf))
        (should (string-match-p "test room" buf))))))

;; --- Passive actions should not trigger NPC behaviors ---

(ert-deftest test-tg-parse-watch-does-not-trigger-npc ()
  "watch command should not trigger NPC behaviors (not consume a turn)."
  (test-with-globals-saved (tg-valid-actions tg-over-p current-room rooms-alist room-map)
    (setq tg-valid-actions '(tg-watch))
    (setq current-room (make-Room :symbol 'test-room :description "A test room"))
    (setq rooms-alist (list (cons 'test-room current-room)))
    (setq room-map '((test-room)))
    (let ((npc-called nil))
      (cl-letf (((symbol-function 'npc-run-behaviors)
                 (lambda () (setq npc-called t))))
        (with-temp-buffer
          (tg-mode)
          (insert ">watch\n")
          (goto-char (point-max))
          (forward-line -1)
          (tg-parse 1)
          (should-not npc-called))))))

(ert-deftest test-tg-parse-attack-triggers-npc ()
  "attack command should trigger NPC behaviors (consumes a turn)."
  (test-with-globals-saved (tg-valid-actions tg-over-p current-room rooms-alist room-map
                             myself creatures-alist)
    (setq tg-valid-actions '(tg-attack))
    (let ((room (make-Room :symbol 'arena :description "An arena"))
          (rat (make-Creature :symbol 'rat :description "A rat"
                              :attr '((hp . 10) (attack . 2) (defense . 0)))))
      (setq current-room room)
      (setf (Room-creature room) '(rat))
      (setq rooms-alist (list (cons 'arena room)))
      (setq room-map '((arena)))
      (setq creatures-alist (list (cons 'rat rat)))
      (setq myself (make-Creature :symbol 'hero :attr '((hp . 100) (attack . 5) (defense . 3))))
      (let ((npc-called nil))
        (cl-letf (((symbol-function 'npc-run-behaviors)
                   (lambda () (setq npc-called t))))
          (with-temp-buffer
            (tg-mode)
            (insert ">attack rat\n")
            (goto-char (point-max))
            (forward-line -1)
            (tg-parse 1)
            (should npc-called)))))))

(provide 'test-tg-mode)
