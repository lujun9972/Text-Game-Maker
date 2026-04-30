;;; test-creature-maker.el --- Tests for creature-maker.el -*- lexical-binding: t; -*-

(require 'ert)
(require 'test-helper)
(require 'creature-maker)

;; --- get-creature-by-symbol ---

(ert-deftest test-get-creature-by-symbol-found ()
  "get-creature-by-symbol should return creature when symbol exists."
  (test-with-globals-saved (creatures-alist)
    (let ((cr (test-make-creature :symbol 'goblin :description "A goblin")))
      (setq creatures-alist (list (cons 'goblin cr)))
      (should (eq (get-creature-by-symbol 'goblin) cr)))))

(ert-deftest test-get-creature-by-symbol-not-found ()
  "get-creature-by-symbol should return nil when symbol doesn't exist."
  (test-with-globals-saved (creatures-alist)
    (setq creatures-alist nil)
    (should (null (get-creature-by-symbol 'nonexistent)))))

;; --- build-creature ---

(ert-deftest test-build-creature-from-tuple ()
  "build-creature should create creature from a tuple."
  (let* ((result (build-creature '(hero "A brave hero" ((hp . 100) (atk . 10)) (sword) (armor))))
         (cr (cdr result)))
    (should (equal (car result) 'hero))
    (should (equal (Creature-symbol cr) 'hero))
    (should (equal (Creature-description cr) "A brave hero"))
    (should (equal (Creature-attr cr) '((hp . 100) (atk . 10))))
    (should (equal (Creature-inventory cr) '(sword)))
    (should (equal (Creature-equipment cr) '(armor)))))

;; --- build-creatures ---

(ert-deftest test-build-creatures-from-file ()
  "build-creatures should read config file and create creatures."
  (test-with-temp-file "(hero \"The hero\" ((hp . 100)) () ())
                         (goblin \"A goblin\" ((hp . 20)) () ())"
    (test-with-globals-saved (creatures-alist)
      (let ((results (build-creatures temp-file)))
        (should (= (length results) 2))
        (should (equal (Creature-symbol (cdar results)) 'hero))
        (should (equal (Creature-symbol (cdadr results)) 'goblin))))))

;; --- creatures-init ---

(ert-deftest test-creatures-init ()
  "creatures-init should initialize creatures-alist and set myself to first creature."
  (test-with-temp-file "(hero \"The hero\" ((hp . 100)) () ())
                         (goblin \"A goblin\" ((hp . 20)) () ())"
    (test-with-globals-saved (creatures-alist myself)
      (creatures-init temp-file)
      (should (= (length creatures-alist) 2))
      (should (equal (Creature-symbol myself) 'hero)))))

;; --- inventory operations ---

(ert-deftest test-add-inventory-to-creature ()
  "add-inventory-to-creature should add inventory to creature."
  (let ((cr (test-make-creature :symbol 'hero :description "test")))
    (add-inventory-to-creature cr 'potion)
    (should (member 'potion (Creature-inventory cr)))))

(ert-deftest test-remove-inventory-from-creature ()
  "remove-inventory-from-creature should remove inventory from creature."
  (let ((cr (test-make-creature :symbol 'hero :description "test" :inventory '(sword potion))))
    (remove-inventory-from-creature cr 'sword)
    (should-not (member 'sword (Creature-inventory cr)))
    (should (member 'potion (Creature-inventory cr)))))

(ert-deftest test-inventory-exist-in-creature-p ()
  "inventory-exist-in-creature-p should check inventory presence."
  (let ((cr (test-make-creature :symbol 'hero :description "test" :inventory '(sword))))
    (should (inventory-exist-in-creature-p cr 'sword))
    (should-not (inventory-exist-in-creature-p cr 'potion))))

;; --- equipment operations ---

(ert-deftest test-add-equipment-to-creature ()
  "add-equipment-to-creature should add equipment to creature."
  (let ((cr (test-make-creature :symbol 'hero :description "test")))
    (add-equipment-to-creature cr 'armor)
    (should (member 'armor (Creature-equipment cr)))))

(ert-deftest test-equipment-exist-in-creature-p ()
  "equipment-exist-in-creature-p should check equipment presence."
  (let ((cr (test-make-creature :symbol 'hero :description "test" :equipment '(armor helmet))))
    (should (equipment-exist-in-creature-p cr 'armor))
    (should-not (equipment-exist-in-creature-p cr 'shield))))

(ert-deftest test-remove-equipment-from-creature ()
  "remove-equipment-from-creature should remove equipment from creature's equipment slot."
  (let ((cr (test-make-creature :symbol 'hero :description "test" :equipment '(armor helmet shield))))
    (remove-equipment-from-creature cr 'helmet)
    (should-not (equipment-exist-in-creature-p cr 'helmet))
    (should (equipment-exist-in-creature-p cr 'armor))
    (should (equipment-exist-in-creature-p cr 'shield))))

;; --- take-effect-to-creature ---

(ert-deftest test-take-effect-existing-attr ()
  "take-effect-to-creature should increase existing attribute."
  (let ((cr (test-make-creature :symbol 'hero :description "test" :attr '((hp . 100)))))
    (take-effect-to-creature cr '(hp . 10))
    (should (= (cdr (assoc 'hp (Creature-attr cr))) 110))))

(ert-deftest test-take-effect-new-attr ()
  "take-effect-to-creature should add new attribute."
  (let ((cr (test-make-creature :symbol 'hero :description "test" :attr '((hp . 100)))))
    (take-effect-to-creature cr '(mp . 50))
    (should (= (cdr (assoc 'mp (Creature-attr cr))) 50))
    (should (= (cdr (assoc 'hp (Creature-attr cr))) 100))))

(ert-deftest test-take-effect-negative-value ()
  "take-effect-to-creature should handle negative values (damage)."
  (let ((cr (test-make-creature :symbol 'hero :description "test" :attr '((hp . 100)))))
    (take-effect-to-creature cr '(hp . -30))
    (should (= (cdr (assoc 'hp (Creature-attr cr))) 70))))

;; --- take-effects-to-creature ---

(ert-deftest test-take-effects-multiple ()
  "take-effects-to-creature should apply multiple effects."
  (let ((cr (test-make-creature :symbol 'hero :description "test" :attr '((hp . 100)))))
    (take-effects-to-creature cr '((hp . 10) (mp . 50)))
    (should (= (cdr (assoc 'hp (Creature-attr cr))) 110))
    (should (= (cdr (assoc 'mp (Creature-attr cr))) 50))))

(ert-deftest test-take-effects-empty-list ()
  "take-effects-to-creature with empty list should not change attributes."
  (let ((cr (test-make-creature :symbol 'hero :description "test" :attr '((hp . 100)))))
    (take-effects-to-creature cr nil)
    (should (= (cdr (assoc 'hp (Creature-attr cr))) 100))))

;; --- describe ---

(ert-deftest test-describe-creature ()
  "describe should return a formatted description of creature."
  (let ((cr (test-make-creature :symbol 'goblin :description "A green goblin"
                                :attr '((hp . 20)) :inventory '(knife) :equipment '(rag))))
    (let ((desc (describe cr)))
      (should (string-match-p "goblin" desc))
      (should (string-match-p "A green goblin" desc)))))

;; --- death-trigger ---

(ert-deftest test-build-creature-with-death-trigger ()
  "build-creature should parse death-trigger from config."
  (let* ((result (build-creature '(dragon "火龙" ((hp . 50)) () () (lambda () (tg-display "龙死了")))))
         (cr (cdr result)))
    (should (equal (car result) 'dragon))
    (should (functionp (Creature-death-trigger cr)))))

(ert-deftest test-build-creature-without-death-trigger ()
  "build-creature should set death-trigger to nil when not provided."
  (let* ((result (build-creature '(goblin "哥布林" ((hp . 30)) () ())))
         (cr (cdr result)))
    (should (null (Creature-death-trigger cr)))))

(provide 'test-creature-maker)
