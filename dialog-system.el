;;; dialog-system.el --- Dialog system for Text-Game-Maker  -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'room-maker)
(require 'creature-maker)
(require 'level-system)
(require 'quest-system)

(defvar dialogs-alist nil
  "NPC symbol到Dialog对象的映射")

(defvar dialog-pending nil
  "当前等待选择的Dialog对象（nil表示无待处理对话）")

(cl-defstruct Dialog
  "Dialog structure"
  (npc nil :documentation "关联的 NPC symbol")
  (greeting "" :documentation "NPC 开场白")
  (options nil :documentation "DialogOption 列表"))

(cl-defstruct DialogOption
  "Dialog option structure"
  (text "" :documentation "玩家看到的选项文本")
  (response "" :documentation "NPC 的回应文本")
  (condition nil :documentation "显示条件（nil 表示总是显示）")
  (effects nil :documentation "效果列表"))

;; --- Config loading ---

(defun build-option (option-data)
  "根据OPTION-DATA创建DialogOption对象."
  (make-DialogOption
   :text (nth 0 option-data)
   :response (nth 1 option-data)
   :condition (nth 2 option-data)
   :effects (nth 3 option-data)))

(defun build-dialog (dialog-entity)
  "根据DIALOG-ENTITY创建Dialog对象."
  (let ((npc (nth 0 dialog-entity))
        (greeting (nth 1 dialog-entity))
        (options-data (nth 2 dialog-entity)))
    (cons npc (make-Dialog
               :npc npc
               :greeting greeting
               :options (mapcar #'build-option options-data)))))

(defun dialog-init (config-file)
  "从CONFIG-FILE加载对话配置."
  (let ((dialog-entities (tg-read-from-whole-string (tg-file-content config-file))))
    (setq dialogs-alist (mapcar #'build-dialog dialog-entities))))

;; --- Condition evaluation ---

(defun dialog-evaluate-condition (cond-expr)
  "评估条件表达式COND-EXPR."
  (cond
   ((null cond-expr) t)
   ((eq (car cond-expr) 'quest-active)
    (let ((q (cdr (assoc (cadr cond-expr) quests-alist))))
      (and q (eq (Quest-status q) 'active))))
   ((eq (car cond-expr) 'quest-completed)
    (let ((q (cdr (assoc (cadr cond-expr) quests-alist))))
      (and q (eq (Quest-status q) 'completed))))
   ((eq (car cond-expr) 'has-item)
    (and tg-myself (member (cadr cond-expr) (Creature-inventory tg-myself))))
   ((eq (car cond-expr) 'and)
    (cl-every #'dialog-evaluate-condition (cdr cond-expr)))
   ((eq (car cond-expr) 'or)
    (cl-some #'dialog-evaluate-condition (cdr cond-expr)))
   (t nil)))

(defun dialog-get-visible-options (dialog)
  "返回DIALOG中满足条件的选项列表."
  (cl-remove-if-not
   (lambda (opt) (dialog-evaluate-condition (DialogOption-condition opt)))
   (Dialog-options dialog)))

;; --- Effect execution ---

(defun dialog-apply-effects (option)
  "执行OPTION的效果."
  (dolist (effect (DialogOption-effects option))
    (let ((key (car effect))
          (value (cdr effect)))
      (pcase key
        ('exp (add-exp-to-creature tg-myself value))
        ('item (tg-add-inventory-to-creature tg-myself value))
        ('bonus-points (tg-take-effect-to-creature tg-myself (cons 'bonus-points value)))
        ('trigger (when (functionp value) (funcall value)))))))

;; --- Dialog interaction ---

(defun dialog-start (npc-symbol)
  "开始与NPC-SYMBOL的对话."
  (let ((dialog (cdr (assoc npc-symbol dialogs-alist))))
    (unless dialog
      (throw 'exception (format "无法与%s对话" npc-symbol)))
    (tg-track-quest 'talk npc-symbol)
    (let ((visible-options (dialog-get-visible-options dialog)))
      (tg-display (format "%s说：%s" npc-symbol (Dialog-greeting dialog)))
      (if (null visible-options)
          (tg-display "没有可用的对话选项")
        (setq dialog-pending dialog)
        (dotimes (i (length visible-options))
          (tg-display (format "  %d. %s" (1+ i) (DialogOption-text (nth i visible-options)))))
        (tg-display "请输入选项编号:")))))

(defun dialog-handle-choice (input)
  "处理玩家对话选择INPUT."
  (let* ((visible-options (dialog-get-visible-options dialog-pending))
         (choice (string-to-number input))
         (npc (Dialog-npc dialog-pending)))
    (if (and (> choice 0) (<= choice (length visible-options)))
        (let ((option (nth (1- choice) visible-options)))
          (tg-display (format "%s说：%s" npc (DialogOption-response option)))
          (dialog-apply-effects option)
          (setq dialog-pending nil))
      (tg-display "请输入有效的选项编号"))))

(provide 'dialog-system)
