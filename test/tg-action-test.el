;;; tg-action-test.el --- Tests for tg-action -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Text Game Maker
;; Author: DarkSun
;; Version: 1.0
;; Keywords: games, text, test

;;; Commentary:
;; Tests for the action system in tg-action.el

;;; Code:

(require 'ert)
(require 'tg-action)

(ert-deftest test-tg-register-action ()
  "Test that registering an action adds all synonyms to the action words hash table."
  ;; Save original hash table
  (let ((original tg--action-words)
        (new-hash (make-hash-table :test 'equal)))
    (setq tg--action-words new-hash)
    ;; Register an action with multiple synonyms
    (tg-register-action
     :id 'take-action
     :synonyms '("take" "get" "pick up")
     :handler (lambda () "take handler"))

    ;; Verify all synonyms are in the hash table
    (should (eq 'take-action (tg-find-action "take")))
    (should (eq 'take-action (tg-find-action "get")))
    (should (eq 'take-action (tg-find-action "pick up")))
    (should (null (tg-find-action "drop")))
    ;; Restore original hash table
    (setq tg--action-words original)))

(ert-deftest test-tg-find-action ()
  "Test finding actions by synonym."
  ;; Save original hash table
  (let ((original tg--action-words)
        (new-hash (make-hash-table :test 'equal)))
    (setq tg--action-words new-hash)
    ;; Register multiple actions
    (tg-register-action
     :id 'look-action
     :synonyms '("look" "l")
     :handler (lambda () "look handler"))

    (tg-register-action
     :id 'examine-action
     :synonyms '("examine" "x")
     :handler (lambda () "examine handler"))

    ;; Test finding actions
    (should (eq 'look-action (tg-find-action "look")))
    (should (eq 'look-action (tg-find-action "l")))
    (should (eq 'examine-action (tg-find-action "examine")))
    (should (eq 'examine-action (tg-find-action "x")))
    (should (null (tg-find-action "unknown")))
    ;; Restore original hash table
    (setq tg--action-words original)))

(ert-deftest test-tg-verb-aliases ()
  "Test verb aliases mapping."
  (should (equal (cdr (assoc "get" tg-verb-aliases)) "take"))
  (should (equal (cdr (assoc "l" tg-verb-aliases)) "look"))
  (should (equal (cdr (assoc "x" tg-verb-aliases)) "examine"))
  (should (equal (cdr (assoc "i" tg-verb-aliases)) "inventory"))
  (should (equal (cdr (assoc "pick up" tg-verb-aliases)) "take"))
  (should (equal (cdr (assoc "put down" tg-verb-aliases)) "drop"))
  (should (equal (cdr (assoc "equip" tg-verb-aliases)) "wear"))
  (should (equal (cdr (assoc "consume" tg-verb-aliases)) "eat"))
  (should (equal (cdr (assoc "hit" tg-verb-aliases)) "attack"))
  (should (equal (cdr (assoc "fight" tg-verb-aliases)) "attack"))
  (should (equal (cdr (assoc "speak" tg-verb-aliases)) "talk"))
  (should (null (cdr (assoc "unknown" tg-verb-aliases)))))

(ert-deftest test-tg-passive-actions ()
  "Test passive actions list."
  (should (member "look" tg-passive-actions))
  (should (member "examine" tg-passive-actions))
  (should (member "inventory" tg-passive-actions))
  (should (member "status" tg-passive-actions))
  (should (member "quests" tg-passive-actions))
  (should (member "help" tg-passive-actions))
  (should (not (member "attack" tg-passive-actions)))
  (should (not (member "take" tg-passive-actions))))

(ert-deftest test-action-structure ()
  "Test the tg-action structure definition."
  (let ((action (make-tg-action
                 :id 'test-action
                 :synonyms '("test" "t")
                 :handler (lambda () "test handler"))))
    (should (eq 'test-action (tg-action-id action)))
    (should (equal '("test" "t") (tg-action-synonyms action)))
    (should (functionp (tg-action-handler action)))))

(provide 'tg-action-test)
;;; tg-action-test.el ends here