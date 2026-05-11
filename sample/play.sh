#!/bin/bash
# 地牢冒险 - Text-Game-Maker 2.0 示例游戏启动脚本
# 用法: bash sample/play.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

emacs --no-init-file -nw --directory "$PROJECT_DIR" \
      --load "$PROJECT_DIR/tg.el" \
      --eval '(tg-start "'"$SCRIPT_DIR"'/game.org")'
