---
name: init-deep-context
description: |
  Guides generating hierarchical, subsystem-scoped AGENTS.md/CLAUDE.md files for a large
  multi-subsystem repository, instead of one giant root file every agent invocation has to
  read in full. Walks the project tree, identifies real subsystem boundaries, drafts a
  focused instruction file at each boundary containing only that subtree's local conventions,
  and leaves the root file as a high-level index that points to them.

  Use proactively when a repository has grown multiple distinct subsystems/packages/apps
  (each with its own conventions, stack, or gotchas) and the root AGENTS.md/CLAUDE.md has
  become a long grab-bag mixing all of them together, or when the user explicitly asks to
  split/restructure/deepen the project's agent instructions.

  Triggers: init deep, deep init, hierarchical AGENTS.md, split CLAUDE.md, subsystem context,
  nested AGENTS.md, per-package instructions, context locality,
  계층형 AGENTS.md, 서브시스템 컨텍스트 분리, 하위 폴더 지침 파일,
  階層AGENTS.md, サブシステム別コンテキスト,
  分层AGENTS.md, 子系统上下文拆分

  Do NOT use for: a small or single-purpose repo where the root file is short and already
  covers everything (splitting it adds maintenance overhead with no locality benefit) — see
  "When NOT to Use" below before starting.
argument-hint: "[optional: subtree to scope the pass to]"
user-invocable: true
allowed-tools:
  - Read
  - Glob
  - Grep
  - Write
  - Edit
pdca-phase: plan
task-template: "[init-deep-context] {scope}"
---

# init-deep-context — Hierarchical AGENTS.md Generator

> This is a guided procedure for an agent invocation to walk through, not a script that runs
> unattended — every judgment call below (which boundaries are real, what's worth its own
> file) needs the model's read of the actual codebase, the same way every other prompt-guidance
> skill in this repo works.

## Purpose

A single root `AGENTS.md`/`CLAUDE.md` that tries to cover an entire large repository — several
subsystems, packages, or apps in one tree — forces every agent invocation to read context that
is irrelevant to the specific subtree it's actually working in. Splitting subsystem-specific
conventions into their own `AGENTS.md` files at meaningful directory boundaries means an agent
working in `src/payments/` only loads `src/payments/AGENTS.md` plus the root index, not the
full detail of `src/notifications/` or `src/admin/` as well. The root file shrinks to a
high-level pointer/index, matching the same "pointer, not duplicate content" philosophy this
ecosystem already uses elsewhere (e.g. a git-tracked canonical file with thin pointers to it
from other locations) — applied here along the directory axis instead.

## When NOT to Use

**Skip this skill entirely if the repo is small or single-purpose and the root file already
covers it without strain.** The entire point is token efficiency and locality for large,
multi-subsystem repos — fragmenting a small repo into many tiny `AGENTS.md` files adds
maintenance overhead (more files to keep in sync, more places a convention can go stale) for no
locality benefit, since a small repo's root file was cheap to read in full anyway. Before
starting, check: does the root file mix together conventions from clearly distinct subsystems
that don't apply to each other? If not, stop here and say so instead of proceeding.

## Process

### 1. Identify meaningful subsystem boundaries

Look at the project's own structure to find natural boundaries — don't impose an arbitrary
depth. Candidates, roughly in order of how likely they are to be real boundaries:

- Top-level directories under `src/` (or the repo's equivalent) that are independently
  deployable, independently owned, or built on a different stack (e.g. `apps/web/`,
  `apps/api/`, `packages/shared-ui/`).
- A directory whose `README.md`, existing comments, or file layout already signal it plays by
  different rules than its siblings (different test framework, different naming convention,
  different external dependency).
- A directory the user names explicitly when invoking this skill (via the `[optional: subtree]`
  argument).

**A boundary needs enough distinct local convention or context to be worth its own file.** If a
subdirectory's "local conventions" would just restate the root file, it's not a boundary —
don't create a file for it. When in doubt, read the directory's actual code before deciding;
don't guess a boundary exists from the directory name alone.

### 2. For each boundary, draft a focused AGENTS.md

For every real boundary found in step 1, write `<subtree>/AGENTS.md` (and a `CLAUDE.md` twin
only if this repo's existing convention mirrors instruction files per engine — check whether
the root already has both before deciding to duplicate at the subtree level too) covering ONLY
that subtree's specifics:

- The subtree's stack/framework, if different from the root (e.g. "this package uses Vitest,
  not the Jest the rest of the repo uses").
- Conventions genuinely local to this subtree (naming, folder layout, an internal API contract
  other parts of the repo don't need to know about).
- Gotchas specific to this subtree (a flaky test, a manual step CI doesn't cover, a legacy
  pattern still in use here only).

Do **not** repeat anything already covered by the root file (build commands, repo-wide commit
conventions, global safety rules) — an agent reading the subtree file will have already read
the root file first; restating shared content just adds drift risk between the two copies.

### 3. Leave the root file as a high-level index

Update the root `AGENTS.md`/`CLAUDE.md` (or add a short new section to it) to:

- Keep everything that genuinely applies repo-wide (this does not move).
- Add pointers to each new subtree file, e.g.:
  ```markdown
  ## Subsystem-specific context
  - `apps/web/` conventions: see `apps/web/AGENTS.md`
  - `apps/api/` conventions: see `apps/api/AGENTS.md`
  - `packages/shared-ui/` conventions: see `packages/shared-ui/AGENTS.md`
  ```
- Not inline-duplicate the subtree files' content — the root file's job after this pass is
  "what's true everywhere, plus where to look for what's true locally," nothing more.

### 4. Verify no orphaned or contradicting content

Before finishing:

- Re-read the root file — confirm nothing left behind still describes a subsystem in detail
  that now has its own file (that content should have moved, not been copied).
- Confirm no subtree file contradicts the root file (e.g. root says "always use npm", a subtree
  file silently assumes yarn without saying it's an intentional local exception — call out the
  exception explicitly if it's real, don't leave it implicit).
- Report back which boundaries were created, which candidate boundaries were considered and
  rejected (and why), and what stayed in the root file.

## Example Outcome

```
repo/
├── AGENTS.md                 # repo-wide rules + index pointing to the two files below
├── apps/
│   ├── web/
│   │   └── AGENTS.md         # Next.js conventions, this app's component structure only
│   └── worker/
│       └── AGENTS.md         # queue processing conventions, retry/backoff rules only
└── packages/
    └── shared-ui/            # (no AGENTS.md — conventions here are just "root rules apply",
                               #  not a real boundary; don't create a file with nothing to say)
```
