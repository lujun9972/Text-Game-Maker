# Modernize Obsolete Technologies in Text-Game-Maker

## 概述

对本项目中的过时技术进行系统化更新，核心是把 EIEIO 对象系统迁移为 cl-defstruct，同时清理其他废弃依赖和缺失的现代实践。

## 变更清单

### 1. EIEIO → cl-defstruct

三个核心类全部重写为 cl-defstruct 结构体：

- `Room`：6 个 slot（symbol, description, inventory, creature, in-trigger, out-trigger）
- `Inventory`：9 个 slot（symbol, description, type, effects, watch-trigger, take-trigger, drop-trigger, use-trigger, wear-trigger）
- `Creature`：7 个 slot（symbol, description, occupation, attr, inventory, equipment, watch-trigger）

**accessor 命名迁移**（所有调用点同步修改）：

| 旧 accessor | Room | Inventory | Creature |
|-------------|------|-----------|----------|
| `member-symbol` | `Room-symbol` | `Inventory-symbol` | `Creature-symbol` |
| `member-description` | `Room-description` | `Inventory-description` | `Creature-description` |
| `member-inventory` | `Room-inventory` | — | `Creature-inventory` |
| `member-creature` | `Room-creature` | — | — |
| `member-type` | — | `Inventory-type` | — |
| `member-effects` | — | `Inventory-effects` | — |
| `member-attr` | — | — | `Creature-attr` |
| `member-occupation` | — | — | `Creature-occupation` |
| `member-equipment` | — | — | `Creature-equipment` |
| `member-in-trigger` | `Room-in-trigger` | — | — |
| `member-out-trigger` | `Room-out-trigger` | — | — |
| `member-watch-trigger` | — | `Inventory-watch-trigger` | `Creature-watch-trigger` |
| `member-take-trigger` | — | `Inventory-take-trigger` | — |
| `member-drop-trigger` | — | `Inventory-drop-trigger` | — |
| `member-use-trigger` | — | `Inventory-use-trigger` | — |
| `member-wear-trigger` | — | `Inventory-wear-trigger` | — |

### 2. 多态 describe 迁移

`defmethod describe` 改为 `cl-defgeneric` + `cl-defmethod`，在 `room-maker.el` 中定义 generic，各模块分别实现 method。

### 3. 构造函数迁移

| 旧 | 新 |
|----|----|
| `(make-instance 'Room ...)` | `(make-Room ...)` |
| `(make-instance 'Inventory ...)` | `(make-Inventory ...)` |
| `(make-instance 'Creature ...)` | `(make-Creature ...)` |

### 4. 废弃依赖清理

| 文件 | 旧代码 | 新代码 |
|------|--------|--------|
| `creature-maker.el` | `(require 'cl)` | `(require 'cl-lib)` |
| `creature-maker.el` | `(incf ...)` | `(cl-incf ...)` |
| `run-tests.sh` | `(require 'eieio-compat)` | 删除 |
| `room-maker.el` | 缺少 lexcial-binding | `-*- lexical-binding: t; -*-` |
| `inventory-maker.el` | 同上 | 同上 |
| `creature-maker.el` | 同上 | 同上 |
| `action.el` | 同上 | 同上 |
| `text-game-maker.el` | 同上 | 同上 |
| `tg-mode.el` | 同上 | 同上 |

### 5. read-from-whole-string

在 `room-maker.el` 中定义该函数，消除对外部配置的依赖：

```elisp
(defun read-from-whole-string (string)
  "Read Emacs Lisp data from STRING as a single form."
  (read (format "(%s)" string)))
```

### 6. 删除重复的 display-fn 定义

`room-maker.el`、`inventory-maker.el`、`creature-maker.el` 中重复的 `(defvar display-fn ...)` 删除，只保留 `text-game-maker.el` 和 `action.el` 中的定义。

## 影响范围

| 文件 | 改动类型 |
|------|----------|
| `room-maker.el` | defclass → cl-defstruct, define describe generic, add read-from-whole-string, add lexical-binding, remove duplicate display-fn |
| `inventory-maker.el` | defclass → cl-defstruct, describe method → cl-defmethod, add lexical-binding, remove duplicate display-fn |
| `creature-maker.el` | defclass → cl-defstruct, describe method → cl-defmethod, require cl → cl-lib, incf → cl-incf, add lexical-binding, remove duplicate display-fn |
| `text-game-maker.el` | add lexical-binding |
| `action.el` | update accessor names, add lexical-binding |
| `tg-mode.el` | add lexical-binding |
| `run-tests.sh` | remove eieio-compat |
| `test/test-helper.el` | make-instance → make-Room/make-Inventory/make-Creature |
| `test/*.el` (6 files) | update all accessor references, update make-instance calls |

## 测试策略

每次更改一个模块后运行 `run-tests.sh` 验证不引入回归。修改顺序建议：

1. `room-maker.el`（最底层依赖）→ 测试
2. `inventory-maker.el` → 测试
3. `creature-maker.el` → 测试
4. `action.el` + `tg-mode.el` + `text-game-maker.el` → 测试
5. 测试辅助文件和测试用例更新 → 全量测试
