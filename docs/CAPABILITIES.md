# giip FDE Agent — 에코시스템 & 심화 역량 (Advanced Capabilities)

> 이 문서는 [README](../README.md)에서 분리된 심화 역량 상세 설명입니다.
> README에는 요약만 두고, 각 기능의 자세한 원리·명령어·링크는 여기서 관리합니다.

giip FDE Agent는 단순한 프롬프트 모음이 아니라, 검증된 여러 프레임워크의 정수를 하나로 통합한
고도화된 에이전트 기술의 집약체입니다. 아래는 에이전트에 내장된 핵심 역량들입니다.

---

## 1. Bkit Vibecoding Kit (PDCA)
- **Plan-Design-Do-Check-Act**: 모든 기능을 구현하기 전 설계(Design)와 분석(Analyze) 단계를 거쳐 '만들면서 생각하는' 실수를 방지합니다.
- **`/pdca` 명령어**: 체계적인 리포팅과 갭 분석을 자동화합니다.

## 2. Superpowers Engineering
- **Subagent-Driven**: 하나의 작업을 `설계` → `구현` → `검증`의 파이프라인으로 분리.
- **Strong Skills**: TDD(Test Driven Development), Systematic Debugging, Brainstorming 스킬이 내장되어 있습니다.

## 3. Gstack (Safety & Security)
- **Founder Mode**: `/office-hours`, `/ceo-review`를 통해 제품의 본질과 UX를 다시 질문합니다.
- **Guardrails**: 파괴적 명령 전 경고(`/careful`) 및 작업 범위 제한(`/freeze`)으로 안전한 개발 환경을 제공합니다.
- **Security Audit**: `/cso` 명령어로 STRIDE/OWASP 기반의 보안 검사를 수행합니다.

## 4. Native Optimization & Tracing
- **`/native-trace`**: AI의 모든 추론 과정과 툴 호출 이력을 기록합니다.
- **`/aioptimize`**: 수집된 데이터를 바탕으로 에이전트가 스스로의 프롬프트를 수정하여 더 똑똑해집니다.

## 5. K-Layer Knowledge System (Karpathy Diagram)
- **Source-linked Knowledge**: 에이전트 작업 이력에서 재사용 가능한 패턴과 교훈을 `Claim` 단위로 자동으로 추출하고 축적합니다.
- **자기강화 루프**: 모든 지식은 원본 근거(Trace/Source)와 연결되어 있으며, 다음 작업 시 에이전트가 이를 참조하여 더 똑똑하게 행동합니다.
- [K-Layer 작동 원리](../.agent/skills/k-layer/SKILL.md) | [지식 베이스](../.agent/knowledge/README.md)

## 5-1. Behavioral Guidelines (Karpathy Style)
- **Think Before Coding**: 구현 전 가정을 명시하고, 불확실하면 질문하며, 여러 해석이 있을 경우 제시합니다.
- **Simplicity First**: 문제를 해결하는 최소한의 코드만 작성합니다. 요청하지 않은 기능, 추상화, 유연성은 추가하지 않습니다.
- **Surgical Changes**: 반드시 필요한 것만 수정합니다. 관련 없는 코드, 주석, 포맷은 건드리지 않습니다.
- **Goal-Driven Execution**: 검증 가능한 성공 기준을 정의하고, 충족될 때까지 반복합니다.
- [Karpathy 가이드라인](../.agent/rules/10_karpathy_guidelines.md) | [원본 레포](https://github.com/forrestchang/andrej-karpathy-skills)

## 6. Multi-Source Design Discovery (design-md)
- **통합 디자인 탐색**: `designmd.ai`, `designmd.app`, `getdesign.md`, `designmd.me` 등 4가지 주요 플랫폼을 결합하여 최적의 디자인 시스템을 발굴합니다.
- **브랜드 복제 & 자동 생성**: Stripe, Vercel 등 유명 브랜드의 스타일을 즉시 이식하거나, 특정 URL로부터 디자인 마크다운을 자동 생성합니다.
- [디자인 탐색 및 통합 가이드](DESIGN_DISCOVERY_GUIDE.md)

## 7. Messenger Control (OpenClaw)
- **메신저 기반 원격 제어**: Slack, Discord, Telegram을 통해 언제 어디서든 레포지토리의 정보를 쿼리하고 작업을 지시합니다.
- **주머니 속의 에이전트**: 모바일 기기에서도 프로젝트의 지식 베이스(K-Layer)에 접근하여 실시간 질문과 답변이 가능합니다.
- [OpenClaw 메신저 연동 가이드](50-technical/openclaw-slack-integration.md)

## 8. 투자/트레이딩 통합 (Vibe Investing)
- **투자 기능 안전 통합**: 외부 투자 레포를 5축(활성도/성숙도/학습곡선/시장적합성/라이선스)으로 평가해 GIIP role/rule/skill/workflow에 최소 변경으로 반영합니다.
- **리스크 우선 체크리스트**: 백테스트 편향, 실행 현실성(슬리피지/유동성/수수료), 규제/비용 항목을 기본 검증으로 강제합니다.
- [투자 스킬](../.agent/skills/vibe-investing/SKILL.md) | [투자 워크플로우](../.agent/workflows/investment-evaluation.md)

## 9. AI Agency 전문가 팀 통합 (Agency-Agents)
- **고도화된 역할 시스템**: `Workflow Architect`(시스템 경로 설계), `Korean Business Navigator`(한국 비즈니스 특화) 등 검증된 전문가 페르소나를 내장.
- **프리미엄 UI/UX**: `premium-ui-craft` 스킬을 통해 단순 기능을 넘어선 고도의 미적 완성도(Glassmorphism, 60fps 애니메이션 등)를 추구.
- **철저한 예외 경로 설계**: `workflow-mapping`을 통해 "코드는 있지만 명세가 없는 워크플로우"를 방지하고 모든 실패 복구 경로를 사전에 정의.

## 10. Codex 성능 유지 (keep-codex-fast)
- **Codex 속도 저하 방지**: 오래된 채팅·워크트리·로그·프로젝트 참조가 쌓여 Codex가 느려질 때, 로컬 상태를 안전하게 점검하고 정리합니다.
- **핸드오프 우선 원칙**: 아카이브 전 반드시 핸드오프 문서를 생성하여 작업 맥락을 보존합니다.
- **주기적 유지보수**: 주간/격주 알림으로 Codex 상태를 자동 점검하되, 적용은 사용자 승인 후 수동으로 진행합니다.
- [keep-codex-fast 스킬](../.agent/skills/keep-codex-fast/SKILL.md) | [유지보수 워크플로우](../.agent/workflows/codex-maintenance.md) | [Codex 도구 가이드](04-tools/codex.md)

---

## 📂 시스템 아키텍처 (System Architecture)
FDE Agent를 구성하는 네 가지 핵심 요소에 대한 상세 가이드입니다.

- [**전체 구성 요소 개요**](02-design/agent-components/overview.md)
- [**역할 (Roles)**](02-design/agent-components/role.md): 에이전트의 페르소나와 책임 정의
- [**규칙 (Rules)**](02-design/agent-components/rule.md): 강제 지침 및 품질 관리 원칙
- [**스킬 (Skills)**](02-design/agent-components/skill.md): 도구 사용법 및 전문 지식 패키지
- [**워크플로우 (Workflows)**](02-design/agent-components/workflow.md): 복잡한 작업 절차 및 커스텀 명령어 생성

---

## 🧭 AI-Native 운영 스타터팩
- [90분 온보딩 경로](00-onboarding/README.md) (Beginner / Team Lead / Ops)
- [운영 KPI 표준](60-operations/ai-native-kpi.md) + [주간 KPI 템플릿](../.agent/templates/weekly-kpi-report.template.md)
- [승인 게이트 워크플로우](../.agent/workflows/human-approval-gate.md)
- [Incident + Rollback 플레이북](60-operations/incident-rollback-playbook.md)
- [Skill/Role 운영 책임 메타데이터 스키마](../.agent/templates/shared/operational-metadata-schema.md)
