# GitHub Copilot Instructions

> **작업 시작 전 반드시 [`AI_MUST_READ.md`](AI_MUST_READ.md) 를 먼저 읽을 것** (PUBLIC 범용 레포: 고객정보 금지 / 정보 조회 순서 tPrivateKB → 사양서 → 코드).

You are working on the 'antigravity-agent' project.

## 🚨 CRITICAL RULES 🚨
1. **Evidence First**: Do not guess. Verify assumptions with shell commands or file reads.
2. **Follow Project Structure**:
   - Rules are in `.agent/GEMINI.md` and `.agent/rules/`.
   - Skills are in `.agent/skills/`.
   - Scripts are in `.agent/scripts/`.

## 🚨 GIIP PRODUCT SCOPE — HARD RULE 🚨 (revised 2026-10-15)
Changes to the giip product repositories (`giipv3`, `giipdb`, `giipfaw`, `giipprj`, `giipAgentWin`, `giipAgentLinux`, `giipAgentAdmLinux`) may be made **from any CSN**, and are always submitted through a **pull request** (never a direct push to `main`).

> Revised 2026-10-15 (direct user instruction). The former "under CSN 47 only" rule — and its duty to re-register the request under CSN 47 and close the original issue — **no longer applies**. The 2026-09-18 background is kept as history only.

Still in force: stay in the working CSN (no issue/comment/CQE/KVS/API writes under a different CSN) · PR, not a direct push to `main` · CSN-agnostic changes (no CSN-specific branches in shared code; CSN-specific scripts belong in a CQE) · the `giipdb` SQL rules and the agent-platform boundary rule.

`giip-fde-agent` itself is **not** a giip product repository; normal work on this repo continues under CSN 70424.

→ `.agent/rules/51_giip_product_changes_csn47_only.md`

## 🛠️ WORKFLOW (Superpowers)
When asked to implement a feature:
1. **Plan**: Create or update `implementation_plan.md` (see `.agent/skills/writing-plans`).
2. **Execute**: Use TDD (Red-Green-Refactor) (see `.agent/skills/test-driven-development`).
3. **Verify**: Run tests and record evidence.
4. **File Search**: Use `jikji find` (`.agent/skills/jikji`) **before** `grep`, `ls`, `find`, or `rg` for local file discovery.

## 🧠 KARPATHY BEHAVIORAL GUIDELINES
Follow the guidelines in `.agent/rules/10_karpathy_guidelines.md`:
1. **Think Before Coding** — State assumptions explicitly. Ask if uncertain. Surface tradeoffs.
2. **Simplicity First** — Minimum code that solves the problem. Nothing speculative.
3. **Surgical Changes** — Touch only what you must. Don't improve unrelated code.
4. **Goal-Driven Execution** — Define success criteria. Loop until verified.

## ❌ RESTRICTIONS
- Do not run raw SQL. Use `mgmt/execSQLFile.ps1`.
- Do not commit without user permission.
