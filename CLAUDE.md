# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Running Tests

**Full suite (258 tests):**
```sh
emacs -batch -L . \
  -l test/tg-registry-test.el -l test/tg-game-test.el \
  -l test/tg-object-test.el -l test/tg-creature-test.el \
  -l test/tg-room-test.el -l test/tg-action-test.el \
  -l test/tg-parser-test.el -l test/tg-commands-test.el \
  -l test/tg-dialog-test.el -l test/tg-npc-test.el \
  -l test/tg-quest-test.el -l test/tg-shop-test.el \
  -l test/tg-level-test.el -l test/tg-builtin-test.el \
  -l test/tg-config-test.el -l test/tg-config-gen-test.el \
  -l test/tg-save-test.el -l test/tg-mode-test.el \
  -l test/tg-integration-test.el \
  -f ert-run-tests-batch-and-exit
```

Note: `run-tests.sh` is outdated (references v1 module names). Use the command above.

**Single test file:**
```sh
emacs -batch -L . -l test/tg-dialog-test.el -f ert-run-tests-batch-and-exit
```

**Single test case:**
```sh
emacs -batch -L . -l test/tg-dialog-test.el --eval '(ert-run-tests-batch "test-name")'
```

**Known test ordering issue:** `test-tg-registry-register-and-get` uses `puthash` directly for actions because `tg-register-action` is overridden by `tg-action.el` with a different signature. Running registry tests alone passes; only fails when `tg-action.el` is loaded first.

## Architecture

17 `tg-*.el` modules + `tg.el` entry point. All modules use `cl-defstruct` for data and a global Registry pattern.

### Dependency Graph (load order)

```
tg-registry (zero deps) → tg-object → tg-creature → tg-game → tg-room
                                                         ↓
tg-dialog ← tg-action ← tg-parser ← tg-commands
     ↑             ↓
     └─────────────┘  (tg-action requires tg-dialog)
```

Additional modules with simpler deps: `tg-npc`, `tg-quest`, `tg-shop`, `tg-level`, `tg-save` (all require `tg-registry` + `tg-game`/`tg-creature`). `tg-config` and `tg-config-gen` only require `tg-registry`.

Entry: `tg.el` provides `tg-start` (with UI) and `tg-init` (headless).

### Key Design Decisions

**tg-game is a hash table, not a struct.** Access via `tg-game-get`/`tg-game-put`. Keys: `:title`, `:author`, `:location`, `:player`, `:state`, `:turns`, `:active-buffs`.

**tg-register-action has two definitions.** `tg-registry.el` defines a simple `(sym value)` version. `tg-action.el` overrides it with `(&rest args)` accepting `:id`, `:synonyms`, `:handler`. The action version is what actually runs at runtime.

**Handler chain dispatch (tg-commands.el):** Player commands go through: error → room-before → io → do → action → after. Non-passive commands then run: NPC behaviors → buffs-tick → turn-increment. Any handler returning non-nil stops the chain.

**Circular dependency on tg-message.** `tg-dialog.el` calls `tg-message` (defined in `tg-commands.el`) at runtime without `require`ing it, because `tg-dialog` → `tg-action` → `tg-parser` → `tg-commands` would be circular. At runtime all modules are loaded, so `tg-message` is available.

### Output: Always Use tg-message

**Never use Emacs's built-in `message` for player-facing output.** `message` writes to `*Message*` buffer. `tg-message` (from `tg-commands.el`) writes to the game buffer via `tg-output-buffer`. Any module producing game output must use `tg-message`.

### Org Config Format

Games are defined in a single `.org` file with 6 sections: Rooms, Objects, Creatures, Dialogs, Shops, Quests. Headers: `#+TITLE`, `#+AUTHOR`, `#+START` (starting room), `#+PLAYER` (player creature symbol). A `handlers.el` file in the same directory is auto-loaded for level table customization.

### Creature Effective Attributes

`tg-creature-effective-attr` calculates `base + equipment-effects + buff-bonuses` at runtime. Equipment in the `equipment` list contributes its `effects` alist dynamically during combat. Attributes are stored as an alist in the `attr` field: `((hp 100) (attack 5) (defense 3))`.

## Agent skills

### Issue tracker

Issues tracked via GitHub Issues using `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Five canonical labels: needs-triage, needs-info, ready-for-agent, ready-for-human, wontfix. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context layout: `CONTEXT.md` + `docs/adr/` at repo root. See `docs/agents/domain.md`.
