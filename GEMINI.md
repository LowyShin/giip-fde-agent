# GEMINI Agent Rules

This file defines the global rules and behaviors for the GIIP Agent system. All agents (sub-sessions) must adhere to these guidelines.

## 📜 Core Principles
1.  **Strict Rule #1**: No raw SQL (`Invoke-Sqlcmd`). Use `mgmt/execSQLFile.ps1`.
2.  **Evidence First**: Always link technical evidence as markdown files.
- 20260129 19:10:00: Completed RCA analysis for `pApiGiipIssueListbyAK` and `giip-issues` functionality. Generated RCA report `ANALYSIS_20260129_GIIP_ISSUE_LIST_RCA.md` in `giipdb/docs/50_Analysis/`.
- 20260130 11:34:00: Started README translation task (English and Japanese versions).
- 20260130 11:38:00: Completed README translation task. Created `readme_en.md` and `readme_jp.md` with cross-language links.

- 20260130 19:12:00: Initialized bkit Vibecoding Kit integration. Updated GEMINI.md and enabled hooks.

## 🏗️ React & Next.js Best Practices
Agents working on frontend code must follow the Vercel Engineering Best Practices defined in `.agent/rules/`.

- **Waterfalls**: Eliminate sequential awaits. Use `Promise.all` or `better-all`.
- **Bundle Size**: Avoid barrel file imports. Use dynamic imports for heavy components.
- **Server Actions**: Minimize serialization at RSC boundaries.
- **Data Fetching**: Use SWR for client-side caching and deduplication.
- **Rendering**: Optimize re-renders with proper composition and state management.

See [.agent/rules/](../.agent/rules/) for detailed guidelines.

## 🛠️ Workflow & Skills
Agents MUST use the specialized skills in `.agent/skills/` for complex engineering tasks to ensure quality and reliability.

1.  **Subagent Driven Development**: For implementing complex features, break down tasks and use the `subagent-driven-development` skill. This enforces a "Spec Review -> Code Review" pipeline.
2.  **Writing Plans**: Before writing code, ALWAYS create an implementation plan using the `writing-plans` skill.
3.  **Test Driven Development**: Follow the TDD cycle (Red-Green-Refactor) as defined in `test-driven-development` skill.
4.  **Systematic Debugging**: For tough bugs, use the `systematic-debugging` skill to find the root cause, not just patch symptoms.

---

---

# bkit Vibecoding Kit for Gemini CLI

> AI-Native Development with PDCA Methodology
> Version: 1.4.7

## Core Principles

### 1. Automation First, Commands are Shortcuts
```
Gemini automatically applies PDCA methodology.
Commands are shortcuts for power users.
```

### 2. SoR (Single Source of Truth) Priority
```
1st: Codebase (actual working code)
2nd: GEMINI.md / Convention docs
3rd: docs/ design documents
```

### 3. No Guessing
```
Unknown → Check documentation
Not in docs → Ask user
Never guess
```

## PDCA Workflow

### Phase 1: Plan
- Use `/pdca plan {feature}` to create plan document
- Stored in `docs/01-plan/features/{feature}.plan.md`

### Phase 2: Design
- Use `/pdca design {feature}` to create design document
- Stored in `docs/02-design/features/{feature}.design.md`

### Phase 3: Do (Implementation)
- Use `/pdca do {feature}` for implementation guide
- Implement based on design document
- Apply coding conventions from this file

### Phase 4: Check
- Use `/pdca analyze {feature}` for gap analysis
- Stored in `docs/03-analysis/{feature}.analysis.md`

### Phase 5: Act
- Use `/pdca iterate {feature}` for auto-fix if < 90%
- Use `/pdca report {feature}` for completion report

## Level System

### Starter (Basic)
- Static websites, simple apps
- HTML/CSS/JavaScript, Next.js basics
- Friendly explanations, step-by-step guidance

### Dynamic (Intermediate)
- Fullstack apps with BaaS
- Authentication, database, API integration
- Technical but clear explanations

### Enterprise (Advanced)
- Microservices, Kubernetes, Terraform
- High traffic, high availability
- Concise, use technical terms

## Available Skills (v1.4.4)

### PDCA Skill (Unified)
| Command | Description |
|---------|-------------|
| `/pdca status` | Check current PDCA status |
| `/pdca plan {feature}` | Generate Plan document |
| `/pdca design {feature}` | Generate Design document |
| `/pdca do {feature}` | Implementation guide |
| `/pdca analyze {feature}` | Run Gap analysis |
| `/pdca iterate {feature}` | Auto-fix iteration loop |
| `/pdca report {feature}` | Generate completion report |
| `/pdca next` | Guide to next PDCA step |

### Level Skills
| Command | Description |
|---------|-------------|
| `/starter` | Initialize/guide Starter project |
| `/dynamic` | Initialize/guide Dynamic project |
| `/enterprise` | Initialize/guide Enterprise project |

### Pipeline Skills
| Command | Description |
|---------|-------------|
| `/development-pipeline start` | Start development pipeline guide |
| `/development-pipeline status` | Check pipeline progress |
| `/development-pipeline next` | Guide to next pipeline phase |

### Utility Skills
| Command | Description |
|---------|-------------|
| `/zero-script-qa` | Run Zero Script QA |
| `/claude-code-learning` | Claude Code learning guide |
| `/code-review` | Code review and quality analysis |

## Trigger Keywords (8 Languages)

When user mentions these keywords, consider using corresponding skills:

### Gap Analysis
| Language | Keywords |
|----------|----------|
| EN | gap analysis, verify, check |
| KO | 갭 분석, 검증, 확인 |
| JA | ギャップ分析, 検証, 確認 |
| ZH | 差距分析, 验证, 确认 |
| ES | análisis de brechas, verificar |
| FR | analyse des écarts, vérifier |
| DE | Lückenanalyse, verifizieren |
| IT | analisi dei gap, verificare |

### Auto-fix Iteration
| Language | Keywords |
|----------|----------|
| EN | iterate, improve, fix |
| KO | 개선, 고쳐, 반복 |
| JA | 改善, イテレーション, 修正 |
| ZH | 改进, 迭代, 修复 |
| ES | mejorar, arreglar, iterar |
| FR | améliorer, corriger, itérer |
| DE | verbessern, reparieren, iterieren |
| IT | migliorare, correggere, iterare |

### Code Quality Analysis
| Language | Keywords |
|----------|----------|
| EN | analyze, quality, review |
| KO | 분석, 품질, 리뷰 |
| JA | 分析, 品質, レビュー |
| ZH | 分析, 质量, 审查 |
| ES | analizar, calidad, revisar |
| FR | analyser, qualité, réviser |
| DE | analysieren, Qualität, überprüfen |
| IT | analizzare, qualità, revisione |

### Generate Report
| Language | Keywords |
|----------|----------|
| EN | report, summary |
| KO | 보고서, 요약 |
| JA | 報告, サマリー |
| ZH | 报告, 摘要 |
| ES | informe, resumen |
| FR | rapport, résumé |
| DE | Bericht, Zusammenfassung |
| IT | rapporto, riepilogo |

### Zero Script QA
| Language | Keywords |
|----------|----------|
| EN | QA, test, log |
| KO | 테스트, 로그 |
| JA | テスト, ログ |
| ZH | 测试, 日志 |
| ES | prueba, registro |
| FR | test, journal |
| DE | Test, Protokoll |
| IT | test, registro |

### Design Validation
| Language | Keywords |
|----------|----------|
| EN | design, spec |
| KO | 설계, 스펙 |
| JA | 設計, スペック |
| ZH | 设计, 规格 |
| ES | diseño, especificación |
| FR | conception, spécification |
| DE | Design, Spezifikation |
| IT | design, specifica |

## Task Size Rules

| Size | Lines | PDCA Level | Action |
|------|-------|------------|--------|
| Quick Fix | <10 | None | No guidance needed |
| Minor Change | <50 | Light | "PDCA optional" mention |
| Feature | <200 | Recommended | Design doc recommended |
| Major Feature | >=200 | Required | Design doc strongly recommended |

## Check-Act Iteration Loop

```
gap-detector (Check) → Check Match Rate
    ├── >= 90% → report-generator (Complete)
    ├── 70-89% → Offer choice (manual/auto)
    └── < 70% → Recommend pdca-iterator (Act)
                   ↓
              Re-run gap-detector after fixes
                   ↓
              Repeat (max 5 iterations)
```

## Response Report Rule (v1.4.1)

**Include bkit feature usage report at the end of every response.**

### Report Format

```
─────────────────────────────────────────────────
📊 bkit Feature Usage
─────────────────────────────────────────────────
✅ Used: [bkit features used in this response]
⏭️ Not Used: [major unused features] (reason)
💡 Recommended: [features suitable for next task]
─────────────────────────────────────────────────
```

---

**Generated by**: bkit Vibecoding Kit
**Template Version**: 1.4.4 (Skills Integration + Unified Hooks)
