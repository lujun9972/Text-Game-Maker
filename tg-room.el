;;; tg-room.el --- 房间与地图系统  -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'tg-registry)
(require 'tg-object)

(cl-defstruct tg-room
  symbol           ;; 唯一标识符
  name             ;; 名称 "房间"
  desc             ;; 完整描述
  short-desc       ;; 简短描述（可选，重复访问时使用）
  exits            ;; 出口列表 ((direction . target-room-symbol) ...)
  contents         ;; 房间内的对象（symbol list）
  creatures        ;; 房间内的生物（symbol list）
  before-handler   ;; 进入前的处理函数
  after-handler    ;; 进入后的处理函数
  visit-count)     ;; 访问计数

(defconst tg-directions
  '((north . n) (south . s) (east . e) (west . w)
    (northeast . ne) (northwest . nw) (southeast . se) (southwest . sw)
    (up . u) (down . d) (in . nil) (out . nil))
  "方向词列表，每个元素为 (direction . abbreviation)")

(defun tg-room-exit (room direction)
  "查找房间在指定方向的出口"
  (cdr (assq direction (tg-room-exits room))))

(defun tg-room-visit (room)
  "增加房间访问计数"
  (setf (tg-room-visit-count room)
        (1+ (tg-room-visit-count room))))

(defun tg-room-all-visible-objects (room)
  "返回房间中所有可见对象的 symbol 列表
递归展开：
- open 容器内的内容
- supporter 上支撑的对象"
  (let ((result '())
        (to-check (copy-sequence (tg-room-contents room))))
    (while to-check
      (let ((sym (pop to-check)))
        (unless (memq sym result)
          (push sym result)
          (let ((obj (tg-get-object sym)))
            (when obj
              ;; 如果是打开的容器，添加内容
              (when (and (tg-object-container-p obj)
                         (tg-object-open-p obj))
                (dolist (content-sym (tg-object-contents obj))
                  (unless (memq content-sym to-check)
                    (push content-sym to-check))))
              ;; 如果是支撑物，添加支撑的对象
              (when (tg-object-supporter-p obj)
                (dolist (support-sym (tg-object-supports obj))
                  (unless (memq support-sym to-check)
                    (push support-sym to-check)))))))))
    (nreverse result)))

(defun tg-room-describe (room)
  "描述房间
首次访问：完整描述 + 可见物品列表 + creature 列表
重复访问：简短描述 + 可见物品列表 + creature 列表"
  (let ((desc "")
        (first-visit (zerop (tg-room-visit-count room))))
    ;; 增加访问计数
    (tg-room-visit room)
    ;; 房间描述
    (if first-visit
        (setq desc (tg-room-desc room))
      (setq desc (or (tg-room-short-desc room)
                     (tg-room-desc room))))
    ;; 添加可见物品
    (let ((visible-objs (tg-room-all-visible-objects room)))
      (when visible-objs
        (let ((obj-names '()))
          (dolist (sym visible-objs)
            (let ((obj (tg-get-object sym)))
              (when (and obj (not (tg-object-scenery-p obj)))
                (push (tg-object-name obj) obj-names))))
          (when obj-names
            (setq desc (concat desc "\n\n这里有："
                                (mapconcat 'identity (nreverse obj-names) "、")))))))
    ;; 添加生物列表
    (let ((creatures (tg-room-creatures room)))
      (when creatures
        (setq desc (concat desc "\n\n这里有"
                            (if (> (length creatures) 1) "这些生物：" "一个生物：")
                            (mapconcat 'symbol-name creatures "、")))))
    ;; 添加出口信息
    (let ((exits (tg-room-exits room)))
      (when exits
        (setq desc (concat desc "\n\n出口："
                            (mapconcat (lambda (e)
                                         (let ((dest (tg-get-room (cdr e))))
                                           (concat (symbol-name (car e)) "→"
                                                   (if dest (tg-room-name dest)
                                                     (symbol-name (cdr e))))))
                                       exits "、")))))
    desc))

(defun tg-room-add-object (room obj-sym)
  "添加对象到房间"
  (setf (tg-room-contents room)
        (append (tg-room-contents room) (list obj-sym))))

(defun tg-room-remove-object (room obj-sym)
  "从房间移除对象"
  (setf (tg-room-contents room)
        (delq obj-sym (tg-room-contents room))))

(defun tg-room-add-creature (room creature-sym)
  "添加生物到房间"
  (setf (tg-room-creatures room)
        (append (tg-room-creatures room) (list creature-sym))))

(defun tg-room-remove-creature (room creature-sym)
  "从房间移除生物"
  (setf (tg-room-creatures room)
        (delq creature-sym (tg-room-creatures room))))

(provide 'tg-room)
;;; tg-room.el ends here
