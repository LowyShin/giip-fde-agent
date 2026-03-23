---
name: gstack-safety
description: |
  Safety guardrails and edit locks. Use to prevent accidental destructive actions.
  Inspired by gstack's /careful, /freeze, and /guard.

  Use proactively when executing potentially dangerous commands or when you need to focus on a specific directory.

  Triggers: be careful, freeze, guard, unfreeze, safety, destructive,
  주의, 조심, 동결, 잠금, 해제, 안전
---

# Gstack Safety Guardrails

> "Maximum safety for production and complex work."

## 1. Careful Mode (Safety Guardrails)

When activated (user says "be careful" or the agent detects a risky command), the agent must:

- **Warn before destructive commands**: `rm -rf`, `DROP TABLE`, `force-push`, `force-delete`, etc.
- **Confirm environment**: Verify if the command is running against production or staging.
- **Explain impact**: Clearly state what will be deleted or changed.
- **Provide override**: Allow the user to proceed explicitly.

## 2. Freeze Mode (Edit Lock)

Restrict file edits to a specific directory or set of files.

- **Locking**: Define the `FREEZE_BOUNDARY` (e.g., `src/app/admin/`).
- **Persistence**: Any edits outside this boundary are blocked until `/unfreeze` or another location is specified.
- **Purpose**: Prevent accidental side-effects in unrelated parts of the codebase while deep in a bug fix.

## 3. Guard Mode (Full Safety)

Combine `/careful` and `/freeze` in one command.

- Enables safety warnings for all commands.
- Locks edits to the current task's scope.

## 4. Usage Table

| Command | Action |
|---------|--------|
| `be careful` | Activate warnings for destructive commands. |
| `freeze {path}` | Lock all subsequent edits to the specified directory. |
| `guard` | Combo: `be careful` + `freeze current_dir`. |
| `unfreeze` | Remove the edit lock. |
