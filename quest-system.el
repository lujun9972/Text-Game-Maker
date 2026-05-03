;;; quest-system.el --- Quest system for Text-Game-Maker  -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'room-maker)
(require 'creature-maker)
(require 'level-system)

(defvar quests-alist nil
  "symbol到Quest对象的映射")

(cl-defstruct Quest
  "Quest structure"
  (symbol nil :documentation "任务唯一标识符")
  (description "" :documentation "任务描述")
  (type nil :documentation "任务类型: kill/collect/explore/talk")
  (target nil :documentation "任务目标 symbol")
  (count 1 :documentation "目标数量")
  (progress 0 :documentation "当前进度")
  (rewards nil :documentation "奖励列表")
  (status 'inactive :documentation "任务状态: inactive/active/completed/failed")
  (description-complete "" :documentation "完成时的提示文本"))

;; --- Config loading ---

(defun build-quest (quest-entity)
  "根据quest-entity创建Quest对象."
  (cl-multiple-value-bind (symbol description type target count rewards status description-complete) quest-entity
    (let ((q (make-Quest :symbol symbol :description description :type type :target target
                          :count count :rewards rewards :status status
                          :description-complete description-complete)))
      (cons symbol q))))

(defun quest-init (config-file)
  "从CONFIG-FILE加载任务配置."
  (let ((quest-entities (read-from-whole-string (file-content config-file))))
    (setq quests-alist (mapcar #'build-quest quest-entities))))

;; --- Reward distribution ---

(defun quest-apply-rewards (quest)
  "发放QUEST的奖励."
  (dolist (reward (Quest-rewards quest))
    (let ((key (car reward))
          (value (cdr reward)))
      (pcase key
        ('exp (tg-display (format "任务奖励：获得 %d 点经验值！" value))
              (add-exp-to-creature myself value))
        ('item (tg-display (format "任务奖励：获得 %s！" value))
               (add-inventory-to-creature myself value))
        ('bonus-points (tg-display (format "任务奖励：获得 %d 技能点！" value))
                       (take-effect-to-creature myself (cons 'bonus-points value)))
        ('trigger (when (functionp value) (funcall value)))))))

;; --- Progress tracking ---

(defun quest-update-progress (quest)
  "Update quest progress and check completion."
  (cl-incf (Quest-progress quest))
  (when (>= (Quest-progress quest) (Quest-count quest))
    (setf (Quest-status quest) 'completed)
    (tg-display (format "任务完成：%s" (Quest-description quest)))
    (when (Quest-description-complete quest)
      (tg-display (Quest-description-complete quest)))
    (quest-apply-rewards quest)))

(defun tg-track-quest (type target-symbol)
  "追踪TYPE类型、目标为TARGET-SYMBOL的任务进度."
  (dolist (pair quests-alist)
    (let ((q (cdr pair)))
      (when (and (eq (Quest-status q) 'active)
                 (eq (Quest-type q) type)
                 (eq (Quest-target q) target-symbol))
        (quest-update-progress q)))))

;; --- Quest listing ---

(defun quest-list-active ()
  "列出所有活跃任务."
  (cl-remove-if-not (lambda (pair) (eq (Quest-status (cdr pair)) 'active)) quests-alist))

(defun quest-list-all ()
  "列出所有任务."
  quests-alist)

(defun quest-find (name)
  "按symbol或description查找任务，返回(cons symbol quest)或nil."
  (when (stringp name)
    (setq name (intern name)))
  (or (assoc name quests-alist)
      (cl-find-if (lambda (pair)
                     (string= (Quest-description (cdr pair)) (symbol-name name)))
                   quests-alist)))

(defun quest-accept (quest-name)
  "接受指定任务，将状态从inactive改为active."
  (let* ((pair (quest-find quest-name))
         (q (cdr pair)))
    (unless pair
      (throw 'exception (format "没有任务%s" quest-name)))
    (unless (eq (Quest-status q) 'inactive)
      (throw 'exception (format "任务%s当前状态无法接受" (Quest-description q))))
    (setf (Quest-status q) 'active)
    (tg-display (format "接受了任务：%s" (Quest-description q)))))

(provide 'quest-system)
