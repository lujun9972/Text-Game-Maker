# Org 解析层补全设计规格

> **面向 AI 代理的工作者：** 必需子技能：`superpowers:serial-executing-plans`（任务间共享 tg-config.el，强耦合）。

**目标：** 补全 README TODO 中 4 个 Org 解析缺口，使所有已有功能均可通过 game.org 配置。

**架构：** 改动集中在 `tg-config.el` 解析层 + 各模块 struct/display 微调。功能代码已就位，只缺解析桥接。

**技术栈：** Emacs Lisp, Org-mode (org-element), ERT

---

## 1. 对话选项条件解析

### 现状

- `tg-dialog-option` struct 已有 `condition` 字段
- `tg-dialog-eval-condition` 已完整实现（支持 `quest-active`, `quest-completed`, `has-item`, `and`, `or`, `not`）
- `tg-config--parse-dialog-option`（tg-config.el:118-138）硬编码 `:condition nil`

### Org 语法

条件前置，方括号包裹：

```
[条件] 选项文本 :: 回复文本 → (奖励)
```

示例：

```org
* Dialogs

** prisoner
:PROPERTIES:
:NPC_SYMBOL: prisoner
:GREETING: 请救救我...你能帮帮我吗？
:END:
你是谁？ :: 我是被骷髅王关押的探险者。如果你能救我出去，我会报答你的！
有什么线索吗？ :: 听说武器库里有把好剑！ → (exp 15)
[(has-item bread)] 给你点面包 :: 谢谢你！这个给你。 → (exp 10)
```

无条件选项格式不变，向后兼容。

### 解析规则

1. 检测行首是否匹配 `^\[.*\]\s+` 模式
2. 提取方括号内文本，用 `read` 解析为 Elisp 表达式
3. 剩余文本按原逻辑解析选项和回复
4. 无方括号前缀时 condition 保持 nil

### 改动文件

- **修改** `tg-config.el::tg-config--parse-dialog-option` — 添加条件提取逻辑
- **修改** `sample/game.org` — prisoner 对话选项添加 `(has-item bread)` 条件
- **修改** `test/tg-config-test.el` — 添加条件解析测试
- **修改** `test/tg-dialog-test.el` — 添加条件过滤测试

---

## 2. Level Org 配置段

### 现状

- `tg-level.el` 定义三个 defvar：`tg-level-exp-table`, `tg-level-bonus-points-per-level`, `tg-level-auto-upgrade-attrs`
- `tg-config.el` 的 section 分发逻辑（约第 378-390 行）只处理 Rooms/Objects/Creatures/Dialogs/Shops/Quests
- Level 配置通过 `handlers.el` 的 `setq` 完成，`tg-config-load` 自动加载同目录 handlers.el

### Org 语法

扁平 PROPERTIES drawer，无子标题：

```org
* Level
:PROPERTIES:
:EXP_TABLE: 0,50,120,220,350,500,700,950,1300,1700
:BONUS_POINTS: 3
:AUTO_UPGRADE: hp 10
:END:
```

字段说明：

| 字段 | 类型 | 必填 | 默认值 | 说明 |
|---+---+---+---+---|
| `EXP_TABLE` | 逗号分隔整数 | 否 | defvar 默认值 | 升级经验表 |
| `BONUS_POINTS` | 整数 | 否 | defvar 默认值 | 每级属性点 |
| `AUTO_UPGRADE` | 属性键值对 | 否 | defvar 默认值 | 每级自动提升属性，格式同 Creature ATTR |

三个字段全部可选。缺失时保留 defvar 默认值。

### 解析方式

EXP_TABLE 需要新增 `tg-config--parse-int-list` 辅助函数：`split-string` 按逗号分割后用 `string-to-number` 转为整数列表。不复用 `tg-config--split-list`（返回符号列表）。

BONUS_POINTS 直接用 `string-to-number`。
AUTO_UPGRADE 复用已有的 `tg-config--parse-attr`（与 Creature ATTR 格式一致）。

### 向后兼容

- handlers.el 仍会被 `tg-config-load` 自动加载
- 若 game.org 有 Level 段且 handlers.el 也有 setq，handlers.el 后加载会覆盖
- 建议选择其一，不冲突即可

### 改动文件

- **修改** `tg-config.el` — 新增 `tg-config--parse-level-section` + section 分发添加 `"level"` case
- **修改** `sample/game.org` — 添加 Level 段
- **修改** `sample/handlers.el` — 移除 Level 相关 setq（迁移到 game.org）
- **修改** `test/tg-config-test.el` — 添加 Level 段解析测试

---

## 3. 任务描述/完成文本

### 现状

- `tg-quest` struct（tg-quest.el）字段：symbol, type, target, count, progress, status, rewards
- `tg-action--handler-quests`（tg-action.el:642-659）显示：`[状态] 任务ID (类型) - 进度/计数`
- `tg-action--handler-quest`（tg-action.el:661-685）显示类型/目标/进度/奖励
- `tg-track-quest` 完成时只发奖励，无文本提示

### Org 语法

```
** kill-rat
:PROPERTIES:
:TYPE: kill
:TARGET: rat
:COUNT: 1
:DESCRIPTION: 消灭地牢里的老鼠
:COMPLETION: 你成功消灭了老鼠！
:REWARDS: (exp 10)
:END:
```

| 字段 | 类型 | 必填 | 默认值 | 说明 |
|---+---+---+---+---|
| `DESCRIPTION` | string | 否 | nil | 任务描述，quests 列表和 quest 详情中显示 |
| `COMPLETION` | string | 否 | nil | 任务完成时通过 tg-message 显示 |

### 显示改动

**`quests` 命令**（tg-action--handler-quests）：
```
当前任务：
  [active] 消灭地牢里的老鼠 (kill) - 0/1
```
有 description 时显示 description 替代任务 symbol。

**`quest kill-rat` 命令**（tg-action--handler-quest）：
```
消灭地牢里的老鼠
  类型: kill  目标: rat  进度: 0/1
  状态: active
  奖励: (exp 10)
```

**完成时**（tg-track-quest）：
当 progress >= count 且有 completion-text 时，先输出 completion-text 再调用 give-rewards。completion-text 只描述成就事件，不包含奖励信息（奖励由 give-rewards 独立输出，避免重复）。

### 改动文件

- **修改** `tg-quest.el` — struct 新增 `description` 和 `completion-text` 字段
- **修改** `tg-config.el::tg-config--parse-quest-section` — 解析 DESCRIPTION 和 COMPLETION
- **修改** `tg-action.el::tg-action--handler-quests` + `tg-action--handler-quest` — 显示描述
- **修改** `tg-quest.el::tg-track-quest` — 完成时显示 completion-text
- **修改** `sample/game.org` — 所有 6 个 quest 添加 DESCRIPTION 和 COMPLETION
- **修改** `test/tg-quest-test.el` — 新增字段测试
- **修改** `test/tg-action-test.el` — 显示逻辑测试

---

## 4. Object 容器初始化

### 现状

- `tg-object` struct 有 `contents`（容器内物品）和 `supports`（支撑物上物品）字段
- `tg-config--parse-object-section`（tg-config.el）硬编码 `:contents nil :supports nil`
- 游戏运行时可通过 open/take/place 命令动态操作容器，但无法在 Org 中预设初始内容

### Org 语法

```
** chest
:PROPERTIES:
:NAME: 宝箱
:SYNONYMS: chest
:PROPS: container,openable
:CONTENTS: gem
:STATE: closed
:KEY: rusty-key
:END:

** table
:PROPERTIES:
:NAME: 木桌
:SYNONYMS: table
:PROPS: supporter
:SUPPORTS: map
:END:
```

| 字段 | 类型 | 必填 | 默认值 | 说明 |
|---+---+---+---+---|
| `CONTENTS` | 逗号分隔 symbol | 否 | nil | 容器内初始物品 |
| `SUPPORTS` | 逗号分隔 symbol | 否 | nil | 支撑物上初始物品 |

解析规则：逗号分隔的 symbol 字符串，按已有 `tg-config--split-list` 辅助函数转为 Elisp symbol 列表。

注意：容器/支撑物内的物品不应同时出现在房间的 CONTENTS 中（否则会出现两份）。这是 game.org 作者的职责，解析器不做去重。

### 改动文件

- **修改** `tg-config.el::tg-config--parse-object-section` — 解析 CONTENTS 和 SUPPORTS
- **修改** `sample/game.org` — 新增 chest（container+openable，放入 throne）和 table（supporter，放入 hall），gem 从 throne CONTENTS 移到 chest CONTENTS，map 从 hall CONTENTS 移到 table SUPPORTS
- **修改** `test/tg-config-test.el` — 添加容器初始化解析测试
- **修改** `test/tg-object-test.el` — 验证 contents/supports 初始值

---

## 文件变更汇总

| 文件 | 改动类型 | 涉及 TODO |
|---|---|---|
| `tg-config.el` | 修改 4 处解析逻辑 | 1,2,3,4 |
| `tg-quest.el` | struct 加 2 字段 | 3 |
| `tg-action.el` | quest 显示 + completion | 3 |
| `sample/game.org` | 添加新 Org 内容 | 1,2,3,4 |
| `sample/handlers.el` | 移除 Level setq | 2 |
| `test/tg-config-test.el` | 4 组解析测试 | 1,2,3,4 |
| `test/tg-dialog-test.el` | 条件过滤测试 | 1 |
| `test/tg-quest-test.el` | 新字段测试 | 3 |
| `test/tg-action-test.el` | 显示逻辑测试 | 3 |
| `test/tg-object-test.el` | 容器初始化测试 | 4 |

---

## 验证标准

1. 所有 4 个 TODO 项的功能通过 game.org 配置可用
2. `sample/game.org` 使用全部 4 个新特性，`bash sample/play.sh` 可正常运行
3. 全部测试通过（含新增测试）
4. README TODO 段清除已完成项
5. handlers.el 移除 Level setq 后 game.org 自包含
