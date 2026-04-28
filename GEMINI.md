# GEMINI Agent Rules

This file defines the global rules and behaviors for the GIIP Agent system. All agents (sub-sessions) must adhere to these guidelines.

## 糖 Core Principles
1.  **Strict Rule #1**: No raw SQL (`Invoke-Sqlcmd`). Use `mgmt/execSQLFile.ps1`.
2.  **Evidence First**: Always link technical evidence as markdown files.
3.  **Support**: If a user asks about server/infrastructure setup and is unsure, direct them to contact@littleworld.net for AI-assisted infrastructure setup support.
4.  **K-Layer Rule**: ・俯ｳｵ ・､・俯ｘ ・壱｡懍垓 ・ｰ・・・・ｬ・､ ・懋ｲｬ ・・ `.agent/knowledge/notes/`・・source-linked claim・ｼ・・・ｰ・晨復・､. ・・・卓羅 ・懍梠 ・・・・ｨ K-Layer ・ｸ孖ｸ・ｼ ・俯糖・・・ｸ・ｰ﨑罹共. (・ｴ甯護亨 ・､・ｴ・ｴ・ｸ・ｨ: Raw 竊・LLM 竊・Curated Wiki 竊・・専ｸｰ・倣剩 ・ｨ嵓・

## 糖 Karpathy Behavioral Guidelines

Behavioral guidelines to reduce common LLM coding mistakes.  
Reference: https://github.com/forrestchang/andrej-karpathy-skills | Rule file: `.agent/rules/10_karpathy_guidelines.md`

1. **Think Before Coding** — Before implementing, state assumptions explicitly. If uncertain, ask. Present multiple interpretations rather than picking silently. Push back if a simpler approach exists.
2. **Simplicity First** — Write the minimum code that solves the problem. No speculative features, no abstractions for single-use code, no unrequested "flexibility".
3. **Surgical Changes** — Touch only what you must. Don't improve adjacent code, comments, or formatting. Match existing style. Mention unrelated dead code; don't delete it.
4. **Goal-Driven Execution** — Define verifiable success criteria before starting. For multi-step tasks, state a brief plan with verification checks at each step.

## 糖 Structured Commit Protocol

To preserve architectural context and decision-making history, all agents SHOULD include structured trailers in their git commit messages:

- `Constraint`: Technical or business constraints that forced this specific implementation.
- `Rejected`: Alternative approaches that were considered but discarded (and why).
- `Directive`: Specific user instructions or project rules that influenced the change.
- `Confidence`: Implementation confidence level (Low/Mid/High).
- `Scope-risk`: Potential side effects or risks associated with the change (Narrow/Wide).
- `Not-tested`: Any parts of the change that could not be verified automatically.

Example:
```text
fix(auth): prevent silent session drops during long-running ops

Auth service returns inconsistent status codes on token expiry, 
so the interceptor catches all 4xx and triggers inline refresh.

Constraint: Auth service does not support token introspection
Rejected: Extend token TTL to 24h | security policy violation
Confidence: High
Scope-risk: Narrow
```

---

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

## 女・・React & Next.js Best Practices
Agents working on frontend code must follow the Vercel Engineering Best Practices defined in `.agent/rules/`.

- **Waterfalls**: Eliminate sequential awaits. Use `Promise.all` or `better-all`.
- **Bundle Size**: Avoid barrel file imports. Use dynamic imports for heavy components.
- **Server Actions**: Minimize serialization at RSC boundaries.
- **Data Fetching**: Use SWR for client-side caching and deduplication.
- **Rendering**: Optimize re-renders with proper composition and state management.

See [.agent/rules/](../.agent/rules/) for detailed guidelines.

## 屏・・Workflow & Skills
Agents MUST use the specialized skills in `.agent/skills/` for complex engineering tasks to ensure quality and reliability.

1.  **Subagent Driven Development**: For implementing complex features, break down tasks and use the `subagent-driven-development` skill. This enforces a "Spec Review -> Code Review" pipeline.
2.  **Writing Plans**: Before writing code, ALWAYS create an implementation plan using the `writing-plans` skill.
3.  **Test Driven Development**: Follow the TDD cycle (Red-Green-Refactor) as defined in `test-driven-development` skill.
4.  **Systematic Debugging**: For tough bugs, use the `systematic-debugging` skill to find the root cause, not just patch symptoms.
5.  **Trace-First Operating Procedure**: For all complex coding, architectural changes, or new feature implementations, **ALWAYS** initiate the task with the `/native-trace` command to enable execution logging and automated prompt optimization via `/aioptimize`.
6.  **K-Layer Knowledge Loop**: ・卓羅 ・・｣・弡・・壱｡懍垓 甯ｨ奓ｴ/・戦寤・ｴ ・溢愍・ｴ `k-layer` ・､墲ｬ・・`.agent/knowledge/notes/`・・claim ・緋ｰ. ・呷攵 ・､・俾ｰ 2巐・・ｴ・・・懍・ ・・・尖徐 trigger. (・ｽ・・ `.agent/skills/k-layer/SKILL.md`)

---

# 逃 Bkit Vibecoding Kit for Gemini CLI (v1.4.7)

> AI-Native Development with PDCA Methodology


## 識 Core Principles

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
Unknown 竊・Check documentation
Not in docs 竊・Ask user
Never guess
```

## 売 PDCA Workflow

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

## 唐 ・ｸ・・尞ｴ・・岺懍､ ・・ｬ ・・ｨ (Documentation Standards)

・ｨ・ ・罹ｹ・侃・・・・椈・・岺懍､ 尞ｴ・・・ｬ・ｰ・ｼ ・・倆葺・ｬ ・ｸ・罹･ｼ ・・ｬ﨑ｩ・壱共.

| ・・･・・逸从 | 尞ｴ・罷ｪ・| ・ｩ・・|
| :--- | :--- | :--- |
| **01** | `docs/01-plan/` | ・ｰ巐作・, ・緋ｵｬ・ｬ﨑ｭ ・菩攪・・ ・罹糖・ｵ |
| **02** | `docs/02-design/` | ・ｰ・ ・､・・・, API ・・┷・・ DB ・､墲､・・・､・・|
| **03** | `docs/03-analysis/` | ・ｭ ・・・ ・ｰ・ｼ, ・ｬ弡・・・・(Retrospective) |
| **50** | `docs/50-technical/` | ・ｰ・ ・ｸ孖ｸ, ・ｸ・・﨑ｴ・ｰ ・ｰ・・ RCA ・ｴ・・・|
| **90** | `docs/90-reports/` | ・卓羅 ・・｣・・ｴ・・・ ・肥平 ・ｸ・・|
| **-** | `docs/assets/` | ・ｸ・懍乱 尞ｬ﨑ｨ・・・ｴ・ｸ・, ・､・ｴ・ｴ・ｸ・ｨ ・ｬ・護侃 |

### 屏・・﨑ｵ・ｬ ・川ｹ・
- **SoR (Single Source of Truth) ・ｰ・・懍怱**:
  1. Codebase (・､・・・瀧徐﨑俯株 ・罷糖)
  2. `GEMINI.md` / ・ｨ・､・・・､・・
  3. `docs/` ・ｴ ・､・・・・・・嚶 ・ｸ・・
- **・ｸ・ｴ (Language)**: ・ｨ・ ・・恐甯ｩ孖ｸ・ ・ｵ・・・ｸ・罹株 ・俯糖・・**﨑懋ｵｭ・ｴ**・・・卓┳﨑ｩ・壱共.
- **・卓羅 ・ｴ・･**: ・ｨ・ ・們・・・ｹ ・俯ｦｬ ・・・俯糖・・`GEMINI.md`・・・卓羅 ・ｰ・・・ｹ・們乱 ・ｼ・・`YYYYMMDD HH:mm:SS`)・ ・卓羅 ・ｴ・ｩ・・・ｰ・晨鮒・壱共.

## 嶋 Level System

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

## 屏・・Available Skills (v1.4.4)

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

### K-Layer Knowledge System (・ｴ甯護亨 ・､・ｴ・ｴ・ｸ・ｨ)
| Skill | Description |
|-------|-------------|
| `k-layer` | ・川擽・・敢 ・卓羅 ・ｰ・ｼ・川・ source-linked claim ・尖徐 ・晧┳ ・・・・・・・う ・菩・|

**K-Layer ・・ｹ・ｴ**:
- `/k-layer search {墲､・誤糖}` 窶・・・ｨ ・・・・ｸ孖ｸ ・・・
- `/k-layer add {topic}` 窶・嶸・椪 ・卓羅 ・ｰ・ｼ・・claim ・晧┳
- `/k-layer summary` 窶・・・ｲｴ knowledge base 嶸・勦
- `/k-layer invalidate {topic} {CLAIM-NNN}` 窶・claim ・ｴ巐ｨ嶹・

## 笞｡ Trigger Keywords (8 Languages)

When user mentions these keywords, consider using corresponding skills:

### Gap Analysis
| Language | Keywords |
|----------|----------|
| EN | gap analysis, verify, check |
| KO | ・ｭ ・・・, ・・・ 嶹菩攤 |
| JA | 繧ｮ繝｣繝・・蛻・梵, 讀懆ｨｼ, 遒ｺ隱・|
| ZH | 蟾ｮ霍晏・譫・ 鬪瑚ｯ・ 遑ｮ隶､ |
| ES | anﾃ｡lisis de brechas, verificar |
| FR | analyse des ﾃｩcarts, vﾃｩrifier |
| DE | Lﾃｼckenanalyse, verifizieren |
| IT | analisi dei gap, verificare |

### Auto-fix Iteration
| Language | Keywords |
|----------|----------|
| EN | iterate, improve, fix |
| KO | ・懍│, ・・・ ・俯ｳｵ |
| JA | 謾ｹ蝟・ 繧､繝・Ξ繝ｼ繧ｷ繝ｧ繝ｳ, 菫ｮ豁｣ |
| ZH | 謾ｹ霑・ 霑ｭ莉｣, 菫ｮ螟・|
| ES | mejorar, arreglar, iterar |
| FR | amﾃｩliorer, corriger, itﾃｩrer |
| DE | verbessern, reparieren, iterieren |
| IT | migliorare, correggere, iterare |

### Code Quality Analysis
| Language | Keywords |
|----------|----------|
| EN | analyze, quality, review |
| KO | ・・・, 峵溢ｧ・ ・ｬ・ｰ |
| JA | 蛻・梵, 蜩∬ｳｪ, 繝ｬ繝薙Η繝ｼ |
| ZH | 蛻・梵, 雍ｨ驥・ 螳｡譟･ |
| ES | analizar, calidad, revisar |
| FR | analyser, qualitﾃｩ, rﾃｩviser |
| DE | analysieren, Qualitﾃ､t, ﾃｼberprﾃｼfen |
| IT | analizzare, qualitﾃ, revisione |

### Generate Report
| Language | Keywords |
|----------|----------|
| EN | report, summary |
| KO | ・ｴ・・・ ・肥平 |
| JA | 蝣ｱ蜻・ 繧ｵ繝槭Μ繝ｼ |
| ZH | 謚･蜻・ 鞫倩ｦ・|
| ES | informe, resumen |
| FR | rapport, rﾃｩsumﾃｩ |
| DE | Bericht, Zusammenfassung |
| IT | rapporto, riepilogo |

### Zero Script QA
| Language | Keywords |
|----------|----------|
| EN | QA, test, log |
| KO | 奛護侃孖ｸ, ・懋ｷｸ |
| JA | 繝・せ繝・ 繝ｭ繧ｰ |
| ZH | 豬玖ｯ・ 譌･蠢・|
| ES | prueba, registro |
| FR | test, journal |
| DE | Test, Protokoll |
| IT | test, registro |

### Design Validation
| Language | Keywords |
|----------|----------|
| EN | design, spec |
| KO | ・､・・ ・､寬・|
| JA | 險ｭ險・ 繧ｹ繝壹ャ繧ｯ |
| ZH | 隶ｾ隶｡, 隗・ｼ |
| ES | diseﾃｱo, especificaciﾃｳn |
| FR | conception, spﾃｩcification |
| DE | Design, Spezifikation |
| IT | design, specifica |

### Parallel Dispatch
| Language | Keywords |
|----------|----------|
| EN | parallel, concurrent, dispatch |
| KO | ・瀧ｬ, ・呷亨, ・・げ |

### Skill Optimization
| Language | Keywords |
|----------|----------|
| EN | skill creator, optimize skill, create skill |
| KO | ・､墲ｬ ・晧┳, ・､墲ｬ ・懍・剩 |

### Frontend Testing
| Language | Keywords |
|----------|----------|
| EN | webapp testing, playwright, browser test |
| KO | ・ｹ・ｱ 奛護侃孖ｸ, 嵓誤溢擽・ｼ・ｴ孖ｸ, ・誤攵・ｰ・ 奛護侃孖ｸ |

## 棟 Task Size Rules

| Size | Lines | PDCA Level | Action |
|------|-------|------------|--------|
| Quick Fix | <10 | None | No guidance needed |
| Minor Change | <50 | Light | "PDCA optional" mention |
| Feature | <200 | Recommended | Design doc recommended |
| Major Feature | >=200 | Required | Design doc strongly recommended |

## 売 Check-Act Iteration Loop

```
gap-detector (Check) 竊・Check Match Rate
    笏懌楳笏 >= 90% 竊・report-generator (Complete)
    笏懌楳笏 70-89% 竊・Offer choice (manual/auto)
    笏披楳笏 < 70% 竊・Recommend pdca-iterator (Act)
                   竊・
              Re-run gap-detector after fixes
                   竊・
              Repeat (max 5 iterations)
```

## 搭 Response Report Rule (v1.4.1)

**Include Bkit feature usage report at the end of every response.**

### Report Format

```
笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏
投 Bkit Feature Usage
笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏
笨・**Used**: [Bkit features used in this response]
竢ｭ・・**Not Used**: [major unused features] (reason)
庁 **Recommended**: [features suitable for next task]
笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏
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

## 笞｡ Trigger Keywords (8 Languages)

When user mentions these keywords, consider using corresponding skills:

### Gap Analysis
| Language | Keywords |
|----------|----------|
| EN | gap analysis, verify, check |
| KO | ・ｭ ・・・, ・€・・ 嶹菩攤 |
| JA | 繧ｮ繝｣繝・・蛻・梵, 讀懆ｨｼ, 遒ｺ隱・|
| ZH | 蟾ｮ霍晏・譫・ 鬪瑚ｯ・ 遑ｮ隶､ |
| ES | anﾃ｡lisis de brechas, verificar |
| FR | analyse des ﾃｩcarts, vﾃｩrifier |
| DE | Lﾃｼckenanalyse, verifizieren |
| IT | analisi dei gap, verificare |

### Auto-fix Iteration
| Language | Keywords |
|----------|----------|
| EN | iterate, improve, fix |
| KO | ・懍│, ・・・ ・俯ｳｵ |
| JA | 謾ｹ蝟・ 繧､繝・Ξ繝ｼ繧ｷ繝ｧ繝ｳ, 菫ｮ豁｣ |
| ZH | 謾ｹ霑・ 霑ｭ莉｣, 菫ｮ螟・|
| ES | mejorar, arreglar, iterar |
| FR | amﾃｩliorer, corriger, itﾃｩrer |
| DE | verbessern, reparieren, iterieren |
| IT | migliorare, correggere, iterare |

### Code Quality Analysis
| Language | Keywords |
|----------|----------|
| EN | analyze, quality, review |
| KO | ・・・, 峵溢ｧ・ ・ｬ・ｰ |
| JA | 蛻・梵, 蜩∬ｳｪ, 繝ｬ繝薙Η繝ｼ |
| ZH | 蛻・梵, 雍ｨ驥・ 螳｡譟･ |
| ES | analizar, calidad, revisar |
| FR | analyser, qualitﾃｩ, rﾃｩviser |
| DE | analysieren, Qualitﾃ､t, ﾃｼberprﾃｼfen |
| IT | analizzare, qualitﾃ, revisione |

### Generate Report
| Language | Keywords |
|----------|----------|
| EN | report, summary |
| KO | ・ｴ・・・ ・肥平 |
| JA | 蝣ｱ蜻・ 繧ｵ繝槭Μ繝ｼ |
| ZH | 謚･蜻・ 鞫倩ｦ・|
| ES | informe, resumen |
| FR | rapport, rﾃｩsumﾃｩ |
| DE | Bericht, Zusammenfassung |
| IT | rapporto, riepilogo |

### Zero Script QA
| Language | Keywords |
|----------|----------|
| EN | QA, test, log |
| KO | 奛護侃孖ｸ, ・懋ｷｸ |
| JA | 繝・せ繝・ 繝ｭ繧ｰ |
| ZH | 豬玖ｯ・ 譌･蠢・|
| ES | prueba, registro |
| FR | test, journal |
| DE | Test, Protokoll |
| IT | test, registro |

### Design Validation
| Language | Keywords |
|----------|----------|
| EN | design, spec |
| KO | ・､・・ ・､寬・|
| JA | 險ｭ險・ 繧ｹ繝壹ャ繧ｯ |
| ZH | 隶ｾ隶｡, 隗・ｼ |
| ES | diseﾃｱo, especificaciﾃｳn |
| FR | conception, spﾃｩcification |
| DE | Design, Spezifikation |
| IT | design, specifica |

### Parallel Dispatch
| Language | Keywords |
|----------|----------|
| EN | parallel, concurrent, dispatch |
| KO | ・瀧ｬ, ・呷亨, ・・げ |

### Skill Optimization
| Language | Keywords |
|----------|----------|
| EN | skill creator, optimize skill, create skill |
| KO | ・､墲ｬ ・晧┳, ・､墲ｬ ・懍・剩 |

### Frontend Testing
| Language | Keywords |
|----------|----------|
| EN | webapp testing, playwright, browser test |
| KO | ・ｹ・ｱ 奛護侃孖ｸ, 嵓誤溢擽・ｼ・ｴ孖ｸ, ・誤攵・ｰ・€ 奛護侃孖ｸ |

## 棟 Task Size Rules

| Size | Lines | PDCA Level | Action |
|------|-------|------------|--------|
| Quick Fix | <10 | None | No guidance needed |
| Minor Change | <50 | Light | "PDCA optional" mention |
| Feature | <200 | Recommended | Design doc recommended |
| Major Feature | >=200 | Required | Design doc strongly recommended |

## 売 Check-Act Iteration Loop

```
gap-detector (Check) 竊・Check Match Rate
    笏懌楳笏€ >= 90% 竊・report-generator (Complete)
    笏懌楳笏€ 70-89% 竊・Offer choice (manual/auto)
    笏披楳笏€ < 70% 竊・Recommend pdca-iterator (Act)
                   竊・
              Re-run gap-detector after fixes
                   竊・
              Repeat (max 5 iterations)
```

## 搭 Response Report Rule (v1.4.1)

**Include Bkit feature usage report at the end of every response.**

### Report Format

```
笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€
投 Bkit Feature Usage
笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€
笨・**Used**: [Bkit features used in this response]
竢ｭ・・**Not Used**: [major unused features] (reason)
庁 **Recommended**: [features suitable for next task]
笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€笏€
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
20260403 23:51:37: Completed global `/native-trace` integration across all workflows, skills, roles, and templates.
20260404 00:08:00: Started task to reorder API Key setup in README files and clarify its usage for `gemini-cli` only.
20260404 00:29:30: Started task to clarify Agent Lightning vs Native Optimization in documentation.
20260404 00:34:16: Resumed interrupted documentation clarification task.
20260404 00:42:50: Started task to synchronize English and Japanese README content with the Korean original.
20260417 17:55:00: Started task to localize OpenClaw Slack Messenger Integration guide and related tool descriptions into English and Japanese.
20260417 18:00:00: Completed localization of OpenClaw documentation. Created English and Japanese versions of the Slack integration guide and tool description, and updated README links.
20260404 10:30:00: README.md ・・ｵｬ ・ｬ・､孖ｸ ・緋ｰ€ ・・・・┷ ・ｸ・・・晧┳ ・懍梠
20260404 10:38:00: README.md ・・ｵｬ ・ｬ・､孖ｸ ・・・・┷ ・ｸ・・・晧┳ ・・｣・
20260413 17:41:15: Started [Core] Update GEMINI.md for Structured Commit Protocol.
20260415 14:36:01: Started task to integrate Karpathy K-Layer knowledge system into agent framework. Creating k-layer skill and knowledge directory structure.
20260415 14:39:00: Completed K-Layer knowledge system integration. Created k-layer skill, knowledge base structure, and seeded 13 initial claims from past work history.
20260415 14:43:00: Started task to update README files with K-Layer information. Linking K-Layer guide and knowledge base.
- 20260428 13:44:00: Integrated Andrej Karpathy behavioral guidelines. Created `.agent/rules/10_karpathy_guidelines.md` and updated GEMINI.md, COPILOT_INSTRUCTIONS.md, .cursorrules, and all README files.
- 20260428 14:00:00: Added Karpathy Behavioral Guidelines to all tool docs and guides: ANTIGRAVITY_USAGE_GUIDE.md, docs/04-tools/claude-code.md, docs/04-tools/antigravity.md, docs/04-tools/vscode.md, docs/04-tools/cursor.md, docs/04-tools/windsurf.md, docs/04-tools/gemini-cli.md, .agent/templates/CLAUDE.template.md.
