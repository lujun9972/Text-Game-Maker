;;; test-inventory-maker.el --- Tests for inventory-maker.el -*- lexical-binding: t; -*-

(require 'ert)
(require 'test-helper)
(require 'inventory-maker)

;; --- get-inventory-by-symbol ---

(ert-deftest test-get-inventory-by-symbol-found ()
  "get-inventory-by-symbol should return inventory when symbol exists."
  (test-with-globals-saved (inventorys-alist)
    (let ((inv (test-make-inventory :symbol 'potion :description "A potion" :type '(usable))))
      (setq inventorys-alist (list (cons 'potion inv)))
      (should (eq (get-inventory-by-symbol 'potion) inv)))))

(ert-deftest test-get-inventory-by-symbol-not-found-throws ()
  "get-inventory-by-symbol should throw exception when symbol not found."
  (test-with-globals-saved (inventorys-alist)
    (setq inventorys-alist nil)
    (should (equal (catch 'exception (get-inventory-by-symbol 'nonexistent))
                   "没有定义该物品[nonexistent]"))))

(ert-deftest test-get-inventory-by-symbol-silent-mode ()
  "get-inventory-by-symbol with noexception should return nil silently."
  (test-with-globals-saved (inventorys-alist)
    (setq inventorys-alist nil)
    (should (null (get-inventory-by-symbol 'nonexistent t)))))

;; --- tg-build-inventory ---

(ert-deftest test-build-inventory-from-tuple ()
  "tg-build-inventory should create inventory from a tuple."
  (let* ((result (tg-build-inventory '(sword "A sharp sword" (weapon) ((attack . 5)))))
         (inv (cdr result)))
    (should (equal (car result) 'sword))
    (should (equal (Inventory-symbol inv) 'sword))
    (should (equal (Inventory-description inv) "A sharp sword"))
    (should (equal (Inventory-type inv) '(weapon)))
    (should (equal (Inventory-effects inv) '((attack . 5))))))

;; --- tg-inventory-init ---

(ert-deftest test-inventory-init-from-file ()
  "tg-inventory-init should read config file and create inventories."
  (test-with-temp-file "(potion \"Healing potion\" (usable) ((hp . 10)))
                         (sword \"Sharp sword\" (weapon) ((atk . 5)))"
    (test-with-globals-saved (inventorys-alist)
      (tg-inventory-init temp-file)
      (should (= (length inventorys-alist) 2))
      (should (equal (Inventory-symbol (cdar inventorys-alist)) 'potion))
      (should (equal (Inventory-symbol (cdadr inventorys-alist)) 'sword)))))

;; --- tg-inventory-init (basic) ---

(ert-deftest test-inventorys-init ()
  "tg-inventory-init should initialize inventorys-alist."
  (test-with-temp-file "(potion \"A potion\" (usable) ())"
    (test-with-globals-saved (inventorys-alist)
      (tg-inventory-init temp-file)
      (should (= (length inventorys-alist) 1))
      (should (equal (caar inventorys-alist) 'potion)))))

;; --- inventory-has-type-p ---

(ert-deftest test-inventory-has-type-p-exact-match ()
  "inventory-has-type-p should match exact type."
  (test-with-globals-saved (inventorys-alist)
    (let ((inv (test-make-inventory :symbol 'potion :description "test" :type 'usable)))
      (setq inventorys-alist (list (cons 'potion inv)))
      (should (inventory-has-type-p inv 'usable)))))

(ert-deftest test-inventory-has-type-p-list-match ()
  "inventory-has-type-p should match type within a list."
  (let ((inv (test-make-inventory :symbol 'sword :description "test" :type '(weapon usable))))
    (should (inventory-has-type-p inv 'usable))
    (should (inventory-has-type-p inv 'weapon))))

(ert-deftest test-inventory-has-type-p-no-match ()
  "inventory-has-type-p should return nil for non-matching type."
  (let ((inv (test-make-inventory :symbol 'rock :description "test" :type '(junk))))
    (should-not (inventory-has-type-p inv 'usable))))

(ert-deftest test-inventory-has-type-p-symbol-arg ()
  "inventory-has-type-p should accept a symbol and look it up."
  (test-with-globals-saved (inventorys-alist)
    (let ((inv (test-make-inventory :symbol 'potion :description "test" :type 'usable)))
      (setq inventorys-alist (list (cons 'potion inv)))
      (should (inventory-has-type-p 'potion 'usable)))))

;; --- inventory-usable-p / inventory-wearable-p ---

(ert-deftest test-inventory-usable-p ()
  "inventory-usable-p should return t for usable items."
  (let ((inv (test-make-inventory :symbol 'potion :description "test" :type '(usable))))
    (should (inventory-usable-p inv))
    (should-not (inventory-usable-p
                 (test-make-inventory :symbol 'armor :description "test" :type '(wearable))))))

(ert-deftest test-inventory-wearable-p ()
  "inventory-wearable-p should return t for wearable items."
  (let ((inv (test-make-inventory :symbol 'armor :description "test" :type '(wearable))))
    (should (inventory-wearable-p inv))
    (should-not (inventory-wearable-p
                 (test-make-inventory :symbol 'potion :description "test" :type '(usable))))))

;; --- describe ---

(ert-deftest test-describe-inventory ()
  "describe should return a formatted description of inventory."
  (let ((inv (test-make-inventory :symbol 'sword :description "A sword"
                                  :type '(weapon) :effects '((atk . 5)))))
    (let ((desc (describe inv)))
      (should (string-match-p "sword" desc))
      (should (string-match-p "A sword" desc)))))

(provide 'test-inventory-maker)
