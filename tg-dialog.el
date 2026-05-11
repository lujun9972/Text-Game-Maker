;;; tg-dialog.el --- 对话系统  -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'tg-registry)
(require 'tg-creature)
(require 'tg-game)

;;; 对话状态机

(cl-defstruct tg-dialog-state
  node-id          ;; 当前节点ID (symbol)
  npc-symbol       ;; NPC的symbol
  greeting         ;; 问候语 (string)
  options)         ;; 选项列表 (tg-dialog-option list)

(cl-defstruct tg-dialog-option
  text             ;; 选项显示文本 (string)
  response         ;; 选择后的回复 (string)
  condition        ;; 显示条件 (nil或条件表达式)
  effects          ;; 效果列表 (list)
  next-node)       ;; 下一个节点ID (symbol或nil)

;;; 当前对话状态

(defvar tg-dialog-pending nil
  "当前待处理的对话状态（nil 或 tg-dialog-state）")

;;; 对话启动

(defun tg-dialog-start (npc-sym &optional entry-node)
  "启动与NPC的对话
npc-sym: NPC的symbol
entry-node: 可选的入口节点ID（默认为npc-sym）
查找NPC的对话节点，设为pending，显示greeting和可见选项"
  (let* ((node-id (or entry-node npc-sym))
         (dialog (tg-get-dialog node-id)))
    (unless dialog
      (error "无法与%s对话：找不到对话节点" npc-sym))
    ;; 设置pending状态
    (setq tg-dialog-pending dialog)
    ;; 显示问候语
    (let ((greeting (tg-dialog-state-greeting dialog)))
      (when greeting
        (message "%s" greeting)))
    ;; 获取可见选项并显示
    (let ((visible-options (tg-dialog-filter-options dialog)))
      (if (null visible-options)
          (progn
            (message "没有可用的对话选项")
            (setq tg-dialog-pending nil))
        (tg-dialog-show-options visible-options)))))

;;; 选项过滤

(defun tg-dialog-filter-options (dialog-state)
  "过滤出满足条件的可见选项
dialog-state: tg-dialog-state结构
返回满足条件的tg-dialog-option列表"
  (let ((options (tg-dialog-state-options dialog-state))
        (game tg-game))
    (cl-remove-if-not
     (lambda (option)
       (let ((condition (tg-dialog-option-condition option)))
         (or (null condition)
             (tg-dialog-eval-condition condition game))))
     options)))

;;; 选项显示

(defun tg-dialog-show-options (options)
  "显示对话选项列表
options: tg-dialog-option列表"
  (cl-loop for option in options
           for i from 1
           do (message "%d. %s" i (tg-dialog-option-text option))))

;;; 选择处理

(defun tg-dialog-handle-choice (choice-str)
  "处理玩家选择的对话选项
choice-str: 玩家输入的选项编号（字符串）
解析编号→过滤可见选项→显示response→应用effects→跳转或结束"
  (unless tg-dialog-pending
    (error "当前没有待处理的对话"))
  ;; 解析编号
  (let ((choice (string-to-number choice-str)))
    (when (<= choice 0)
      (error "请输入有效的选项编号")))
  ;; 获取可见选项
  (let* ((visible-options (tg-dialog-filter-options tg-dialog-pending))
         (choice (1- (string-to-number choice-str))))  ; 转为0-based索引
    (when (or (< choice 0) (>= choice (length visible-options)))
      (error "请输入有效的选项编号（1-%d）" (length visible-options)))
    ;; 获取选中的选项
    (let* ((option (nth choice visible-options))
           (response (tg-dialog-option-response option))
           (effects (tg-dialog-option-effects option))
           (next-node (tg-dialog-option-next-node option))
           (npc-sym (tg-dialog-state-npc-symbol tg-dialog-pending)))
      ;; 显示回复
      (when response
        (message "%s" response))
      ;; 应用效果
      (when effects
        (tg-dialog-apply-effects effects))
      ;; 跳转或结束
      (if next-node
          (progn
            ;; 跳转到下一个节点
            (let ((next-dialog (tg-get-dialog next-node)))
              (unless next-dialog
                (error "对话节点%s不存在" next-node))
              (setq tg-dialog-pending next-dialog)
              (message "")
              ;; 显示新节点的问候语和选项
              (let ((greeting (tg-dialog-state-greeting next-dialog)))
                (when greeting
                  (message "%s" greeting)))
              (let ((next-visible (tg-dialog-filter-options next-dialog)))
                (if (null next-visible)
                    (progn
                      (message "对话结束")
                      (setq tg-dialog-pending nil))
                  (tg-dialog-show-options next-visible)))))
        ;; 对话结束
        (setq tg-dialog-pending nil)
        (message "对话结束")))))

;;; 条件求值

(defun tg-dialog-eval-condition (condition game)
  "递归求值条件表达式
condition: 条件表达式
game: 游戏状态哈希表
返回t或nil"
  (pcase condition
    ('nil t)
    (`(quest-active ,quest-sym)
     (let ((quest (tg-get-quest quest-sym)))
       (and quest (eq (tg-quest-status quest) 'active))))
    (`(quest-completed ,quest-sym)
     (let ((quest (tg-get-quest quest-sym)))
       (and quest (eq (tg-quest-status quest) 'completed))))
    (`(has-item ,item-sym)
     (let ((player (tg-player game)))
       (and player (tg-creature-has-item player item-sym))))
    (`(and . ,sub-conditions)
     (cl-every (lambda (c) (tg-dialog-eval-condition c game)) sub-conditions))
    (`(or . ,sub-conditions)
     (cl-some (lambda (c) (tg-dialog-eval-condition c game)) sub-conditions))
    (`(not ,sub-condition)
     (not (tg-dialog-eval-condition sub-condition game)))
    (_
     (error "未知的对话条件: %S" condition))))

;;; 效果应用

(defun tg-dialog-apply-effects (effects)
  "应用对话选项的效果列表
effects: 效果列表，格式如 ((exp 50) (item potion) (gold 100) (bonus-points 2) (quest-activate q1) (trigger fn))"
  (let ((game tg-game))
    (unless game
      (error "游戏未初始化"))
    (dolist (effect effects)
      (pcase effect
        (`(exp ,amount)
         (let ((player (tg-player game)))
           (when player
             (tg-creature-take-effect player (list 'exp amount))
             (message "获得 %d 点经验" amount))))
        (`(item ,item-sym)
         (let ((player (tg-player game)))
           (when player
             (tg-creature-add-item player item-sym)
             (message "获得物品: %s" item-sym))))
        (`(gold ,amount)
         (let ((player (tg-player game)))
           (when player
             (tg-creature-take-effect player (list 'gold amount))
             (message "获得 %d 金币" amount))))
        (`(bonus-points ,amount)
         (let ((player (tg-player game)))
           (when player
             (tg-creature-take-effect player (list 'bonus-points amount))
             (message "获得 %d 技能点" amount))))
        (`(quest-activate ,quest-sym)
         (let ((quest (tg-get-quest quest-sym)))
           (when quest
             (setf (cl-struct-slot-value 'tg-quest 'status quest) 'active)
             (message "任务已激活: %s" quest-sym))))
        (`(trigger ,fn)
         (when (functionp fn)
           (funcall fn)))
        (_
         (error "未知的对话效果: %S" effect))))))

(provide 'tg-dialog)
;;; tg-dialog.el ends here
