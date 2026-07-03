# giip FDE Agent — Ecosystem & Advanced Capabilities

> This document is split out from the [README](../readme_en.md).
> The README keeps only a summary; the detailed principles, commands, and links for each capability live here.

The giip FDE Agent is not just a collection of prompts — it's a consolidation of the essence of several proven frameworks into a single agent. Below are the core capabilities built into the agent.

---

## 1. Bkit Vibecoding Kit (PDCA)
- **Plan-Design-Do-Check-Act**: Ensures a 'thinking before making' process through Design and Analysis phases before implementation.
- **`/pdca` Commands**: Automates systematic reporting and gap analysis.

## 2. Superpowers Engineering
- **Subagent-Driven**: Decouples a single task into a pipeline of `Design` → `Implementation` → `Verification`.
- **Strong Skills**: Built-in TDD (Test Driven Development), Systematic Debugging, and Brainstorming skills.

## 3. Gstack (Safety & Security)
- **Founder Mode**: Challenges the essence of the product and UX via `/office-hours` and `/ceo-review`.
- **Guardrails**: Provides a safe development environment with warnings before destructive commands (`/careful`) and scope locking (`/freeze`).
- **Security Audit**: Performs STRIDE/OWASP-based security checks with the `/cso` command.

## 4. Native Optimization & Tracing
- **`/native-trace`**: Records all reasoning steps and tool invocation histories of the AI.
- **`/aioptimize`**: The agent automatically refines its own prompts based on collected data to become smarter.

## 5. K-Layer Knowledge System (Karpathy Diagram)
- **Source-linked Knowledge**: Automatically extracts and accumulates reusable patterns and lessons from agent history as `Claim` units.
- **Self-Reinforcement Loop**: Every piece of knowledge is linked to its original evidence (Trace/Source), allowing agents to act smarter in subsequent tasks by referring to it.
- [K-Layer Principles](../.agent/skills/k-layer/SKILL.md) | [Knowledge Base](../.agent/knowledge/README.md)

## 5-1. Andrej Karpathy Behavioral Guidelines
- **Think Before Coding**: State assumptions explicitly before implementing. Ask when uncertain. Present multiple interpretations instead of picking silently.
- **Simplicity First**: Write the minimum code that solves the problem. No speculative features, abstractions, or unrequested flexibility.
- **Surgical Changes**: Touch only what you must. Don't improve unrelated code, comments, or formatting.
- **Goal-Driven Execution**: Define verifiable success criteria before starting and loop until they are met.
- [Karpathy Guidelines](../.agent/rules/10_karpathy_guidelines.md) | [Original Repo](https://github.com/forrestchang/andrej-karpathy-skills)

## 6. Multi-Source Design Discovery (design-md)
- **Consolidated Scouting**: Integrates 4 major platforms (`designmd.ai`, `designmd.app`, `getdesign.md`, `designmd.me`) to scout the best design systems.
- **Brand Cloning & Auto-Generation**: Instantly transplant styles from famous brands (Stripe, Vercel) or auto-generate design markdown from any URL.
- [Design Discovery & Integration Guide](DESIGN_DISCOVERY_GUIDE.md)

## 7. Messenger Control (OpenClaw)
- **Remote Messenger Control**: Query repository info and give orders via Slack, Discord, or Telegram anytime, anywhere.
- **Agent in Your Pocket**: Access the project's knowledge base (K-Layer) from mobile for real-time Q&A.
- [OpenClaw Messenger Integration Guide](50-technical/openclaw-slack-integration_en.md)

## 8. Investment/Trading Integration (Vibe Investing)
- **Safe capability grafting**: Evaluate external investing repositories on 5 axes (activity, maturity, learning curve, market fit, license) and map them into GIIP role/rule/skill/workflow with minimal changes.
- **Risk-first checklist**: Enforce backtest-bias checks, execution realism (slippage/liquidity/fees), and regulation/cost guardrails by default.
- [Investment Skill](../.agent/skills/vibe-investing/SKILL.md) | [Investment Workflow](../.agent/workflows/investment-evaluation.md)

## 9. AI Agency Expert Team Integration (Agency-Agents)
- **Advanced Role System**: Built-in specialized expert personas like `Workflow Architect` (system path design) and `Korean Business Navigator` (specialized in Korean business).
- **Premium UI/UX**: Pursue high aesthetic quality (Glassmorphism, 60fps animations, etc.) through the `premium-ui-craft` skill.
- **Exhaustive Exception Design**: Prevent "workflows that exist in code but not in specs" via `workflow-mapping` and define all failure recovery paths in advance.

## 10. Codex Performance Maintenance (keep-codex-fast)
- **Prevent Codex Slowdowns**: When old chats, worktrees, logs, and project references accumulate and Codex starts feeling heavy, safely inspect and clean up local state.
- **Handoffs-First Principle**: Always create handoff documents before archiving to preserve work context.
- **Periodic Maintenance**: Automatic weekly/biweekly inspection reminders — applies only after user approval.
- [keep-codex-fast Skill](../.agent/skills/keep-codex-fast/SKILL.md) | [Maintenance Workflow](../.agent/workflows/codex-maintenance.md) | [Codex Tool Guide](04-tools/codex.md)

---

## 📂 System Architecture
Detailed guides for the four core components that make up the FDE Agent.

- [**Components Overview**](02-design/agent-components/overview.md)
- [**Roles**](02-design/agent-components/role.md): Define persona and scope of responsibility
- [**Rules**](02-design/agent-components/rule.md): Enforced guidelines and quality control
- [**Skills**](02-design/agent-components/skill.md): Specialized knowledge and tool packages
- [**Workflows**](02-design/agent-components/workflow.md): Complex procedures and custom commands

---

## 🧭 AI-Native Operations Starter Pack
- [90-min onboarding paths](00-onboarding/README.md) (Beginner / Team Lead / Ops)
- [Operations KPI standard](60-operations/ai-native-kpi.md) + [weekly KPI template](../.agent/templates/weekly-kpi-report.template.md)
- [Human approval gate workflow](../.agent/workflows/human-approval-gate.md)
- [Incident + rollback playbook](60-operations/incident-rollback-playbook.md)
- [Skill/Role operational metadata schema](../.agent/templates/shared/operational-metadata-schema.md)
