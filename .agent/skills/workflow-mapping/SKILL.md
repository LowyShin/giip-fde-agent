# Skill: Workflow Mapping

This skill provides the methodology for exhaustive system path discovery and specification. It ensures that before implementation, every possible branch is accounted for.

## 💡 When to use
- Before implementing a new feature or complex API.
- When refactoring legacy code with unclear logic.
- When designing system-to-system integrations.

## 🛠️ Step-by-Step Methodology

### 1. Discovery Pass (Scouting)
Identify all entry points and state transitions in the existing codebase:
- **Routes**: Search for API endpoint definitions.
- **Workers**: Locate background job processors.
- **Migrations**: Analyze DB schema changes as they imply lifecycles.
- **States**: Search for status/state transition logic (e.g., `status = '...'`).

### 2. Map the Workflow Tree
Create a structured document (`WORKFLOW-[name].md`) covering:
- **Happy Path**: The successful end-to-end case.
- **Branches**: Every "what if" scenario (timeout, validation error, conflict).
- **Contracts**: Explicit payload and response schemas for every handoff.

### 3. Cleanup Inventory
List every resource created during the workflow that must be destroyed on failure to prevent orphans (DB records, files, cloud resources).

### 4. Test Case Derivation
Every branch in the tree must correspond to exactly one test case.

## 📄 Template: WORKFLOW-spec.md
```markdown
# WORKFLOW: [Name]
**Status**: Draft | Approved

## Overview
[Description]

## Workflow Tree
### STEP 1: [Action]
- **Success**: Go to Step 2
- **Failure (Timeout)**: Retry x2 -> ABORT_CLEANUP
- **Failure (Error)**: Return Error -> ABORT_CLEANUP

## Cleanup Inventory
| Resource | Destroy Method |
|---|---|
| ... | ... |
```

## 🔍 Discovery Commands
```powershell
# Find API routes
Select-String -Path "src\**\*.ts" -Pattern "router\.(post|put|get|delete)"
# Find state transitions
Select-String -Path "src\**\*.ts" -Pattern "status\s*="
```
