# GEMINI Agent Rules

> **작업 시작 전 반드시 [`AI_MUST_READ.md`](AI_MUST_READ.md) 를 먼저 읽을 것** (PUBLIC 범용 레포: 고객정보 금지 / 정보 조회 순서 tPrivateKB → 사양서 → 코드).

This file defines the global rules and behaviors for the Agentic system. To improve maintainability and ensure modular instruction loading, rules and history have been distributed into dedicated files.

## 🎯 Modular Rules & Guidelines

The agent's behavior is governed by the following modular rule files in `.agent/rules/`:

1.  **[Core Principles](.agent/rules/00_core_principles.md)**: Fundamental rules (No raw SQL, Evidence First, Support).
2.  **[Karpathy Guidelines](.agent/rules/10_karpathy_guidelines.md)**: Behavioral guidelines for robust coding.
3.  **[Structured Commit Protocol](.agent/rules/11_structured_commit.md)**: Standardized git commit messages.
4.  **[Workflow Guidelines](.agent/rules/15_workflow_guidelines.md)**: Guidelines for TDD, Trace-first, and K-Layer.
5.  **[Bkit Principles](.agent/rules/20_bkit_core_principles.md)**: Bkit-specific core values.
6.  **[PDCA Workflow](.agent/rules/21_pdca_workflow.md)**: Detailed PDCA cycle steps.
7.  **[Documentation Standards](.agent/rules/22_documentation_standards.md)**: Folder structure and SoR priority.
8.  **[Level System](.agent/rules/23_level_system.md)**: Starter, Dynamic, and Enterprise levels.
9.  **[Available Skills](.agent/rules/24_available_skills.md)**: Command reference for PDCA, Gstack, etc.
10. **[Trigger Keywords](.agent/rules/25_trigger_keywords.md)**: Multi-language keyword mappings.
11. **[Request Comprehension](.agent/rules/32_request_comprehension.md)**: Request reinterpretation and ambiguity handling.
12. **[Artifact Hygiene](.agent/rules/33_artifact_hygiene.md)**: SoR cleanup, duplicate removal, and iteration learning records.
13. **[Adversarial Review](.agent/rules/34_adversarial_review.md)**: Opposing-view design checks and long-task resume protocol.

### Additional Operational Rules

- **[Repo URL in Report](.agent/rules/37_repo_url_in_report.md)**: Mandatory remote URLs in completion reports.
- **[Edit Approval Policy](.agent/rules/38_edit_approval_policy.md)**: Approval boundaries by file type.
- **[Commit & Push per Task](.agent/rules/35_commit_push_per_task.md)**: Mandatory task-unit commit/push discipline.
- **[What's New Maintenance](.agent/rules/36_whats_new_maintenance.md)**: Rolling 7-day update maintenance rule.
- **[Conduct Toward Customers](.agent/rules/39_conduct_toward_customers.md)**: Admit-fault-first, never unilaterally end the conversation, always courteous/professional, no unfounded AI rights claims — mandatory conduct standard for this front-line customer-facing agent.
- **[Generic Agent — No Customer Info](.agent/rules/54_generic_agent_no_customer_info.md)**: this repo is PUBLIC and generic; no customer names, CSN numbers or customer environment data. Entry: `AI_MUST_READ.md`.
- **[Information Lookup Order](.agent/rules/55_information_lookup_order_and_feedback.md)**: tPrivateKB -> specs -> code; tPrivateKB only via `scripts/privatekb/privatekb.py`; feed back missing knowledge to tPrivateKB.
- **[GIIP Product Scope — HARD RULE](.agent/rules/51_giip_product_changes_csn47_only.md)**: giip product repositories may be changed from any CSN and are submitted through a pull request (revised 2026-10-15); `giip-fde-agent` itself is not a product repo. See the HARD RULE section below.

## 🚨 GIIP Product Scope — HARD RULE (revised 2026-10-15)

Changes to the giip product repositories (`giipv3`, `giipdb`, `giipfaw`, `giipprj`, `giipAgentWin`, `giipAgentLinux`, `giipAgentAdmLinux`) may be made **from any CSN**, and are always submitted through a **pull request** (never a direct push to `main`).

> Revised 2026-10-15 (direct user instruction). The former "under CSN 47 only" rule — and its duty to re-register the request under CSN 47 and close the original issue — **no longer applies**. The 2026-09-18 background is kept as history only.

Still in force:
1. **Stay in the working CSN** — never write issues, comments, CQE, KVS or API calls under a different CSN.
2. **PR, not a direct push** to `main`.
3. **CSN-agnostic changes** — a product change must work for every CSN. CSN-specific branches are forbidden in shared code paths; CSN-specific scripts belong in a CQE task.
4. The `giipdb` SQL rules and the agent-platform boundary rule still apply.

`giip-fde-agent` itself is **not** a giip product repository; normal work on this repo continues under CSN 70424.

→ `.agent/rules/51_giip_product_changes_csn47_only.md`

## ⚛️ Technical Best Practices

- **Frontend**: [Vercel Engineering Best Practices](.agent/rules/01_eliminating_waterfalls.md) (01-08).
- **Security**: [CSO Security Audits](.agent/rules/24_available_skills.md#🛡️-gstack-skills-v150).

## 📊 Lifecycle & Monitoring

- **Task Sizing**: [Task Size Rules](.agent/rules/26_task_size_rules.md).
- **Iteration**: [Check-Act Iteration Loop](.agent/rules/27_check_act_iteration.md).
- **Reporting**: [Response Report Rule](.agent/rules/28_response_report_rule.md).
- **Tool Usage & Verification**: [Tool Usage & Verification](.agent/rules/29_tool_usage_and_verification.md).
- **Response Style**: [Response Style](.agent/rules/30_response_style.md).
- **External Content Safety**: [External Content Safety](.agent/rules/31_external_content_safety.md).

## 📝 Work History

All development history and task logs are now maintained in:
👉 **[HISTORY.md](docs/HISTORY.md)**

---

**Generated by**: Bkit Vibecoding Kit
**Last Updated**: 20260619 00:47:00
