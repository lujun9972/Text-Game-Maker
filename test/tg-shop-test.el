;;; tg-shop-test.el --- 商店系统测试  -*- lexical-binding: t; -*-

(require 'ert)
(require 'tg-registry)
(require 'tg-creature)
(require 'tg-shop)

(ert-deftest test-tg-shop-buy-success ()
  "测试成功购买物品"
  (tg-registry-clear)
  (let ((shop (make-tg-shop :npc-symbol 'merchant :sell-rate 0.5
                            :goods '((potion . 30) (sword . 100))))
        (player (make-tg-creature :symbol 'hero :attr '((gold 200)))))
    (tg-register-shop 'merchant shop)
    (tg-register-creature 'hero player)
    (tg-shop-buy 'potion (tg-get-shop 'merchant) player)
    (should (tg-creature-has-item player 'potion))
    (should (= (tg-creature-attr-get player 'gold) 170))))

(ert-deftest test-tg-shop-buy-insufficient-gold ()
  "测试金币不足时购买失败"
  (let ((shop (make-tg-shop :npc-symbol 'merchant :sell-rate 0.5
                            :goods '((sword . 100))))
        (player (make-tg-creature :symbol 'hero :attr '((gold 50)))))
    (should-error (tg-shop-buy 'sword shop player)
                  :type 'error)))

(ert-deftest test-tg-shop-buy-item-not-available ()
  "测试购买商店不卖的物品失败"
  (let ((shop (make-tg-shop :npc-symbol 'merchant :sell-rate 0.5
                            :goods '((potion . 30))))
        (player (make-tg-creature :symbol 'hero :attr '((gold 200)))))
    (should-error (tg-shop-buy 'shield shop player)
                  :type 'error)))

(ert-deftest test-tg-shop-sell ()
  "测试成功出售物品"
  (let ((shop (make-tg-shop :npc-symbol 'merchant :sell-rate 0.5
                            :goods '((potion . 30))))
        (player (make-tg-creature :symbol 'hero
                                   :inventory '(potion)
                                   :attr '((gold 10)))))
    (tg-shop-sell 'potion shop player)
    (should (not (tg-creature-has-item player 'potion)))
    (should (= (tg-creature-attr-get player 'gold) 25))))

(ert-deftest test-tg-shop-sell-item-not-owned ()
  "测试出售不拥有的物品失败"
  (let ((shop (make-tg-shop :npc-symbol 'merchant :sell-rate 0.5
                            :goods '((potion . 30))))
        (player (make-tg-creature :symbol 'hero
                                   :inventory nil
                                   :attr '((gold 10)))))
    (should-error (tg-shop-sell 'potion shop player)
                  :type 'error)))

(ert-deftest test-tg-shop-sell-unknown-item ()
  "测试出售商店未定价的物品（价格为 0）"
  (let ((shop (make-tg-shop :npc-symbol 'merchant :sell-rate 0.5
                            :goods '((potion . 30))))
        (player (make-tg-creature :symbol 'hero
                                   :inventory '(trash)
                                   :attr '((gold 10)))))
    ;; 商店不收 trash，出售价格为 0
    (tg-shop-sell 'trash shop player)
    (should (not (tg-creature-has-item player 'trash)))
    ;; 金币不变
    (should (= (tg-creature-attr-get player 'gold) 10))))

(ert-deftest test-tg-shop-sell-rate-calculation ()
  "测试出售价格比例计算"
  (let ((shop (make-tg-shop :npc-symbol 'merchant :sell-rate 0.6
                            :goods '((sword . 100))))
        (player (make-tg-creature :symbol 'hero
                                   :inventory '(sword)
                                   :attr '((gold 0)))))
    ;; 出售价格 = 100 * 0.6 = 60
    (tg-shop-sell 'sword shop player)
    (should (= (tg-creature-attr-get player 'gold) 60))))

(provide 'tg-shop-test)
;;; tg-shop-test.el ends here
