# Windsurf 🏄‍♂️

## 📋 개요
**Windsurf**는 Codeium에서 개발한 새로운 차원의 AI 에이전틱 IDE입니다. "Flow"라는 독창적인 인터페이스를 통해 개발자가 코딩의 흐름을 놓치지 않으면서도 AI 에이전트의 강력한 지원을 받을 수 있도록 합니다.

## ✨ 주요 특징
- **Flow State**: AI가 개발자의 현재 위치와 작업 맥락을 실시간으로 추적하며 필요한 코드를 선제적으로 제안합니다.
- **자율 에이전트 인터페이스**: `Cursor`의 Composer와 유사하게, 에이전트가 복잡한 태스크를 스스로 계획하고 다수의 파일을 수정할 수 있습니다.
- **풍부한 통합**: VS Code 기반 아키텍처로 기존 생태계의 편리함을 모두 수용합니다.
- **고성능 로컬 인덱싱**: 하이브리드 인덱싱 기술을 통해 매우 빠르고 정확한 코드 검색 및 의미 분석을 지원합니다.

## 🔗 공식 다운로드
- **공식 사이트**: [windsurf.ai](https://windsurf.ai/)
- **개발자 블로그**: [codeium.com/blog](https://codeium.com/blog)

## 🚀 Agentic Framework 적용 및 사용법

### 1. 프로젝트 이식 (Transplantation)
Windsurf에서 에이전트 시스템의 Flow를 경험하려면 아래 파일들을 프로젝트 루트로 복사하세요.

- **복사할 항목**:
    - `.agent/`: 핵심 엔진 (규칙, 스킬, 워크플로우)
    - `.windsurfrules`: Windsurf 전용 규칙 파일 (GEMINI.md의 지침을 에이전트에게 강제합니다)
    - `GEMINI.md`: 에이전트 페르소나 및 시스템 전체 지침

### 2. 사용 방법 (Usage)
Windsurf를 실행한 후 Cascade(오른쪽 사이드바의 AI 채팅)에서 작업을 지시합니다.

- **명령 예시**:
    ```text
    현재 태스크 현황 알려줘 (전체 프로젝트 상태 확인)
    @GEMINI.md 이 파일의 지침에 따라 다음 기능을 설계하고 구현해줘.
    ```

### 3. 정상 작동 확인 (Validation)
Windsurf 에이전트가 시스템을 제대로 로드했는지 확인하려면 다음을 입력하세요.
- **입력**: `agent status`
- **기대 결과**: 에이전트가 "Agent Orchestrator"로서 응답하며, `.agent/rules/`의 내용에 따라 현재 프로젝트의 태스크 현황과 할 일 목록을 상세히 브리핑해야 합니다.

### 4. 최신 버전 업데이트 (Update)
에이전트 시스템의 최신 기능을 Windsurf 프로젝트에 반영하려면 에이전트에게 다음과 같이 요청하세요.

> **업데이트 프롬프트**:
> `에이전트 규칙 저장소의 최신 .agent 폴더와 .windsurfrules 파일의 내용을 확인하고, 내 프로젝트의 에이전트 시스템에 최신 변경 사항을 적용해줘.`

## 🧠 Karpathy 행동 지침

본 프레임워크는 Windsurf 사용 시 LLM 코딩 실수를 방지하기 위해 [Karpathy 행동 지침](../../.agent/rules/10_karpathy_guidelines.md)을 따릅니다. `.cursorrules` 설정이 Windsurf에서도 동일하게 적용됩니다.

1. **Think Before Coding** — 가정을 명시적으로 밝히고, 불확실하면 질문합니다.
2. **Simplicity First** — 문제를 해결하는 최소한의 코드만 작성합니다.
3. **Surgical Changes** — 반드시 필요한 것만 수정합니다.
4. **Goal-Driven Execution** — 시작 전에 검증 가능한 성공 기준을 정의합니다.

> 전체 내용: [`.agent/rules/10_karpathy_guidelines.md`](../../.agent/rules/10_karpathy_guidelines.md) | [원본 레포](https://github.com/forrestchang/andrej-karpathy-skills)

---
*Windsurf의 Flow 기능을 통해 에이전트와 긴밀하게 협업할 수 있습니다.*
