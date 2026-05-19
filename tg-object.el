;;; tg-object.el --- 对象属性系统  -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'tg-registry)

(cl-defstruct tg-object
  symbol           ;; 唯一标识符
  name             ;; 名称 "木箱"
  synonyms         ;; 别名列表 (chest crate)
  contents         ;; 容器内容（symbol list）
  supports         ;; 支撑物内容（symbol list，仅 supporter）
  props            ;; 属性集合 (container supporter scenery static wearable edible readable)
  state            ;; 容器开闭状态: open / closed / locked / nil（非容器为 nil）
  key              ;; 解锁所需钥匙的 object symbol（nil 表示无需钥匙/任何方式可开）
  effects          ;; 效果列表 ((hp 20) (attack 3 :duration 10) ...)
  handler)         ;; 自定义处理函数

;;; 属性谓词

(defun tg-object-has-prop-p (object prop)
  "检查对象是否具有指定属性"
  (memq prop (tg-object-props object)))

(defun tg-object-container-p (object)
  "检查对象是否为容器"
  (tg-object-has-prop-p object 'container))

(defun tg-object-supporter-p (object)
  "检查对象是否为支撑物"
  (tg-object-has-prop-p object 'supporter))

(defun tg-object-wearable-p (object)
  "检查对象是否可穿戴"
  (tg-object-has-prop-p object 'wearable))

(defun tg-object-edible-p (object)
  "检查对象是否可食用"
  (tg-object-has-prop-p object 'edible))

(defun tg-object-readable-p (object)
  "检查对象是否可阅读"
  (tg-object-has-prop-p object 'readable))

(defun tg-object-scenery-p (object)
  "检查对象是否为风景"
  (tg-object-has-prop-p object 'scenery))

(defun tg-object-static-p (object)
  "检查对象是否为静态物体"
  (tg-object-has-prop-p object 'static))

(defun tg-object-takeable-p (object)
  "检查对象是否可取走
非 scenery、非 supporter、非 static 的对象可取"
  (not (or (tg-object-scenery-p object)
           (tg-object-supporter-p object)
           (tg-object-static-p object))))

;;; 容器状态机

(defun tg-object-open-p (object)
  "检查容器是否打开"
  (eq (tg-object-state object) 'open))

(defun tg-object-locked-p (object)
  "检查容器是否锁定"
  (eq (tg-object-state object) 'locked))

(defun tg-object-can-open-p (object)
  "检查容器是否可以打开
非容器或已打开或锁定的容器不能打开"
  (and (tg-object-container-p object)
       (not (tg-object-open-p object))
       (not (tg-object-locked-p object))))

(defun tg-object-can-close-p (object)
  "检查容器是否可以关闭
非容器或已关闭或锁定的容器不能关闭"
  (and (tg-object-container-p object)
       (tg-object-open-p object)
       (not (tg-object-locked-p object))))

(defun tg-object-can-lock-p (object)
  "检查容器是否可以锁定
非容器或已锁定或打开的容器不能锁定"
  (and (tg-object-container-p object)
       (eq (tg-object-state object) 'closed)
       (tg-object-key object)))

(defun tg-object-can-unlock-p (object)
  "检查容器是否可以解锁
非容器或未锁定的容器不能解锁"
  (and (tg-object-container-p object)
       (tg-object-locked-p object)))

(defun tg-object-set-state (object new-state)
  "设置容器状态
状态转换规则：open ↔ closed ↔ locked"
  (let ((current (tg-object-state object)))
    (cond
     ;; open → closed
     ((and (eq current 'open) (eq new-state 'closed))
      (setf (tg-object-state object) 'closed))
     ;; closed → open
     ((and (eq current 'closed) (eq new-state 'open))
      (setf (tg-object-state object) 'open))
     ;; closed → locked
     ((and (eq current 'closed) (eq new-state 'locked))
      (setf (tg-object-state object) 'locked))
     ;; locked → closed
     ((and (eq current 'locked) (eq new-state 'closed))
      (setf (tg-object-state object) 'closed))
     (t
      (error "Invalid state transition from %s to %s" current new-state))))
  new-state)

;;; 可访问性判定

(defun tg-object-accessible-p (object room)
  "检查对象是否可访问
对象可访问的条件：
1. 对象在房间中（直接或通过 supporter）
2. 或对象在 open 容器中
3. 不包括 closed/locked 容器内的对象"
  (let ((obj-sym (tg-object-symbol object)))
    (or
     ;; 直接在房间中
     (memq obj-sym (tg-room-contents room))
     ;; 在 supporter 上
     (cl-loop for container-sym in (tg-room-contents room)
              for container = (tg-get-object container-sym)
              when (and container (tg-object-supporter-p container))
              when (memq obj-sym (tg-object-supports container))
              return t)
     ;; 在 open 容器中
     (cl-loop for container-sym in (tg-room-contents room)
              for container = (tg-get-object container-sym)
              when (and container
                        (tg-object-container-p container)
                        (tg-object-open-p container))
              when (memq obj-sym (tg-object-contents container))
              return t))))

;;; 查找函数

(defun tg-object-find (sym)
  "从全局注册表查找对象"
  (tg-get-object sym))

(defun tg-object-find-parent (object room)
  "查找对象的父容器
返回对象所在的容器 symbol，或 'room（如果在房间中），或 nil（找不到）"
  (let ((obj-sym (tg-object-symbol object)))
    (cond
     ;; 直接在房间中
     ((memq obj-sym (tg-room-contents room))
      'room)
     ;; 在某个容器的内容或支撑物中
     (t
      (cl-loop for container-sym in (tg-room-contents room)
               for container = (tg-get-object container-sym)
               when (or (and (tg-object-container-p container)
                            (memq obj-sym (tg-object-contents container)))
                        (and (tg-object-supporter-p container)
                             (memq obj-sym (tg-object-supports container))))
               return container-sym)))))

(defun tg-object-find-in-room (room sym)
  "在房间中查找对象（包括 supporter 和 open container）"
  (or
   ;; 直接在房间中
   (and (memq sym (tg-room-contents room)) sym)
   ;; 在 supporter 或 open container 中
   (cl-loop for container-sym in (tg-room-contents room)
            for container = (tg-get-object container-sym)
            when (and container
                      (or (and (tg-object-supporter-p container)
                               (memq sym (tg-object-supports container)))
                          (and (tg-object-container-p container)
                               (tg-object-open-p container)
                               (memq sym (tg-object-contents container)))))
            return sym)))

(defun tg-object-find-in-inventory (inventory sym)
  "在背包列表中查找对象（只查顶层，不递归）"
  (when (memq sym inventory)
    sym))

;;; 移动对象

(defun tg-object-move (obj-sym from-room to-room)
  "将对象从一个房间移动到另一个房间
obj-sym: 对象的 symbol
from-room: 源 room 结构
to-room: 目标 room 结构"
  ;; cl-defstruct 创建的是 record 类型
  ;; slot 0: 类型名, slot 1: symbol, 2: name, 3: desc, 4: short-desc, 5: exits, 6: contents
  (aset from-room 6 (remove obj-sym (aref from-room 6)))
  (aset to-room 6 (append (aref to-room 6) (list obj-sym)))
  nil)

;;; 存档快照

(defun tg-object-snapshot (obj)
  "返回对象动态状态的 alist"
  (list (cons :state (tg-object-state obj))
        (cons :contents (tg-object-contents obj))
        (cons :supports (tg-object-supports obj))))

(defun tg-object-restore-snapshot (obj snapshot)
  "从 SNAPSHOT 恢复对象动态状态"
  (setf (tg-object-state obj) (cdr (assq :state snapshot)))
  (setf (tg-object-contents obj) (cdr (assq :contents snapshot)))
  (setf (tg-object-supports obj) (cdr (assq :supports snapshot))))

(provide 'tg-object)
;;; tg-object.el ends here
