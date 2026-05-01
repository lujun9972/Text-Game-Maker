# Modernize Obsolete Technologies Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 EIEIO 对象系统迁移为 cl-defstruct，清理废弃依赖，添加 lexical-binding 等现代实践

**Architecture:** 保持模块结构和外部接口不变，仅替换内部实现。Room/Inventory/Creature 从 defclass 变为 cl-defstruct，多态 describe 用 cl-defgeneric/cl-defmethod 保留。accessor 从共用的 `member-xxx` 改为类型前缀的 `Room/Inventory/Creature-xxx`。

**Tech Stack:** Emacs Lisp, cl-defstruct, cl-defgeneric, cl-lib, cl-generic

---

### Task 1: 迁移 room-maker.el

**Files:**
- Modify: `room-maker.el` (全部替换为 cl-defstruct)

**Step 1: 替换文件头部和 require**

改前第1-4行：
```elisp
(require 'eieio)
(require 'thingatpt)
(defvar display-fn #'message
  "显示信息的函数")
```

改后：
```elisp
;;; room-maker.el --- Room system for Text-Game-Maker  -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'cl-generic)
(require 'thingatpt)
```

删除 `(require 'eieio)` 和重复的 `display-fn`。

**Step 2: 在文件前部添加 read-from-whole-string**

```elisp
(defun read-from-whole-string (string)
  "Read Emacs Lisp data from STRING as a single form."
  (read (format "(%s)" string)))
```

**Step 3: 替换 Room 类定义和 describe 方法**

改前：
```elisp
(defclass Room nil
  ((symbol :initform (intern (format "room-%s" (length rooms-alist))) :initarg :symbol :accessor member-symbol :documentation "ROOM标志")
   (description :initarg :description :accessor member-description :documentation "ROOM描述")
   (inventory :initform nil :initarg :inventory :accessor member-inventory :documentation "ROOM中所有的物品")
   (creature :initform nil :initarg :creature :accessor member-creature :documentation "ROOM中所拥有的生物")
   (in-trigger :initform nil :initarg :in-trigger :accessor member-in-trigger :documentation "进入该ROOM后触发的事件")
   (out-trigger :initform nil :initarg :out-trigger :accessor member-out-trigger :documentation "离开该ROOM后触发的事件")
   ))

(defmethod describe ((room Room))
  "输出room的描述"
  (cl-multiple-value-bind (up-room right-room down-room left-room)  (beyond-rooms (member-symbol room) room-map)
	(format "这里是%s\n%s\n物品列表:%s\n生物列表:%s\n附近的rooms: up:%s right:%s down:%s left:%s" (member-symbol room) (member-description room) (member-inventory room) (member-creature room) up-room right-room down-room left-room)))
```

改后：
```elisp
(cl-defstruct Room
  "Room structure"
  (symbol nil :documentation "ROOM标志")
  (description "" :documentation "ROOM描述")
  (inventory nil :documentation "ROOM中所有的物品")
  (creature nil :documentation "ROOM中所拥有的生物")
  (in-trigger nil :documentation "进入该ROOM后触发的事件")
  (out-trigger nil :documentation "离开该ROOM后触发的事件"))

(cl-defgeneric describe (object)
  "Describe an object.")

(cl-defmethod describe ((room Room))
  "输出room的描述"
  (cl-multiple-value-bind (up-room right-room down-room left-room) (beyond-rooms (Room-symbol room) room-map)
	(format "这里是%s\n%s\n物品列表:%s\n生物列表:%s\n附近的rooms: up:%s right:%s down:%s left:%s"
	        (Room-symbol room) (Room-description room) (Room-inventory room) (Room-creature room)
	        up-room right-room down-room left-room)))
```

**Step 4: 替换 build-room**

改前：
```elisp
(defun build-room (room-entity)
  "根据`text'创建room,并将room存入`rooms-alist'中"
  (cl-multiple-value-bind (symbol description inventory creature) room-entity
	(cons symbol (make-instance Room :symbol symbol :description description :inventory inventory :creature creature))))
```

改后：
```elisp
(defun build-room (room-entity)
  "根据room-entity创建room,并将room存入rooms-alist中"
  (cl-multiple-value-bind (symbol description inventory creature) room-entity
	(cons symbol (make-Room :symbol symbol :description description :inventory inventory :creature creature))))
```

**Step 5: 替换所有 `member-` accessor 为 `Room-`**

- `member-inventory` → `Room-inventory` (line 41, 43, 46, 50, 53, 56, 58)
- `member-creature` → `Room-creature` (line 47, 51, 54, 59)
- `member-description` → `Room-description` (line 68)
- `member-symbol` → `Room-symbol` (line 68, 109, 168, 169)
- `member-in-trigger` → `Room-in-trigger` (lines for in-trigger)
- `member-out-trigger` → `Room-out-trigger` (lines for out-trigger)

各辅助函数中 accessor 名称替换对照：

| 所在函数 | 旧 accessor | 新 accessor |
|----------|-------------|-------------|
| `remove-inventory-from-room` | `member-inventory` | `Room-inventory` |
| `add-inventory-to-room` | `member-inventory` | `Room-inventory` |
| `remove-creature-from-room` | `member-creature` | `Room-creature` |
| `add-creature-to-room` | `member-creature` | `Room-creature` |
| `inventory-exist-in-room-p` | `member-inventory` | `Room-inventory` |
| `creature-exist-in-room-p` | `member-creature` | `Room-creature` |
| `describe` (Room method) | `member-symbol/description/inventory/creature` | `Room-symbol/description/inventory/creature` |
| `map-init` | `member-symbol` | `Room-symbol` |

**Step 6: 验证文件可加载**

Run:
```bash
emacs --batch --directory /home/lujun9972/github/Text-Game-Maker \
  --eval "(progn
    (require 'cl-lib)
    (require 'cl-generic)
    (require 'thingatpt)
    (load-file \"room-maker.el\"))"
```
Expected: no errors, buffer output showing loading complete.

- [ ] **Step 1: 替换文件头部和 require**
- [ ] **Step 2: 添加 read-from-whole-string**
- [ ] **Step 3: 替换 Room defclass → cl-defstruct + describe → cl-defgeneric**
- [ ] **Step 4: 替换 build-room 中的 make-instance**
- [ ] **Step 5: 替换所有 member-xxx → Room-xxx**
- [ ] **Step 6: 验证文件可加载**

---

### Task 2: 迁移 inventory-maker.el

**Files:**
- Modify: `inventory-maker.el`

**Step 1: 替换文件头部**

改前：
```elisp
(require 'eieio)
(require 'thingatpt)
(defvar display-fn #'message
  "显示信息的函数")
```

改后：
```elisp
;;; inventory-maker.el --- Inventory system for Text-Game-Maker  -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'thingatpt)
```

**Step 2: 替换 Inventory 类定义和 describe 方法**

改前：
```elisp
(defclass Inventory nil
  ((symbol :initform (intern (format "inventory-%s" (length inventorys-alist))) :initarg :symbol :accessor member-symbol :documentation "INVENTORY标志")
   (description :initarg :description :accessor member-description :documentation "INVENTORY描述")
   (type :initarg :type :accessor member-type :documentation "INVENTORY的类型")
   (effects :initarg :effects :accessor member-effects :documentation "INVENTORY的使用效果")
   (watch-trigger :initform nil :initarg :watch-trigger :accessor member-watch-trigger :documentation "查看该INVENTORY时触发的事件")
   (take-trigger :initform nil :initarg :take-trigger :accessor member-take-trigger :documentation "获取该INVENTORY时触发的事件")
   (drop-trigger :initform nil :initarg :drop-trigger :accessor member-drop-trigger :documentation "丢弃该INVENTORY时触发的事件")
   (use-trigger :initform nil :initarg :use-trigger :accessor member-use-trigger :documentation "使用该INVENTORY时触发的事件")
   (wear-trigger :initform nil :initarg :wear-trigger :accessor member-wear-trigger :documentation "装备该INVENTORY时触发的事件")
   ))

(defmethod describe ((inventory Inventory))
  "输出inventory的描述"
  (format "这个是%s\n%s\n类型:%s\n使用效果:%s" (member-symbol inventory) (member-description inventory) (member-type inventory) (member-effects inventory)))
```

改后：
```elisp
(cl-defstruct Inventory
  "Inventory structure"
  (symbol nil :documentation "INVENTORY标志")
  (description "" :documentation "INVENTORY描述")
  (type nil :documentation "INVENTORY的类型")
  (effects nil :documentation "INVENTORY的使用效果")
  (watch-trigger nil :documentation "查看该INVENTORY时触发的事件")
  (take-trigger nil :documentation "获取该INVENTORY时触发的事件")
  (drop-trigger nil :documentation "丢弃该INVENTORY时触发的事件")
  (use-trigger nil :documentation "使用该INVENTORY时触发的事件")
  (wear-trigger nil :documentation "装备该INVENTORY时触发的事件"))

(cl-defmethod describe ((inventory Inventory))
  "输出inventory的描述"
  (format "这个是%s\n%s\n类型:%s\n使用效果:%s"
          (Inventory-symbol inventory) (Inventory-description inventory)
          (Inventory-type inventory) (Inventory-effects inventory)))
```

**Step 3: 替换 build-inventory**

改前：
```elisp
(make-instance Inventory :symbol symbol :description description :type type :effects effects)
```

改后：
```elisp
(make-Inventory :symbol symbol :description description :type type :effects effects)
```

**Step 4: 替换所有 member-xxx → Inventory-xxx**

- `member-symbol` → `Inventory-symbol`
- `member-description` → `Inventory-description`
- `member-type` → `Inventory-type`
- `member-effects` → `Inventory-effects`

**Step 5: 验证文件可加载**

Run:
```bash
emacs --batch --directory /home/lujun9972/github/Text-Game-Maker \
  --eval "(progn
    (require 'cl-lib)
    (require 'thingatpt)
    (load-file \"inventory-maker.el\"))"
```
Expected: no errors.

- [ ] **Step 1: 替换文件头部和 require**
- [ ] **Step 2: 替换 Inventory defclass → cl-defstruct + describe → cl-defmethod**
- [ ] **Step 3: 替换 build-inventory 中的 make-instance**
- [ ] **Step 4: 替换所有 member-xxx → Inventory-xxx**
- [ ] **Step 5: 验证文件可加载**

---

### Task 3: 迁移 creature-maker.el

**Files:**
- Modify: `creature-maker.el`

**Step 1: 替换文件头部**

改前：
```elisp
(require 'eieio)
(require 'thingatpt)
(require 'cl)
(defvar display-fn #'message
  "显示信息的函数")
```

改后：
```elisp
;;; creature-maker.el --- Creature system for Text-Game-Maker  -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'thingatpt)
```

**Step 2: 替换 Creature 类定义和 describe 方法**

改前：
```elisp
(defclass Creature nil
  ((symbol :initform (intern (format "creature-%s" (length creatures-alist))) :initarg :symbol :accessor member-symbol :documentation "CREATURE标志")
   (description :initarg :description :accessor member-description :documentation "CREATURE描述")
   (occupation :initform 'human :initarg :occupation :accessor member-occupation :documentation "CREATURE的职业")
   (attr :initform nil :initarg :attr :accessor member-attr :documentation "CREATURE的属性")
   (inventory :initform nil :initarg :inventory :accessor member-inventory :documentation "CREATURE所只有的物品")
   (equipment :initform nil :initarg :equipment :accessor member-equipment :documentation "CREATURE装备的装备")
   (watch-trigger :initform nil :initarg :watch-trigger :accessor member-watch-trigger :documentation "查看该CREATURE后触发的事件")
   ))

(defmethod describe ((creature Creature))
  "输出creature的描述"
  (format "这个是%s\n%s\n属性值:%s\n拥有物品:%s\n装备了:%s" (member-symbol creature) (member-description creature) (member-attr creature) (member-inventory creature) (member-equipment creature)))
```

改后：
```elisp
(cl-defstruct Creature
  "Creature structure"
  (symbol nil :documentation "CREATURE标志")
  (description "" :documentation "CREATURE描述")
  (occupation 'human :documentation "CREATURE的职业")
  (attr nil :documentation "CREATURE的属性")
  (inventory nil :documentation "CREATURE所拥有的物品")
  (equipment nil :documentation "CREATURE装备的装备")
  (watch-trigger nil :documentation "查看该CREATURE后触发的事件"))

(cl-defmethod describe ((creature Creature))
  "输出creature的描述"
  (format "这个是%s\n%s\n属性值:%s\n拥有物品:%s\n装备了:%s"
          (Creature-symbol creature) (Creature-description creature)
          (Creature-attr creature) (Creature-inventory creature)
          (Creature-equipment creature)))
```

**Step 3: 替换 build-creature**

改前：
```elisp
(make-instance Creature :symbol symbol :description description :inventory inventory :equipment equipment :attr attr)
```

改后：
```elisp
(make-Creature :symbol symbol :description description :inventory inventory :equipment equipment :attr attr)
```

**Step 4: 替换所有 member-xxx → Creature-xxx + incf → cl-incf**

| 所在函数 | 旧代码 | 新代码 |
|----------|--------|--------|
| `remove-inventory-from-creature` | `member-inventory` | `Creature-inventory` |
| `add-inventory-to-creature` | `member-inventory` | `Creature-inventory` |
| `inventory-exist-in-creature-p` | `member-inventory` | `Creature-inventory` |
| `remove-equipment-from-creature` | `member-equipment` | `Creature-equipment` |
| `add-equipment-to-creature` | `member-equipment` | `Creature-equipment` |
| `equipment-exist-in-creature-p` | `member-equipment` | `Creature-equipment` |
| `take-effect-to-creature` | `member-attr` + `incf` | `Creature-attr` + `cl-incf` |
| `describe` | `member-symbol/description/attr/inventory/equipment` | `Creature-symbol/description/attr/inventory/equipment` |
| `creatures-init` | `member-symbol` | `Creature-symbol` |

**Step 5: 验证文件可加载**

Run:
```bash
emacs --batch --directory /home/lujun9972/github/Text-Game-Maker \
  --eval "(progn
    (require 'cl-lib)
    (require 'thingatpt)
    (load-file \"creature-maker.el\"))"
```
Expected: no errors.

- [ ] **Step 1: 替换文件头部和 require (cl → cl-lib)**
- [ ] **Step 2: 替换 Creature defclass → cl-defstruct + describe → cl-defmethod**
- [ ] **Step 3: 替换 build-creature 中的 make-instance**
- [ ] **Step 4: 替换所有 member-xxx → Creature-xxx, incf → cl-incf**
- [ ] **Step 5: 验证文件可加载**

---

### Task 4: 更新 test-helper.el 和全部测试文件

**Files:**
- Modify: `test/test-helper.el`
- Modify: `test/test-room-maker.el`
- Modify: `test/test-inventory-maker.el`
- Modify: `test/test-creature-maker.el`

**Step 1: 更新 test-helper.el**

改前第33-45行：
```elisp
(defun test-make-room (&rest plist)
  "Create a Room instance for testing. PLIST keys: :symbol :description :inventory :creature."
  (apply #'make-instance 'Room plist))

(defun test-make-inventory (&rest plist)
  "Create an Inventory instance for testing. PLIST keys: :symbol :description :type :effects."
  (apply #'make-instance 'Inventory plist))

(defun test-make-creature (&rest plist)
  "Create a Creature instance for testing. PLIST keys: :symbol :description :attr :inventory :equipment."
  (apply #'make-instance 'Creature plist))
```

改后：
```elisp
(defun test-make-room (&rest plist)
  "Create a Room instance for testing. PLIST keys: :symbol :description :inventory :creature."
  (apply #'make-Room plist))

(defun test-make-inventory (&rest plist)
  "Create an Inventory instance for testing. PLIST keys: :symbol :description :type :effects."
  (apply #'make-Inventory plist))

(defun test-make-creature (&rest plist)
  "Create a Creature instance for testing. PLIST keys: :symbol :description :attr :inventory :equipment."
  (apply #'make-Creature plist))
```

**Step 2: 更新 test-room-maker.el — 替换所有 accessor**

全局替换：
- `member-symbol` → `Room-symbol` (lines 35, 36, 45, 46, 59, 60, 169)
- `member-description` → `Room-description` (lines 37, 47, 68, 180)
- `member-inventory` → `Room-inventory` (lines 38, 48, 68, 74, 75)
- `member-creature` → `Room-creature` (lines 39, 49, 89, 95, 96)

**Step 3: 更新 test-inventory-maker.el — 替换所有 accessor**

全局替换：
- `member-symbol` → `Inventory-symbol` (lines 36, 37, 50, 51)
- `member-description` → `Inventory-description` (lines 38)
- `member-type` → `Inventory-type` (lines 39)
- `member-effects` → `Inventory-effects` (lines 40)

**Step 4: 更新 test-creature-maker.el — 替换所有 accessor**

全局替换：
- `member-symbol` → `Creature-symbol` (lines 29, 30, 44, 45, 56)
- `member-description` → `Creature-description` (lines 31)
- `member-attr` → `Creature-attr` (lines 32, 107, 108, 113, 114, 120, 128, 129, 135)
- `member-inventory` → `Creature-inventory` (lines 33, 64, 70, 71, 77)
- `member-equipment` → `Creature-equipment` (lines 34, 85, 90, 91, 97, 98, 99)

**Step 5: 运行 room + inventory + creature 测试**

Run:
```bash
emacs --batch --no-site-file --no-init-file \
  --directory /home/lujun9972/github/Text-Game-Maker \
  --directory /home/lujun9972/github/Text-Game-Maker/test \
  --eval "(progn
    (require 'ert)
    (require 'cl-lib)
    (require 'thingatpt)
    (require 'room-maker)
    (require 'inventory-maker)
    (require 'creature-maker)
    (require 'test-helper)
    (require 'test-room-maker)
    (require 'test-inventory-maker)
    (require 'test-creature-maker)
    (ert-run-tests-batch-and-exit '(or \"test-\" t)))"
```
Expected: All tests passed (each ert-deftest returns passed).

- [ ] **Step 1: 更新 test-helper.el 中 make-instance → make-Room/make-Inventory/make-Creature**
- [ ] **Step 2: 更新 test-room-maker.el 中 accessor**
- [ ] **Step 3: 更新 test-inventory-maker.el 中 accessor**
- [ ] **Step 4: 更新 test-creature-maker.el 中 accessor**
- [ ] **Step 5: 运行三个模块测试**

---

### Task 5: 更新 action.el 和 test-action.el

**Files:**
- Modify: `action.el`
- Modify: `test/test-action.el`

**Step 1: action.el — 添加 lexical-binding 头部**

第1行前添加：
```elisp
;;; action.el --- Game action commands for Text-Game-Maker  -*- lexical-binding: t; -*-
```

**Step 2: action.el — 替换所有 accessor**

| 行号 | 旧代码 | 新代码 |
|------|--------|--------|
| 28,30 | `member-out-trigger` | `Room-out-trigger` |
| 32 | `member-in-trigger` | `Room-in-trigger` |
| 45 | `get-room-by-symbol` | 不变（不是 accessor） |
| 46 | `get-inventory-by-symbol` | 不变 |
| 47 | `get-creature-by-symbol` | 不变 |
| 49-52 | `slot-exists-p/slot-boundp/slot-value` on watch-trigger | `Inventory-watch-trigger` / `Creature-watch-trigger` |
| 62-65 | `slot-exists-p/slot-boundp/slot-value` on take-trigger | `Inventory-take-trigger` |
| 76-79 | `slot-exists-p/slot-boundp/slot-value` on drop-trigger | `Inventory-drop-trigger` |
| 92-95 | `slot-exists-p/slot-boundp/slot-value` on use-trigger | `Inventory-use-trigger` |
| 97 | `member-effects` | `Inventory-effects` |
| 109-112 | `slot-exists-p/slot-boundp/slot-value` on wear-trigger | `Inventory-wear-trigger` |
| 114 | `member-effects` | `Inventory-effects` |

关键变化：用 accessor 函数直接读取 trigger slot，替代 EIEIO 的 `slot-exists-p` + `slot-boundp` + `slot-value` 三步检查。

因为 cl-defstruct 始终绑定所有 slot（没有 unbound 状态），`slot-exists-p` 和 `slot-boundp` 不再需要。原来检查 trigger 的代码：

```elisp
(when (and (slot-exists-p object 'watch-trigger)
           (slot-boundp object 'watch-trigger)
           (slot-value object 'watch-trigger))
  (funcall (slot-value object 'watch-trigger)))
```

注意 `tg-watch` 中 watch-trigger 只存在于 Inventory 和 Creature 上（Room 没有此 slot），需用 cl-defstruct 自动生成的 `-p` type predicates 判断分发：

```elisp
;; 改后：
(when-let ((trig (cond ((Inventory-p object) (Inventory-watch-trigger object))
                       ((Creature-p object) (Creature-watch-trigger object)))))
  (funcall trig))
```

**Step 3: test-action.el — 替换所有 make-instance**

全局替换（共36处）：
- `(make-instance 'Room` → `(make-Room`
- `(make-instance 'Inventory` → `(make-Inventory`
- `(make-instance 'Creature` → `(make-Creature`

**Step 4: test-action.el — 替换所有 member-xxx accessor**

- `member-symbol` → `Room-symbol` (lines 62, 72)
- `member-attr` → `Creature-attr` (line 311)

**Step 5: 运行 action 测试**

Run:
```bash
emacs --batch --no-site-file --no-init-file \
  --directory /home/lujun9972/github/Text-Game-Maker \
  --directory /home/lujun9972/github/Text-Game-Maker/test \
  --eval "(progn
    (require 'ert)
    (require 'cl-lib)
    (require 'thingatpt)
    (require 'text-game-maker)
    (require 'test-text-game-maker)
    (require 'test-room-maker)
    (require 'test-inventory-maker)
    (require 'test-creature-maker)
    (require 'test-action)
    (ert-run-tests-batch-and-exit '(or \"test-\" t)))"
```
Expected: All tests passed.

- [ ] **Step 1: action.el — 添加 lexical-binding 头部**
- [ ] **Step 2: action.el — 替换 accessor （移除 slot-exists-p / slot-boundp 检查）**
- [ ] **Step 3: test-action.el — 替换 make-instance**
- [ ] **Step 4: test-action.el — 替换 member-xxx**
- [ ] **Step 5: 运行 action 测试**

---

### Task 6: 更新 tg-mode.el, text-game-maker.el, run-tests.sh

**Files:**
- Modify: `tg-mode.el`
- Modify: `text-game-maker.el`
- Modify: `run-tests.sh`

**Step 1: tg-mode.el — 添加 lexical-binding 头部**

第1行前添加：
```elisp
;;; tg-mode.el --- Major mode for Text-Game-Maker  -*- lexical-binding: t; -*-
```

**Step 2: text-game-maker.el — 添加 lexical-binding 头部**

第1行前添加：
```elisp
;;; text-game-maker.el --- Main entry for Text-Game-Maker  -*- lexical-binding: t; -*-
```

另外从 `run-tests.sh` 删除 `(require 'eieio-compat)` 和 `(require 'eieio)`。

**Step 3: run-tests.sh — 移除 eieio 依赖**

改前第14-15行：
```elisp
    (require 'eieio)
    (require 'eieio-compat)
```

改后删除这两行。

**Step 4: 运行全量测试**

Run:
```bash
bash /home/lujun9972/github/Text-Game-Maker/run-tests.sh
```
Expected: All ERT tests passed. No errors.

- [ ] **Step 1: tg-mode.el — 添加 lexical-binding**
- [ ] **Step 2: text-game-maker.el — 添加 lexical-binding**
- [ ] **Step 3: run-tests.sh — 移除 eieio / eieio-compat**
- [ ] **Step 4: 运行全量测试**

---

### Task 7: 提交所有更改

- [ ] **Step 1: 提交代码**

```bash
git add -A
git commit -m "$(cat <<'EOF'
refactor: 迁移 EIEIO 到 cl-defstruct，清理废弃依赖

- 将 Room/Inventory/Creature 从 defclass 迁移到 cl-defstruct
- 用 cl-defgeneric/cl-defmethod 替代 defmethod describe
- 用 make-Room/make-Inventory/make-Creature 替代 make-instance
- accessor 从 member-xxx 改为 Room/Inventory/Creature-xxx
- 移除 (require 'cl) (require 'eieio) (require 'eieio-compat)
- 添加 (require 'cl-lib) (require 'cl-generic)
- incf → cl-incf
- 所有源文件添加 lexical-binding: t
- 所有受影响的测试文件同步更新

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```
