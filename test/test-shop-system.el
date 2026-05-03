;;; test-shop-system.el --- Tests for shop-system.el -*- lexical-binding: t; -*-

(require 'ert)
(require 'test-helper)
(require 'shop-system)

;; --- tg-player-gold ---

(ert-deftest test-tg-player-gold-default ()
  "tg-player-gold should default to 0."
  (test-with-globals-saved (tg-player-gold)
    (setq tg-player-gold 0)
    (should (= tg-player-gold 0))))

;; --- tg-shop-init ---

(ert-deftest test-tg-shop-init-parses-config ()
  "tg-shop-init should parse shop config file."
  (test-with-globals-saved (tg-shop-alist)
    (setq tg-shop-alist nil)
    (test-with-temp-file "(goblin-merchant 0.3 ((bread . 10) (health-potion . 25)))"
      (tg-shop-init temp-file)
      (let ((entry (cdr (assoc 'goblin-merchant tg-shop-alist))))
        (should entry)
        (should (= (ShopConfig-sell-rate entry) 0.3))
        (should (equal (ShopConfig-goods entry) '((bread . 10) (health-potion . 25))))))))

(ert-deftest test-tg-shop-init-multiple-merchants ()
  "tg-shop-init should handle multiple merchants."
  (test-with-globals-saved (tg-shop-alist)
    (setq tg-shop-alist nil)
    (test-with-temp-file "(merchant-a 0.5 ((sword . 30)))
(merchant-b 0.3 ((bread . 10)))"
      (tg-shop-init temp-file)
      (should (= (length tg-shop-alist) 2)))))

;; --- shop helper functions ---

(ert-deftest test-get-shopkeeper-in-room ()
  "tg-shop-get-shopkeeper should return first shopkeeper creature in room."
  (test-with-globals-saved (tg-current-room tg-rooms-alist tg-room-map tg-creatures-alist)
    (setq tg-creatures-alist nil)
    (push (cons 'merchant (make-Creature :symbol 'merchant :shopkeeper t)) tg-creatures-alist)
    (push (cons 'goblin (make-Creature :symbol 'goblin :shopkeeper nil)) tg-creatures-alist)
    (setq tg-current-room (make-Room :symbol 'market :description "Market"
                                   :creature '(merchant goblin)))
    (let ((sk (tg-shop-get-shopkeeper)))
      (should sk)
      (should (eq (Creature-symbol sk) 'merchant)))))

(ert-deftest test-get-shopkeeper-no-shopkeeper ()
  "tg-shop-get-shopkeeper should return nil when no shopkeeper in room."
  (test-with-globals-saved (tg-current-room tg-rooms-alist tg-room-map tg-creatures-alist)
    (setq tg-creatures-alist nil)
    (push (cons 'goblin (make-Creature :symbol 'goblin)) tg-creatures-alist)
    (setq tg-current-room (make-Room :symbol 'cave :description "Cave"
                                   :creature '(goblin)))
    (should-not (tg-shop-get-shopkeeper))))

(ert-deftest test-get-shopkeeper-empty-room ()
  "tg-shop-get-shopkeeper should return nil for empty room."
  (test-with-globals-saved (tg-current-room tg-rooms-alist tg-room-map)
    (setq tg-current-room (make-Room :symbol 'empty :description "Empty room"
                                   :creature nil))
    (should-not (tg-shop-get-shopkeeper))))

(ert-deftest test-tg-shop-get-goods ()
  "tg-shop-get-goods should return goods list for a merchant."
  (test-with-globals-saved (tg-shop-alist)
    (setq tg-shop-alist (list (cons 'merchant (make-ShopConfig :sell-rate 0.5 :goods '((sword . 30) (bread . 10))))))
    (should (equal (tg-shop-get-goods 'merchant) '((sword . 30) (bread . 10))))))

(ert-deftest test-tg-shop-get-goods-unknown ()
  "tg-shop-get-goods should return nil for unknown merchant."
  (test-with-globals-saved (tg-shop-alist)
    (setq tg-shop-alist nil)
    (should-not (tg-shop-get-goods 'unknown))))

(ert-deftest test-tg-shop-get-sell-rate ()
  "tg-shop-get-sell-rate should return sell rate for merchant."
  (test-with-globals-saved (tg-shop-alist)
    (setq tg-shop-alist (list (cons 'merchant (make-ShopConfig :sell-rate 0.3 :goods '((sword . 30))))))
    (should (= (tg-shop-get-sell-rate 'merchant) 0.3))))

(ert-deftest test-tg-shop-get-item-price ()
  "tg-shop-get-item-price should return price of item in merchant's goods."
  (test-with-globals-saved (tg-shop-alist)
    (setq tg-shop-alist (list (cons 'merchant (make-ShopConfig :sell-rate 0.5 :goods '((sword . 30) (bread . 10))))))
    (should (= (tg-shop-get-item-price 'merchant 'sword) 30))
    (should (= (tg-shop-get-item-price 'merchant 'bread) 10))
    (should-not (tg-shop-get-item-price 'merchant 'unknown))))

(ert-deftest test-tg-shop-remove-item ()
  "tg-shop-remove-item should remove item from merchant's goods."
  (test-with-globals-saved (tg-shop-alist)
    (setq tg-shop-alist (list (cons 'merchant (make-ShopConfig :sell-rate 0.5 :goods '((sword . 30) (bread . 10))))))
    (tg-shop-remove-item 'merchant 'sword)
    (should (equal (tg-shop-get-goods 'merchant) '((bread . 10))))))

(ert-deftest test-tg-shop-add-item ()
  "tg-shop-add-item should add item to merchant's goods."
  (test-with-globals-saved (tg-shop-alist)
    (setq tg-shop-alist (list (cons 'merchant (make-ShopConfig :sell-rate 0.5 :goods '((sword . 30))))))
    (tg-shop-add-item 'merchant 'bread 10)
    (should (member '(bread . 10) (tg-shop-get-goods 'merchant)))))

(provide 'test-shop-system)
