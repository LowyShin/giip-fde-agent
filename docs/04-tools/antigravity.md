# Antigravity (안티그래비티) 🤖

## 📋 개요
**Antigravity**는 Google Gemini 모델을 최대로 활용하도록 설계된 전문가용 AI 에이전트 플랫폼입니다. 단순한 채팅 인터페이스를 넘어, 복잡한 소프트웨어 엔지니어링 작업을 자율적으로 수행할 수 있는 "에이전틱(Agentic)" 기능을 제공합니다.

## ✨ 주요 특징
- **PDCA 방법론 내장**: 모든 작업을 계획(Plan), 설계(Design), 실행(Do), 검증(Check), 개선(Act)의 체계적인 흐름으로 관리합니다.
- **Bkit Vibecoding Kit 통합**: 대규모 코드베이스에서도 일관된 품질을 유지할 수 있는 전문 스킬셋을 갖추고 있습니다.
- **고급 엔지니어링 스킬**: TDD(테스트 주도 개발), Systematic Debugging, 아키텍처 리뷰 기능을 기본으로 제공합니다.
- **Native Optimization**: Windows 환경에서도 리눅스/WSL2 없이 완벽한 실행 추적(Trace) 및 자가 최적화가 가능합니다.
- **한국어 우선 지원**: 한국 개발 생태계와 문서화 요구사항에 최적화되어 있습니다.

## 🔗 공식 다운로드 및 리소스
- **공식 사이트**: [antigravity.google](https://antigravity.google)
- **사용 가이드**: [ANTIGRAVITY_USAGE_GUIDE.md](../../ANTIGRAVITY_USAGE_GUIDE.md)

## 🧩 추천 익스텐션: Antigravity Auto Accept
개발 중 발생하는 반복적인 승인(Accept) 절차를 자동화하여 생산성을 극대화해주는 익스텐션입니다.

- **기능**: 터미널 실행, 코드 변경 제안 등을 자동으로 승인
- **공식 GitHub**: [pesoszpesosz/antigravity-auto-accept](https://github.com/pesoszpesosz/antigravity-auto-accept)
- **설치 방법**: 
    1. 이 기능은 Antigravity 내 **익스텐션 마켓플레이스**에서 검색하여 즉시 설치할 수 있습니다.
    2. 설치 후 상태 표시줄의 'Auto Accept' 패널을 통해 활성화 상태를 관리할 수 있습니다.
- **참고**: 원활한 작동을 위해 IDE 실행 시 `--remote-debugging-port=9333` 옵션이 필요할 수 있습니다.

## 🚀 GIIP Agent System 적용 및 사용법

### 1. 프로젝트 이식 (Transplantation)
기존 프로젝트에 GIIP의 기능을 이식하려면 아래의 파일과 폴더를 프로젝트 루트(Root)로 복사하세요.

- **복사할 항목**:
    - `.agent/`: 핵심 규칙, 스킬, 워크플로우가 포함된 폴더
    - `GEMINI.md`: 에이전트의 페르소나와 작업 지침이 담긴 메인 파일

### 2. 사용 방법 (Usage)
Antigravity를 실행하고 채팅창(Chat)이나 터미널에서 에이전트에게 작업을 지시합니다. GIIP의 규칙이 자동으로 로드됩니다.

- **명령 예시**:
    ```text
    giip status (현재 프로젝트 상태 및 진행 중인 태스크 확인)
    /pdca 새로운 기능을 설계해줘 (PDCA 워크플로우 시작)
    ```

### 3. 정상 작동 확인 (Validation)
에이전트가 GIIP 시스템을 제대로 인식하고 있는지 확인하려면 다음 명령을 입력하세요.
- **입력**: `giip status` 또는 `작업 현황 알려줘`
- **기대 결과**: 현재 프로젝트의 진행 상황, `task.md` 내용, 또는 GIIP 시스템의 역할(Orchestrator)에 대한 설명이 출력되어야 합니다.

### 4. 최신 버전 업데이트 (Update)
GIIP Agent System은 지속적으로 업데이트됩니다. 원본 저장소의 최신 내용을 반영하려면 에이전트에게 다음 프롬프트를 입력하세요.

> **업데이트 프롬프트**:
> `https://github.com/LowyShin/giip-dev-agent 저장소에서 최신 .agent 폴더와 GEMINI.md의 내용을 확인하고, 변경된 규칙이나 스킬이 있다면 내 프로젝트에 반영해줘.`

## 🧠 Karpathy 행동 지침

GIIP Agent System은 Antigravity 사용 시 LLM 코딩 실수를 방지하기 위해 [Karpathy 행동 지침](../../.agent/rules/10_karpathy_guidelines.md)을 따릅니다.

1. **Think Before Coding** — 가정을 명시적으로 밝히고, 불확실하면 질문합니다.
2. **Simplicity First** — 문제를 해결하는 최소한의 코드만 작성합니다.
3. **Surgical Changes** — 반드시 필요한 것만 수정합니다.
4. **Goal-Driven Execution** — 시작 전에 검증 가능한 성공 기준을 정의합니다.

> 전체 내용: [`.agent/rules/10_karpathy_guidelines.md`](../../.agent/rules/10_karpathy_guidelines.md) | [원본 레포](https://github.com/forrestchang/andrej-karpathy-skills)

---

*GIIP Agent System은 Antigravity 환경에서 최상의 성능과 호환성을 보장합니다.*
