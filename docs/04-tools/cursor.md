# Cursor (커서) 🚀

## 📋 개요
**Cursor**는 VS Code를 포크(Fork)하여 AI 기능을 엔진 레벨에서 통합한 차세대 코드 에디터입니다. 기존 VS Code의 편리함은 유지하면서도, AI가 코드베이스 전체를 이해하고 작업할 수 있도록 설계되었습니다.

## ✨ 주요 특징
- **전체 코드베이스 인덱싱**: 프로젝트의 모든 파일을 학습하여 "어디에 무엇이 있는지" 정확히 파악하고 질문에 답합니다.
- **네이티브 프롬프트 입력**: `Ctrl+K`(코드 생성/수정), `Ctrl+L`(채팅)을 통해 편집기 내에서 흐름 끊김 없이 AI와 대화합니다.
- **Composer 모드**: 여러 파일에 걸친 복잡한 작업을 한 번에 수행할 수 있는 멀티 에이전트 기능입니다.
- **VS Code 기반**: 기존의 모든 VS Code 확장 프로그램과 테마를 그대로 사용할 수 있습니다.
- **.cursorrules 지원**: 프로젝트 단위의 코딩 규칙을 에이전트에게 강제할 수 있습니다.

## 🔗 공식 다운로드
- **공식 사이트**: [www.cursor.com](https://www.cursor.com/)
- **공식 문서**: [docs.cursor.com](https://docs.cursor.com/)

## 🚀 Agentic Framework 적용 및 사용법

### 1. 프로젝트 이식 (Transplantation)
Cursor에서 에이전트 시스템의 워크플로우를 활성화하려면 아래 파일들을 프로젝트 루트로 복사하세요.

- **복사할 항목**:
    - `.agent/`: 핵심 엔진 (규칙, 스킬, 워크플로우)
    - `.cursorrules`: Cursor 전용 규칙 파일 (GEMINI.md의 지침을 에이전트에게 강제합니다)
    - `GEMINI.md`: 에이전트 페르소나 및 시스템 전체 지침

### 2. 사용 방법 (Usage)
Cursor를 실행한 후 Composer(`Ctrl+I`)나 Chat(`Ctrl+L`)에서 에이전트에게 명령을 내립니다.

- **명령 예시**:
    ```text
    현재 태스크 현황 알려줘 (현재 태스크와 진행 상황 요약)
    @GEMINI.md 이 파일을 참고해서 새로운 모듈을 설계해줘 (PDCA 기반 설계 시작)
    ```

### 3. 정상 작동 확인 (Validation)
Cursor가 프로젝트의 지능형 에이전트 시스템을 인식하고 있는지 확인하려면 다음을 입력하세요.
- **입력**: `agent status`
- **기대 결과**: 에이전트가 "Agent Orchestrator"로서 응답하며, `.agent/rules/` 폴더 내의 규칙을 참조하여 현재 `task.md` 기반의 할 일을 나열해야 합니다.

### 4. 최신 버전 업데이트 (Update)
에이전트 시스템의 최신 규칙과 스킬을 Cursor 프로젝트에 반영하려면 에이전트에게 다음과 같이 요청하세요.

> **업데이트 프롬프트**:
> `에이전트 규칙 저장소의 최신 .agent 폴더와 .cursorrules 파일의 내용을 확인하고, 내 프로젝트의 에이전트 시스템에 최신 변경 사항을 적용해줘.`

## 🧠 Karpathy 행동 지침

본 프레임워크는 Cursor 사용 시 LLM 코딩 실수를 방지하기 위해 [Karpathy 행동 지침](../../.agent/rules/10_karpathy_guidelines.md)을 따릅니다. 관련 설정은 `.cursorrules`에 포함되어 있으며 Cursor에서 자동으로 적용됩니다.

1. **Think Before Coding** — 가정을 명시적으로 밝히고, 불확실하면 질문합니다.
2. **Simplicity First** — 문제를 해결하는 최소한의 코드만 작성합니다.
3. **Surgical Changes** — 반드시 필요한 것만 수정합니다.
4. **Goal-Driven Execution** — 시작 전에 검증 가능한 성공 기준을 정의합니다.

> 전체 내용: [`.agent/rules/10_karpathy_guidelines.md`](../../.agent/rules/10_karpathy_guidelines.md) | [원본 레포](https://github.com/forrestchang/andrej-karpathy-skills)

---
*본 에이전트 시스템의 `.cursorrules` 설정은 Cursor 에디터에서 자동 적용되어 최적의 경험을 제공합니다.*
