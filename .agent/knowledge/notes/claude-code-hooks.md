# Claude Code Hook System Patterns

> Generic patterns for configuring and troubleshooting `.claude/settings.json` hooks in any project.
> All claims are source-linked. Do not delete — use invalidated_at to retire.

---

CLAIM-025: Claude Code hook output format must use `systemMessage` + `hookSpecificOutput.additionalContext`, NOT `type/content`
- **evidence**: `{"type":"system","content":"..."}` format does not work. Correct format: `{"systemMessage":"...","hookSpecificOutput":{"hookEventName":"Stop","additionalContext":"..."}}`
- **source**: `.claude/settings.json` hook configuration, hook scripts
- **observed_at**: 20260614
- **invalidated_at**: null
- **confidence**: high
- **note**: `systemMessage` → shown in user UI. `hookSpecificOutput.additionalContext` → injected into model context. Event name must be set in `hookEventName` field.

CLAIM-026: Writing `.claude/settings.json` in Claude Code auto mode is auto-blocked — requires explicit user approval
- **evidence**: First attempt blocked by auto-mode classifier with "Self-Modification" reason; allowed after user explicitly re-requested
- **observed_at**: 20260614
- **invalidated_at**: null
- **confidence**: high
- **fix**: Inform user in advance that this operation requires explicit permission, and wait for approval before proceeding.

CLAIM-027: Hook pipe-test can be validated in PowerShell with `echo '{}' | node script.js`
- **evidence**: `echo '{"prompt":"some task"}' | node .agent/hooks/trace-start.js` returns valid JSON output with exit 0
- **observed_at**: 20260614
- **invalidated_at**: null
- **confidence**: high
- **note**: Always run pipe-test before registering in settings.json. Hook failures are silently ignored, making them hard to debug.

CLAIM-028: Injecting K-Layer claims via UserPromptSubmit hook auto-loads relevant knowledge before task starts
- **evidence**: `trace-start.js` parses prompt keywords, searches `.agent/knowledge/notes/`, injects matching claims via `hookSpecificOutput.additionalContext`
- **observed_at**: 20260614
- **invalidated_at**: null
- **confidence**: high
- **note**: Keyword mappings managed in `KEYWORDS` object in the hook script. When adding new topics, also add keywords to that object.

CLAIM-029: `.claude/settings.json` hook commands depend on CWD — use `git rev-parse` to always resolve project root
- **evidence**: `node .agent/hooks/post-task.js` assumes project root CWD, but after using Bash in a subdirectory (e.g. a sub-package folder), the Stop hook looks for `.agent/hooks/post-task.js` relative to that subdirectory → MODULE_NOT_FOUND
- **observed_at**: 20260616
- **invalidated_at**: null
- **confidence**: high
- **fix**: Use this pattern to make hooks portable regardless of CWD:
  ```
  "command": "powershell -NoProfile -Command \"Set-Location (git rev-parse --show-toplevel); node .agent/hooks/post-task.js\""
  ```
- **never_do**: Register hooks with bare relative paths like `node .agent/hooks/...` — they break whenever CWD changes.

CLAIM-030: Changes to `.claude/settings.json` must be verified immediately. Hook errors are non-blocking and silently fail.
- **evidence**: Stop hook error "Failed with non-blocking status code" — Claude still responds so the failure is easy to miss
- **observed_at**: 20260616
- **invalidated_at**: null
- **confidence**: high
- **rule**: After any settings.json change, run `echo '{}' | node .agent/hooks/post-task.js` and confirm exit 0 (see CLAIM-027).

CLAIM-032: After Claude runs Bash in a subdirectory, the Stop hook inherits that subdirectory as CWD — always use CWD-invariant hook format
- **evidence**: After using Bash inside a sub-package folder, Stop hook tried `C:\...\{sub-package}\.agent\hooks\post-task.js` → MODULE_NOT_FOUND
- **observed_at**: 20260616
- **invalidated_at**: null
- **confidence**: high
- **fix**: `powershell -NoProfile -Command "Set-Location (git rev-parse --show-toplevel); node .agent/hooks/XXX.js"` — git dynamically resolves repo root from any CWD
- **pipe_test**: `echo '{}' | powershell -NoProfile -Command "Set-Location (git rev-parse --show-toplevel); node .agent/hooks/post-task.js"` → EXIT:0

CLAIM-035: PowerShell `Set-StrictMode -Version Latest` causes `PropertyNotFoundException` when accessing non-existent PSObject properties
- **evidence**: `$settings.properties.$key` throws `The variable '$x' cannot be retrieved because it has not been set` in strict mode when property doesn't exist
- **observed_at**: 20260616
- **invalidated_at**: null
- **confidence**: high
- **fix**: Remove `Set-StrictMode -Version Latest` from scripts, OR check property existence with `$obj.PSObject.Properties.Match($key).Count -gt 0`
- **note**: Initializing with `$null` alone does NOT fix this. Use `Match()` method or remove strict mode.

CLAIM-036: PowerShell variables (`$r`, `$x`, etc.) inside `.claude/settings.json` hook commands get expanded to empty strings by the outer PowerShell process before JSON parsing
- **evidence**: Command containing `$r=(git rev-parse --show-toplevel)` caused error "= : '=' is not recognized as a command name" — outer PowerShell expanded `$r` to empty string, producing `= (git ...)` which is invalid
- **observed_at**: 20260616
- **invalidated_at**: null
- **confidence**: high
- **fix**: Never use `$variable` assignment inside hook command strings. Pass subexpressions directly:
  ```
  "if (Test-Path (Join-Path (git rev-parse --show-toplevel) '.agent/hooks/post-task.js')) { Set-Location (git rev-parse --show-toplevel) } ..."
  ```
