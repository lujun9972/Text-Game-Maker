;;; tg-config-gen.el --- Org 配置生成器与交叉引用验证  -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'tg-registry)
(require 'tg-room)
(require 'tg-object)
(require 'tg-creature)
(require 'tg-dialog)
(require 'tg-shop)
(require 'tg-quest)

;;; 工具函数

(defun tg-config-gen--or-empty (str)
  "返回 STR 本身，若为 nil 则返回空字符串。"
  (or str ""))

;;; tg-gen-game

(defun tg-gen-game (title author start-room)
  "生成完整的游戏配置模板，包含全局关键字和各 section 空模板。
TITLE: 游戏标题
AUTHOR: 作者
START-ROOM: 起始房间 symbol 字符串
返回 Org 格式字符串。"
  (format "#+TITLE: %s
#+AUTHOR: %s
#+START: %s

* Rooms

* Objects

* Creatures

* Dialogs

* Shops

* Quests
"
          (tg-config-gen--or-empty title)
          (tg-config-gen--or-empty author)
          (tg-config-gen--or-empty start-room)))

;;; tg-gen-room

(defun tg-gen-room (sym name desc exits contents creatures)
  "生成一个 Room 的 Org 配置。
SYM: 房间标识符字符串
NAME: 房间名
DESC: 完整描述
EXITS: 出口字符串 \"north=room2,south=room1\"
CONTENTS: 内容物列表字符串 \"key,sword\"
CREATURES: 生物列表字符串 \"goblin\"
返回 Org 格式字符串。"
  (format "** %s
:PROPERTIES:
:NAME: %s
:DESC: %s
:SHORT_DESC: %s
:EXITS: %s
:CONTENTS: %s
:CREATURES: %s
:END:
"
          (tg-config-gen--or-empty sym)
          (tg-config-gen--or-empty name)
          (tg-config-gen--or-empty desc)
          (tg-config-gen--or-empty desc) ; SHORT_DESC 默认同 DESC
          (tg-config-gen--or-empty exits)
          (tg-config-gen--or-empty contents)
          (tg-config-gen--or-empty creatures)))

;;; tg-gen-object

(defun tg-gen-object (sym name synonyms props state key effects handler)
  "生成一个 Object 的 Org 配置。
SYM: 对象标识符字符串
NAME: 对象名
SYNONYMS: 同义词字符串 \"sword,blade\"
PROPS: 属性字符串 \"wearable\"
STATE: 容器状态字符串
KEY: 解锁钥匙字符串
EFFECTS: 效果字符串
HANDLER: 处理函数字符串
返回 Org 格式字符串。"
  (format "** %s
:PROPERTIES:
:NAME: %s
:SYNONYMS: %s
:PROPS: %s
:STATE: %s
:KEY: %s
:EFFECTS: %s
:HANDLER: %s
:END:
"
          (tg-config-gen--or-empty sym)
          (tg-config-gen--or-empty name)
          (tg-config-gen--or-empty synonyms)
          (tg-config-gen--or-empty props)
          (tg-config-gen--or-empty state)
          (tg-config-gen--or-empty key)
          (tg-config-gen--or-empty effects)
          (tg-config-gen--or-empty handler)))

;;; tg-gen-creature

(defun tg-gen-creature (sym name attr inventory equipment behaviors shopkeeper handler)
  "生成一个 Creature 的 Org 配置。
SYM: 生物标识符字符串
NAME: 生物名
ATTR: 属性字符串 \"hp 30 attack 5\"
INVENTORY: 背包列表字符串
EQUIPMENT: 装备列表字符串
BEHAVIORS: 行为字符串
SHOPKEEPER: 商人标记字符串
HANDLER: 处理函数字符串
返回 Org 格式字符串。"
  (format "** %s
:PROPERTIES:
:NAME: %s
:ATTR: %s
:INVENTORY: %s
:EQUIPMENT: %s
:BEHAVIORS: %s
:SHOPKEEPER: %s
:HANDLER: %s
:END:
"
          (tg-config-gen--or-empty sym)
          (tg-config-gen--or-empty name)
          (tg-config-gen--or-empty attr)
          (tg-config-gen--or-empty inventory)
          (tg-config-gen--or-empty equipment)
          (tg-config-gen--or-empty behaviors)
          (tg-config-gen--or-empty shopkeeper)
          (tg-config-gen--or-empty handler)))

;;; tg-gen-dialog

(defun tg-gen-dialog (node-id npc-symbol greeting options)
  "生成一个 Dialog 节点的 Org 配置。
NODE-ID: 节点 ID 字符串
NPC-SYMBOL: NPC 的 symbol 字符串
GREETING: 问候语字符串
OPTIONS: 选项行列表，每个元素为字符串
  格式: \"选项文本 :: 回复文本 → 效果 → next-node\"
返回 Org 格式字符串。"
  (let ((header (format "** %s
:PROPERTIES:
:NPC_SYMBOL: %s
:GREETING: %s
:END:
"
                        (tg-config-gen--or-empty node-id)
                        (tg-config-gen--or-empty npc-symbol)
                        (tg-config-gen--or-empty greeting))))
    (if options
        (concat header (mapconcat (lambda (opt) (concat opt "\n")) options ""))
      header)))

;;; tg-gen-shop

(defun tg-gen-shop (sym npc-symbol sell-rate goods)
  "生成一个 Shop 的 Org 配置。
SYM: 商店标识符字符串
NPC-SYMBOL: NPC symbol 字符串
SELL-RATE: 出售价格比例字符串 \"0.5\"
GOODS: 商品列表字符串 \"potion=10,sword=30\"
返回 Org 格式字符串。"
  (format "** %s
:PROPERTIES:
:NPC_SYMBOL: %s
:SELL_RATE: %s
:GOODS: %s
:END:
"
          (tg-config-gen--or-empty sym)
          (tg-config-gen--or-empty npc-symbol)
          (tg-config-gen--or-empty sell-rate)
          (tg-config-gen--or-empty goods)))

;;; tg-gen-quest

(defun tg-gen-quest (sym type target count rewards)
  "生成一个 Quest 的 Org 配置。
SYM: 任务标识符字符串
TYPE: 任务类型字符串 \"kill\"
TARGET: 目标字符串
COUNT: 数量字符串 \"3\"
REWARDS: 奖励字符串 \"(exp 20) (item potion)\"
返回 Org 格式字符串。"
  (format "** %s
:PROPERTIES:
:TYPE: %s
:TARGET: %s
:COUNT: %s
:REWARDS: %s
:END:
"
          (tg-config-gen--or-empty sym)
          (tg-config-gen--or-empty type)
          (tg-config-gen--or-empty target)
          (tg-config-gen--or-empty count)
          (tg-config-gen--or-empty rewards)))

;;; tg-validate-config

(defun tg-validate-config ()
  "交叉引用验证已注册的游戏实体。
检查：
1. 房间 exit 引用不存在的房间
2. 房间 contents 中引用未定义对象
3. 对话选项 next-node 引用不存在的对话节点
返回警告字符串列表。"
  (let (warnings)
    ;; 1. 检查 exit 引用不存在的房间
    (maphash
     (lambda (room-sym room)
       (dolist (exit (tg-room-exits room))
         (let ((target (cdr exit)))
           (unless (tg-get-room target)
             (push (format "Room %s: exit %s references nonexistent room %s"
                           room-sym (car exit) target)
                   warnings)))))
     tg--rooms)

    ;; 2. 检查 contents 引用未定义对象
    (maphash
     (lambda (room-sym room)
       (dolist (obj-sym (tg-room-contents room))
         (unless (tg-get-object obj-sym)
           (push (format "Room %s: contents references undefined object %s"
                         room-sym obj-sym)
                 warnings))))
     tg--rooms)

    ;; 3. 检查对话 next-node 引用不存在的节点
    (maphash
     (lambda (node-id dialog)
       (dolist (option (tg-dialog-state-options dialog))
         (let ((next-node (tg-dialog-option-next-node option)))
           (when (and next-node (not (tg-get-dialog next-node)))
             (push (format "Dialog %s: option next-node references nonexistent dialog %s"
                           node-id next-node)
                   warnings)))))
     tg--dialogs)

    (nreverse warnings)))

(provide 'tg-config-gen)
;;; tg-config-gen.el ends here
