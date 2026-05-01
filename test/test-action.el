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
  (let* ((room1 (make-Room :symbol 'room1 :description "Room 1"))
         (room2 (make-Room :symbol 'room2 :description "Room 2"
                               :in-trigger (lambda () (tg-display "entered room2"))))
         (rmap '((room1 room2))))
    (setq rooms-alist (list (cons 'room1 room1) (cons 'room2 room2)))
    (setq room-map rmap)
    (setq current-room room1)
    (list :room1 room1 :room2 room2)))

(ert-deftest test-tg-move-valid-direction-string ()
  "tg-move should move to correct room with string direction."
  (test-with-globals-saved (rooms-alist room-map current-room tg-valid-actions display-fn)
    (setq tg-valid-actions (copy-sequence tg-valid-actions))
    (let ((display-output nil)
          (env (test-setup-move-env)))
      (setq display-fn (lambda (&rest args) (setq display-output args)))
      ;; room1 is at (0,0), right neighbor is room2
      (tg-move "right")
      (should (equal (Room-symbol current-room) 'room2)))))

(ert-deftest test-tg-move-valid-direction-symbol ()
  "tg-move should move to correct room with symbol direction."
  (test-with-globals-saved (rooms-alist room-map current-room tg-valid-actions display-fn)
    (setq tg-valid-actions (copy-sequence tg-valid-actions))
    (let ((display-output nil)
          (env (test-setup-move-env)))
      (setq display-fn (lambda (&rest args) (setq display-output args)))
      (tg-move 'right)
      (should (equal (Room-symbol current-room) 'room2)))))

(ert-deftest test-tg-move-unknown-direction ()
  "tg-move should throw exception for unknown direction."
  (test-with-globals-saved (rooms-alist room-map current-room tg-valid-actions display-fn)
    (setq tg-valid-actions (copy-sequence tg-valid-actions))
    (test-setup-move-env)
    (setq display-fn #'ignore)
    (should (equal (catch 'exception (tg-move "diagonal"))
                   "未知的方向"))))

(ert-deftest test-tg-move-no-path ()
  "tg-move should throw exception when there is no room in that direction."
  (test-with-globals-saved (rooms-alist room-map current-room tg-valid-actions display-fn)
    (setq tg-valid-actions (copy-sequence tg-valid-actions))
    (test-setup-move-env)
    (setq display-fn #'ignore)
    ;; room1 is at top-left, no room above
    (should (equal (catch 'exception (tg-move "up"))
                   "那里没有路"))))

(ert-deftest test-tg-move-triggers-out-trigger ()
  "tg-move should call out-trigger when leaving room."
  (test-with-globals-saved (rooms-alist room-map current-room tg-valid-actions display-fn)
    (setq tg-valid-actions (copy-sequence tg-valid-actions))
    (let ((room1 (make-Room :symbol 'room1 :description "Room 1"
                                :out-trigger (lambda () (setq test-trigger-called t))))
          (room2 (make-Room :symbol 'room2 :description "Room 2")))
      (setq rooms-alist (list (cons 'room1 room1) (cons 'room2 room2)))
      (setq room-map '((room1 room2)))
      (setq current-room room1)
      (setq display-fn #'ignore)
      (setq test-trigger-called nil)
      (tg-move "right")
      (should test-trigger-called))))

(ert-deftest test-tg-move-triggers-in-trigger ()
  "tg-move should call in-trigger when entering room."
  (test-with-globals-saved (rooms-alist room-map current-room tg-valid-actions display-fn)
    (setq tg-valid-actions (copy-sequence tg-valid-actions))
    (let ((room1 (make-Room :symbol 'room1 :description "Room 1"))
          (room2 (make-Room :symbol 'room2 :description "Room 2"
                                :in-trigger (lambda () (setq test-trigger-called t)))))
      (setq rooms-alist (list (cons 'room1 room1) (cons 'room2 room2)))
      (setq room-map '((room1 room2)))
      (setq current-room room1)
      (setq display-fn #'ignore)
      (setq test-trigger-called nil)
      (tg-move "right")
      (should test-trigger-called))))

;; --- tg-watch ---

(ert-deftest test-tg-watch-room-description ()
  "tg-watch with no args should describe current room."
  (test-with-globals-saved (rooms-alist room-map current-room tg-valid-actions display-fn)
    (setq tg-valid-actions (copy-sequence tg-valid-actions))
    (let ((room (make-Room :symbol 'room1 :description "A room")))
      (setq rooms-alist (list (cons 'room1 room)))
      (setq room-map '((room1)))
      (setq current-room room)
      (setq display-fn #'ignore)
      (let ((result (tg-watch)))
        (should (string-match-p "room1" result))))))

(ert-deftest test-tg-watch-inventory ()
  "tg-watch with inventory symbol should describe the inventory."
  (test-with-globals-saved (rooms-alist room-map current-room tg-valid-actions display-fn inventorys-alist)
    (setq tg-valid-actions (copy-sequence tg-valid-actions))
    (let* ((room (make-Room :symbol 'room1 :description "A room" :inventory '(potion)))
           (inv (make-Inventory :symbol 'potion :description "A potion" :type '(usable) :effects nil)))
      (setq rooms-alist (list (cons 'room1 room)))
      (setq room-map '((room1)))
      (setq current-room room)
      (setq inventorys-alist (list (cons 'potion inv)))
      (setq display-fn #'ignore)
      (let ((result (tg-watch 'potion)))
        (should (string-match-p "potion" result))))))

(ert-deftest test-tg-watch-nonexistent-item ()
  "tg-watch should throw exception for nonexistent item in room."
  (test-with-globals-saved (rooms-alist room-map current-room tg-valid-actions display-fn inventorys-alist)
    (setq tg-valid-actions (copy-sequence tg-valid-actions))
    (let ((room (make-Room :symbol 'room1 :description "A room")))
      (setq rooms-alist (list (cons 'room1 room)))
      (setq room-map '((room1)))
      (setq current-room room)
      (setq inventorys-alist nil)
      (setq display-fn #'ignore)
      (should (equal (catch 'exception (tg-watch 'ghost))
                     "房间中没有ghost")))))

(ert-deftest test-tg-watch-creature ()
  "tg-watch should describe a creature in the room."
  (test-with-globals-saved (rooms-alist room-map current-room tg-valid-actions display-fn
                                        inventorys-alist creatures-alist)
    (setq tg-valid-actions (copy-sequence tg-valid-actions))
    (let* ((room (make-Room :symbol 'room1 :description "A room" :creature '(goblin)))
           (cr (make-Creature :symbol 'goblin :description "A goblin"
                              :attr '((hp . 20)))))
      (setq rooms-alist (list (cons 'room1 room)))
      (setq room-map '((room1)))
      (setq current-room room)
      (setq inventorys-alist nil)
      (setq creatures-alist (list (cons 'goblin cr)))
      (setq display-fn #'ignore)
      (let ((result (tg-watch 'goblin)))
        (should (string-match-p "goblin" result))))))

;; --- tg-take ---

(ert-deftest test-tg-take-existing-item ()
  "tg-take should move item from room to creature inventory."
  (test-with-globals-saved (rooms-alist room-map current-room tg-valid-actions display-fn
                                        inventorys-alist creatures-alist myself)
    (setq tg-valid-actions (copy-sequence tg-valid-actions))
    (let* ((room (make-Room :symbol 'room1 :description "A room" :inventory '(potion)))
           (inv (make-Inventory :symbol 'potion :description "A potion" :type '(usable)))
           (cr (make-Creature :symbol 'hero :description "The hero" :attr '((hp . 100)))))
      (setq rooms-alist (list (cons 'room1 room)))
      (setq room-map '((room1)))
      (setq current-room room)
      (setq inventorys-alist (list (cons 'potion inv)))
      (setq creatures-alist (list (cons 'hero cr)))
      (setq myself cr)
      (setq display-fn #'ignore)
      (tg-take 'potion)
      (should-not (inventory-exist-in-room-p room 'potion))
      (should (inventory-exist-in-creature-p cr 'potion)))))

(ert-deftest test-tg-take-nonexistent-item ()
  "tg-take should throw exception for nonexistent item."
  (test-with-globals-saved (rooms-alist room-map current-room tg-valid-actions display-fn)
    (setq tg-valid-actions (copy-sequence tg-valid-actions))
    (let ((room (make-Room :symbol 'room1 :description "A room")))
      (setq rooms-alist (list (cons 'room1 room)))
      (setq room-map '((room1)))
      (setq current-room room)
      (setq display-fn #'ignore)
      (should (equal (catch 'exception (tg-take 'nothing))
                     "房间中没有nothing")))))

(ert-deftest test-tg-take-triggers-take-trigger ()
  "tg-take should call take-trigger on the inventory."
  (test-with-globals-saved (rooms-alist room-map current-room tg-valid-actions display-fn
                                        inventorys-alist creatures-alist myself)
    (setq tg-valid-actions (copy-sequence tg-valid-actions))
    (let ((room (make-Room :symbol 'room1 :description "A room" :inventory '(potion)))
          (inv (make-Inventory :symbol 'potion :description "A potion" :type '(usable)
                              :take-trigger (lambda () (setq test-trigger-called t))))
          (cr (make-Creature :symbol 'hero :description "The hero")))
      (setq rooms-alist (list (cons 'room1 room)))
      (setq room-map '((room1)))
      (setq current-room room)
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
  (test-with-globals-saved (rooms-alist room-map current-room tg-valid-actions display-fn
                                        inventorys-alist creatures-alist myself)
    (setq tg-valid-actions (copy-sequence tg-valid-actions))
    (let* ((room (make-Room :symbol 'room1 :description "A room"))
           (inv (make-Inventory :symbol 'potion :description "A potion" :type '(usable)))
           (cr (make-Creature :symbol 'hero :description "The hero" :inventory '(potion))))
      (setq rooms-alist (list (cons 'room1 room)))
      (setq room-map '((room1)))
      (setq current-room room)
      (setq inventorys-alist (list (cons 'potion inv)))
      (setq creatures-alist (list (cons 'hero cr)))
      (setq myself cr)
      (setq display-fn #'ignore)
      (tg-drop 'potion)
      (should-not (inventory-exist-in-creature-p cr 'potion))
      (should (inventory-exist-in-room-p room 'potion)))))

(ert-deftest test-tg-drop-not-carried ()
  "tg-drop should throw exception when item not carried."
  (test-with-globals-saved (rooms-alist room-map current-room tg-valid-actions display-fn
                                        creatures-alist myself)
    (setq tg-valid-actions (copy-sequence tg-valid-actions))
    (let* ((room (make-Room :symbol 'room1 :description "A room"))
           (cr (make-Creature :symbol 'hero :description "The hero")))
      (setq rooms-alist (list (cons 'room1 room)))
      (setq room-map '((room1)))
      (setq current-room room)
      (setq creatures-alist (list (cons 'hero cr)))
      (setq myself cr)
      (setq display-fn #'ignore)
      (should (equal (catch 'exception (tg-drop 'nothing))
                     "身上没有nothing")))))

(ert-deftest test-tg-drop-triggers-drop-trigger ()
  "tg-drop should call drop-trigger on the inventory."
  (test-with-globals-saved (rooms-alist room-map current-room tg-valid-actions display-fn
                                        inventorys-alist creatures-alist myself)
    (setq tg-valid-actions (copy-sequence tg-valid-actions))
    (let ((room (make-Room :symbol 'room1 :description "A room"))
          (inv (make-Inventory :symbol 'potion :description "A potion" :type '(usable)
                              :drop-trigger (lambda () (setq test-trigger-called t))))
          (cr (make-Creature :symbol 'hero :description "The hero" :inventory '(potion))))
      (setq rooms-alist (list (cons 'room1 room)))
      (setq room-map '((room1)))
      (setq current-room room)
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
  (test-with-globals-saved (rooms-alist room-map current-room tg-valid-actions display-fn
                                        inventorys-alist creatures-alist myself)
    (setq tg-valid-actions (copy-sequence tg-valid-actions))
    (let* ((room (make-Room :symbol 'room1 :description "A room"))
           (inv (make-Inventory :symbol 'potion :description "A potion"
                               :type '(usable) :effects '((hp . 10))))
           (cr (make-Creature :symbol 'hero :description "The hero"
                              :attr '((hp . 100)) :inventory '(potion))))
      (setq rooms-alist (list (cons 'room1 room)))
      (setq room-map '((room1)))
      (setq current-room room)
      (setq inventorys-alist (list (cons 'potion inv)))
      (setq creatures-alist (list (cons 'hero cr)))
      (setq myself cr)
      (setq display-fn #'ignore)
      (tg-use 'potion)
      (should (= (cdr (assoc 'hp (Creature-attr cr))) 110))
      (should-not (inventory-exist-in-creature-p cr 'potion)))))

(ert-deftest test-tg-use-not-carried ()
  "tg-use should throw exception when item not carried."
  (test-with-globals-saved (rooms-alist room-map current-room tg-valid-actions display-fn
                                        creatures-alist myself)
    (setq tg-valid-actions (copy-sequence tg-valid-actions))
    (let* ((room (make-Room :symbol 'room1 :description "A room"))
           (cr (make-Creature :symbol 'hero :description "The hero")))
      (setq rooms-alist (list (cons 'room1 room)))
      (setq room-map '((room1)))
      (setq current-room room)
      (setq creatures-alist (list (cons 'hero cr)))
      (setq myself cr)
      (setq display-fn #'ignore)
      (should (equal (catch 'exception (tg-use 'potion))
                     "未携带potion")))))

(ert-deftest test-tg-use-not-consumable ()
  "tg-use should throw exception for non-consumable items."
  (test-with-globals-saved (rooms-alist room-map current-room tg-valid-actions display-fn
                                        inventorys-alist creatures-alist myself)
    (setq tg-valid-actions (copy-sequence tg-valid-actions))
    (let* ((room (make-Room :symbol 'room1 :description "A room"))
           (inv (make-Inventory :symbol 'rock :description "A rock"
                               :type '(junk) :effects nil))
           (cr (make-Creature :symbol 'hero :description "The hero" :inventory '(rock))))
      (setq rooms-alist (list (cons 'room1 room)))
      (setq room-map '((room1)))
      (setq current-room room)
      (setq inventorys-alist (list (cons 'rock inv)))
      (setq creatures-alist (list (cons 'hero cr)))
      (setq myself cr)
      (setq display-fn #'ignore)
      (should (equal (catch 'exception (tg-use 'rock))
                     "rock不可使用")))))

;; --- tg-wear ---

(ert-deftest test-tg-wear-wearable-item ()
  "tg-wear should equip item from creature's inventory."
  (test-with-globals-saved (rooms-alist room-map current-room tg-valid-actions display-fn
                                        inventorys-alist creatures-alist myself)
    (setq tg-valid-actions (copy-sequence tg-valid-actions))
    (let* ((room (make-Room :symbol 'room1 :description "A room"))
           (inv (make-Inventory :symbol 'armor :description "Steel armor"
                               :type '(wearable) :effects '((def . 5))))
           (cr (make-Creature :symbol 'hero :description "The hero"
                              :attr '((hp . 100)) :inventory '(armor))))
      (setq rooms-alist (list (cons 'room1 room)))
      (setq room-map '((room1)))
      (setq current-room room)
      (setq inventorys-alist (list (cons 'armor inv)))
      (setq creatures-alist (list (cons 'hero cr)))
      (setq myself cr)
      (setq display-fn #'ignore)
      (tg-wear 'armor)
      (should-not (inventory-exist-in-creature-p cr 'armor))
      (should (equipment-exist-in-creature-p cr 'armor)))))

(ert-deftest test-tg-wear-not-carried ()
  "tg-wear should throw exception when item not in creature's equipment list."
  (test-with-globals-saved (rooms-alist room-map current-room tg-valid-actions display-fn
                                        creatures-alist myself)
    (setq tg-valid-actions (copy-sequence tg-valid-actions))
    (let* ((room (make-Room :symbol 'room1 :description "A room"))
           (cr (make-Creature :symbol 'hero :description "The hero")))
      (setq rooms-alist (list (cons 'room1 room)))
      (setq room-map '((room1)))
      (setq current-room room)
      (setq creatures-alist (list (cons 'hero cr)))
      (setq myself cr)
      (setq display-fn #'ignore)
      (should (equal (catch 'exception (tg-wear 'armor))
                     "未携带armor")))))

(ert-deftest test-tg-wear-not-wearable ()
  "tg-wear should throw exception for non-wearable items."
  (test-with-globals-saved (rooms-alist room-map current-room tg-valid-actions display-fn
                                        inventorys-alist creatures-alist myself)
    (setq tg-valid-actions (copy-sequence tg-valid-actions))
    (let* ((room (make-Room :symbol 'room1 :description "A room"))
           (inv (make-Inventory :symbol 'potion :description "A potion"
                               :type '(usable) :effects '((hp . 10))))
           (cr (make-Creature :symbol 'hero :description "The hero"
                              :inventory '(potion))))
      (setq rooms-alist (list (cons 'room1 room)))
      (setq room-map '((room1)))
      (setq current-room room)
      (setq inventorys-alist (list (cons 'potion inv)))
      (setq creatures-alist (list (cons 'hero cr)))
      (setq myself cr)
      (setq display-fn #'ignore)
      (should (equal (catch 'exception (tg-wear 'potion))
                     "potion不可装备")))))

(ert-deftest test-tg-wear-triggers-wear-trigger ()
  "tg-wear should call wear-trigger on the inventory."
  (test-with-globals-saved (rooms-alist room-map current-room tg-valid-actions display-fn
                                        inventorys-alist creatures-alist myself)
    (setq tg-valid-actions (copy-sequence tg-valid-actions))
    (let ((room (make-Room :symbol 'room1 :description "A room"))
          (inv (make-Inventory :symbol 'armor :description "Steel armor"
                              :type '(wearable) :effects nil
                              :wear-trigger (lambda () (setq test-trigger-called t))))
          (cr (make-Creature :symbol 'hero :description "The hero"
                             :inventory '(armor))))
      (setq rooms-alist (list (cons 'room1 room)))
      (setq room-map '((room1)))
      (setq current-room room)
      (setq inventorys-alist (list (cons 'armor inv)))
      (setq creatures-alist (list (cons 'hero cr)))
      (setq myself cr)
      (setq display-fn #'ignore)
      (setq test-trigger-called nil)
      (tg-wear 'armor)
      (should test-trigger-called))))

;; --- tg-status ---

(ert-deftest test-tg-status ()
  "tg-status should display current creature description."
  (test-with-globals-saved (tg-valid-actions creatures-alist myself display-fn)
    (setq tg-valid-actions (copy-sequence tg-valid-actions))
    (let* ((cr (make-Creature :symbol 'hero :description "The hero"
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

;; --- tg-attack ---

(ert-deftest test-tg-attack-target-in-room ()
  "tg-attack should deal damage to target creature."
  (test-with-globals-saved (rooms-alist room-map current-room tg-valid-actions display-fn
                                        inventorys-alist creatures-alist myself)
    (setq tg-valid-actions (copy-sequence tg-valid-actions))
    (let* ((room (make-Room :symbol 'room1 :description "A room" :creature '(goblin)))
           (cr (make-Creature :symbol 'goblin :description "A goblin"
                              :attr '((hp . 30) (attack . 6) (defense . 2)))))
      (setq rooms-alist (list (cons 'room1 room)))
      (setq room-map '((room1)))
      (setq current-room room)
      (setq myself (make-Creature :symbol 'hero :description "The hero"
                                  :attr '((hp . 100) (attack . 10) (defense . 5))))
      (setq creatures-alist (list (cons 'goblin cr)
                                  (cons 'hero myself)))
      (setq display-fn #'ignore)
      (tg-attack 'goblin)
      ;; damage = max(1, 10 - 2) = 8, goblin hp: 30 - 8 = 22
      (should (= (cdr (assoc 'hp (Creature-attr cr))) 22))
      ;; counter damage = max(1, 6 - 5) = 1, hero hp: 100 - 1 = 99
      (should (= (cdr (assoc 'hp (Creature-attr myself))) 99)))))

(ert-deftest test-tg-attack-target-not-in-room ()
  "tg-attack should throw exception when target not in room."
  (test-with-globals-saved (rooms-alist room-map current-room tg-valid-actions display-fn
                                        creatures-alist myself)
    (setq tg-valid-actions (copy-sequence tg-valid-actions))
    (let ((room (make-Room :symbol 'room1 :description "A room")))
      (setq rooms-alist (list (cons 'room1 room)))
      (setq room-map '((room1)))
      (setq current-room room)
      (setq myself (make-Creature :symbol 'hero :description "The hero"
                                  :attr '((hp . 100))))
      (setq creatures-alist (list (cons 'hero myself)))
      (setq display-fn #'ignore)
      (should (equal (catch 'exception (tg-attack 'ghost))
                     "房间中没有ghost")))))

(ert-deftest test-tg-attack-kills-target ()
  "tg-attack should remove target from room when HP drops to 0."
  (test-with-globals-saved (rooms-alist room-map current-room tg-valid-actions display-fn
                                        creatures-alist myself)
    (setq tg-valid-actions (copy-sequence tg-valid-actions))
    (let* ((room (make-Room :symbol 'room1 :description "A room" :creature '(rat)))
           (cr (make-Creature :symbol 'rat :description "A rat"
                              :attr '((hp . 5) (attack . 1) (defense . 0)))))
      (setq rooms-alist (list (cons 'room1 room)))
      (setq room-map '((room1)))
      (setq current-room room)
      (setq myself (make-Creature :symbol 'hero :description "The hero"
                                  :attr '((hp . 100) (attack . 10) (defense . 5))))
      (setq creatures-alist (list (cons 'rat cr)
                                  (cons 'hero myself)))
      (setq display-fn #'ignore)
      (tg-attack 'rat)
      (should-not (creature-exist-in-room-p room 'rat)))))

(ert-deftest test-tg-attack-triggers-death-trigger ()
  "tg-attack should call death-trigger when target is killed."
  (test-with-globals-saved (rooms-alist room-map current-room tg-valid-actions display-fn
                                        creatures-alist myself)
    (setq tg-valid-actions (copy-sequence tg-valid-actions))
    (let* ((room (make-Room :symbol 'room1 :description "A room" :creature '(rat)))
           (cr (make-Creature :symbol 'rat :description "A rat"
                              :attr '((hp . 5) (attack . 1) (defense . 0))
                              :death-trigger (lambda () (setq test-trigger-called t)))))
      (setq rooms-alist (list (cons 'room1 room)))
      (setq room-map '((room1)))
      (setq current-room room)
      (setq myself (make-Creature :symbol 'hero :description "The hero"
                                  :attr '((hp . 100) (attack . 10) (defense . 5))))
      (setq creatures-alist (list (cons 'rat cr)
                                  (cons 'hero myself)))
      (setq display-fn #'ignore)
      (setq test-trigger-called nil)
      (tg-attack 'rat)
      (should test-trigger-called))))

(ert-deftest test-tg-attack-counter-attack ()
  "tg-attack should trigger counter-attack when target survives."
  (test-with-globals-saved (rooms-alist room-map current-room tg-valid-actions display-fn
                                        creatures-alist myself)
    (setq tg-valid-actions (copy-sequence tg-valid-actions))
    (let* ((room (make-Room :symbol 'room1 :description "A room" :creature '(orc)))
           (cr (make-Creature :symbol 'orc :description "An orc"
                              :attr '((hp . 50) (attack . 8) (defense . 3)))))
      (setq rooms-alist (list (cons 'room1 room)))
      (setq room-map '((room1)))
      (setq current-room room)
      (setq myself (make-Creature :symbol 'hero :description "The hero"
                                  :attr '((hp . 100) (attack . 10) (defense . 2))))
      (setq creatures-alist (list (cons 'orc cr)
                                  (cons 'hero myself)))
      (setq display-fn #'ignore)
      (tg-attack 'orc)
      ;; damage to orc = max(1, 10-3) = 7, orc hp: 50-7 = 43
      (should (= (cdr (assoc 'hp (Creature-attr cr))) 43))
      ;; counter = max(1, 8-2) = 6, hero hp: 100-6 = 94
      (should (= (cdr (assoc 'hp (Creature-attr myself))) 94)))))

(ert-deftest test-tg-attack-player-death ()
  "tg-attack should end game when player HP drops to 0."
  (test-with-globals-saved (rooms-alist room-map current-room tg-valid-actions display-fn
                                        creatures-alist myself tg-over-p)
    (setq tg-valid-actions (copy-sequence tg-valid-actions))
    (let* ((room (make-Room :symbol 'room1 :description "A room" :creature '(dragon)))
           (cr (make-Creature :symbol 'dragon :description "Dragon"
                              :attr '((hp . 100) (attack . 50) (defense . 20)))))
      (setq rooms-alist (list (cons 'room1 room)))
      (setq room-map '((room1)))
      (setq current-room room)
      (setq myself (make-Creature :symbol 'hero :description "The hero"
                                  :attr '((hp . 5) (attack . 10) (defense . 0))))
      (setq creatures-alist (list (cons 'dragon cr)
                                  (cons 'hero myself)))
      (setq display-fn #'ignore)
      (setq tg-over-p nil)
      (tg-attack 'dragon)
      ;; hero hp: 5 - max(1, 50-0) = 5-50 = -45, dead
      (should tg-over-p))))

(ert-deftest test-tg-attack-no-attack-attr-defaults-zero ()
  "tg-attack should default attack/defense to 0 when not in attr."
  (test-with-globals-saved (rooms-alist room-map current-room tg-valid-actions display-fn
                                        creatures-alist myself)
    (setq tg-valid-actions (copy-sequence tg-valid-actions))
    (let* ((room (make-Room :symbol 'room1 :description "A room" :creature '(slime)))
           (cr (make-Creature :symbol 'slime :description "A slime"
                              :attr '((hp . 10)))))
      (setq rooms-alist (list (cons 'room1 room)))
      (setq room-map '((room1)))
      (setq current-room room)
      (setq myself (make-Creature :symbol 'hero :description "The hero"
                                  :attr '((hp . 100))))
      (setq creatures-alist (list (cons 'slime cr)
                                  (cons 'hero myself)))
      (setq display-fn #'ignore)
      (tg-attack 'slime)
      ;; damage = max(1, 0-0) = 1, slime hp: 10-1 = 9
      (should (= (cdr (assoc 'hp (Creature-attr cr))) 9))
      ;; counter = max(1, 0-0) = 1, hero hp: 100-1 = 99
      (should (= (cdr (assoc 'hp (Creature-attr myself))) 99)))))

(ert-deftest test-tg-attack-string-target ()
  "tg-attack should accept string target and convert to symbol."
  (test-with-globals-saved (rooms-alist room-map current-room tg-valid-actions display-fn
                                        creatures-alist myself)
    (setq tg-valid-actions (copy-sequence tg-valid-actions))
    (let* ((room (make-Room :symbol 'room1 :description "A room" :creature '(goblin)))
           (cr (make-Creature :symbol 'goblin :description "A goblin"
                              :attr '((hp . 30) (attack . 0) (defense . 0)))))
      (setq rooms-alist (list (cons 'room1 room)))
      (setq room-map '((room1)))
      (setq current-room room)
      (setq myself (make-Creature :symbol 'hero :description "The hero"
                                  :attr '((hp . 100) (attack . 10) (defense . 5))))
      (setq creatures-alist (list (cons 'goblin cr)
                                  (cons 'hero myself)))
      (setq display-fn #'ignore)
      (tg-attack "goblin")
      ;; Should work same as symbol, damage = max(1, 10-0) = 10, hp: 30-10 = 20
      (should (= (cdr (assoc 'hp (Creature-attr cr))) 20)))))

;; --- tg-upgrade ---

(ert-deftest test-tg-upgrade-allocates-points ()
  "tg-upgrade should increase target attr and decrease bonus-points."
  (test-with-globals-saved (tg-valid-actions display-fn creatures-alist myself level-exp-table level-up-bonus-points auto-upgrade-attrs)
    (setq tg-valid-actions (copy-sequence tg-valid-actions))
    (setq display-fn #'ignore)
    (setq level-exp-table '(0 100))
    (setq level-up-bonus-points 3)
    (setq auto-upgrade-attrs '((hp . 5)))
    (let ((cr (make-Creature :symbol 'hero :attr '((hp . 100) (attack . 5) (defense . 3) (bonus-points . 3)))))
      (setq creatures-alist (list (cons 'hero cr)))
      (setq myself cr)
      (tg-upgrade "attack" "2")
      (should (= (cdr (assoc 'attack (Creature-attr cr))) 7))
      (should (= (cdr (assoc 'bonus-points (Creature-attr cr))) 1)))))

(ert-deftest test-tg-upgrade-insufficient-points ()
  "tg-upgrade should throw when not enough bonus-points."
  (test-with-globals-saved (tg-valid-actions display-fn creatures-alist myself level-exp-table level-up-bonus-points auto-upgrade-attrs)
    (setq tg-valid-actions (copy-sequence tg-valid-actions))
    (setq display-fn #'ignore)
    (setq level-exp-table '(0 100))
    (setq level-up-bonus-points 3)
    (setq auto-upgrade-attrs '((hp . 5)))
    (let ((cr (make-Creature :symbol 'hero :attr '((hp . 100) (attack . 5) (bonus-points . 1)))))
      (setq creatures-alist (list (cons 'hero cr)))
      (setq myself cr)
      (should (equal (catch 'exception (tg-upgrade "attack" "3"))
                     "技能点不足")))))

(ert-deftest test-tg-upgrade-invalid-attr ()
  "tg-upgrade should throw when attr does not exist."
  (test-with-globals-saved (tg-valid-actions display-fn creatures-alist myself level-exp-table level-up-bonus-points auto-upgrade-attrs)
    (setq tg-valid-actions (copy-sequence tg-valid-actions))
    (setq display-fn #'ignore)
    (setq level-exp-table '(0 100))
    (setq level-up-bonus-points 3)
    (setq auto-upgrade-attrs '((hp . 5)))
    (let ((cr (make-Creature :symbol 'hero :attr '((hp . 100) (bonus-points . 3)))))
      (setq creatures-alist (list (cons 'hero cr)))
      (setq myself cr)
      (should (equal (catch 'exception (tg-upgrade "magic" "1"))
                     "没有magic属性，无法分配")))))

(ert-deftest test-tg-upgrade-no-bonus-attr ()
  "tg-upgrade should throw when creature has no bonus-points attr."
  (test-with-globals-saved (tg-valid-actions display-fn creatures-alist myself level-exp-table level-up-bonus-points auto-upgrade-attrs)
    (setq tg-valid-actions (copy-sequence tg-valid-actions))
    (setq display-fn #'ignore)
    (setq level-exp-table '(0 100))
    (setq level-up-bonus-points 3)
    (setq auto-upgrade-attrs '((hp . 5)))
    (let ((cr (make-Creature :symbol 'goblin :attr '((hp . 25) (attack . 6)))))
      (setq creatures-alist (list (cons 'goblin cr)))
      (setq myself cr)
      (should (equal (catch 'exception (tg-upgrade "attack" "1"))
                     "没有bonus-points属性")))))

;; --- tg-attack exp reward ---

(ert-deftest test-tg-attack-gives-exp-on-kill ()
  "tg-attack should add exp to player when target is killed."
  (test-with-globals-saved (rooms-alist room-map current-room tg-valid-actions display-fn
                                        creatures-alist myself level-exp-table level-up-bonus-points auto-upgrade-attrs)
    (setq tg-valid-actions (copy-sequence tg-valid-actions))
    (setq display-fn #'ignore)
    (setq level-exp-table '(0 100 250))
    (setq level-up-bonus-points 3)
    (setq auto-upgrade-attrs '((hp . 5)))
    (let* ((room (make-Room :symbol 'room1 :description "A room" :creature '(rat)))
           (rat (make-Creature :symbol 'rat :description "A rat"
                               :attr '((hp . 5) (attack . 1) (defense . 0)) :exp-reward 10)))
      (setq rooms-alist (list (cons 'room1 room)))
      (setq room-map '((room1)))
      (setq current-room room)
      (setq myself (make-Creature :symbol 'hero :description "The hero"
                                  :attr '((hp . 100) (attack . 10) (defense . 5) (exp . 0) (level . 1) (bonus-points . 0))))
      (setq creatures-alist (list (cons 'rat rat) (cons 'hero myself)))
      (tg-attack 'rat)
      ;; hero should gain 10 exp from killing rat
      (should (= (cdr (assoc 'exp (Creature-attr myself))) 10)))))

(ert-deftest test-tg-attack-exp-triggers-level-up ()
  "tg-attack exp gain should trigger level up when threshold reached."
  (test-with-globals-saved (rooms-alist room-map current-room tg-valid-actions display-fn
                                        creatures-alist myself level-exp-table level-up-bonus-points auto-upgrade-attrs)
    (setq tg-valid-actions (copy-sequence tg-valid-actions))
    (setq display-fn #'ignore)
    (setq level-exp-table '(0 100 250))
    (setq level-up-bonus-points 3)
    (setq auto-upgrade-attrs '((hp . 5)))
    (let* ((room (make-Room :symbol 'room1 :description "A room" :creature '(rat)))
           (rat (make-Creature :symbol 'rat :description "A rat"
                               :attr '((hp . 5) (attack . 1) (defense . 0)) :exp-reward 150)))
      (setq rooms-alist (list (cons 'room1 room)))
      (setq room-map '((room1)))
      (setq current-room room)
      (setq myself (make-Creature :symbol 'hero :description "The hero"
                                  :attr '((hp . 100) (attack . 10) (defense . 5) (exp . 0) (level . 1) (bonus-points . 0))))
      (setq creatures-alist (list (cons 'rat rat) (cons 'hero myself)))
      (tg-attack 'rat)
      (should (= (cdr (assoc 'exp (Creature-attr myself))) 150))
      (should (= (cdr (assoc 'level (Creature-attr myself))) 2))
      (should (= (cdr (assoc 'hp (Creature-attr myself))) 105))
      (should (= (cdr (assoc 'bonus-points (Creature-attr myself))) 3)))))

(provide 'test-action)
