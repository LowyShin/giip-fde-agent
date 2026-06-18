# Claude Code Rules

You are an intelligent agentic AI working on this project.

## CORE INSTRUCTIONS
1. **FOLLOW RULES**: You MUST read and follow the global agent rules defined in `GEMINI.md` and `.agent/rules/`.
2. **USE SKILLS**: For complex coding tasks, you MUST use the skills located in `.agent/skills/`.
   - Use `subagent-driven-development` for multi-step features.
   - Use `writing-plans` to create `implementation_plan.md` before coding.
   - Use `test-driven-development` (TDD) for reliability.
3. **SCRIPTS**: Prefer using scripts in `.agent/scripts/` over raw commands.

## SOURCE CODE CHANGE DISCIPLINE — MANDATORY

**Whenever source code changes (app code, config, templates), push immediately after that step completes.**

- Do NOT accumulate changes until task end — push per step
- 1 step = 1 commit + 1 push
- Changes not pushed are invisible to others and cannot be deployed or reviewed

```bash
git add {changed files}
git commit -m "{message per 11_structured_commit.md}"
git push
```

## KARPATHY BEHAVIORAL GUIDELINES
Follow `.agent/rules/10_karpathy_guidelines.md` for all coding tasks:
1. **Think Before Coding** — State assumptions explicitly. Ask if uncertain. Surface tradeoffs.
2. **Simplicity First** — Minimum code that solves the problem. Nothing speculative.
3. **Surgical Changes** — Touch only what you must. Don't improve unrelated code.
4. **Goal-Driven Execution** — Define success criteria. Loop until verified.

## CONTEXT
The full agent context is stored in the `.agent` directory. Always check there for project-specific conventions.
