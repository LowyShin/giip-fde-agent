---
name: trace-manager
description: Record, read, and manage execution traces for agent optimization. Use this skill whenever a task is explicitly marked as "traced" or when you want to collect performance data for later prompt optimization (APO).
---

# Trace Manager

A skill for recording agent execution steps (traces) to support "Native Agent Optimization".

## Tracing Process

### 1. Initialize Trace
At the beginning of a traced task, create a new trace ID: `YYYYMMDDHHMMSS_task_name`.

### 2. Record Step
For each significant tool call or decision point, record a "step" in the trace JSON:
- `timestamp`: Current time.
- `action`: Tool name or logic step.
- `input`: Arguments passed to the tool.
- `output`: Result from the tool (truncated if too large).
- `reasoning`: Brief explanation of *why* this step was taken.

### 3. Collect Reward
When the task is complete, request a "Reward Score" (0.0 to 1.0) from the user or evaluate it based on the success criteria.
- **1.0**: Perfect execution.
- **0.0 - 0.7**: Needs optimization.

### 4. Save Trace
Save the final trace to `.agent/traces/<trace_id>.json`.

## Trace Format (JSON)

```json
{
  "trace_id": "20260403233435_example_task",
  "skill_used": "skill-name",
  "task": "Task description from user",
  "steps": [
    {
      "timestamp": "2026-04-03T23:34:40",
      "action": "run_command",
      "input": "ls -la",
      "output": "file1, file2...",
      "reasoning": "Checking directory content to identify target files."
    }
  ],
  "reward": 0.9,
  "feedback": "User feedback if any"
}
```

## When to use this skill
- Use this when the user triggers the `/native-trace` workflow.
- Use this when you are working on a critical skill that needs refinement.


## ⚡ Optimization Integration
When using this skill for critical tasks, please run it within a /native-trace context to capture performance data for self-improvement via /aioptimize.

