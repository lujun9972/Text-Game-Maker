# v1→v2 文档与 Sample 迁移实现计划

> **面向 AI 代理的工作者：** 必需子技能：`superpowers:serial-executing-plans`（任务规模小，共享 sample/ 目录，强耦合）。

**目标：** 将 README.md、docs/manual.org、sample/ 游戏从 v1 格式迁移到 v2 Org-based 架构，并修复 explore/talk 任务追踪 bug。

**架构：** v1 的 8 个 Elisp 配置文件合并为单个 game.org；升级表通过 handlers.el 配置；入口从手动 init 改为 `tg-start`。tg-action.el 补全 2 行 quest tracking。

**技术栈：** Emacs Lisp, Org-mode (org-element), ERT

---

## 文件结构

| 文件 | 职责 | 操作 |
|---|---|---|
| `tg-action.el` | 补全 explore/talk 任务追踪（2 行） | 修改 |
| `sample/game.org` | 全部游戏配置（Rooms/Objects/Creatures/Dialogs/Shops/Quests） | 创建 |
| `sample/handlers.el` | 升级表自定义 | 创建 |
| `sample/sample-game.el` | 启动入口（调用 tg-start） | 重写 |
| `sample/play.sh` | 终端启动脚本 | 重写 |
| `sample/room-config.el` 等 8 个 v1 文件 | 旧配置 | 删除 |
| `README.md` | 项目概览 | 重写 |
| `docs/manual.org` | 完整使用手册 | 重写 |
| `test/tg-integration-test.el` | 补充 explore/talk quest 追踪测试 | 修改 |

---

### 任务 1：修复 explore/talk 任务追踪

**依赖：** 无
**文件集：** `tg-action.el`, `test/tg-integration-test.el`
**导出/变更接口：** `tg-action.el::tg-action--handler-go`, `tg-action.el::tg-action--handler-talk`
**消费接口：** `tg-quest.el::tg-track-quest`
**复杂度：** quick

**文件：**
- 修改：`tg-action.el:80-84`（go handler）
- 修改：`tg-action.el:463-464`（talk handler）
- 修改：`test/tg-integration-test.el`

- [ ] **步骤 1：编写 explore quest 追踪测试**

在 `test/tg-integration-test.el` 末尾添加测试。该文件已定义 `tg-integration-setup`/`tg-integration-teardown`/`tg-simulate-command`。

```elisp
(ert-deftest test-tg-explore-quest-tracking ()
  "测试移动到目标房间追踪 explore 类型任务。"
  (unwind-protect
      (progn
        (tg-integration-setup)
        ;; 手动注册一个 explore 类型任务
        (let ((quest (make-tg-quest :symbol 'test-explore
                                    :type 'explore :target 'forest-path
                                    :count 1 :progress 0 :status 'active
                                    :rewards '((exp 50)))))
          (tg-register-quest 'test-explore quest))
        ;; 移动到目标房间
        (tg-simulate-command "north")
        (should (eq (tg-game-get tg-game :location) 'forest-path))
        ;; 任务应完成
        (let ((q (tg-get-quest 'test-explore)))
          (should (eq (tg-quest-status q) 'completed))))
    (tg-integration-teardown)))
```

```elisp
(ert-deftest test-tg-talk-quest-tracking ()
  "测试与 NPC 对话追踪 talk 类型任务。"
  (unwind-protect
      (progn
        (tg-integration-setup)
        ;; 手动注册一个 talk 类型任务（target 为 old-man，在 village）
        (let ((quest (make-tg-quest :symbol 'test-talk
                                    :type 'talk :target 'old-man
                                    :count 1 :progress 0 :status 'active
                                    :rewards '((exp 10)))))
          (tg-register-quest 'test-talk quest))
        ;; 与 NPC 对话
        (tg-simulate-command "talk old-man")
        ;; 任务应完成
        (let ((q (tg-get-quest 'test-talk)))
          (should (eq (tg-quest-status q) 'completed))))
    (tg-integration-teardown)))
```

- [ ] **步骤 2：运行测试验证失败**

运行：`emacs -batch -L . -l test/tg-integration-test.el -f ert-run-tests-batch-and-exit 2>&1 | grep -E "(FAILED|passed|Ran).*(test-tg-explore|test-tg-talk)"`
预期：两个新测试 FAILED

- [ ] **步骤 3：修复 tg-action.el**

在 `tg-action--handler-go` 中，`when target-room` 块内，`tg-room-visit` 行之后插入：

```elisp
(tg-track-quest 'explore target-sym)
```

在 `tg-action--handler-talk` 中，`(tg-dialog-start do-key)` 行之后插入：

```elisp
(tg-track-quest 'talk do-key)
```

- [ ] **步骤 4：运行测试验证通过**

运行：`emacs -batch -L . -l test/tg-integration-test.el -f ert-run-tests-batch-and-exit 2>&1 | tail -5`
预期：全部通过（含新测试）

- [ ] **步骤 5：Commit**

```bash
git add tg-action.el test/tg-integration-test.el
git commit -m "fix: add explore/talk quest tracking in go and talk handlers"
```

---

### 任务 2：创建 sample v2 游戏文件

**依赖：** 任务 1
**文件集：** `sample/game.org`, `sample/handlers.el`, `sample/sample-game.el`, `sample/play.sh`, `sample/room-config.el`, `sample/map-config.el`, `sample/inventory-config.el`, `sample/creature-config.el`, `sample/level-config.el`, `sample/quest-config.el`, `sample/dialog-config.el`, `sample/shop-config.el`
**导出/变更接口：** 无
**消费接口：** `tg-config.el::tg-config-load`, `tg.el::tg-start`
**复杂度：** standard

**文件：**
- 创建：`sample/game.org`（完整内容见规格第 2 节）
- 创建：`sample/handlers.el`
- 重写：`sample/sample-game.el`
- 重写：`sample/play.sh`
- 删除：8 个 v1 配置文件

- [ ] **步骤 1：创建 sample/game.org**

按规格第 2 节完整内容创建文件。内容为规格中 `## 2. sample/game.org 完整内容` 下 ````org` 到 ````` 之间的全部文本。

- [ ] **步骤 2：创建 sample/handlers.el**

```elisp
;;; handlers.el --- 地牢冒险自定义配置  -*- lexical-binding: t; -*-

;; 升级表（索引 0 = 等级 1→2 所需累计经验）
(setq tg-level-exp-table '(0 50 120 220 350 500 700 950 1300 1700))
;; 每次升级获得自由属性点
(setq tg-level-bonus-points-per-level 3)
;; 每次升级自动提升的属性
(setq tg-level-auto-upgrade-attrs '((hp 10)))

(provide 'handlers)
;;; handlers.el ends here
```

- [ ] **步骤 3：重写 sample/sample-game.el**

```elisp
;;; sample-game.el --- 地牢冒险示例游戏  -*- lexical-binding: t; -*-

;; 使用方法：
;;   M-x eval-buffer 然后 M-x play-sample-game
;;   或 bash sample/play.sh

(require 'tg)

(defun play-sample-game ()
  "启动地牢冒险示例游戏。"
  (interactive)
  (let ((game-file (expand-file-name "game.org"
                                      (file-name-directory (or load-file-name buffer-file-name)))))
    (tg-start game-file)))

(provide 'sample-game)
;;; sample-game.el ends here
```

- [ ] **步骤 4：重写 sample/play.sh**

```bash
#!/bin/bash
# 地牢冒险 - Text-Game-Maker 2.0 示例游戏启动脚本
# 用法: bash sample/play.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

emacs --no-init-file -nw --directory "$PROJECT_DIR" \
      --load "$PROJECT_DIR/tg.el" \
      --eval '(tg-start "'"$SCRIPT_DIR"'/game.org")'
```

- [ ] **步骤 5：删除 v1 配置文件**

```bash
rm sample/room-config.el sample/map-config.el sample/inventory-config.el sample/creature-config.el sample/level-config.el sample/quest-config.el sample/dialog-config.el sample/shop-config.el
```

- [ ] **步骤 6：验证 sample 游戏可加载**

```bash
emacs -batch -L . --eval '(progn (require (quote tg)) (tg-init "sample/game.org") (princ (format "location: %s\n" (tg-game-get tg-game :location))) (princ (format "player: %s\n" (tg-creature-name (tg-player tg-game)))))'
```
预期输出包含 `location: entrance` 和 `player: 勇敢的冒险者`

- [ ] **步骤 7：运行全量测试确认无回归**

```bash
emacs -batch -L . -l test/tg-registry-test.el -l test/tg-game-test.el -l test/tg-object-test.el -l test/tg-creature-test.el -l test/tg-room-test.el -l test/tg-action-test.el -l test/tg-parser-test.el -l test/tg-commands-test.el -l test/tg-dialog-test.el -l test/tg-npc-test.el -l test/tg-quest-test.el -l test/tg-shop-test.el -l test/tg-level-test.el -l test/tg-builtin-test.el -l test/tg-config-test.el -l test/tg-config-gen-test.el -l test/tg-save-test.el -l test/tg-mode-test.el -l test/tg-integration-test.el -f ert-run-tests-batch-and-exit 2>&1 | tail -5
```

- [ ] **步骤 8：Commit**

```bash
git add sample/game.org sample/handlers.el sample/sample-game.el sample/play.sh && git rm sample/room-config.el sample/map-config.el sample/inventory-config.el sample/creature-config.el sample/level-config.el sample/quest-config.el sample/dialog-config.el sample/shop-config.el && git commit -m "feat: migrate sample game to v2 Org-based config"
```

---

### 任务 3：重写 README.md

**依赖：** 任务 2
**文件集：** `README.md`
**导出/变更接口：** 无
**消费接口：** 无
**复杂度：** standard

**文件：**
- 重写：`README.md`

- [ ] **步骤 1：重写 README.md**

按规格第 6 节大纲编写。约 80-100 行。包含以下章节：

1. **Text-Game-Maker** — 基于 Emacs Lisp 的文字冒险游戏制作框架。通过单个 Org 文件定义全部游戏配置。
2. **特性** — 8 条要点：Org 配置、cl-defstruct 架构、27 内置命令、装备动态属性加成、NPC 行为引擎、对话状态机、商店/任务/升级系统、存档系统、可扩展动词系统
3. **依赖** — Emacs 27+（org-element, cl-lib）
4. **安装** — `(add-to-list 'load-path "~/path/to/Text-Game-Maker")`
5. **快速开始** — `M-x tg-start RET path/to/game.org RET` 或 `bash sample/play.sh`
6. **文件结构** — 18 个模块表格（tg-registry, tg-game, tg-object, tg-creature, tg-room, tg-action, tg-parser, tg-commands, tg-dialog, tg-npc, tg-quest, tg-shop, tg-level, tg-save, tg-config, tg-config-gen, tg-mode, tg）
7. **测试** — `emacs -batch -L . -l test/... -f ert-run-tests-batch-and-exit`（256 测试）
8. **TODO** — 4 条功能缺口表格（对话条件解析、Level Org 段、任务描述字段、Object 容器初始化）

- [ ] **步骤 2：Commit**

```bash
git add README.md && git commit -m "docs: rewrite README for v2 architecture"
```

---

### 任务 4：重写 docs/manual.org

**依赖：** 任务 3
**文件集：** `docs/manual.org`
**导出/变更接口：** 无
**消费接口：** 无
**复杂度：** deep

**文件：**
- 重写：`docs/manual.org`

- [ ] **步骤 1：重写 docs/manual.org**

按规格第 7 节大纲编写。8 个章节。内容要求：

**第 1 章 简介：** v2 架构概览——Registry 全局注册表 + Org 配置文件 + 9 步 handler chain dispatch（error→room-before→io→do→action→after→NPC→buffs-tick→turn-increment）。

**第 2 章 安装与快速开始：** 依赖、load-path 设置、`(require 'tg)`、`M-x tg-start`、运行 sample 游戏的完整命令。

**第 3 章 核心概念：** 5 个核心 struct 的字段说明表格。重点说明：
- tg-creature 的 `attr` 是 alist 格式 `((hp 100) (attack 5))`，通过 `tg-creature-attr-get` 读取，`tg-creature-take-effect` 增量修改
- tg-creature 的 `equipment` 列表中的对象 effects 在 `tg-creature-effective-attr` 中动态累加
- tg-game 是哈希表而非 struct，通过 `tg-game-get`/`tg-game-put` 访问

**第 4 章 Org 配置格式：** 六个 section（Rooms/Objects/Creatures/Dialogs/Shops/Quests）逐字段说明。每个字段给出：字段名、类型、是否必填、默认值、示例值。引用 `sample/game.org` 作为完整示例。说明 `#+START`、`#+PLAYER`、`#+TITLE`、`#+AUTHOR` 头部关键字。说明同目录 `handlers.el` 自动加载机制。

**第 5 章 游戏命令：** 27 个内置命令，按功能分组表格（移动探索 3、物品操作 4、容器 3、装备消耗 3、背包 1、战斗 1、对话 1、商店 3、角色 2、任务 3、系统 3）。列：命令名、同义词、说明。说明方向移动支持 n/s/e/w/ne/nw/se/sw/u/d/in/out。说明 `accept` 命令激活任务。

**第 6 章 扩展开发：**
- `tg-register-action` 注册自定义动词，给出完整示例代码（注册 `search` 命令）
- handlers.el 中可定义的回调：房间 before-handler/after-handler、对象 handler、生物 death-trigger/handler
- `tg-message-hook` 用法（`add-hook` 拦截输出）
- `tg-register-builtins` 注册流程说明

**第 7 章 模块参考：** 18 个模块的 API 表格。每模块列出：文件名、核心 struct/类型、公共函数签名 + 一行说明。按依赖顺序排列（tg-registry → tg-object → tg-creature → tg-game → tg-room → tg-action → tg-parser → tg-commands → tg-dialog → tg-npc → tg-quest → tg-shop → tg-level → tg-save → tg-config → tg-config-gen → tg-mode → tg）。

**第 8 章 已知限制：** 同 README TODO 的 4 条表格。

- [ ] **步骤 2：Commit**

```bash
git add docs/manual.org && git commit -m "docs: rewrite manual for v2 architecture"
```

---

## 并行执行图

> 仅 `parallel-executing-plans` 使用；`serial-executing-plans` 忽略本节。

**Critical Path:** 任务 1 → 任务 2 → 任务 3 → 任务 4

- Wave 1（无依赖）：任务 1
- Wave 2（依赖 Wave 1）：任务 2
- Wave 3（依赖 Wave 2）：任务 3
- Wave 4（依赖 Wave 3）：任务 4

---

## 执行交接

计划已完成并保存到 `docs/superpowers/plans/2026-05-12-docs-sample-migration.md`。两种执行方式：

**1. 子代理驱动（适合较大计划）** - 平台支持子代理时，多 wave 执行，wave 内并行多任务。但本计划 4 个任务强耦合（共享 sample/ 目录），Wave 2-4 各只有 1 个任务，并行收益为零。

**2. 串行执行（适合小计划或无子代理平台）** - 使用 serial-executing-plans 按任务编号执行，串行推进。

**推荐：串行执行**（任务间文件集重叠、Wave 2-4 各只有 1 个任务，并行无收益）。
