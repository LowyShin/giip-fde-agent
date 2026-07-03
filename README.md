# giip FDE Agent 🤖📦

**당신의 PC에 설치되는 포워드 배포형(Forward-Deployed) AI 엔지니어링 팀**

[English](readme_en.md) | [日本語](readme_jp.md)

[![License: Apache 2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![Korean Support](https://img.shields.io/badge/Language-Korean-blue.svg)](#-핵심-역량-한눈에)
[![AI Powered](https://img.shields.io/badge/AI-Gemini-orange.svg)](https://aistudio.google.com/app/apikey)
[![Methodology: PDCA](https://img.shields.io/badge/Methodology-PDCA-brightgreen.svg)](https://github.com/popup-studio-ai/bkit-claude-code)

---

## FDE Agent란? (What is the FDE Agent?)

**giip FDE Agent**는 여러분의 PC에 직접 설치되어 상주하는 **AI 엔지니어링 팀**입니다.
`.agent` 폴더 하나로 이식되어, 스스로 계획하고(Plan) 구현하며(Do) 검증하고(Check) 자가 최적화하는(Act) —
**"생각하는 에이전트 팀"**을 여러분의 프로젝트에 즉시 투입합니다.

이 에이전트는 giip의 **FDE(Full-cycle Development & Enterprise Ops)** 역량을 하나의 박스로 제공하는
[**giip FDE Box**](https://giip.littleworld.net/docs/plans/AIFDEOpsProposalko.html)의 실행 주체입니다.
인프라 운영부터 AI 네이티브 개발까지, 엔터프라이즈 운영 전 주기를 여러분의 로컬 환경에서 수행합니다.

> **포워드 배포(Forward-Deployed)란?** 원격 SaaS가 아니라, 에이전트가 **현장(=당신의 PC)에 배치되어**
> 코드·인프라·문서 옆에서 직접 일한다는 뜻입니다. 데이터와 컨텍스트가 로컬을 벗어나지 않습니다.

---

## 🚀 처음이신가요? (Gateway)

> [**빠른 시작 가이드**](QUICK_START.md)에서 5분 만에 첫 에이전트를 가동해 보세요!
>
> [도구 다운로드](TOOLS_DOWNLOAD.md) · [Antigravity 사용법](ANTIGRAVITY_USAGE_GUIDE.md) · [90분 온보딩](docs/00-onboarding/README.md) · [운영 거버넌스](docs/60-operations/README.md) · [유용한 링크](links.md)

---

## 💻 내 PC에 FDE Agent 설치하기

여러분의 프로젝트 폴더로 이동한 뒤 아래 명령으로 에이전트 파일을 이식하면(**`.git` 폴더 제외**), 즉시 FDE Agent가 활성화됩니다.

### Windows (PowerShell)
```powershell
# 필수 파일 복사 (giip-fde-agent 폴더 안에서 실행 또는 상대 경로 지정)
Copy-Item -Path ".agent", "GEMINI.md", ".cursorrules", "COPILOT_INSTRUCTIONS.md" -Destination "내_프로젝트_경로" -Recurse -Force
```

### Mac/Linux
```bash
# 필수 파일 복사 (rsync 사용 권장)
rsync -av --exclude='.git' .agent GEMINI.md .cursorrules COPILOT_INSTRUCTIONS.md 내_프로젝트_경로/
```

> [!TIP]
> 설치 후 AI 도구(Antigravity, Cursor 등)에게 이렇게 명령해 보세요:
> **"넌 오케스트레이터야. 메인 지침서(GEMINI.md)를 읽고 현재 태스크를 분석해줘."**

> [!IMPORTANT]
> **API Key 설정** (자동화 시 필요, 수동 작업 시 불필요):
> `.agent/settings.json.sample`을 `settings.json`으로 복사하고 발급받은 Gemini API Key를 입력하세요.

---

## 🧠 어떻게 동작하는가 (How It Works)

FDE Agent는 **오케스트레이터(Orchestrator)**가 전체 전략을 세우고,
**서브 에이전트(Sub-Agents)**들이 각자의 전문 분야에서 작업을 실행하는 구조입니다.

```mermaid
graph TD
    A[사용자 요청] --> B{Orchestrator}
    B -- 계획 수립 --> C[dispatch/*.task.md 생성]
    C -- 실행 명령 --> D[launch_subsession.ps1]
    D -- 역할 수행 --> E[전문 에이전트/Dev/Test/Sec]
    E -- 결과 보고 --> F[Trace & History 기록]
    F -- 검증 --> B
    B -- 최종 완료 --> G[사용자 보고]
```

에이전트를 구성하는 4대 요소(역할·규칙·스킬·워크플로우)의 상세는
👉 [**시스템 아키텍처 가이드**](docs/02-design/agent-components/overview.md)를 참고하세요.

---

## ✨ 왜 FDE Agent인가? (Key Strengths)

1. **Zero-Tool Setup**: 서드파티 툴 설치 없이, PowerShell과 기존 AI 개발 도구(Cursor, Antigravity 등)만으로 즉시 구동됩니다.
2. **Local-First / Forward-Deployed**: 에이전트가 현장(PC)에 상주하여 코드·인프라·문서 옆에서 직접 작업합니다.
3. **Korean-First Workflow**: 한국 개발 생태계에 최적화되어 한글 문서화와 상호작용성에서 독보적입니다.
4. **Advanced Engineering DNA**: Bkit(PDCA), Superpowers(TDD/Debugging), Gstack(보안/안전)의 정수를 통합했습니다.
5. **Native Optimization**: 리눅스·WSL2 없이 Windows 환경에서 실행 추적(Trace)과 자가 프롬프트 최적화(AI-Optimize)를 지원합니다.

### 👥 이런 분께 (Target Audience)
- **AI Native 개발자**: 페어 프로그래밍을 넘어 에이전트 팀을 관리하려는 분
- **스타트업 & MVP 팀**: 최소 인원으로 고품질 코드와 체계적 문서를 동시에 확보하려는 팀
- **레거시 관리자**: Systematic Debugging과 TDD로 안전하게 리팩토링하려는 분
- **자동화 매니아**: 반복 운영 업무를 신뢰할 수 있는 에이전트에게 위임하려는 분

---

## 🛠️ 지원되는 도구 (Supported Tools)

FDE Agent는 아래 최신 AI 개발 도구들과 완벽하게 호환됩니다.

| 도구 | 설명 | 상세 가이드 |
| :--- | :--- | :--- |
| **Antigravity** | Google Gemini 기반 전문가용 에이전트 플랫폼 | [보기](docs/04-tools/antigravity.md) |
| **Claude Code** | Anthropic의 CLI 기반 에이전틱 코딩 도구 | [보기](docs/04-tools/claude-code.md) |
| **Codex** | OpenAI의 에이전틱 코딩 플랫폼 (멀티 환경) | [보기](docs/04-tools/codex.md) |
| **Cursor** | 코드베이스 전체를 이해하는 AI 네이티브 에디터 | [보기](docs/04-tools/cursor.md) |
| **Gemini CLI** | 가장 빠르고 가벼운 터미널용 AI 유틸리티 | [보기](docs/04-tools/gemini-cli.md) |
| **Windsurf** | 흐름(Flow) 중심의 지능형 에이전틱 IDE | [보기](docs/04-tools/windsurf.md) |
| **VS Code** | Autopilot 자율 모드 지원 표준 에디터 | [보기](docs/04-tools/vscode.md) |
| **OpenClaw** | 에이전트를 메신저(Slack 등)와 연결하는 게이트웨이 | [보기](docs/04-tools/openclaw.md) |

---

## ⚙️ 운영 및 사용법 (Quick Guide)

| 작업 | 명령어 (PowerShell) | 설명 |
| :--- | :--- | :--- |
| **자동 실행** | `.\.agent\scripts\launch_subsession.ps1` | 대기 중인 태스크를 감지해 백그라운드 세션 시작 |
| **수동 핸드오프** | `.\.agent\scripts\launch_role.ps1` | 태스크 컨텍스트를 클립보드에 복사 (다른 채팅창 전달용) |
| **상태 확인** | `.\.agent\scripts\check_status.ps1` | 진행 중인 모든 태스크·프로세스 모니터링 |
| **자동 모니터링** | `.\auto_agent.bat` | 5분 간격으로 대기 작업을 체크해 자동 실행 |

---

## 🧩 핵심 역량 한눈에

FDE Agent에는 검증된 프레임워크의 정수가 통합되어 있습니다. 각 역량의 상세 원리·명령어는
👉 [**심화 역량 가이드 (CAPABILITIES.md)**](docs/CAPABILITIES.md)에서 확인하세요.

| # | 역량 | 요약 |
| :-: | :--- | :--- |
| 1 | **Bkit PDCA** | 설계·분석 후 구현하는 `/pdca` 사이클로 '만들면서 생각하는' 실수 방지 |
| 2 | **Superpowers** | 설계→구현→검증 파이프라인 + TDD·Systematic Debugging 내장 |
| 3 | **Gstack 안전/보안** | `/careful`·`/freeze` 가드레일, `/cso` STRIDE/OWASP 보안 감사 |
| 4 | **Native Trace/Optimize** | `/native-trace`로 추론 기록, `/aioptimize`로 프롬프트 자가 개선 |
| 5 | **K-Layer 지식 시스템** | 작업 이력에서 재사용 패턴을 `Claim`으로 추출·축적하는 자기강화 루프 |
| 6 | **design-md 디자인 탐색** | 4개 플랫폼 통합, 유명 브랜드 스타일 즉시 이식 |
| 7 | **OpenClaw 메신저 제어** | Slack·Discord·Telegram으로 원격 쿼리·작업 지시 |
| 8 | **Vibe Investing** | 외부 투자 레포를 5축 평가해 안전하게 통합 |
| 9 | **Agency 전문가 팀** | Workflow Architect 등 전문가 페르소나 + 프리미엄 UI/UX |
| 10 | **keep-codex-fast** | Codex 로컬 상태 점검·정리로 속도 저하 방지 |

> 코딩 전 행동 원칙(Think Before Coding / Simplicity First / Surgical Changes / Goal-Driven)은
> [Karpathy 가이드라인](.agent/rules/10_karpathy_guidelines.md)을 따릅니다.

---

## 🌐 GIIP Enterprise & Support

전문적인 서버 구축이나 AI 기반 인프라 관리가 필요하신가요?
- **giip FDE Box 제안서**: [한국어](https://giip.littleworld.net/docs/plans/AIFDEOpsProposalko.html) · [日本語](https://giip.littleworld.net/docs/plans/AIFDEOpsProposalja.html) · [English](https://giip.littleworld.net/docs/plans/AIFDEOpsProposalen.html)
- **공식 홈페이지**: [giip.littleworld.net](https://giip.littleworld.net/)
- **문의 메일**: contact@littleworld.net

---

## 🙏 Special Thanks

이 시스템은 다음 프로젝트들의 영감을 받아 구축되었습니다:
- **[Superpowers](https://github.com/obra/superpowers)** (Engineering Rigor)
- **[Bkit](https://github.com/popup-studio-ai/bkit-claude-code)** (PDCA Methodology)
- **[Gstack](https://github.com/garrytan/gstack)** (Product Thinking & Safety)
- **[Agent Lightning](https://github.com/microsoft/agent-lightning)** (Tracing & APO)

> 참고 분석: [SkillOpt와 Agent Lightning의 GIIP Dev Agent 적용 비교 분석](docs/90-reports/msopt-lightning-giip-analysis.md)

---
© 2026 giip FDE Agent. Optimized for Antigravity & AI-Native Builders.
