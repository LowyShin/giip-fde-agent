---
description: 외부 저장소에서 새로운 Gemini 스킬을 감지하고 에이전트에 통합합니다.
---

# Custom Workflow: /gaupdate

This workflow monitors specified repositories for new or updated Gemini skills and integrates them into the agent.

## Workflow Steps

1. **Read Configuration**: Load the list of source URLs from `.agent/config/update_urls.json`.
2. **Analyze Knowledge Context**: Read `.agent/knowledge/notes/*.md` to extract the current project's technology stack, active issues, and business domains (K-Layer Context).
3. **Scan & Filter Repositories**:
   - For each URL, use `browser_subagent` to check for new or updated roles, rules, skills, and workflows.
   - **Matching Rule**: Cross-reference the features with the K-Layer Context. Prioritize and select only those that:
     - Match the tech stack (e.g., Next.js, PowerShell, Azure).
     - Address documented pain points or recurring bugs in K-Layer claims.
     - Support the business domain (e.g., Investment, Business Navigation).
4. **Download & Integrate**:
   - Fetch the selected features and their associated files.
   - Save roles to `.agent/roles/`, skills to `.agent/skills/`, and rules to `.agent/rules/`.
5. **Update Registry**:
   - Update `lastUpdate` timestamp in `update_urls.json`.
6. **Summarize**:
   - Report the new capabilities added and explain how they align with the current K-Layer knowledge base.

## Trigger
Use the slash command: `/gaupdate`
