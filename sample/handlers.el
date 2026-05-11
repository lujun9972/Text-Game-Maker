;;; handlers.el --- 地牢冒险自定义配置  -*- lexical-binding: t; -*-

;; 升级表（索引 0 = 等级 1→2 所需累计经验）
(setq tg-level-exp-table '(0 50 120 220 350 500 700 950 1300 1700))
;; 每次升级获得自由属性点
(setq tg-level-bonus-points-per-level 3)
;; 每次升级自动提升的属性
(setq tg-level-auto-upgrade-attrs '((hp 10)))

(provide 'handlers)
;;; handlers.el ends here
