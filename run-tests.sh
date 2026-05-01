#!/bin/bash
# Run all ERT tests for Text-Game-Maker
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEST_DIR="$SCRIPT_DIR/test"

emacs --batch --no-site-file --no-init-file \
  --directory "$SCRIPT_DIR" \
  --directory "$TEST_DIR" \
  --eval "(progn
    (require 'ert)
    (require 'cl-macs)
    (require 'thingatpt)
    (require 'test-text-game-maker)
    (require 'test-room-maker)
    (require 'test-inventory-maker)
    (require 'test-creature-maker)
    (require 'test-action)
    (require 'test-tg-mode)
    (require 'test-tg-config-generator)
    (require 'test-npc-behavior)
    (require 'test-save-system)
    (require 'test-quest-system)
    (require 'test-dialog-system)
    (ert-run-tests-batch-and-exit '(or \"test-\" t)))"
