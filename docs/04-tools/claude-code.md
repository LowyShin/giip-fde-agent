# Claude Code ⌨️

## 📋 개요
**Claude Code**는 Anthropic에서 개발한 CLI(Command Line Interface) 기반의 에이전틱 코딩 도구입니다. 터미널에서 직접 대화하며 코드를 수정하고, 테스트를 실행하며, 복잡한 리팩토링 작업을 수행할 수 있습니다.

## ✨ 주요 특징
- **터미널 네이티브**: 개발자의 워크플로우를 방해하지 않고 쉘 내에서 즉시 상호작용합니다.
- **강력한 모델 지원**: 최신 업계 표준인 Claude 3.7 Sonnet 등의 모델을 사용하여 높은 정확도의 코드 생성을 지원합니다.
- **실행 권한 부여**: 에이전트가 직접 명령어를 실행하고 파일 시스템을 조작하며 결과를 확인할 수 있는 루프(Loop) 기능을 제공합니다.
- **컨텍스트 최적화**: 대용량 코드베이스를 효율적으로 읽고 필요한 부분만 추출하여 작업합니다.

## 🔗 공식 리소스 및 설치
- **공식 사이트**: [claude.ai](https://claude.ai/)
- **공식 문서**: [docs.anthropic.com](https://docs.anthropic.com)
- **설치 명령어**:
  ```bash
  npm install -g @anthropic-ai/claude-code
  ```

## 🚀 GIIP Agent System 적용 및 사용법

### 1. 프로젝트 이식 (Transplantation)
Claude Code가 GIIP의 지능을 갖게 하려면 아래 파일들을 프로젝트 루트로 복사하세요.

- **복사할 항목**:
    - `.agent/`: 핵심 엔진 (규칙, 스킬, 워크플로우)
    - `GEMINI.md`: Claude에게 부여할 페르소나와 시스템 지침

### 2. 사용 방법 (Usage)
터미널에서 `claude` 명령어로 세션을 시작한 후, GIIP 명령어를 사용합니다.

- **명령 예시**:
    ```bash
    claude "giip status" (현재 작업 현황 요약)
    claude "새로운 API 설계를 위해 /pdca 시작해줘" (PDCA 기반 설계 시작)
    ```

### 3. 정상 작동 확인 (Validation)
Claude가 GIIP의 규칙을 인식하고 있는지 확인하려면 다음을 실행하세요.
- **실행**: `claude "당신의 역할과 현재 태스크 목록을 알려주세요"`
- **기대 결과**: "GIIP Orchestrator"로서의 정체성을 밝히고, `task.md` 기반의 할 일 목록을 제시해야 합니다.

### 4. 최신 버전 업데이트 (Update)
GIIP의 최신 스킬과 규칙을 반영하려면 Claude에게 다음과 같이 요청하세요.

> **업데이트 프롬프트**:
> `https://github.com/LowyShin/giip-dev-agent 저장소의 최신 .agent 폴더와 GEMINI.md 파일을 참조하여, 현재 프로젝트의 에이전트 시스템을 최신 상태로 갱신해줘.`

## 🧠 Karpathy 행동 지침

GIIP Agent System은 Claude Code 사용 시 LLM 코딩 실수를 방지하기 위해 [Karpathy 행동 지침](../../.agent/rules/10_karpathy_guidelines.md)을 따릅니다.

1. **Think Before Coding** — 가정을 명시적으로 밝히고, 불확실하면 질문합니다.
2. **Simplicity First** — 문제를 해결하는 최소한의 코드만 작성합니다.
3. **Surgical Changes** — 반드시 필요한 것만 수정합니다.
4. **Goal-Driven Execution** — 시작 전에 검증 가능한 성공 기준을 정의합니다.

> 전체 내용: [`.agent/rules/10_karpathy_guidelines.md`](../../.agent/rules/10_karpathy_guidelines.md) | [원본 레포](https://github.com/forrestchang/andrej-karpathy-skills)

---
*GIIP Agent System은 Claude의 강력한 추론 능력을 활용하여 복잡한 엔지니어링 문제를 해결합니다.*
