# GIIP Evidence and K-Layer Safety Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Keep customer project knowledge isolated and distinguish executor reports from observed verification in GIIP task results.

**Architecture:** Improve the existing `slack-bot/k-layer.js` selector and task execution callback; reuse the existing model router and cost tracker without importing Hermes-specific components. Preserve existing issue statuses: `REVIEW` means awaiting management review, never `DONE`.

**Tech Stack:** Node.js, built-in `node:test`, existing Slack bot and `.agent` runtime.

---

### Task 1: Scope and freshness of K-Layer claims

**Files:** Modify `slack-bot/k-layer.js`, `slack-bot/task-manager.js`, `.agent/skills/k-layer/SKILL.md`; create `slack-bot/tools/test-k-layer-scope.js`.

1. Write tests that search claims across two temporary workspaces: scoped and fresh claim included, other-project or other-CSN claims excluded, expired/invalidated/source-changed claims excluded, legacy unscoped claim withheld from customer workspace, legacy heading forms parsed correctly, output length capped.
2. Run tests and observe expected failures.
3. Implement a local notes selector that takes workspace, project and CSN explicitly; never fall back to the GIIP agent repository's notes for another workspace. Apply a bounded recall budget and validate explicit freshness/source-digest metadata without network calls.
4. Pass workspace context from the execution entry point and document scope and freshness fields for newly authored claims. Run focused tests.

### Task 2: Evidence states in the Slack task lifecycle

**Files:** Modify `slack-bot/task-manager.js`, `slack-bot/handlers.js`; create `slack-bot/task-evidence.js` and `slack-bot/tools/test-task-evidence.js`.

1. Write failing tests for a task evidence receipt: prepared is not executed, process exit 0 means executor-reported completion, a nonzero exit remains failed, and forged verifier fields cannot produce `verified`.
2. Run tests and observe expected failures. Implement bounded, secret-masked local evidence receipts keyed by task ID. Leave verified promotion unavailable until an independent verification gate is implemented.
3. Wire process start/exit to receipts, attach `verification_state` to tasklist, and label issue `REVIEW` comments and Slack completion as pending independent verification. Keep the GIIP workflow state `REVIEW`.
4. Run focused tests and existing bot pipeline/cost regression tests. Confirm the route and telemetry remain unchanged.

### Delivery

Update `docs/WHATS_NEW.md` with the user-visible changes. Review the diff, run `git diff --check`, commit on a feature branch, push, and prepare a draft PR for review.
