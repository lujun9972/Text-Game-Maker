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
active-buffs: buff列表，支持两种格式：
  简单格式: ((attr-key value) ...)
  game格式: ((attr-key . (:delta value :remaining N)) ...)
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
    ;; 遍历buff计算加成（兼容两种格式）
    (dolist (buff active-buffs)
      (when (eq (car buff) attr-key)
        (let ((val (cdr buff)))
          (setq buff-bonus
                (+ buff-bonus
                   (if (and (consp val) (keywordp (car val)))
                       (plist-get val :delta)   ;; game格式: (attr . (:delta v ...))
                     (car val)))))))             ;; 简单格式: (attr value)
    ;; 返回总和
    (+ base-value equipment-bonus buff-bonus)))

;;; 经验等级系统

(defvar tg-level-exp-table '(0 100 250 500 850 1300 1900 2700 3800 5000)
  "升级所需经验表
索引 0 对应等级 1，索引 1 对应等级 2，依此类推
例如：等级 1->2 需要 100 经验，等级 2->3 需要 250 经验")

(defvar tg-level-bonus-points-per-level 3
  "每次升级获得的自由属性点数")

(defvar tg-level-auto-upgrade-attrs '((hp 5))
  "每次升级自动提升的属性增量
格式：((attr-key delta) ...)
例如：((hp 5)) 表示每次升级 hp +5")

(defun tg-level-check (creature)
  "检查生物经验值并自动升级
creature: 生物结构体
当 exp >= exp-table[level] 时触发升级，每次升级：
1. level +1
2. bonus-points + bonus-points-per-level
3. auto-upgrade-attrs 各自增加对应值"
  (let ((level (tg-creature-attr-get creature 'level))
        (exp (tg-creature-attr-get creature 'exp)))
    (while (and (< level (length tg-level-exp-table))
                (>= exp (nth level tg-level-exp-table)))
      ;; 升级：level +1
      (tg-creature-take-effect creature (list 'level 1))
      (cl-incf level)
      ;; 赠送自由属性点
      (tg-creature-take-effect creature (list 'bonus-points tg-level-bonus-points-per-level))
      ;; 自动提升属性
      (dolist (upgrade tg-level-auto-upgrade-attrs)
        (tg-creature-take-effect creature upgrade)))))

(defun tg-level-upgrade (creature attr-key delta)
  "使用 bonus-points 手动升级属性
creature: 生物结构体
attr-key: 要升级的属性键（如 'hp, 'attack）
delta: 要增加的数值
要求：creature 必须有足够的 bonus-points（每点消耗 1 bonus-point）"
  (let ((bonus-points (tg-creature-attr-get creature 'bonus-points)))
    (if (and bonus-points (>= bonus-points delta))
        (progn
          (tg-creature-take-effect creature (list 'bonus-points (- delta)))
          (tg-creature-take-effect creature (list attr-key delta))
          t)
      nil)))

;;; 存档快照

(defun tg-creature-snapshot (creature)
  "返回生物动态状态的 alist"
  (list (cons :attr (tg-creature-attr creature))
        (cons :inventory (tg-creature-inventory creature))
        (cons :equipment (tg-creature-equipment creature))))

(defun tg-creature-restore-snapshot (creature snapshot)
  "从 SNAPSHOT 恢复生物动态状态"
  (setf (tg-creature-attr creature) (cdr (assq :attr snapshot)))
  (setf (tg-creature-inventory creature) (cdr (assq :inventory snapshot)))
  (setf (tg-creature-equipment creature) (cdr (assq :equipment snapshot))))

(provide 'tg-creature)
;;; tg-creature.el ends here
