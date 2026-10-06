# Cursor & Windsurf Rules

You are an intelligent agent working on the 'antigravity-agent' project.

## CORE INSTRUCTIONS
1. **READ THE RULES**: Before doing anything, you MUST read and follow the global agent rules defined in `.agent/GEMINI.md`.
2. **USE SKILLS**: For complex coding tasks, you MUST use the skills located in `.agent/skills/`.
   - Use `subagent-driven-development` for multi-step features.
   - Use `writing-plans` to create `implementation_plan.md` before coding.
   - Use `test-driven-development` (TDD) for reliability.
3. **SCRIPTS**: Prefer using scripts in `.agent/scripts/` over raw commands.

## GIIP PRODUCT SCOPE — HARD RULE

Changes to the giip product repositories (`giipv3`, `giipdb`, `giipfaw`, `giipprj`,
`giipAgentWin`, `giipAgentLinux`, `giipAgentAdmLinux`) must be registered and handled
**under CSN 47 only**. This repository runs under CSN 70424: if a task here asks you to
change a giip product repository, do not change it — register a new issue under CSN 47,
link that issue number back in a comment on the original issue, and only then close the
original. Never drop the request silently.

`giip-fde-agent` itself is **not** a giip product repository; normal work on this repo
continues under CSN 70424.

→ `.agent/rules/51_giip_product_changes_csn47_only.md`

## KARPATHY BEHAVIORAL GUIDELINES
Follow `.agent/rules/10_karpathy_guidelines.md` for all coding tasks:
1. **Think Before Coding** — State assumptions explicitly. Ask if uncertain. Surface tradeoffs.
2. **Simplicity First** — Minimum code that solves the problem. Nothing speculative.
3. **Surgical Changes** — Touch only what you must. Don't improve unrelated code.
4. **Goal-Driven Execution** — Define success criteria. Loop until verified.

## CONTEXT
The full agent context is stored in the `.agent` directory. Always check there for project-specific conventions.
