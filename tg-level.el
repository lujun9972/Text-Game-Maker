;;; tg-level.el --- 经验等级系统  -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'tg-creature)

;;; 配置变量

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

;;; 升级检查

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

;;; 手动升级

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

(provide 'tg-level)
;;; tg-level.el ends here
