# Text-Game-Maker

基于 Emacs Lisp 的文字冒险游戏制作框架。通过单个 Org 文件定义全部游戏配置（房间、物品、生物、对话、商店、任务），`M-x tg-start` 即可开始游戏。

## 特性

- **Org 配置** — 单个 `game.org` 定义完整游戏世界，告别散落的 Elisp 配置文件
- **cl-defstruct 架构** — 18 个模块，Registry 全局注册表 + 纯数据 struct
- **27 个内置命令** — 移动、拾取、装备、战斗、对话、商店、任务、存档等
- **装备动态属性加成** — `tg-creature-effective-attr` 在战斗时动态计算 base + equipment + buff
- **NPC 行为引擎** — 条件驱动的主动行为（攻击、移动、施放 debuff/buff、对话）
- **对话状态机** — 带奖励的分支对话，支持经验值和物品奖励
- **商店/任务/升级系统** — 完整的 RPG 经济循环
- **存档系统** — 游戏状态序列化/反序列化
- **可扩展动词系统** — `tg-register-action` 注册自定义命令

## 依赖

- Emacs 27+（org-element, cl-lib）

## 安装

```elisp
(add-to-list 'load-path "~/path/to/Text-Game-Maker")
(require 'tg)
```

## 快速开始

```elisp
M-x tg-start RET path/to/game.org RET
```

或运行示例游戏：

```sh
bash sample/play.sh
```

完整使用手册见 [docs/manual.org](docs/manual.org)。

## 文件结构

| 模块 | 说明 |
|------|------|
| `tg.el` | 入口，提供 `tg-start` |
| `tg-registry.el` | 全局注册表（零依赖） |
| `tg-object.el` | 物品系统 |
| `tg-creature.el` | 生物系统（属性、装备、背包） |
| `tg-game.el` | 游戏状态（哈希表） |
| `tg-room.el` | 房间系统（出口、容器、支撑物） |
| `tg-action.el` | 动作系统（动词注册 + handler chain） |
| `tg-parser.el` | 自然语言解析器 |
| `tg-commands.el` | 输入调度 |
| `tg-dialog.el` | 对话状态机 |
| `tg-npc.el` | NPC 行为引擎 |
| `tg-quest.el` | 任务系统（kill/collect/explore/talk） |
| `tg-shop.el` | 商店系统 |
| `tg-level.el` | 经验等级系统 |
| `tg-save.el` | 存档系统 |
| `tg-config.el` | Org 配置解析器 |
| `tg-config-gen.el` | 配置文件生成器 |
| `tg-mode.el` | 交互式游戏 major mode（eldoc 支持） |

## 测试

```sh
emacs -batch -L . \
  -l test/tg-registry-test.el \
  -l test/tg-game-test.el \
  -l test/tg-object-test.el \
  -l test/tg-creature-test.el \
  -l test/tg-room-test.el \
  -l test/tg-action-test.el \
  -l test/tg-parser-test.el \
  -l test/tg-commands-test.el \
  -l test/tg-dialog-test.el \
  -l test/tg-npc-test.el \
  -l test/tg-quest-test.el \
  -l test/tg-shop-test.el \
  -l test/tg-level-test.el \
  -l test/tg-builtin-test.el \
  -l test/tg-config-test.el \
  -l test/tg-config-gen-test.el \
  -l test/tg-save-test.el \
  -l test/tg-mode-test.el \
  -l test/tg-integration-test.el \
  -f ert-run-tests-batch-and-exit
```

258 个 ERT 测试。

## TODO

| 缺口 | 说明 |
|------|------|
| 对话选项条件 | `tg-config--parse-dialog-option` 未解析条件字段，所有选项始终可见 |
| Level Org 配置段 | `tg-config-load` 不处理 Level section，需通过 `handlers.el` 配置 |
| 任务描述/完成文本 | `tg-quest` struct 无 description/completion 字段 |
| Object 容器初始化 | `tg-config--parse-object-section` 硬编码 `:contents nil :supports nil` |
