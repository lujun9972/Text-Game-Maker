# Config Generator Design

## 概述

为 Text-Game-Maker 提供交互式配置文件生成器，通过专用 buffer 表单引导用户生成 room、map、inventory、creature 四种配置文件。

## 交互方式

用户调用 `M-x tg-gen-<type>-config`，打开专用 buffer，其中包含键值对模板。用户编辑字段值，按 `C-c C-c` 提交，系统解析 buffer 内容并写入 Elisp 配置文件。

## 新文件

### `tg-config-generator.el`

包含以下组件：

#### 1. tg-gen-config-mode

专用 major mode（derived from text-mode）：
- `C-c C-c` 绑定到提交函数
- `#` 开头的行和空行为注释，解析时忽略
- buffer 顶部显示提示信息

#### 2. 四个交互命令

| 命令 | 功能 |
|------|------|
| `tg-gen-room-config` | 生成 room-config 文件 |
| `tg-gen-map-config` | 生成 room-map-config 文件 |
| `tg-gen-inventory-config` | 生成 inventory-config 文件 |
| `tg-gen-creature-config` | 生成 creature-config 文件 |

每个命令：
1. 弹出 buffer `*TG Config: <type>*`
2. 插入模板（包含示例值）
3. 切换到 `tg-gen-config-mode`
4. 设置 buffer-local 变量 `tg-config-type` 标识配置类型

#### 3. 提交函数 `tg-gen-config-submit`

解析 buffer 内容，根据 `tg-config-type` 分派到对应的解析函数，生成 Elisp 数据，写入用户选择的文件。

## 表单格式

### Room 配置

```
# Room Configuration
# Fill in values, press C-c C-c to save

## Room 1
symbol: living-room
description: 一间宽敞的客厅
inventory: key sword
creature: cat
```

生成结果：
```elisp
((living-room "一间宽敞的客厅" (key sword) (cat)))
```

### Inventory 配置

```
# Inventory Configuration
# Fill in values, press C-c C-c to save

## Item 1
symbol: key
description: 一把生锈的钥匙
type: usable
effects: (wisdom . 1)
```

生成结果：
```elisp
((key "一把生锈的钥匙" usable ((wisdom . 1))))
```

### Creature 配置

```
# Creature Configuration
# Fill in values, press C-c C-c to save

## Creature 1
symbol: hero
description: 勇敢的冒险者
attr: (hp . 100) (attack . 10) (defense . 5)
inventory: key
equipment:
```

生成结果：
```elisp
((hero "勇敢的冒险者" ((hp . 100) (attack . 10) (defense . 5)) (key) ()))
```

### Map 配置

```
# Map Configuration
# Fill in room symbols in grid layout, press C-c C-c to save

living-room kitchen
bedroom     bathroom
```

生成结果（直接保存为文本文件，不做 Elisp 转换）。

## 解析规则

- `#` 开头的行为注释，跳过
- 空行跳过
- `##` 开头的行为实体分隔符（Room/Item/Creature 配置）
- `key: value` 格式的行：`key` 为字段名，`value` 为字段值
- 多个空格分隔的值视为列表（如 `inventory: key sword` → `(key sword)`）
- `value` 为空视为空列表 `()`
- `attr` 和 `effects` 字段特殊处理：用 `read-from-whole-string` 解析为 Elisp 数据
- Map 配置不使用 `##` / `key: value` 格式，直接解析每行为 room symbol 列表

## 数据类型转换

| 字段 | 输入格式 | 输出格式 |
|------|----------|----------|
| symbol | `living-room` | `'living-room` |
| description | `一间客厅` | `"一间客厅"` |
| inventory/creature/equipment | `key sword` 或空 | `(key sword)` 或 `()` |
| attr/effects | `(hp . 100) (attack . 10)` | `((hp . 100) (attack . 10))` |
| type | `usable` 或 `wearable` | `'usable` 或 `'wearable` |

## 测试覆盖

### 解析函数测试
- 解析 Room 配置（单条、多条）
- 解析 Inventory 配置（含 effects）
- 解析 Creature 配置（含 attr）
- 解析 Map 配置
- 空值字段转为空列表
- 注释行和空行被跳过
- attr/effects 的 Elisp 数据解析

### 生成命令测试
- `tg-gen-room-config` 创建正确 buffer 和 mode
- `tg-gen-config-submit` 生成正确的 Elisp 数据

## 影响范围

| 文件 | 改动 |
|------|------|
| `tg-config-generator.el` | 新文件：所有生成逻辑 |
| `test/test-tg-config-generator.el` | 新文件：测试 |
| `text-game-maker.el` | 添加 `(require 'tg-config-generator)` |
