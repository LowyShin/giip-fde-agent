---
name: retro
description: |
  Post-task retrospective and learning extraction skill.
  Inspired by gstack's /retro and integrated with K-Layer.
  Use this after completing a significant task or resolving a complex issue
  to document lessons learned and improve future performance.

  Triggers: retro, retrospective, post-mortem, lessons learned, 회고, 사후 분석, 振り返り
---

# Retro Skill

The `retro` skill helps you reflect on a completed task to extract valuable insights and prevent future mistakes.

## Workflow

1.  **Summary**: Briefly summarize the completed task.
2.  **What went well**: List the successful aspects of the implementation.
3.  **What could be improved**: Identify pain points, bottlenecks, or mistakes.
4.  **Lessons Learned**: Extract actionable advice for future tasks.
5.  **K-Layer Integration**: Automatically convert lessons into "Source-linked claims" for the Knowledge Layer.

## Usage

```bash
/retro [task-id or feature-name]
```

## Template

The retrospective should follow this structure:

### 📝 Task Retrospective: [Feature Name]
- **Completion Date**: YYYY-MM-DD
- **Related Task/Issue**: [Link]

#### 🚀 Successes
- [Item 1]
- [Item 2]

#### ⚠️ Challenges & Mistakes
- [Problem 1]: [Root Cause]
- [Problem 2]: [Root Cause]

#### 💡 Key Lessons
- [Lesson 1] -> [Action for next time]
- [Lesson 2] -> [Action for next time]

#### 🧠 K-Layer Claims
- [Claim 1]: [Source Reference]
- [Claim 2]: [Source Reference]
