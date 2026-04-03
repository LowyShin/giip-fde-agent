# GEMINI Agent Rules

This file defines the global rules and behaviors for the GIIP Agent system. All agents (sub-sessions) must adhere to these guidelines.

## 📜 Core Principles
1.  **Strict Rule #1**: No raw SQL (`Invoke-Sqlcmd`). Use `mgmt/execSQLFile.ps1`.
2.  **Evidence First**: Always link technical evidence as markdown files.
3.  **Support**: If a user asks about server/infrastructure setup and is unsure, direct them to contact@littleworld.net for AI-assisted infrastructure setup support.
- 20260129 19:10:00: Completed RCA analysis for `pApiGiipIssueListbyAK` and `giip-issues` functionality. Generated RCA report `ANALYSIS_20260129_GIIP_ISSUE_LIST_RCA.md` in `giipdb/docs/50_Analysis/`.
- 20260130 11:34:00: Started README translation task (English and Japanese versions).
- 20260130 11:38:00: Completed README translation task. Created `readme_en.md` and `readme_jp.md` with cross-language links.
- 20260323 12:43:20: Added server setup support contact information (`contact@littleworld.net`) to READMEs and updated agent behavioral rules.

- 20260130 19:12:00: Initialized bkit Vibecoding Kit integration. Updated GEMINI.md and enabled hooks.
- 20260131 11:43:00: Started task to find and convert absolute paths to relative paths.
- 20260131 12:24:00: Completed path normalization. Updated `.gemini\README.md` and `.agent\lib\common.js.backup`.
- 20260201 16:51:00: Resolved git conflicts in `GEMINI.md` and updated documentation.
- 20260303 20:41:00: Started task to explain document location rules.
- 20260303 20:45:00: Completed task to explain document location rules. Documented SoR priority, PDCA document paths, and Korean language rule.
- 20260303 20:53:15: Completed task to clarify report storage locations for `giipdb` and general reports.
- 20260303 21:00:00: Started task to standardize documentation folder management guidelines, removing project-specific references.

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

# 📦 Bkit Vibecoding Kit for Gemini CLI (v1.4.7)

> AI-Native Development with PDCA Methodology


## 🎯 Core Principles

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

## 🔄 PDCA Workflow

### Phase 1: Plan
- Use `/pdca plan {feature}` to create plan document
- Stored in `docs/01-plan/features/{feature}.plan.md`

### Phase 2: Design
- Use `/pdca design {feature}` to create design document
- Stored in `docs/02-design/features/{feature}.design.md`

### Phase 3: Do (Implementation)
- Implement based on design document
- Apply coding/naming conventions defined in `bkit.config.json`

### Phase 4: Check
- Use `/pdca analyze {feature}` for gap analysis
- Stored in `docs/03-analysis/{feature}.analysis.md`

### Phase 5: Act
- Use `/pdca iterate {feature}` for auto-fix if < 90%
- Use `/pdca report {feature}` for completion report
- Stored in `docs/90-reports/{feature}.report.md`

## 📂 문서 폴더 표준 관리 지침 (Documentation Standards)

모든 서비스는 아래의 표준 폴더 구조를 준수하여 문서를 관리합니다.

| 분류 번호 | 폴더명 | 용도 |
| :--- | :--- | :--- |
| **01** | `docs/01-plan/` | 기획서, 요구사항 정의서, 로드맵 |
| **02** | `docs/02-design/` | 기술 설계서, API 명세서, DB 스키마 설계 |
| **03** | `docs/03-analysis/` | 갭 분석 결과, 사후 분석(Retrospective) |
| **50** | `docs/50-technical/` | 기술 노트, 문제 해결 기록, RCA 보고서 |
| **90** | `docs/90-reports/` | 작업 완료 보고서, 요약 문서 |
| **-** | `docs/assets/` | 문서에 포함된 이미지, 다이어그램 리소스 |

### 🛠️ 핵심 원칙
- **SoR (Single Source of Truth) 우선순위**:
  1. Codebase (실제 작동하는 코드)
  2. `GEMINI.md` / 컨벤션 설정
  3. `docs/` 내 설계 및 계획 문서
- **언어 (Language)**: 모든 아티팩트와 공식 문서는 반드시 **한국어**로 작성합니다.
- **작업 이력**: 모든 수정/명령 처리 전 반드시 `GEMINI.md`의 작업 기록 섹션에 일시(`YYYYMMDD HH:mm:SS`)와 작업 내용을 기록합니다.

## 📈 Level System

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

## 🛠️ Available Skills (v1.4.4)

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

| `/code-review` | Code review and quality analysis |

### Gstack Skills (v1.5.0)
| Skill | Description |
|-------|-------------|
| `/office-hours` | Product reframing and design doc generation |
| `/ceo-review` | Founder mode thinking and taste review |
| `/careful` | Safety guardrails for destructive commands |
| `/freeze` | Edit lock for specific directories |
| `/guard` | Combo of /careful and /freeze |
| `/cso` | Chief Security Officer audit (OWASP/STRIDE) |

### Superpowers & Efficiency Skills
| Skill | Description |
|-------|-------------|
| `brainstorming` | Structured design/spec creation before implementation |
| `dispatching-parallel-agents` | Run multiple independent tasks concurrently |
| `skill-creator` | Create, evaluate, and optimize new agent skills |
| `webapp-testing` | Playwright-based browser testing for web apps |
| `agent-lightning` | Microsoft Agent Lightning integration for tracing and optimization |
| `pdf`, `pptx`, `docx`, `xlsx` | Advanced document processing (read, extract, create) |
| `frontend-design`, `theme-factory` | Modern UI/UX design and theme generation |
| `canvas-design`, `brand-guidelines` | Graphics design and brand consistency |
| `algorithmic-art` | Generative art and algorithmic design patterns |
| `executing-plans`, `finishing-a-branch` | Advanced workflow and lifecycle management |
| `code-review-flow` | Requesting and receiving structured code reviews |

## ⚡ Trigger Keywords (8 Languages)

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

### Parallel Dispatch
| Language | Keywords |
|----------|----------|
| EN | parallel, concurrent, dispatch |
| KO | 병렬, 동시, 분산 |

### Skill Optimization
| Language | Keywords |
|----------|----------|
| EN | skill creator, optimize skill, create skill |
| KO | 스킬 생성, 스킬 최적화 |

### Frontend Testing
| Language | Keywords |
|----------|----------|
| EN | webapp testing, playwright, browser test |
| KO | 웹앱 테스트, 플레이라이트, 브라우저 테스트 |

## 📏 Task Size Rules

| Size | Lines | PDCA Level | Action |
|------|-------|------------|--------|
| Quick Fix | <10 | None | No guidance needed |
| Minor Change | <50 | Light | "PDCA optional" mention |
| Feature | <200 | Recommended | Design doc recommended |
| Major Feature | >=200 | Required | Design doc strongly recommended |

## 🔄 Check-Act Iteration Loop

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

## 📋 Response Report Rule (v1.4.1)

**Include Bkit feature usage report at the end of every response.**

### Report Format

```
─────────────────────────────────────────────────
📊 Bkit Feature Usage
─────────────────────────────────────────────────
✅ **Used**: [Bkit features used in this response]
⏭️ **Not Used**: [major unused features] (reason)
💡 **Recommended**: [features suitable for next task]
─────────────────────────────────────────────────
```

---

**Generated by**: Bkit Vibecoding Kit
**Template Version**: 1.4.4 (Skills Integration + Unified Hooks)
20260323 09:54:10: Started task to integrate gstack features into giip-dev-agent.
20260323 10:25:00: Started task to research and add useful skills from `https://github.com/anthropics/skills`.

20260323 10:30:00: Started task to enhance agent skills by researching and adding content from 'agent-ref/skills'.
20260323 11:38:24: Started task to research and integrate useful agent skills from `agent-ref`.
20260323 11:45:00: Completed integration of brainstorming, dispatching-parallel-agents, skill-creator, and webapp-testing skills from agent-ref.
20260323 11:47:20: Started task to add `links.md` and link it from `README.md`.
20260323 12:00:00: Completed task to create `links.md` and update all README versions (KR, EN, JP).
20260323 13:14:00: Started task to verify and integrate missing skills from `agent-ref`.
20260323 16:35:00: Completed integration of 13 new skills from `agent-ref`.
20260403 22:56:50: Started task to research and integrate `microsoft/agent-lightning`. Created implementation plan for integration.
20260403 23:04:00: Completed `microsoft/agent-lightning` integration. Added setup scripts, skills, workflows, and updated documentation across all languages.
20260403 23:17:32: Completed 'Native' Agent Optimization integration (Concept of Agent Lightning without WSL2 requirement). Implemented `trace-manager` skill and `native-trace` workflow.
20260403 23:34:35: Completed custom workflow `/aioptimize` implementation. Added `giipdb/scripts/prompt_optimization/native_optimizer.py` and updated documentation across all languages.
