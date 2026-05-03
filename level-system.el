;;; level-system.el --- Level and experience system for Text-Game-Maker  -*- lexical-binding: t; -*-

(require 'creature-maker)
(require 'room-maker)

(defvar level-exp-table nil
  "每级所需累计经验值列表。
表长度 = 最大等级+1，索引0为占位符。
例如 (0 100 250 500) 表示：
  1→2 级需要 100 经验
  2→3 级需要 250 经验
  3→4 级需要 500 经验
  最大等级 = (1- 表长度) = 3")

(defvar level-up-bonus-points 0
  "每次升级获得的可分配技能点数")

(defvar auto-upgrade-attrs nil
  "升级时自动提升的属性列表, 如 ((hp . 5))")

(defun level-init (config-file)
  "从 CONFIG-FILE 加载升级配置。"
  (let ((config (tg-read-from-whole-string (tg-file-content config-file))))
    (setq level-exp-table (cdr (assoc 'level-exp-table config)))
    (setq level-up-bonus-points (cadr (assoc 'level-up-bonus-points config)))
    (setq auto-upgrade-attrs (cadr (assoc 'auto-upgrade-attrs config)))))

(defun get-exp-reward (creature)
  "获取 CREATURE 的经验奖励值。
优先使用 exp-reward slot，否则按 hp+attack+defense 自动计算。"
  (or (Creature-exp-reward creature)
      (let ((attr (Creature-attr creature)))
        (+ (or (cdr (assoc 'hp attr)) 0)
           (or (cdr (assoc 'attack attr)) 0)
           (or (cdr (assoc 'defense attr)) 0)))))

(defun add-exp-to-creature (creature exp)
  "给 CREATURE 增加 EXP 经验值，自动检查并处理升级。

经验值表示为累计值。level-exp-table 的索引0为占位符，
索引 level 为对应等级的门槛值。
最大等级为 (1- (length level-exp-table))。"
  (when (assoc 'exp (Creature-attr creature))
    (cl-incf (cdr (assoc 'exp (Creature-attr creature))) exp)
    (while (and level-exp-table
                (< (cdr (assoc 'level (Creature-attr creature))) (1- (length level-exp-table)))
                (>= (cdr (assoc 'exp (Creature-attr creature)))
                    (nth (cdr (assoc 'level (Creature-attr creature))) level-exp-table)))
      ;; Level up
      (cl-incf (cdr (assoc 'level (Creature-attr creature))))
      ;; Apply auto-upgrade-attrs
      (dolist (effect auto-upgrade-attrs)
        (take-effect-to-creature creature effect))
      ;; Add bonus points
      (when (assoc 'bonus-points (Creature-attr creature))
        (cl-incf (cdr (assoc 'bonus-points (Creature-attr creature))) level-up-bonus-points))
      ;; Display level up message
      (tg-display (format "恭喜升级！当前等级: %d" (cdr (assoc 'level (Creature-attr creature))))))))

(provide 'level-system)
