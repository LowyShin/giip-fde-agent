---
name: ast-grep
description: |
  Structural, AST-pattern-aware code search and rewrite across 25+ languages using the
  standalone `ast-grep` (`sg`) CLI. Use instead of plain grep/ripgrep whenever the task needs
  to match code by its *shape* rather than its text — e.g. "find every call to `foo()` whose
  second argument is an object literal", "find all React components missing a `key` prop",
  "rewrite every `.then(x => x.y)` into `.then(({ y }) => y)` across the repo" — comments,
  string contents, and formatting/whitespace differences are ignored automatically.

  Use proactively when the user asks for a structural refactor, a codebase-wide rename of a
  call pattern, or a precise "find all usages that match this shape" query that plain text
  search would over- or under-match.

  Triggers: ast-grep, sg, structural search, structural rewrite, AST pattern, pattern-based
  refactor, codemod, find all calls to, rewrite all instances of,
  구조 검색, 구조적 리팩터링, 패턴 기반 리팩터링, AST 패턴, 코드모드,
  構造検索, パターンベースのリファクタリング, コードモッド,
  结构化搜索, 结构化重构, 代码模式改写

  Do NOT use for: single-file small edits (use Edit directly), plain text/non-code search (use
  Grep/jikji), or renaming a single known symbol (a normal find-and-replace is faster and the
  AST pattern engine adds no value there).
argument-hint: "[pattern] [lang] [--rewrite <replacement>]"
user-invocable: true
allowed-tools:
  - Bash
  - Read
  - Glob
  - Grep
pdca-phase: do
task-template: "[ast-grep] {pattern}"
---

# ast-grep — Structural Code Search & Rewrite

> pattern matches code *structure* (AST), not raw text — comments, string literals, and
> whitespace differences don't cause false matches or misses the way grep/ripgrep can.

## When to Use This Instead of grep/ripgrep

| Need | Tool |
|------|------|
| "find the text `TODO`" | `Grep` / ripgrep |
| "find every call to `apiClient.get(...)` whose first arg is a string literal" | `ast-grep` |
| "find every React component that renders a `<Modal>` without an `onClose` prop" | `ast-grep` |
| "rewrite every `foo.bar(a, b)` to `foo.bar({ a, b })` across the repo" | `ast-grep` (rewrite mode) |
| local file/folder discovery by natural-language clue | `jikji` (see `.agent/skills/jikji/SKILL.md`) |

Plain text search can't express "the second argument to this call is an object literal" or
"this JSX element is missing a specific prop" — it only knows about characters. `ast-grep`
parses the file into its real syntax tree per language and matches on that tree, so a pattern
like `$OBJ.map($FN)` matches every method call shaped that way regardless of variable names,
formatting, or surrounding comments.

## Install Check

`ast-grep` is a standalone binary (Rust), not tied to any Node/plugin runtime. Check first:

```bash
sg --version
```

If missing, install with whichever package manager is already available on this machine — no
need to guess, check what's on PATH first (`env-check` skill), then pick one:

```bash
npm i -g @ast-grep/cli      # Node/npm environments (this PC has Node — use this by default)
# or
pip install ast-grep-cli    # Python environments
# or
cargo install ast-grep --locked   # if Rust toolchain is available
```

Reference: https://ast-grep.github.io/

## Usage

### 1. Search — print every match

```bash
sg -p '$OBJ.map($FN)' -l ts
```

- `$FOO` (uppercase) is a single-node metavariable — matches any one expression/identifier.
- `$$$FOO` matches zero or more nodes (e.g. a variable-length argument list).
- `-l` (or `--lang`) picks the parser: `ts`, `tsx`, `js`, `jsx`, `python`, `go`, `rust`, `java`,
  `csharp`, `html`, `css`, and 15+ more — run `sg --help` for the full list.
- Omit `-l` and pass a path with `sg -p '...' path/` to let it infer language per file
  extension across a whole tree.

### 2. Search scoped to a directory

```bash
sg -p 'console.log($$$ARGS)' -l ts src/
```

### 3. Search with a YAML rule (for multi-condition patterns)

For patterns needing constraints beyond a single expression (e.g. "match `$FN` only when it's
NOT already wrapped"), write a rule file — see `sg new` / `ast-grep --help scan` for the rule
schema. For the common case, an inline `-p` pattern is enough; reach for a rule file only when
`-p` genuinely can't express the constraint.

### 4. Rewrite — ALWAYS dry-run/preview before writing

Matching this repo's general caution-before-destructive-action posture (see
`.agent/skills/gstack-safety/SKILL.md`): a rewrite touches multiple files in one shot, so treat
it like any other bulk file-modifying operation — preview first, then apply deliberately.

```bash
# Step 1 — preview only, writes nothing (no -i, no --update-all)
sg -p '$OBJ.then($FN => $FN.$PROP)' -r '$OBJ.then(({ $PROP }) => $PROP)' -l ts

# Step 2a — apply interactively, confirm each hunk one at a time
sg -p '$OBJ.then($FN => $FN.$PROP)' -r '$OBJ.then(({ $PROP }) => $PROP)' -l ts --interactive

# Step 2b — apply everywhere at once (only after the dry-run preview in Step 1 looked correct
# across ALL matches, not just the first few)
sg -p '$OBJ.then($FN => $FN.$PROP)' -r '$OBJ.then(({ $PROP }) => $PROP)' -l ts --update-all
```

Never jump straight to `--update-all` — always run the plain `-p ... -r ...` preview (no write
flag) first and read through the diff it prints, the same way any other multi-file
find-and-replace in this repo gets a dry run before it's allowed to touch disk.

## When NOT to Use ast-grep

- **Single small edit in one known file** — use `Edit` directly, it's faster and the AST engine
  adds no value for a one-off change you can already point at.
- **Plain text / non-code content** — Markdown prose, config values, log lines: use `Grep` or
  `jikji`, not `ast-grep` (its parsers are for programming-language syntax, not free text).
- **Renaming one already-known symbol everywhere** — a straightforward project-wide rename is
  usually better served by the editor's / language server's rename-symbol facility (if
  available) or a simple text find-and-replace; reach for `ast-grep` when the *shape* of the
  match matters, not just the name.
