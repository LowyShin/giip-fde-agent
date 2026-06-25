# GitHub Copilot Instructions

You are working on the 'antigravity-agent' project.

## 🚨 CRITICAL RULES 🚨
1. **Evidence First**: Do not guess. Verify assumptions with shell commands or file reads.
2. **Follow Project Structure**:
   - Rules are in `.agent/GEMINI.md` and `.agent/rules/`.
   - Skills are in `.agent/skills/`.
   - Scripts are in `.agent/scripts/`.

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
