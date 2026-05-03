;;; test-creature-maker.el --- Tests for creature-maker.el -*- lexical-binding: t; -*-

(require 'ert)
(require 'test-helper)
(require 'creature-maker)

;; --- tg-get-creature-by-symbol ---

(ert-deftest test-tg-get-creature-by-symbol-found ()
  "tg-get-creature-by-symbol should return creature when symbol exists."
  (test-with-globals-saved (tg-creatures-alist)
    (let ((cr (test-make-creature :symbol 'goblin :description "A goblin")))
      (setq tg-creatures-alist (list (cons 'goblin cr)))
      (should (eq (tg-get-creature-by-symbol 'goblin) cr)))))

(ert-deftest test-tg-get-creature-by-symbol-not-found ()
  "tg-get-creature-by-symbol should return nil when symbol doesn't exist."
  (test-with-globals-saved (tg-creatures-alist)
    (setq tg-creatures-alist nil)
    (should (null (tg-get-creature-by-symbol 'nonexistent)))))

;; --- tg-build-creature ---

(ert-deftest test-tg-build-creature-from-tuple ()
  "tg-build-creature should create creature from a tuple."
  (let* ((result (tg-build-creature '(hero "A brave hero" ((hp . 100) (atk . 10)) (sword) (armor))))
         (cr (cdr result)))
    (should (equal (car result) 'hero))
    (should (equal (Creature-symbol cr) 'hero))
    (should (equal (Creature-description cr) "A brave hero"))
    (should (equal (Creature-attr cr) '((hp . 100) (atk . 10))))
    (should (equal (Creature-inventory cr) '(sword)))
    (should (equal (Creature-equipment cr) '(armor)))))

;; --- tg-build-creatures ---

(ert-deftest test-tg-build-creatures-from-file ()
  "tg-build-creatures should read config file and create creatures."
  (test-with-temp-file "(hero \"The hero\" ((hp . 100)) () ())
                         (goblin \"A goblin\" ((hp . 20)) () ())"
    (test-with-globals-saved (tg-creatures-alist)
      (let ((results (tg-build-creatures temp-file)))
        (should (= (length results) 2))
        (should (equal (Creature-symbol (cdar results)) 'hero))
        (should (equal (Creature-symbol (cdadr results)) 'goblin))))))

;; --- tg-creatures-init ---

(ert-deftest test-tg-creatures-init ()
  "tg-creatures-init should initialize tg-creatures-alist and set tg-myself to first creature."
  (test-with-temp-file "(hero \"The hero\" ((hp . 100)) () ())
                         (goblin \"A goblin\" ((hp . 20)) () ())"
    (test-with-globals-saved (tg-creatures-alist tg-myself)
      (tg-creatures-init temp-file)
      (should (= (length tg-creatures-alist) 2))
      (should (equal (Creature-symbol tg-myself) 'hero)))))

;; --- inventory operations ---

(ert-deftest test-tg-add-inventory-to-creature ()
  "tg-add-inventory-to-creature should add inventory to creature."
  (let ((cr (test-make-creature :symbol 'hero :description "test")))
    (tg-add-inventory-to-creature cr 'potion)
    (should (member 'potion (Creature-inventory cr)))))

(ert-deftest test-tg-remove-inventory-from-creature ()
  "tg-remove-inventory-from-creature should remove inventory from creature."
  (let ((cr (test-make-creature :symbol 'hero :description "test" :inventory '(sword potion))))
    (tg-remove-inventory-from-creature cr 'sword)
    (should-not (member 'sword (Creature-inventory cr)))
    (should (member 'potion (Creature-inventory cr)))))

(ert-deftest test-tg-inventory-exist-in-creature-p ()
  "tg-inventory-exist-in-creature-p should check inventory presence."
  (let ((cr (test-make-creature :symbol 'hero :description "test" :inventory '(sword))))
    (should (tg-inventory-exist-in-creature-p cr 'sword))
    (should-not (tg-inventory-exist-in-creature-p cr 'potion))))

;; --- equipment operations ---

(ert-deftest test-tg-add-equipment-to-creature ()
  "tg-add-equipment-to-creature should add equipment to creature."
  (let ((cr (test-make-creature :symbol 'hero :description "test")))
    (tg-add-equipment-to-creature cr 'armor)
    (should (member 'armor (Creature-equipment cr)))))

(ert-deftest test-tg-equipment-exist-in-creature-p ()
  "tg-equipment-exist-in-creature-p should check equipment presence."
  (let ((cr (test-make-creature :symbol 'hero :description "test" :equipment '(armor helmet))))
    (should (tg-equipment-exist-in-creature-p cr 'armor))
    (should-not (tg-equipment-exist-in-creature-p cr 'shield))))

(ert-deftest test-tg-remove-equipment-from-creature ()
  "tg-remove-equipment-from-creature should remove equipment from creature's equipment slot."
  (let ((cr (test-make-creature :symbol 'hero :description "test" :equipment '(armor helmet shield))))
    (tg-remove-equipment-from-creature cr 'helmet)
    (should-not (tg-equipment-exist-in-creature-p cr 'helmet))
    (should (tg-equipment-exist-in-creature-p cr 'armor))
    (should (tg-equipment-exist-in-creature-p cr 'shield))))

;; --- tg-take-effect-to-creature ---

(ert-deftest test-take-effect-existing-attr ()
  "tg-take-effect-to-creature should increase existing attribute."
  (let ((cr (test-make-creature :symbol 'hero :description "test" :attr '((hp . 100)))))
    (tg-take-effect-to-creature cr '(hp . 10))
    (should (= (cdr (assoc 'hp (Creature-attr cr))) 110))))

(ert-deftest test-take-effect-new-attr ()
  "tg-take-effect-to-creature should add new attribute."
  (let ((cr (test-make-creature :symbol 'hero :description "test" :attr '((hp . 100)))))
    (tg-take-effect-to-creature cr '(mp . 50))
    (should (= (cdr (assoc 'mp (Creature-attr cr))) 50))
    (should (= (cdr (assoc 'hp (Creature-attr cr))) 100))))

(ert-deftest test-take-effect-negative-value ()
  "tg-take-effect-to-creature should handle negative values (damage)."
  (let ((cr (test-make-creature :symbol 'hero :description "test" :attr '((hp . 100)))))
    (tg-take-effect-to-creature cr '(hp . -30))
    (should (= (cdr (assoc 'hp (Creature-attr cr))) 70))))

;; --- tg-take-effects-to-creature ---

(ert-deftest test-take-effects-multiple ()
  "tg-take-effects-to-creature should apply multiple effects."
  (let ((cr (test-make-creature :symbol 'hero :description "test" :attr '((hp . 100)))))
    (tg-take-effects-to-creature cr '((hp . 10) (mp . 50)))
    (should (= (cdr (assoc 'hp (Creature-attr cr))) 110))
    (should (= (cdr (assoc 'mp (Creature-attr cr))) 50))))

(ert-deftest test-take-effects-empty-list ()
  "tg-take-effects-to-creature with empty list should not change attributes."
  (let ((cr (test-make-creature :symbol 'hero :description "test" :attr '((hp . 100)))))
    (tg-take-effects-to-creature cr nil)
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

(ert-deftest test-tg-build-creature-with-death-trigger ()
  "tg-build-creature should parse death-trigger from config."
  (let* ((result (tg-build-creature '(dragon "火龙" ((hp . 50)) () () (lambda () (tg-display "龙死了")))))
         (cr (cdr result)))
    (should (equal (car result) 'dragon))
    (should (functionp (Creature-death-trigger cr)))))

(ert-deftest test-tg-build-creature-without-death-trigger ()
  "tg-build-creature should set death-trigger to nil when not provided."
  (let* ((result (tg-build-creature '(goblin "哥布林" ((hp . 30)) () ())))
         (cr (cdr result)))
    (should (null (Creature-death-trigger cr)))))

;; --- exp-reward slot ---

(ert-deftest test-creature-exp-reward-slot-default-nil ()
  "Creature exp-reward slot should default to nil."
  (let ((cr (make-Creature :symbol 'goblin :description "A goblin")))
    (should (null (Creature-exp-reward cr)))))

(ert-deftest test-creature-exp-reward-slot-set ()
  "Creature exp-reward slot should be settable."
  (let ((cr (make-Creature :symbol 'goblin :description "A goblin" :exp-reward 15)))
    (should (= (Creature-exp-reward cr) 15))))

(ert-deftest test-tg-build-creature-with-exp-reward ()
  "tg-build-creature should parse 7-element tuple with exp-reward."
  (let* ((result (tg-build-creature '(goblin "A goblin" ((hp . 25) (attack . 6) (defense . 2)) () () nil 15)))
         (cr (cdr result)))
    (should (= (Creature-exp-reward cr) 15))))

(ert-deftest test-tg-build-creature-without-exp-reward ()
  "tg-build-creature should default exp-reward to nil for 6-element tuple."
  (let* ((result (tg-build-creature '(goblin "A goblin" ((hp . 25)) () () nil)))
         (cr (cdr result)))
    (should (null (Creature-exp-reward cr)))))

;; --- behaviors slot ---

(ert-deftest test-creature-behaviors-slot-default-nil ()
  "Creature behaviors slot should default to nil."
  (let ((cr (make-Creature :symbol 'goblin :description "A goblin")))
    (should (null (Creature-behaviors cr)))))

(ert-deftest test-creature-behaviors-slot-set ()
  "Creature behaviors slot should be settable."
  (let* ((rules '((((always) attack))))
         (cr (make-Creature :symbol 'goblin :description "A goblin" :behaviors rules)))
    (should (equal (Creature-behaviors cr) rules))))

(ert-deftest test-tg-build-creature-with-behaviors ()
  "tg-build-creature should parse 8-element tuple with behaviors."
  (let* ((result (tg-build-creature '(goblin "A goblin" ((hp . 25) (attack . 6) (defense . 2)) () () nil 15 (((always) attack)))))
         (cr (cdr result)))
    (should (= (length (Creature-behaviors cr)) 1))))

(ert-deftest test-tg-build-creature-without-behaviors ()
  "tg-build-creature should default behaviors to nil for 7-element tuple."
  (let* ((result (tg-build-creature '(goblin "A goblin" ((hp . 25) (attack . 6) (defense . 2)) () () nil 15)))
         (cr (cdr result)))
    (should (null (Creature-behaviors cr)))))

;; --- Shopkeeper ---

(ert-deftest test-creature-shopkeeper-default-nil ()
  "Creature shopkeeper should default to nil."
  (let ((c (make-Creature :symbol 'goblin :description "A goblin")))
    (should-not (Creature-shopkeeper c))))

(ert-deftest test-creature-shopkeeper-set ()
  "Creature shopkeeper can be set to t."
  (let ((c (make-Creature :symbol 'merchant :description "A merchant" :shopkeeper t)))
    (should (Creature-shopkeeper c))))

(ert-deftest test-tg-build-creature-with-shopkeeper ()
  "tg-build-creature should parse 9th element as shopkeeper."
  (test-with-globals-saved (tg-creatures-alist)
    (setq tg-creatures-alist nil)
    (let ((result (tg-build-creature '(merchant "商人" ((hp . 30)) () () nil 0 nil t))))
      (should (Creature-shopkeeper (cdr result))))))

(ert-deftest test-tg-build-creature-without-shopkeeper ()
  "tg-build-creature should default shopkeeper to nil for 8-element config."
  (test-with-globals-saved (tg-creatures-alist)
    (setq tg-creatures-alist nil)
    (let ((result (tg-build-creature '(goblin "哥布林" ((hp . 25)) () () nil 10 nil))))
      (should-not (Creature-shopkeeper (cdr result))))))

(provide 'test-creature-maker)
