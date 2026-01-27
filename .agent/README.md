# GIIP Agent System Guide

This directory contains the definitions and tools for the GIIP AI Agent system.

## 🚀 Quick Start
To launch the next pending task automatically:
```powershell
.\.agent\scripts\launch_subsession.ps1
```
This script will automatically detect the **next pending task**, identify the **required role**, and launch a `gemini-cli` session with the correct context.

## 📁 Directory Structure
- `roles/`: Markdown files defining the persona and responsibilities of each agent (Developer, Error Analyst, etc.).
- `dispatch/`: Task definition files. New tasks are created here as `TASK_YYYYMMDD-ID.md`.
- `scripts/`:
  - `launch_subsession.ps1`: The primary tool for starting automated sub-sessions.
  - `check_status.ps1`: Check the current status of all tasks.
  - `launch_role.ps1`: Legacy tool for manual clipboard-based handoff.

## 🚨 Core Rules (Enforced by GEMINI.md)
Any session started via `gemini-cli` (including sub-sessions) automatically inherits rules from `[GEMINI.md](../GEMINI.md)`:
1.  **Strict Rule #1**: No raw SQL (`Invoke-Sqlcmd`). Use `mgmt/execSQLFile.ps1`.
2.  **Evidence First**: Always link technical evidence as markdown files.
3.  **Script Reuse**: Check `giipdb/mgmt/scriptlist.md` before writing new scripts.

## 📊 Monitoring Sub-Sessions
To check the current status of all tasks and background sessions:
```powershell
.\.agent\scripts\check_status.ps1
```
This will display:
- **Logical Status**: The current state (Pending, In Progress, Completed) as recorded in the dispatch files.
- **Background Processes**: Any running `gemini-cli` instances acting as sub-sessions.

## 🔄 Agent Workflow
1.  **Orchestrator** receives a request and creates a **Dispatch Task**.
2.  **Orchestrator** (or User) runs `launch_subsession.ps1`.
3.  The **Sub-Agent** (e.g., Developer) completes the work and updates the task status to `Completed`.
4.  **Orchestrator** verifies and moves to the next task in the queue.
