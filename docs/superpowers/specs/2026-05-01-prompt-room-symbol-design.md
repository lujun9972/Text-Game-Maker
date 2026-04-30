# Prompt Room Symbol Design

## 概述

在 tg-mode 的 prompt 中显示当前房间的 symbol，格式为 `[symbol]>`。

## 当前行为

- `tg-messages` 中 prompt 硬编码为 `">"`（`tg-mode.el:10`）
- `tg-parse` 通过 `(string= ">" (buffer-substring (- beg 1) beg))` 检测 prompt 行（`tg-mode.el:47`）

## 目标行为

- prompt 显示为 `[living-room]>`（方括号包裹房间 symbol）
- `tg-parse` 能正确识别新的 prompt 格式

## 改动

### `tg-mode.el`

1. 新增辅助函数 `tg-prompt-string`，返回当前房间的 prompt 字符串：
   - 如果 `current-room` 有值，返回 `[(Room-symbol current-room)]>`
   - 否则返回 `>`

2. 修改 `tg-messages`，将 `">"` 替换为 `(tg-prompt-string)`

3. 修改 `tg-parse` 中的 prompt 检测逻辑：
   - 不再检查固定字符 `">"`
   - 改为从行首向前查找 `>` 字符，取 `>` 后的内容作为用户输入

## 测试覆盖

- `tg-prompt-string` 在 `current-room` 有值时返回 `[symbol]>`
- `tg-prompt-string` 在 `current-room` 为 nil 时返回 `>`
- `tg-parse` 能正确解析 `[living-room]> attack goblin` 这样的输入
- `tg-parse` 对无 prompt 的行不解析

## 影响范围

| 文件 | 改动 |
|------|------|
| `tg-mode.el` | 新增 `tg-prompt-string`，修改 `tg-messages` 和 `tg-parse` |
| `test/test-tg-mode.el` | 新增 prompt 相关测试 |
