;;; tg-shop.el --- 商店系统  -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'tg-registry)
(require 'tg-creature)

(cl-defstruct tg-shop
  npc-symbol       ;; NPC symbol
  sell-rate        ;; 出售价格比例 (0.5 表示原价 50%)
  goods)           ;; 商品清单 ((item-symbol . price) ...)

;;; 商店购买

(defun tg-shop-buy (item-sym shop player)
  "玩家从商店购买物品
item-sym: 要购买的物品 symbol
shop: 商店结构
player: 玩家生物结构

流程：
1. 检查商店是否卖该物品
2. 检查玩家金币是否足够
3. 扣除金币
4. 添加物品到背包

失败时抛出错误"
  (let ((price (cdr (assq item-sym (tg-shop-goods shop)))))
    ;; 检查商店是否卖该物品
    (unless price
      (error "Shop does not sell %s" item-sym))
    ;; 检查玩家金币是否足够
    (let ((player-gold (tg-creature-attr-get player 'gold)))
      (unless (and player-gold (>= player-gold price))
        (error "Insufficient gold: need %d, have %d" price (or player-gold 0))))
    ;; 扣除金币
    (tg-creature-take-effect player (list 'gold (- price)))
    ;; 添加物品到背包
    (tg-creature-add-item player item-sym)
    nil))

;;; 商店出售

(defun tg-shop-sell (item-sym shop player)
  "玩家向商店出售物品
item-sym: 要出售的物品 symbol
shop: 商店结构
player: 玩家生物结构

流程：
1. 检查玩家是否有该物品
2. 计算出售价格 = 物品价格 × sell-rate
3. 移除物品
4. 增加金币

失败时抛出错误"
  ;; 检查玩家是否有该物品
  (unless (tg-creature-has-item player item-sym)
    (error "Player does not have %s" item-sym))
  ;; 获取原价并计算出售价格
  (let* ((original-price (cdr (assq item-sym (tg-shop-goods shop))))
         (price (if original-price
                    (floor (* original-price (tg-shop-sell-rate shop)))
                  0)))
    ;; 移除物品
    (tg-creature-remove-item player item-sym)
    ;; 增加金币
    (tg-creature-take-effect player (list 'gold price))
    nil))

(provide 'tg-shop)
;;; tg-shop.el ends here
