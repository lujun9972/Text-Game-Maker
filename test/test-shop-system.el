;;; test-shop-system.el --- Tests for shop-system.el -*- lexical-binding: t; -*-

(require 'ert)
(require 'test-helper)
(require 'shop-system)

;; --- player-gold ---

(ert-deftest test-player-gold-default ()
  "player-gold should default to 0."
  (test-with-globals-saved (player-gold)
    (setq player-gold 0)
    (should (= player-gold 0))))

;; --- shop-init ---

(ert-deftest test-shop-init-parses-config ()
  "shop-init should parse shop config file."
  (test-with-globals-saved (shop-alist)
    (setq shop-alist nil)
    (test-with-temp-file "(goblin-merchant 0.3 ((bread . 10) (health-potion . 25)))"
      (shop-init temp-file)
      (let ((entry (cdr (assoc 'goblin-merchant shop-alist))))
        (should entry)
        (should (= (car entry) 0.3))
        (should (equal (cdr entry) '((bread . 10) (health-potion . 25))))))))

(ert-deftest test-shop-init-multiple-merchants ()
  "shop-init should handle multiple merchants."
  (test-with-globals-saved (shop-alist)
    (setq shop-alist nil)
    (test-with-temp-file "(merchant-a 0.5 ((sword . 30)))
(merchant-b 0.3 ((bread . 10)))"
      (shop-init temp-file)
      (should (= (length shop-alist) 2)))))

;; --- shop helper functions ---

(ert-deftest test-get-shopkeeper-in-room ()
  "shop-get-shopkeeper should return first shopkeeper creature in room."
  (test-with-globals-saved (current-room rooms-alist room-map creatures-alist)
    (setq creatures-alist nil)
    (push (cons 'merchant (make-Creature :symbol 'merchant :shopkeeper t)) creatures-alist)
    (push (cons 'goblin (make-Creature :symbol 'goblin :shopkeeper nil)) creatures-alist)
    (setq current-room (make-Room :symbol 'market :description "Market"
                                   :creature '(merchant goblin)))
    (let ((sk (shop-get-shopkeeper)))
      (should sk)
      (should (eq (Creature-symbol sk) 'merchant)))))

(ert-deftest test-get-shopkeeper-no-shopkeeper ()
  "shop-get-shopkeeper should return nil when no shopkeeper in room."
  (test-with-globals-saved (current-room rooms-alist room-map creatures-alist)
    (setq creatures-alist nil)
    (push (cons 'goblin (make-Creature :symbol 'goblin)) creatures-alist)
    (setq current-room (make-Room :symbol 'cave :description "Cave"
                                   :creature '(goblin)))
    (should-not (shop-get-shopkeeper))))

(ert-deftest test-get-shopkeeper-empty-room ()
  "shop-get-shopkeeper should return nil for empty room."
  (test-with-globals-saved (current-room rooms-alist room-map)
    (setq current-room (make-Room :symbol 'empty :description "Empty room"
                                   :creature nil))
    (should-not (shop-get-shopkeeper))))

(ert-deftest test-shop-get-goods ()
  "shop-get-goods should return goods list for a merchant."
  (test-with-globals-saved (shop-alist)
    (setq shop-alist '((merchant . (0.5 . ((sword . 30) (bread . 10))))))
    (should (equal (shop-get-goods 'merchant) '((sword . 30) (bread . 10))))))

(ert-deftest test-shop-get-goods-unknown ()
  "shop-get-goods should return nil for unknown merchant."
  (test-with-globals-saved (shop-alist)
    (setq shop-alist nil)
    (should-not (shop-get-goods 'unknown))))

(ert-deftest test-shop-get-sell-rate ()
  "shop-get-sell-rate should return sell rate for merchant."
  (test-with-globals-saved (shop-alist)
    (setq shop-alist '((merchant . (0.3 . ((sword . 30))))))
    (should (= (shop-get-sell-rate 'merchant) 0.3))))

(ert-deftest test-shop-get-item-price ()
  "shop-get-item-price should return price of item in merchant's goods."
  (test-with-globals-saved (shop-alist)
    (setq shop-alist '((merchant . (0.5 . ((sword . 30) (bread . 10))))))
    (should (= (shop-get-item-price 'merchant 'sword) 30))
    (should (= (shop-get-item-price 'merchant 'bread) 10))
    (should-not (shop-get-item-price 'merchant 'unknown))))

(ert-deftest test-shop-remove-item ()
  "shop-remove-item should remove item from merchant's goods."
  (test-with-globals-saved (shop-alist)
    (setq shop-alist '((merchant . (0.5 . ((sword . 30) (bread . 10))))))
    (shop-remove-item 'merchant 'sword)
    (should (equal (shop-get-goods 'merchant) '((bread . 10))))))

(ert-deftest test-shop-add-item ()
  "shop-add-item should add item to merchant's goods."
  (test-with-globals-saved (shop-alist)
    (setq shop-alist '((merchant . (0.5 . ((sword . 30))))))
    (shop-add-item 'merchant 'bread 10)
    (should (member '(bread . 10) (shop-get-goods 'merchant)))))

(provide 'test-shop-system)
