---
description: Execute a task with automatic trace logging for optimized AI performance.
---

# /native-trace Workflow

This workflow executes an AI task while recording every step for later analysis and optimization.

## 1. Setup Logging
Ensure the `.agent/traces/` directory exists.

## 2. Execute Task
Start the task using the relevant skills.
For each tool call:
- Record the input and output.
- Record the reasoning behind it.

## 3. Award Reward Score
At the end of the task, the user provides a "Reward Score" (0.0 to 1.0) and optional feedback.
- **1.0**: Success, no improvement needed.
- **< 0.8**: Ready for `/aioptimize`.

## 4. Finalize Trace
Save all steps and the reward to a JSON file: `.agent/traces/YYYYMMDDHHMMSS_task.json`.
