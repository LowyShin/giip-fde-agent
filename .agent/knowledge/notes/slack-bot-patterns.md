# Slack Bot Design Patterns — Lessons Learned

> Generic patterns for building reliable Slack bots using Node.js + Claude CLI on Windows.
> Applicable to any project running a Slack bot with polling or Socket Mode.

---

## CLAIM-001: Avoid duplicate message processing — save state BEFORE spawning async/sync child process

**evidence**: Sending a command triggered 4 duplicate "analyzing request" responses. Root cause: `spawnSync('claude', ...)` blocked the event loop for up to 90s. When the bot was restarted during that time, the state file hadn't been updated yet, so the same message (ts) was reprocessed on the next run.
**observed_at**: 2026-06-15
**confidence**: 0.95

**Fix**: Call `onTsUpdate(latestTs)` (which writes to the state file) BEFORE calling `spawnSync`:
```javascript
onTsUpdate(latestTs); // ← executed BEFORE spawnSync
spawnSync('claude', [...]);
```

---

## CLAIM-002: Guard against concurrent polling with `isPolling` flag

**evidence**: `setInterval(async () => { await poll(); }, 60000)` does not prevent the next timer callback from firing before the previous `await` resolves. When two callbacks run concurrently with the same `since` timestamp, the same message is processed twice.
**observed_at**: 2026-06-15
**confidence**: 0.90

**Fix**:
```javascript
let isPolling = false;
setInterval(async () => {
  if (isPolling) return;
  isPolling = true;
  try { await poll(); } finally { isPolling = false; }
}, POLL_INTERVAL_MS);
```

---

## CLAIM-003: Normalize Slack message text before command matching

**evidence**: `tasklist all` command was not matched because Slack messages can contain full-width spaces or non-breaking spaces that `.trim()` alone doesn't remove.
**observed_at**: 2026-06-15
**confidence**: 0.85

**Fix**:
```javascript
const cmd = text.trim().replace(/\s+/g, ' ').toLowerCase();
```
Normalize all whitespace variants before comparison.

---

## CLAIM-004: On Windows, `pkill` doesn't work — use PowerShell to kill duplicate node processes

**evidence**: `pkill -f "node index.js"` via Bash tool had no effect on Windows. Result: 8 old bot instances remained running and processed the same message 8 times.
**observed_at**: 2026-06-15
**confidence**: 0.99

**Fix**: Use `killDuplicateBots()` at startup and during polling — detect other `index.js` node processes via PowerShell and kill them with `taskkill /F /PID`:
```javascript
spawnSync('powershell', ['-NonInteractive', '-NoProfile', '-Command',
  `Get-WmiObject Win32_Process -Filter "Name='node.exe'" | Where-Object { $_.CommandLine -like '*index.js*' } | Select-Object -ExpandProperty ProcessId`
])
```
**Note**: `wmic get /format:csv` outputs UTF-16 LE — this breaks `encoding:'utf8'` in Node.js. Always use PowerShell instead of wmic on Windows.

---

## CLAIM-005: Slack file upload URLs cause ETIMEDOUT — strip them before passing to Claude CLI

**evidence**: Image upload messages contain `<https://files.slack.com/...|filename>` in `msg.text`. These pass through mention cleanup (which only strips `<@USERID>`) and reach `claude -p`, causing 30s + 120s timeout chain → ETIMEDOUT.
**observed_at**: 2026-06-15
**confidence**: 0.95

**Fix**: In `cleanText`, strip Slack URL formats:
```javascript
.replace(/<https?:\/\/[^|>]*\|[^>]*>/g, '')  // <URL|label>
.replace(/<https?:\/\/[^>]+>/g, '')           // <URL>
```
For file-only messages (no text after cleanup), reply "画像は処理できません" and skip processing entirely.

---

## CLAIM-006: `gitPushResult()` fails with non-fast-forward if other agents push concurrently — add `git pull --rebase` before push

**evidence**: Slack bot's `gitPushResult()` called `git push` directly. When Claude Code made commits during task execution, the remote branch advanced, causing the result file push to fail → Slack notification showed "(git push 失敗)" even though the actual task succeeded.
**observed_at**: 2026-06-18
**confidence**: 0.98

**Fix**: Add `git pull --rebase origin` immediately before `git push` in any function that commits + pushes result files:
```javascript
spawnSync('git', ['pull', '--rebase', 'origin'], { cwd: BASE_DIR, encoding: 'utf8' });
const pushRes = spawnSync('git', ['push'], { cwd: BASE_DIR, encoding: 'utf8' });
```
