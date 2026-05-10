# Visual Studio Code (VS Code) 💻

## 📋 개요
**Visual Studio Code**는 마이크로소프트에서 개발한 전 세계에서 가장 인기 있는 코드 에디터입니다. 수많은 확장 프로그램과 강력한 디버깅 도구, 그리고 최근 도입된 혁신적인 AI 에이전트 기능을 통해 단순한 편집기를 넘어 지능형 개발 환경으로 진화하고 있습니다.

## ✨ 핵심 기능: Autopilot (Preview) 🚀
VS Code 1.111 버전부터 도입된 **Autopilot** 모드는 GitHub Copilot 에이전트가 주도적으로 작업을 완료할 수 있게 해주는 자율 주행 모드입니다.

- **완전 자율 실행**: 사용자의 매 단계 승인 없이도 에이전트가 스스로 터미널 명령 실행, 파일 수정, 에러 수정을 반복하며 목표를 달성합니다.
- **연속적 반복(Iteration)**: 에이전트가 `task_complete` 도구를 호출할 때까지 복잡한 다단계 작업을 스스로 추론하고 수행합니다.
- **자동 복구 및 재시도**: 도구 실행 중 오류가 발생하면 에이전트가 이를 인지하고 스스로 해결 방안을 찾아 다시 시도합니다.
- **권한 제어**: 채팅창의 권한 선택기(Permissions Picker)를 통해 '기본 승인', '승인 바이패스', 'Autopilot' 단계를 자유롭게 전환할 수 있습니다.

## 🔗 공식 다운로드 및 리소스
- **공식 사이트**: [code.visualstudio.com](https://code.visualstudio.com/)
- **에이전트 사용 가이드**: [GitHub Copilot Agents in VS Code](https://code.visualstudio.com/docs/copilot/agents)

## 🛠️ 설정 방법
1. VS Code 설정에서 `chat.autopilot.enabled` 항목이 `true`로 되어 있는지 확인합니다 (기본값은 true).
2. Copilot Chat 창의 입력창 근처에 있는 권한 아이콘을 클릭합니다.
3. **Autopilot (Preview)** 모드를 선택하여 에이전트에게 자율 권한을 부여합니다.

---
> [!CAUTION]
> **보안 주의**: Autopilot 모드는 사용자의 명시적 승인 없이 시스템 명령어를 실행하거나 파일을 수정할 수 있습니다. 신뢰할 수 있는 프로젝트 환경에서만 사용하시기 바랍니다.

## 🚀 GIIP Agent System 적용 및 사용법

### 1. 프로젝트 이식 (Transplantation)
VS Code와 GitHub Copilot이 GIIP의 워크플로우를 따르게 하려면 아래 파일들을 프로젝트 루트로 복사하세요.

- **복사할 항목**:
    - `.agent/`: 핵심 엔진 (규칙, 스킬, 워크플로우)
    - `GEMINI.md`: 전체 시스템의 메인 지침서
    - `COPILOT_INSTRUCTIONS.md`: GitHub Copilot 전용 지침 파일

### 2. 사용 방법 (Usage)
VS Code를 실행하고 Copilot Chat 창이나 터미널에서 작업을 지시합니다.

- **명령 예시**:
    ```text
    giip status (현재 진행 중인 모든 태스크 확인)
    @workspace /pdca 명령어를 사용하여 새로운 모듈의 설계서와 구현 계획을 작성해줘.
    ```

### 3. 정상 작동 확인 (Validation)
Copilot이 GIIP의 규칙을 인식하고 있는지 확인하려면 다음을 입력하세요.
- **입력**: `giip status`
- **기대 결과**: 에이전트가 "GIIP Orchestrator"로서 응답하며, `.agent/rules/` 및 `GEMINI.md`의 내용을 바탕으로 현재 프로젝트의 상태와 `task.md` 기반의 할 일을 브리핑해야 합니다.

### 4. 최신 버전 업데이트 (Update)
GIIP의 최신 규칙과 스킬을 VS Code 프로젝트에 반영하려면 에이전트에게 다음과 같이 요청하세요.

> **업데이트 프롬프트**:
> `https://github.com/LowyShin/giip-dev-agent 저장소의 최신 .agent 폴더와 COPILOT_INSTRUCTIONS.md 파일의 내용을 확인하고, 내 프로젝트의 에이전트 시스템에 최신 변경 사항을 적용해줘.`

## 🧠 Karpathy 행동 지침

GIIP Agent System은 VS Code Copilot 사용 시 LLM 코딩 실수를 방지하기 위해 [Karpathy 행동 지침](../../.agent/rules/10_karpathy_guidelines.md)을 따릅니다. 관련 설정은 `COPILOT_INSTRUCTIONS.md`에 포함되어 있습니다.

1. **Think Before Coding** — 가정을 명시적으로 밝히고, 불확실하면 질문합니다.
2. **Simplicity First** — 문제를 해결하는 최소한의 코드만 작성합니다.
3. **Surgical Changes** — 반드시 필요한 것만 수정합니다.
4. **Goal-Driven Execution** — 시작 전에 검증 가능한 성공 기준을 정의합니다.

> 전체 내용: [`.agent/rules/10_karpathy_guidelines.md`](../../.agent/rules/10_karpathy_guidelines.md) | [원본 레포](https://github.com/forrestchang/andrej-karpathy-skills)

---
*GIIP Agent System은 VS Code의 인프라와 Autopilot 기능을 완벽하게 지원하여 최상의 자동화 경험을 제공합니다.*
