# Workflow & Skills Guidelines

Agents MUST use the specialized skills in `.agent/skills/` for complex engineering tasks to ensure quality and reliability.

## 🛠️ Key Workflows

1.  **Subagent Driven Development**: For implementing complex features, break down tasks and use the `subagent-driven-development` skill. This enforces a "Spec Review -> Code Review" pipeline.
2.  **Writing Plans**: Before writing code, ALWAYS create an implementation plan using the `writing-plans` skill.
3.  **Test Driven Development**: Follow the TDD cycle (Red-Green-Refactor) as defined in `test-driven-development` skill.
4.  **Systematic Debugging**: For tough bugs, use the `systematic-debugging` skill to find the root cause, not just patch symptoms.
5.  **Trace-First Operating Procedure**: For all complex coding, architectural changes, or new feature implementations, **ALWAYS** initiate the task with the `/native-trace` command to enable execution logging and automated prompt optimization via `/aioptimize`.
6.  **K-Layer Knowledge Loop**: 작업 시 습득한 새로운 지식이나 교훈은 `k-layer` 스킬을 통해 `.agent/knowledge/notes/`에 claim으로 추가한다. 동일한 지식이나 패턴이 2회 이상 발견될 때 위키화를 수행한다. (상세: `.agent/skills/k-layer/SKILL.md`)
7.  **Workflow Mapping**: Before implementing complex logic, use the `workflow-mapping` skill to map all paths (happy paths, branches, recovery). "A workflow that exists in code but not in a spec is a liability."
8.  **Premium Craftsmanship**: When building user-facing components, use the `premium-ui-craft` skill to ensure high-quality aesthetics, smooth animations, and interactive excellence.
9.  **Knowledge-Based Updates**: When running `/gaupdate`, agents MUST first analyze the K-Layer knowledge base to ensure external roles, rules, or skills are relevant to the current project's context and technical needs.

## Task File Rules

> **PROHIBITED**: Do NOT add `## Estimated Time` (予想所要時間 / 예상 소요 시간) sections to task files.
> Time estimates are inaccurate and create confusion. Omit entirely.

> **MANDATORY — Immediate push after source code changes**:
> When source code (application code, config files, templates) is modified, run `git add → commit → push` immediately after that step.
> Do NOT defer pushes until task completion. Unpushed changes are invisible to others and cannot be deployed or reviewed.
