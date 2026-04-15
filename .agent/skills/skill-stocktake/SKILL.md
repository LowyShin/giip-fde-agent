---
name: skill-stocktake
description: Self-audits the agent's skills folder to ensure metadata completeness, valid frontmatter, and current documentation.
triggers: skill-stocktake, 스킬 점검, 스킬 상태 확인, audit skills
---

# skill-stocktake Skill

This skill allows the agent to audit its own internal knowledge base and skill directory.

## 🛠️ Usage

Trigger this whenever new skills are added or when the system behavior feels outdated.

### Audit Checklist

1.  **Frontmatter Check**: Verify each `SKILL.md` contains the mandatory fields: `name`, `description`, `triggers`.
2.  **Documentation Coverage**: Ensure each skill has a clear description of its purpose and usage examples.
3.  **Cross-linking**: Verify that all skills are correctly listed in the project's root `README.md` or `GEMINI.md`.
4.  **Stub Detection**: Find any "TODO" or placeholder skills that need implementation.

## 💻 Implementation Protocol

1.  **List Skills**: Use `list_dir` to find all subdirectories in `.agent/skills/`.
2.  **Read Content**: Use `view_file` to inspect the `SKILL.md` of each folder.
3.  **Analyze**: Check for frontmatter validity and completeness.
4.  **Report**: Generate a "Skill Health Report" highlighting any gaps.

## 🛡️ Response Actions

If a skill is found to be deficient:
1.  **Flag**: Mark it for a subsequent `pdca iterate` pass.
2.  **Repair**: If the fix is minor (e.g., missing trigger), propose an immediate update.
