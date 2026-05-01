;;; creature-maker.el --- Creature system for Text-Game-Maker  -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'thingatpt)
(defvar creatures-alist nil
  "symbol与creature对象的映射")

(defun get-creature-by-symbol (symbol)
  "根据symbol获取creature对象"
  (cdr (assoc symbol creatures-alist)))

(cl-defstruct Creature
  "Creature structure"
  (symbol nil :documentation "CREATURE标志")
  (description "" :documentation "CREATURE描述")
  (occupation 'human :documentation "CREATURE的职业")
  (attr nil :documentation "CREATURE的属性")
  (inventory nil :documentation "CREATURE所拥有的物品")
  (equipment nil :documentation "CREATURE装备的装备")
  (watch-trigger nil :documentation "查看该CREATURE后触发的事件")
  (death-trigger nil :documentation "该CREATURE被击败后触发的事件")
  (exp-reward nil :documentation "击败该CREATURE获得的经验值"))

(cl-defmethod describe ((creature Creature))
  "输出creature的描述"
  (format "这个是%s\n%s\n属性值:%s\n拥有物品:%s\n装备了:%s"
          (Creature-symbol creature) (Creature-description creature)
          (Creature-attr creature) (Creature-inventory creature)
          (Creature-equipment creature)))

;; 创建creature列表的方法
(defun build-creature (creature-entity)
  "根据creature-entity创建creature,并将creature存入creatures-alist中"
  (cl-multiple-value-bind (symbol description attr inventory equipment death-trigger exp-reward) creature-entity
	(cons symbol (make-Creature :symbol symbol :description description :inventory inventory :equipment equipment :attr attr :death-trigger death-trigger :exp-reward exp-reward))))

(defun build-creatures(creature-config-file)
  "根据`creature-config-file'中的配置信息创建各个creature"
  (let ((creature-entities (read-from-whole-string (file-content creature-config-file))))
	(mapcar #'build-creature creature-entities)))

;; 定义初始化函数
(defvar myself nil				;
  "当前所处的creature对象")

(defun creatures-init(creature-config-file)
  "初始化函数,生成creature对象,组装map"
  (setq creatures-alist (build-creatures creature-config-file))
  (setq myself (get-creature-by-symbol (caar creatures-alist))))


(defun remove-inventory-from-creature (creature inventory)
  ""
  (setf (Creature-inventory creature) (remove inventory (Creature-inventory creature))))

(defun add-inventory-to-creature (creature inventory)
  ""
  (push inventory (Creature-inventory creature)))

(defun inventory-exist-in-creature-p (creature inventory)
  ""
  (member inventory (Creature-inventory creature)))

(defun remove-equipment-from-creature (creature equipment)
  ""
  (setf (Creature-equipment creature) (remove equipment (Creature-equipment creature))))

(defun add-equipment-to-creature (creature equipment)
  ""
  (push equipment (Creature-equipment creature)))

(defun equipment-exist-in-creature-p (creature equipment)
  ""
  (member equipment (Creature-equipment creature)))

(defun take-effect-to-creature (creature effect)
  ""
  (let* ((attr-type (car effect))
		(value (cdr effect)))
	(if (assoc attr-type (Creature-attr creature))
		(cl-incf (cdr (assoc attr-type (Creature-attr creature))) value)
	  (push (cl-copy-list effect ) (Creature-attr creature)))))

(defun take-effects-to-creature(creature effects)
  ""
  (dolist (effect effects)
	(take-effect-to-creature creature effect)))

(provide 'creature-maker)

