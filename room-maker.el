;;; room-maker.el --- Room system for Text-Game-Maker  -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'cl-generic)
(require 'thingatpt)

(defun tg-read-from-whole-string (string)
  "Read Emacs Lisp data from STRING as a single form."
  (read (format "(%s)" string)))

(defvar tg-rooms-alist nil
  "symbol与room对象的映射")

(defun tg-get-room-by-symbol (symbol)
  "根据symbol获取room对象"
  (tg-get-entity tg-rooms-alist symbol t))

;; 定义Room结构体
(cl-defstruct Room
  "Room structure"
  (symbol nil :documentation "ROOM标志")
  (description "" :documentation "ROOM描述")
  (inventory nil :documentation "ROOM中所有的物品")
  (creature nil :documentation "ROOM中所拥有的生物")
  (in-trigger nil :documentation "进入该ROOM后触发的事件")
  (out-trigger nil :documentation "离开该ROOM后触发的事件"))

(tg-def-config-builder room tg-rooms-alist Room (symbol description inventory creature))

(cl-defgeneric describe (object)
  "Describe an object.")

(cl-defmethod describe ((room Room))
  "输出room的描述"
  (cl-multiple-value-bind (up-room right-room down-room left-room) (tg-beyond-rooms (Room-symbol room) tg-room-map)
	(format "这里是%s\n%s\n物品列表:%s\n生物列表:%s\n附近的rooms: up:%s right:%s down:%s left:%s"
	        (Room-symbol room) (Room-description room) (Room-inventory room) (Room-creature room)
	        up-room right-room down-room left-room)))

;; 创建room列表的方法

(defun tg-remove-inventory-from-room (room inventory)
  ""
  (setf (Room-inventory room) (remove inventory (Room-inventory room))))

(defun tg-add-inventory-to-room (room inventory)
  ""
  (push inventory (Room-inventory room)))

(defun tg-remove-creature-from-room (room inventory)
  ""
  (setf (Room-creature room) (remove inventory (Room-creature room))))

(defun tg-add-creature-to-room (room creature)
  ""
  (push creature (Room-creature room)))

(defun tg-inventory-exist-in-room-p (room inventory)
  ""
  (member inventory (Room-inventory room)))

(defun tg-creature-exist-in-room-p (room creature)
  ""
  (member creature (Room-creature room)))
;; 将各room组装成地图的方法
(defvar tg-room-map nil
  "room的地图")

(defun tg-build-room-map(tg-room-map-config-file)
  "根据`tg-room-map-config-file'中的配置信息创建地图"
  (let* ((file-lines (split-string (tg-file-content tg-room-map-config-file) "[\r\n]")))
	(mapcar (lambda(line)
			  (mapcar #'intern (split-string line)))
			file-lines)))

;; 
(defun tg-get-room-position (room-symbol tg-room-map)
  "从`tg-room-map'中取出`room-symbol'标识的room的坐标"
  (let* ((x (cl-position-if (lambda(x-rooms)
							  (member room-symbol x-rooms)) tg-room-map))
		 (y (cl-position room-symbol (nth x tg-room-map))))
	(list x y)))

;; 
(defun tg-beyond-rooms (room-symbol tg-room-map)
  "根据tg-room-map取与room-symbol相邻的room列表"
  (cl-multiple-value-bind (x y) (tg-get-room-position room-symbol tg-room-map)
	(let ((height (length tg-room-map))
		  (width (length (car tg-room-map)))
		  up down left right)
	  (setq up (if (= x 0)
				   nil
				 (nth y (nth (1- x) tg-room-map))))
	  (setq down (if (= x (1- height))
					 nil
				   (nth y (nth (1+ x) tg-room-map))))
	  (setq left (if (= y 0)
					 nil
				   (nth (1- y) (nth x tg-room-map))))
	  (setq right (if (= y (1- width))
					  nil
					(nth (1+ y) (nth x tg-room-map))))
	  (list up right down left))))

;; 定义初始化函数
(defvar tg-current-room nil				;
  "当前所处的room对象")

(defvar tg-config-dir nil
  "游戏配置文件目录路径，用于存档恢复时重新加载配置。")

(defun tg-map-init(room-config-file tg-room-map-config-file)
  "初始化函数,生成room对象,组装map"
  (setq tg-config-dir (file-name-directory room-config-file))
  (tg-room-init room-config-file)
  (setq tg-room-map (tg-build-room-map tg-room-map-config-file))
  (setq tg-current-room (tg-get-room-by-symbol (caar tg-rooms-alist))))

(provide 'room-maker)

