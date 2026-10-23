# Codex Agent Rules

> **작업 시작 전 반드시 [`AI_MUST_READ.md`](AI_MUST_READ.md) 를 먼저 읽을 것** (PUBLIC 범용 레포: 고객정보 금지 / 정보 조회 순서 tPrivateKB → 사양서 → 코드).

You are an intelligent agentic AI working on this project.

## CORE INSTRUCTIONS
1. **FOLLOW RULES**: You MUST read and follow the global agent rules defined in `GEMINI.md` and `.agent/rules/`.
2. **USE SKILLS**: For complex coding tasks, you MUST use the skills located in `.agent/skills/`.
   - Use `subagent-driven-development` for multi-step features.
   - Use `writing-plans` to create `implementation_plan.md` before coding.
   - Use `test-driven-development` (TDD) for reliability.
   - Use `keep-codex-fast` when Codex feels slow or local state needs cleanup.
3. **SCRIPTS**: Prefer using scripts in `.agent/scripts/` over raw commands.

## GIIP PRODUCT SCOPE — HARD RULE (revised 2026-10-15)

Changes to the giip product repositories (`giipv3`, `giipdb`, `giipfaw`, `giipprj`,
`giipAgentWin`, `giipAgentLinux`, `giipAgentAdmLinux`) may be made **from any CSN**, and are
always submitted through a **pull request** (never a direct push to `main`).

> Revised 2026-10-15 (direct user instruction). The former "under CSN 47 only" rule — and its
> duty to re-register the request under CSN 47 and close the original issue — **no longer
> applies**. The 2026-09-18 background is kept as history only.

Still in force:
1. **Stay in the working CSN** — never write issues, comments, CQE, KVS or API calls under a
   different CSN.
2. **PR, not a direct push** to `main`.
3. **CSN-agnostic changes** — a product change must work for every CSN. CSN-specific branches
   are forbidden in shared code paths; CSN-specific scripts belong in a CQE task.
4. The `giipdb` SQL rules and the agent-platform boundary rule still apply.

`giip-fde-agent` itself is **not** a giip product repository; normal work on this repo
continues under CSN 70424.

→ `.agent/rules/51_giip_product_changes_csn47_only.md`

## KARPATHY BEHAVIORAL GUIDELINES
Follow `.agent/rules/10_karpathy_guidelines.md` for all coding tasks:
1. **Think Before Coding** — State assumptions explicitly. Ask if uncertain. Surface tradeoffs.
2. **Simplicity First** — Minimum code that solves the problem. Nothing speculative.
3. **Surgical Changes** — Touch only what you must. Don't improve unrelated code.
4. **Goal-Driven Execution** — Define success criteria. Loop until verified.

## CODEX PERFORMANCE
When Codex starts feeling slow after heavy use, run the keep-codex-fast skill:
```
Use $keep-codex-fast to inspect my Codex local state and recommend a safe maintenance plan.
```
Handoffs first. Archive, don't delete. Apply only when ready.

## CONTEXT
The full agent context is stored in the `.agent` directory. Always check there for project-specific conventions.
