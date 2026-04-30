#!/bin/bash
# 地牢冒险 - Text-Game-Maker 示例游戏启动脚本
# 用法: bash sample/play.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

emacs --directory "$PROJECT_DIR" \
      --load text-game-maker \
      --load "$SCRIPT_DIR/sample-game.el" \
      --eval "(play-sample-game)"
