# Plan: Custom Workflow Centralization

## Goal
Centralize the management and documentation of custom workflows in `giipdb/docs/CUSTOM_WORKFLOWS.md` and automate its updates.

## Background
Currently, custom workflows are scattered across `.agent/workflows/` and documentation like `GEMINI.md`. There is no single place where all available workflows are listed and explained.

## Technical Requirements
1. **Central Registry**: Create `giipdb/docs/CUSTOM_WORKFLOWS.md`.
2. **Automation**: Update `/gaupdate` to synchronize workflow files with the documentation.
3. **Registry Script**: PowerShell script to generate markdown from workflow files.
4. **Agent Alignment**: Update `GEMINI.md` to point to the new registry.

## Timeline
1. Research (Completed)
2. Design & Implementation
3. Verification & Report
