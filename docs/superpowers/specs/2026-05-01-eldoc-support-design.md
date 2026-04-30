# tg-mode Eldoc Support Design

## 概述

为 tg-mode 添加 eldoc 支持，在用户输入命令时实时显示命令文档。

## 行为

- 用户在 `tg-mode` buffer 中输入命令时，eldoc 在 echo area 实时显示匹配命令的 docstring
- 使用 `try-completion` 对当前输入与 `tg-valid-actions` 中的命令名进行前缀匹配
- 匹配逻辑：取当前行 `>` 后的输入，去掉 `tg-` 前缀后做前缀匹配
- 匹配到唯一命令时显示其 `documentation` 返回值
- 无匹配时不显示任何内容

## 交互示例

```
用户输入: [living-room]> at
Eldoc 显示: 使用'attack <target>'攻击当前房间中的生物

用户输入: [living-room]> mo
Eldoc 显示: 使用'move up/right/down/left'往directory方向移动

用户输入: [living-room]> xyz
Eldoc 显示: (无)
```

## 改动

### `tg-mode.el`

1. 新增 `tg-eldoc-function`：
   - 读取当前行 `>` 之后的内容作为输入
   - 将 `tg-valid-actions` 中的 symbol 转为字符串（去掉 `tg-` 前缀）作为候选
   - 用 `try-completion` 匹配，返回匹配命令的 docstring

2. 在 `tg-mode` 的 mode definition 中设置 `eldoc-documentation-function`：
   ```elisp
   (setq-local eldoc-documentation-function #'tg-eldoc-function)
   ```

3. 在 mode definition 中启用 `eldoc-mode`：
   ```elisp
   (eldoc-mode 1)
   ```

## 测试覆盖

- `tg-eldoc-function` 完整命令匹配返回 docstring
- `tg-eldoc-function` 前缀匹配返回唯一匹配的 docstring
- `tg-eldoc-function` 多义前缀不返回内容
- `tg-eldoc-function` 无匹配不返回内容
- `tg-eldoc-function` 无 prompt 行时不返回内容

## 影响范围

| 文件 | 改动 |
|------|------|
| `tg-mode.el` | 新增 `tg-eldoc-function`，修改 `tg-mode` 定义 |
| `test/test-tg-mode.el` | 新增 eldoc 相关测试 |
