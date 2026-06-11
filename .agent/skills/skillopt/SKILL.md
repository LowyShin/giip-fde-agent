---
name: skillopt
description: |
  Bounded text-space gradient optimization for SKILL.md prompts using execution traces.
  Loads low-reward traces (reward < 0.8) from .agent/traces/, groups them by skill, and applies
  bounded edits (max 15% word change) with a Validation Gate to prevent destructive rewrites.
  Use when you want to run the SkillOpt algorithm to automatically improve skill prompts,
  or when a skill repeatedly underperforms and you want a systematic text-space optimization pass.
  Triggers: skillopt, skill optimization, bounded edits, prompt gradient, validation gate, improve skill
---

# SkillOpt — Bounded Text-Space Skill Optimization

Runs the SkillOpt algorithm: loads low-reward execution traces, proposes bounded edits to the
responsible SKILL.md, and checks those edits through a Validation Gate before committing.

> [!IMPORTANT]
> Traces must already exist in `.agent/traces/` (collected via `/native-trace` or `trace-manager`).
> Without traces there is nothing to analyze.

## 1. Run the Optimizer

```powershell
# From the project root (WSL2 or PowerShell)
python giipdb/scripts/prompt_optimization/skillopt_optimizer.py
```

The script:
1. Reads all `*.json` files from `.agent/traces/`
2. Filters traces where `reward < 0.8`
3. Groups low-reward traces by `skill_used`
4. For each underperforming skill: proposes a bounded edit, runs the Validation Gate, and saves the
   result to `outputs/skillopt/best_<skill_name>.md` if the gate passes

## 2. Bounded Edit Budget

The optimizer enforces a **learning-rate budget** of max 15% word change (minimum 20 words).
If the proposed edit exceeds this budget the Validation Gate rejects it automatically.

This prevents catastrophic rewrites — only targeted, surgical improvements survive.

## 3. Validation Gate

After each candidate edit the gate checks:
- **Edit size**: rejects if word-change count > budget
- **Issue resolution**: verifies that feedback keywords from failed traces now appear in the
  candidate (simulated pass/fail — real deployments replace this with an actual agent re-run)

A `[✓] Validation Gate PASSED` message means the artifact is deployable.

## 4. Apply the Optimized Skill

When the gate passes, the deployable artifact is at:
```
outputs/skillopt/best_<skill_name>.md
```

Review the diff, then overwrite the original:
```powershell
Copy-Item "outputs/skillopt/best_<skill_name>.md" ".agent/skills/<skill_name>/SKILL.md"
```

## 5. Verify

Re-run the task that previously scored low and collect a new trace. The new reward should be ≥ 0.8.
If not, repeat the optimization loop.

## Related Skills

- [[trace-manager]] — record traces and assign reward scores
- [[native-trace]] — `/native-trace` workflow for capturing execution data
- [[aioptimize]] — AI-assisted prompt optimization using the same trace data
- [[skill-creator]] — create or fully rewrite a skill from scratch

## ⚡ Optimization Integration

When using this skill for critical tasks, run it within a `/native-trace` context to capture
performance data for self-improvement via `/aioptimize`.
