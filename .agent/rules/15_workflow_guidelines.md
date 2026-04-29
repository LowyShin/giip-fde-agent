# Workflow & Skills Guidelines

Agents MUST use the specialized skills in `.agent/skills/` for complex engineering tasks to ensure quality and reliability.

## 🛠️ Key Workflows

1.  **Subagent Driven Development**: For implementing complex features, break down tasks and use the `subagent-driven-development` skill. This enforces a "Spec Review -> Code Review" pipeline.
2.  **Writing Plans**: Before writing code, ALWAYS create an implementation plan using the `writing-plans` skill.
3.  **Test Driven Development**: Follow the TDD cycle (Red-Green-Refactor) as defined in `test-driven-development` skill.
4.  **Systematic Debugging**: For tough bugs, use the `systematic-debugging` skill to find the root cause, not just patch symptoms.
5.  **Trace-First Operating Procedure**: For all complex coding, architectural changes, or new feature implementations, **ALWAYS** initiate the task with the `/native-trace` command to enable execution logging and automated prompt optimization via `/aioptimize`.
6.  **K-Layer Knowledge Loop**: 작업 시 습득한 새로운 지식이나 교훈은 `k-layer` 스킬을 통해 `.agent/knowledge/notes/`에 claim으로 추가한다. 동일한 지식이나 패턴이 2회 이상 발견될 때 위키화를 수행한다. (상세: `.agent/skills/k-layer/SKILL.md`)
