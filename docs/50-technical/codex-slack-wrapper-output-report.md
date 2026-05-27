# Codex Slack Wrapper Output Report Pattern

## Purpose

This document records the problem observed while operating the `giipcodex` Slack bot and defines the recommended implementation pattern for any Codex Slack execution wrapper.

The target wrapper is not the Codex source package itself. Do not patch files under `node_modules/@openai/codex` or the Codex CLI package. Apply the fix in the local Slack wrapper that launches Codex.

Current known wrapper path on Lowy's PC:

```text
C:\Users\lowys\Documents\Codex\2026-05-26\google-mcp
```

## Problem

Observed Slack error:

```text
Error while running the command:
RangeError [ERR_CHILD_PROCESS_STDIO_MAXBUFFER]: stderr maxBuffer length exceeded
```

Cause:

- The Slack wrapper launched Codex through Node.js `child_process.execFile`.
- `execFile` buffers stdout and stderr in memory until the child process exits.
- Codex or a command executed by Codex produced more stderr than the configured `maxBuffer`.
- Node failed before the wrapper could send the real command result to Slack.

This error is a wrapper output-handling failure. It may hide the original Codex or shell error.

## Decision

Use this pattern:

1. Launch Codex with `child_process.spawn`, not `exec` or `execFile`.
2. Stream combined stdout and stderr directly into a temporary Markdown report file.
3. Ask Codex to write its final answer with `--output-last-message`.
4. Send only a short Slack message body.
5. Upload the Markdown report to Slack with `files.uploadV2`.
6. Delete the temporary report directory after Slack upload succeeds or fails.

This preserves full logs without storing large child-process output in memory.

## Required Slack Scope

The Slack app must include:

```text
files:write
```

Reinstall the Slack app after adding the scope.

## AI Implementation Instructions

When applying this fix to a Node.js Slack Codex wrapper:

1. Find code that imports `exec`, `execFile`, or uses `maxBuffer` around Codex execution.
2. Replace Codex process execution with `spawn`.
3. Configure the child process with:

```js
stdio: ['pipe', 'pipe', 'pipe']
```

4. Immediately close stdin:

```js
child.stdin?.end();
```

5. Create a temp directory with `mkdtemp(join(tmpdir(), 'slack-codex-'))`.
6. Create two files in that temp directory:

```text
last-message.md
codex-result-<timestamp>.md
```

7. Pass this argument to Codex:

```text
--output-last-message <path-to-last-message.md>
```

8. Stream both stdout and stderr into the Markdown report:

```js
child.stdout.on('data', (chunk) => reportStream.write(chunk));
child.stderr.on('data', (chunk) => reportStream.write(chunk));
```

9. After process close, append exit code, signal, finish time, and `last-message.md` content to the report.
10. Post a short Slack message containing:

```text
status
exit code
report filename
short final Codex message
```

11. Upload the report:

```js
await client.files.uploadV2({
  channel_id: channel,
  file: createReadStream(reportPath),
  filename: basename(reportPath),
  title: basename(reportPath),
  initial_comment: 'Full Codex stdout/stderr report.',
});
```

12. Use `finally` to delete the temp directory:

```js
await rm(tempDir, { recursive: true, force: true });
```

## Acceptance Criteria

The fix is complete when:

- No Codex execution path uses `exec`, `execFile`, or `maxBuffer` for long command output.
- Slack message body is bounded by a configured character limit.
- Full stdout/stderr is available in an uploaded `.md` file.
- Non-zero Codex exit codes still upload the report.
- Wrapper-level spawn errors also upload a report when the report file was created.
- Temporary report directories are removed after handling.
- The Slack app documents the required `files:write` scope.

## Verification

Run syntax checks:

```powershell
node --check src/index.js
node --check scripts/test-codex-command.js
```

Run the wrapper:

```powershell
npm start
```

Then send a Slack test instruction that produces enough output to prove the wrapper uploads a Markdown file instead of pasting full output into the Slack message body.

## Notes

Do not solve this by only increasing `maxBuffer`. That reduces the chance of failure but keeps the same memory-buffering failure mode.

Prompting Codex to answer under a character limit is useful for Slack readability, but it does not protect the wrapper from command stderr output. The process output must be streamed.
