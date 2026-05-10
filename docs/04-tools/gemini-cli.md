# Gemini CLI ⚡

## 📋 개요
**Gemini CLI**는 터미널(명령줄) 환경에서 Google의 최신 Gemini 모델을 즉시 호출하고 작업을 자동화할 수 있는 강력한 유틸리티입니다.

## ✨ 주요 특징
- **초고속 응답**: 불필요한 GUI 오버헤드 없이 텍스트 기반으로 가장 빠른 응답 속도를 보여줍니다.
- **스크립트 친화적**: PowerShell이나 Bash 스크립트 내에서 AI를 하나의 함수처럼 호출하여 복잡한 파이프라인을 구성할 수 있습니다.
- **멀티 모델 지원**: `gemini-1.5-flash`, `gemini-1.5-pro` 등 용도에 맞는 모델을 선택하여 사용 가능합니다.
- **경량성**: 아주 적은 리소스로 구동되며, 원격 서버나 CI/CD 환경에서도 문제없이 작동합니다.

## 🔗 공식 리소스 및 설치
- **GitHub 저장소**: [github.com/google-gemini/gemini-cli](https://github.com/google-gemini/gemini-cli)
- **설치 명령어**:
  ```bash
  npm install -g @google/gemini-cli
  ```
- **API 키 발급**: [Google AI Studio](https://aistudio.google.com/app/apikey)

## 🚀 Agentic Framework 적용 및 사용법

### 1. 프로젝트 이식 (Transplantation)
명령줄 환경에서 에이전트 자동화 기능을 활성화하려면 아래 폴더를 복사하세요.

- **복사할 항목**:
    - `.agent/`: 모든 실행 스크립트와 규칙이 포함된 핵심 폴더

### 2. 사용 방법 (Usage)
PowerShell 터미널에서 전용 스크립트를 실행하여 작업을 관리합니다.

- **명령 예시**:
    ```powershell
    # 대기 중인 태스크를 감지하고 자동으로 작업을 수행하는 백그라운드 세션 시작
    .\.agent\scripts\launch_subsession.ps1
    
    # 현재 모든 태스크의 상태와 프로세스 모니터링
    .\.agent\scripts\check_status.ps1
    ```

### 3. 정상 작동 확인 (Validation)
스크립트가 정상적으로 실행되는지 확인하려면 다음을 입력하세요.
- **입력**: `.\.agent\scripts\check_status.ps1`
- **기대 결과**: 현재 대기 중(Pending), 진행 중(In Progress)인 태스크 목록이 테이블 형태로 출력되어야 합니다.

### 4. 최신 버전 업데이트 (Update)
에이전트 시스템의 실행 스크립트와 핵심 규칙을 최신 상태로 유지하려면 다음 명령을 실행하세요.

> **업데이트 프롬프트**:
> `https://github.com/LowyShin/giip-dev-agent 저장소의 최신 .agent 폴더 내용을 확인하고, 현재 프로젝트의 .agent 폴더 내 스크립트와 규칙들을 최신 버전으로 갱신해줘.`

## 🧠 Karpathy 행동 지침

본 프레임워크는 Gemini CLI 사용 시 LLM 코딩 실수를 방지하기 위해 [Karpathy 행동 지침](../../.agent/rules/10_karpathy_guidelines.md)을 따릅니다. 관련 설정은 `GEMINI.md`에 포함되어 있습니다.

1. **Think Before Coding** — 가정을 명시적으로 밝히고, 불확실하면 질문합니다.
2. **Simplicity First** — 문제를 해결하는 최소한의 코드만 작성합니다.
3. **Surgical Changes** — 반드시 필요한 것만 수정합니다.
4. **Goal-Driven Execution** — 시작 전에 검증 가능한 성공 기준을 정의합니다.

> 전체 내용: [`.agent/rules/10_karpathy_guidelines.md`](../../.agent/rules/10_karpathy_guidelines.md) | [원본 레포](https://github.com/forrestchang/andrej-karpathy-skills)

---
*본 에이전트 시스템의 백그라운드 자동화 세션은 Gemini CLI를 활용하여 고성능을 유지합니다.*
