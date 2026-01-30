# .gemini Directory Documentation

This directory contains configurations and extensions for the Gemini Agent environment.

## bkit Vibecoding Kit Integration

The `bkit` Vibecoding Kit (v1.4.7) has been integrated to enhance the development workflow using the **PDCA (Plan-Design-Do-Check-Act)** methodology.

### Key Components

- **Extensions**: Located in `./extensions/bkit/`.
- **Skills**: Integrated through `GEMINI.md` and `.agent/skills/`.
- **Hooks**: Enabled in `C:\Users\lowys\.gemini\settings.json`.

### Usage Guide

#### 1. PDCA Workflow
Follow these phases for feature development and bug fixes:

- **Plan**: Analyze requirements and create a plan.
  - Command: `/pdca plan {feature_name}`
- **Design**: Create technical specifications.
  - Command: `/pdca design {feature_name}`
- **Do**: Implement the changes.
- **Check**: Perform gap analysis.
  - Command: `/pdca analyze {feature_name}`
- **Act**: Iterate on findings or report completion.
  - Command: `/pdca iterate` or `/pdca report`

#### 2. Automatic Reporting
Every response now includes a mandatory **bkit Feature Usage** report at the end. This report tracks which `bkit` features were utilized and provides recommendations for next steps.

### Important Rules
- **No Guessing**: Always refer to the codebase or documentation.
- **Evidence First**: All technical claims must be backed by evidence (logs, code snippets, etc.).
- **Doc Language**: All artifacts and documentation MUST be in **Korean**.

---
📊 bkit Feature Usage
✅ Used: bkit-rules, Documentation
⏭️ Not Used: /pdca commands (Documentation update only)
💡 Recommended: Refer to `GEMINI.md` for full skill list.
