;;; test-action.el --- Tests for action.el -*- lexical-binding: t; -*-

(require 'ert)
(require 'test-helper)
(require 'text-game-maker)

;; Dynamic variable for trigger tests (EIEIO slots lose lexical closures)
(defvar test-trigger-called nil)

;; --- tg-defaction ---

(ert-deftest test-tg-defaction-registers-action ()
  "tg-defaction should register the action in tg-valid-actions."
  (test-with-globals-saved (tg-valid-actions)
    (setq tg-valid-actions nil)
    (tg-defaction tg-test-action1 ()
      "A test action."
      "test-result")
    (should (member 'tg-test-action1 tg-valid-actions))))

(ert-deftest test-tg-defaction-defines-function ()
  "tg-defaction should define the function."
  (test-with-globals-saved (tg-valid-actions)
    (setq tg-valid-actions nil)
    (tg-defaction tg-test-action2 (x)
      "A test action with arg."
      (format "got %s" x))
    (should (fboundp 'tg-test-action2))
    (should (equal (tg-test-action2 "hello") "got hello"))))

(ert-deftest test-tg-defaction-docstring ()
  "tg-defaction should set the docstring."
  (test-with-globals-saved (tg-valid-actions)
    (setq tg-valid-actions nil)
    (tg-defaction tg-test-action3 ()
      "Test docstring here."
      nil)
    (should (equal (documentation 'tg-test-action3) "Test docstring here."))))

;; --- tg-move ---

(defun test-setup-move-env ()
  "Set up environment for move tests. Returns a plist with rooms."
  (let* ((room1 (make-instance 'Room :symbol 'room1 :description "Room 1"))
         (room2 (make-instance 'Room :symbol 'room2 :description "Room 2"
                               :in-trigger (lambda () (tg-display "entered room2"))))
         (rmap '((room1 room2))))
    (setq rooms-alist (list (cons 'room1 room1) (cons 'room2 room2)))
    (setq room-map rmap)
    (setq currect-room room1)
    (list :room1 room1 :room2 room2)))

(ert-deftest test-tg-move-valid-direction-string ()
  "tg-move should move to correct room with string direction."
  (test-with-globals-saved (rooms-alist room-map currect-room tg-valid-actions display-fn)
    (setq tg-valid-actions (copy-sequence tg-valid-actions))
    (let ((display-output nil)
          (env (test-setup-move-env)))
      (setq display-fn (lambda (&rest args) (setq display-output args)))
      ;; room1 is at (0,0), right neighbor is room2
      (tg-move "right")
      (should (equal (member-symbol currect-room) 'room2)))))

(ert-deftest test-tg-move-valid-direction-symbol ()
  "tg-move should move to correct room with symbol direction."
  (test-with-globals-saved (rooms-alist room-map currect-room tg-valid-actions display-fn)
    (setq tg-valid-actions (copy-sequence tg-valid-actions))
    (let ((display-output nil)
          (env (test-setup-move-env)))
      (setq display-fn (lambda (&rest args) (setq display-output args)))
      (tg-move 'right)
      (should (equal (member-symbol currect-room) 'room2)))))

(ert-deftest test-tg-move-unknown-direction ()
  "tg-move should throw exception for unknown direction."
  (test-with-globals-saved (rooms-alist room-map currect-room tg-valid-actions display-fn)
    (setq tg-valid-actions (copy-sequence tg-valid-actions))
    (test-setup-move-env)
    (setq display-fn #'ignore)
    (should (equal (catch 'exception (tg-move "diagonal"))
                   "未知的方向"))))

(ert-deftest test-tg-move-no-path ()
  "tg-move should throw exception when there is no room in that direction."
  (test-with-globals-saved (rooms-alist room-map currect-room tg-valid-actions display-fn)
    (setq tg-valid-actions (copy-sequence tg-valid-actions))
    (test-setup-move-env)
    (setq display-fn #'ignore)
    ;; room1 is at top-left, no room above
    (should (equal (catch 'exception (tg-move "up"))
                   "那里没有路"))))

(ert-deftest test-tg-move-triggers-out-trigger ()
  "tg-move should call out-trigger when leaving room."
  (test-with-globals-saved (rooms-alist room-map currect-room tg-valid-actions display-fn)
    (setq tg-valid-actions (copy-sequence tg-valid-actions))
    (let ((room1 (make-instance 'Room :symbol 'room1 :description "Room 1"
                                :out-trigger (lambda () (setq test-trigger-called t))))
          (room2 (make-instance 'Room :symbol 'room2 :description "Room 2")))
      (setq rooms-alist (list (cons 'room1 room1) (cons 'room2 room2)))
      (setq room-map '((room1 room2)))
      (setq currect-room room1)
      (setq display-fn #'ignore)
      (setq test-trigger-called nil)
      (tg-move "right")
      (should test-trigger-called))))

(ert-deftest test-tg-move-triggers-in-trigger ()
  "tg-move should call in-trigger when entering room."
  (test-with-globals-saved (rooms-alist room-map currect-room tg-valid-actions display-fn)
    (setq tg-valid-actions (copy-sequence tg-valid-actions))
    (let ((room1 (make-instance 'Room :symbol 'room1 :description "Room 1"))
          (room2 (make-instance 'Room :symbol 'room2 :description "Room 2"
                                :in-trigger (lambda () (setq test-trigger-called t)))))
      (setq rooms-alist (list (cons 'room1 room1) (cons 'room2 room2)))
      (setq room-map '((room1 room2)))
      (setq currect-room room1)
      (setq display-fn #'ignore)
      (setq test-trigger-called nil)
      (tg-move "right")
      (should test-trigger-called))))

;; --- tg-watch ---

(ert-deftest test-tg-watch-room-description ()
  "tg-watch with no args should describe current room."
  (test-with-globals-saved (rooms-alist room-map currect-room tg-valid-actions display-fn)
    (setq tg-valid-actions (copy-sequence tg-valid-actions))
    (let ((room (make-instance 'Room :symbol 'room1 :description "A room")))
      (setq rooms-alist (list (cons 'room1 room)))
      (setq room-map '((room1)))
      (setq currect-room room)
      (setq display-fn #'ignore)
      (let ((result (tg-watch)))
        (should (string-match-p "room1" result))))))

(ert-deftest test-tg-watch-inventory ()
  "tg-watch with inventory symbol should describe the inventory."
  (test-with-globals-saved (rooms-alist room-map currect-room tg-valid-actions display-fn inventorys-alist)
    (setq tg-valid-actions (copy-sequence tg-valid-actions))
    (let* ((room (make-instance 'Room :symbol 'room1 :description "A room" :inventory '(potion)))
           (inv (make-instance 'Inventory :symbol 'potion :description "A potion" :type '(usable) :effects nil)))
      (setq rooms-alist (list (cons 'room1 room)))
      (setq room-map '((room1)))
      (setq currect-room room)
      (setq inventorys-alist (list (cons 'potion inv)))
      (setq display-fn #'ignore)
      (let ((result (tg-watch 'potion)))
        (should (string-match-p "potion" result))))))

(ert-deftest test-tg-watch-nonexistent-item ()
  "tg-watch should throw exception for nonexistent item in room."
  (test-with-globals-saved (rooms-alist room-map currect-room tg-valid-actions display-fn inventorys-alist)
    (setq tg-valid-actions (copy-sequence tg-valid-actions))
    (let ((room (make-instance 'Room :symbol 'room1 :description "A room")))
      (setq rooms-alist (list (cons 'room1 room)))
      (setq room-map '((room1)))
      (setq currect-room room)
      (setq inventorys-alist nil)
      (setq display-fn #'ignore)
      (should (equal (catch 'exception (tg-watch 'ghost))
                     "房间中没有ghost")))))

;; --- tg-take ---

(ert-deftest test-tg-take-existing-item ()
  "tg-take should move item from room to creature inventory."
  (test-with-globals-saved (rooms-alist room-map currect-room tg-valid-actions display-fn
                                        inventorys-alist creatures-alist myself)
    (setq tg-valid-actions (copy-sequence tg-valid-actions))
    (let* ((room (make-instance 'Room :symbol 'room1 :description "A room" :inventory '(potion)))
           (inv (make-instance 'Inventory :symbol 'potion :description "A potion" :type '(usable)))
           (cr (make-instance 'Creature :symbol 'hero :description "The hero" :attr '((hp . 100)))))
      (setq rooms-alist (list (cons 'room1 room)))
      (setq room-map '((room1)))
      (setq currect-room room)
      (setq inventorys-alist (list (cons 'potion inv)))
      (setq creatures-alist (list (cons 'hero cr)))
      (setq myself cr)
      (setq display-fn #'ignore)
      (tg-take 'potion)
      (should-not (inventory-exist-in-room-p room 'potion))
      (should (inventory-exist-in-creature-p cr 'potion)))))

(ert-deftest test-tg-take-nonexistent-item ()
  "tg-take should throw exception for nonexistent item."
  (test-with-globals-saved (rooms-alist room-map currect-room tg-valid-actions display-fn)
    (setq tg-valid-actions (copy-sequence tg-valid-actions))
    (let ((room (make-instance 'Room :symbol 'room1 :description "A room")))
      (setq rooms-alist (list (cons 'room1 room)))
      (setq room-map '((room1)))
      (setq currect-room room)
      (setq display-fn #'ignore)
      (should (equal (catch 'exception (tg-take 'nothing))
                     "房间中没有nothing")))))

(ert-deftest test-tg-take-triggers-take-trigger ()
  "tg-take should call take-trigger on the inventory."
  (test-with-globals-saved (rooms-alist room-map currect-room tg-valid-actions display-fn
                                        inventorys-alist creatures-alist myself)
    (setq tg-valid-actions (copy-sequence tg-valid-actions))
    (let ((room (make-instance 'Room :symbol 'room1 :description "A room" :inventory '(potion)))
          (inv (make-instance 'Inventory :symbol 'potion :description "A potion" :type '(usable)
                              :take-trigger (lambda () (setq test-trigger-called t))))
          (cr (make-instance 'Creature :symbol 'hero :description "The hero")))
      (setq rooms-alist (list (cons 'room1 room)))
      (setq room-map '((room1)))
      (setq currect-room room)
      (setq inventorys-alist (list (cons 'potion inv)))
      (setq creatures-alist (list (cons 'hero cr)))
      (setq myself cr)
      (setq display-fn #'ignore)
      (setq test-trigger-called nil)
      (tg-take 'potion)
      (should test-trigger-called))))

;; --- tg-drop ---

(ert-deftest test-tg-drop-carried-item ()
  "tg-drop should move item from creature to room."
  (test-with-globals-saved (rooms-alist room-map currect-room tg-valid-actions display-fn
                                        inventorys-alist creatures-alist myself)
    (setq tg-valid-actions (copy-sequence tg-valid-actions))
    (let* ((room (make-instance 'Room :symbol 'room1 :description "A room"))
           (inv (make-instance 'Inventory :symbol 'potion :description "A potion" :type '(usable)))
           (cr (make-instance 'Creature :symbol 'hero :description "The hero" :inventory '(potion))))
      (setq rooms-alist (list (cons 'room1 room)))
      (setq room-map '((room1)))
      (setq currect-room room)
      (setq inventorys-alist (list (cons 'potion inv)))
      (setq creatures-alist (list (cons 'hero cr)))
      (setq myself cr)
      (setq display-fn #'ignore)
      (tg-drop 'potion)
      (should-not (inventory-exist-in-creature-p cr 'potion))
      (should (inventory-exist-in-room-p room 'potion)))))

(ert-deftest test-tg-drop-not-carried ()
  "tg-drop should throw exception when item not carried."
  (test-with-globals-saved (rooms-alist room-map currect-room tg-valid-actions display-fn
                                        creatures-alist myself)
    (setq tg-valid-actions (copy-sequence tg-valid-actions))
    (let* ((room (make-instance 'Room :symbol 'room1 :description "A room"))
           (cr (make-instance 'Creature :symbol 'hero :description "The hero")))
      (setq rooms-alist (list (cons 'room1 room)))
      (setq room-map '((room1)))
      (setq currect-room room)
      (setq creatures-alist (list (cons 'hero cr)))
      (setq myself cr)
      (setq display-fn #'ignore)
      (should (equal (catch 'exception (tg-drop 'nothing))
                     "身上没有nothing")))))

(ert-deftest test-tg-drop-triggers-drop-trigger ()
  "tg-drop should call drop-trigger on the inventory."
  (test-with-globals-saved (rooms-alist room-map currect-room tg-valid-actions display-fn
                                        inventorys-alist creatures-alist myself)
    (setq tg-valid-actions (copy-sequence tg-valid-actions))
    (let ((room (make-instance 'Room :symbol 'room1 :description "A room"))
          (inv (make-instance 'Inventory :symbol 'potion :description "A potion" :type '(usable)
                              :drop-trigger (lambda () (setq test-trigger-called t))))
          (cr (make-instance 'Creature :symbol 'hero :description "The hero" :inventory '(potion))))
      (setq rooms-alist (list (cons 'room1 room)))
      (setq room-map '((room1)))
      (setq currect-room room)
      (setq inventorys-alist (list (cons 'potion inv)))
      (setq creatures-alist (list (cons 'hero cr)))
      (setq myself cr)
      (setq display-fn #'ignore)
      (setq test-trigger-called nil)
      (tg-drop 'potion)
      (should test-trigger-called))))

;; --- tg-use ---

(ert-deftest test-tg-use-usable-item ()
  "tg-use should apply effects and remove consumable item."
  (test-with-globals-saved (rooms-alist room-map currect-room tg-valid-actions display-fn
                                        inventorys-alist creatures-alist myself)
    (setq tg-valid-actions (copy-sequence tg-valid-actions))
    (let* ((room (make-instance 'Room :symbol 'room1 :description "A room"))
           (inv (make-instance 'Inventory :symbol 'potion :description "A potion"
                               :type '(usable) :effects '((hp . 10))))
           (cr (make-instance 'Creature :symbol 'hero :description "The hero"
                              :attr '((hp . 100)) :inventory '(potion))))
      (setq rooms-alist (list (cons 'room1 room)))
      (setq room-map '((room1)))
      (setq currect-room room)
      (setq inventorys-alist (list (cons 'potion inv)))
      (setq creatures-alist (list (cons 'hero cr)))
      (setq myself cr)
      (setq display-fn #'ignore)
      (tg-use 'potion)
      (should (= (cdr (assoc 'hp (member-attr cr))) 110))
      (should-not (inventory-exist-in-creature-p cr 'potion)))))

(ert-deftest test-tg-use-not-carried ()
  "tg-use should throw exception when item not carried."
  (test-with-globals-saved (rooms-alist room-map currect-room tg-valid-actions display-fn
                                        creatures-alist myself)
    (setq tg-valid-actions (copy-sequence tg-valid-actions))
    (let* ((room (make-instance 'Room :symbol 'room1 :description "A room"))
           (cr (make-instance 'Creature :symbol 'hero :description "The hero")))
      (setq rooms-alist (list (cons 'room1 room)))
      (setq room-map '((room1)))
      (setq currect-room room)
      (setq creatures-alist (list (cons 'hero cr)))
      (setq myself cr)
      (setq display-fn #'ignore)
      (should (equal (catch 'exception (tg-use 'potion))
                     "未携带potion")))))

(ert-deftest test-tg-use-not-consumable ()
  "tg-use should throw exception for non-consumable items."
  (test-with-globals-saved (rooms-alist room-map currect-room tg-valid-actions display-fn
                                        inventorys-alist creatures-alist myself)
    (setq tg-valid-actions (copy-sequence tg-valid-actions))
    (let* ((room (make-instance 'Room :symbol 'room1 :description "A room"))
           (inv (make-instance 'Inventory :symbol 'rock :description "A rock"
                               :type '(junk) :effects nil))
           (cr (make-instance 'Creature :symbol 'hero :description "The hero" :inventory '(rock))))
      (setq rooms-alist (list (cons 'room1 room)))
      (setq room-map '((room1)))
      (setq currect-room room)
      (setq inventorys-alist (list (cons 'rock inv)))
      (setq creatures-alist (list (cons 'hero cr)))
      (setq myself cr)
      (setq display-fn #'ignore)
      (should (equal (catch 'exception (tg-use 'rock))
                     "rock不可使用")))))

;; --- tg-status ---

(ert-deftest test-tg-status ()
  "tg-status should display current creature description."
  (test-with-globals-saved (tg-valid-actions creatures-alist myself display-fn)
    (setq tg-valid-actions (copy-sequence tg-valid-actions))
    (let* ((cr (make-instance 'Creature :symbol 'hero :description "The hero"
                              :attr '((hp . 100))))
           (output nil))
      (setq creatures-alist (list (cons 'hero cr)))
      (setq myself cr)
      (setq display-fn (lambda (&rest args) (setq output args)))
      (tg-status)
      (should output)
      (should (string-match-p "hero" (car output))))))

;; --- tg-help ---

(ert-deftest test-tg-help-all ()
  "tg-help with no args should show all actions."
  (test-with-globals-saved (tg-valid-actions display-fn)
    (setq tg-valid-actions (copy-sequence tg-valid-actions))
    (let ((output nil))
      (setq display-fn (lambda (&rest args) (push args output)))
      (tg-help)
      ;; Should have displayed docs for each valid action
      (should (>= (length output) (length tg-valid-actions))))))

(ert-deftest test-tg-help-specific-command ()
  "tg-help with specific command should show that command's doc."
  (test-with-globals-saved (tg-valid-actions display-fn)
    (setq tg-valid-actions (copy-sequence tg-valid-actions))
    (let ((output nil))
      (setq display-fn (lambda (&rest args) (push args output)))
      (tg-help "move")
      (should (= (length output) 1))
      (should (string-match-p "move" (caar output))))))

;; --- tg-quit ---

(ert-deftest test-tg-quit ()
  "tg-quit should set tg-over-p to t."
  (test-with-globals-saved (tg-over-p tg-valid-actions)
    (setq tg-valid-actions (copy-sequence tg-valid-actions))
    (setq tg-over-p nil)
    (tg-quit)
    (should tg-over-p)))

(provide 'test-action)
