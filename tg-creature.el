;;; tg-creature.el --- 生物系统  -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'tg-registry)
(require 'tg-object)

(cl-defstruct tg-creature
  symbol           ;; 唯一标识符
  name             ;; 名称 "哥布林"
  attr             ;; 属性 alist ((hp 30) (attack 5) (defense 2))
  inventory        ;; 背包 (symbol list)
  equipment        ;; 装备栏 (symbol list)
  exp-reward       ;; 击杀经验奖励
  behaviors        ;; 行为列表 (aggressive passive neutral)
  death-trigger    ;; 死亡触发器
  shopkeeper       ;; 是否为商人
  handler          ;; 自定义处理函数
  respawn-interval ;; 刷新区间 (min . max) cons 或 nil
  initial-attr     ;; 初始属性快照（解析时 copy-tree 保存）
  initial-inventory ;; 初始背包（解析时 copy-sequence 保存）
  initial-equipment) ;; 初始装备（解析时 copy-sequence 保存）

;;; 属性查询

(defun tg-creature-attr-get (creature key)
  "从生物的 attr alist 中获取指定属性的值
attr 格式：((hp 30) (attack 5))，返回 30 或 nil"
  (let ((result (assq key (tg-creature-attr creature))))
    (when result
      (cadr result))))

;;; 生命状态判定

(defun tg-creature-dead-p (creature)
  "判断生物是否死亡（hp ≤ 0）"
  (let ((hp (tg-creature-attr-get creature 'hp)))
    (and hp (<= hp 0))))

;;; 效果应用

(defun tg-creature-take-effect (creature effect)
  "对生物应用效果（增量叠加）
effect 格式：(attr-key delta-value)
- 如果属性已存在，则叠加 value
- 如果属性不存在，则添加（value 作为初始值）
- hp 不会低于 0"
  (let* ((key (car effect))
         (value (cadr effect))
         (attr (tg-creature-attr creature))
         (existing (assq key attr)))
    (if existing
        ;; 叠加现有属性 ((hp 100) + (hp -20) -> (hp 80))
        (let ((new-value (+ (cadr existing) value)))
          (setcar (cdr existing) new-value)
          ;; hp 不低于 0
          (when (and (eq key 'hp) (< new-value 0))
            (setcar (cdr existing) 0)))
      ;; 添加新属性 ((hp 100) (defense 5))
      ;; 如果是新添加的 hp 且为负，设为 0
      (let ((final-value (if (and (eq key 'hp) (< value 0)) 0 value)))
        (setf (tg-creature-attr creature)
              (append attr (list (list key final-value)))))))
  nil)

;;; 物品管理

(defun tg-creature-add-item (creature item-sym)
  "向生物背包添加物品"
  (let ((inventory (tg-creature-inventory creature)))
    (unless (member item-sym inventory)
      (setf (tg-creature-inventory creature)
            (append inventory (list item-sym))))))

(defun tg-creature-remove-item (creature item-sym)
  "从生物背包移除物品"
  (setf (tg-creature-inventory creature)
        (delete item-sym (tg-creature-inventory creature))))

(defun tg-creature-has-item (creature item-sym)
  "检查生物是否拥有指定物品"
  (member item-sym (tg-creature-inventory creature)))

;;; 有效属性计算

(defun tg-creature-effective-attr (creature attr-key active-buffs)
  "计算生物的有效属性值
考虑基础属性 + 装备效果 + 临时buff
creature: 生物结构
attr-key: 属性键（hp/attack/defense等）
active-buffs: 当前激活的buff列表 ((attr-key value) ...）
返回：叠加后的属性值（未知属性返回0）"
  (let ((base-value (or (tg-creature-attr-get creature attr-key) 0))
        (equipment-bonus 0)
        (buff-bonus 0))
    ;; 遍历装备计算加成
    (dolist (equip-sym (tg-creature-equipment creature))
      (let ((obj (tg-get-object equip-sym)))
        (when obj
          (let ((effects (tg-object-effects obj)))
            (dolist (effect effects)
              (when (eq (car effect) attr-key)
                (setq equipment-bonus (+ equipment-bonus (cadr effect)))))))))
    ;; 遍历buff计算加成
    (dolist (buff active-buffs)
      (when (eq (car buff) attr-key)
        (setq buff-bonus (+ buff-bonus (cadr buff)))))
    ;; 返回总和
    (+ base-value equipment-bonus buff-bonus)))

(provide 'tg-creature)
;;; tg-creature.el ends here
