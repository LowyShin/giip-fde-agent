# OpenClaw (오픈클로) 💬

## 📋 개요
**OpenClaw**는 자율형 AI 에이전트를 위한 오픈소스 **메신저 게이트웨이 및 프레임워크**입니다. 로컬 PC나 서버에서 실행 중인 에이전트를 Slack, Discord, Telegram 등 익숙한 채팅 플랫폼에 연결하여, 장소에 구애받지 않고 프로젝트를 제어할 수 있게 해줍니다.

## ✨ 주요 특징
- **멀티 플랫폼 지원**: Slack, WhatsApp, Telegram, Discord 등 다양한 메신저 연동 가능.
- **방화벽 친화적**: Slack Socket Mode 등을 지원하여 복잡한 네트워크 설정 없이 터널링 연결 제공.
- **로컬 워크스페이스 제어**: 에이전트가 로컬 파일 시스템에 접근하여 코드를 읽거나 수정하고, 명령어를 실행할 수 있음.
- **보안 및 권한 관리**: 페어링 코드 모드 및 샌드박스 실행(Docker)을 지원하여 안전한 원격 제어 가능.
- **셀프 호스팅**: 클라우드 의존성 없이 본인의 인프라에서 에이전트를 완전히 통제할 수 있음.

## 🔗 공식 리소스 및 연동 가이드
- **GitHub**: [OpenClaw/OpenClaw](https://github.com/OpenClaw/OpenClaw)
- **연동 가이드**: [Slack 메신저 연동 상세 가이드](../50-technical/openclaw-slack-integration.md)

## 🚀 GIIP Agent System 적용 및 사용법

### 1. 프로젝트 이식 (Transplantation)
메신저를 통해 GIIP 에이전트와 대화하려면 아래 항목들이 서버/로컬 환경에 준비되어야 합니다.

- **복사할 항목**:
    - `.agent/`: 핵심 엔진 (규칙, 스킬, 워크플로우)
    - `GEMINI.md`: 에이전트 페르소나 및 시스템 지침

### 2. 사용 방법 (Usage)
OpenClaw를 통해 메신저(Slack 등)에 연결된 에이전트에게 메시지를 보냅니다.

- **명령 예시**:
    ```text
    giip status (현재 프로젝트 상태 및 태스크 확인)
    @에이전트 /pdca를 사용해서 오늘 작업한 내용을 요약해줘.
    ```

### 3. 정상 작동 확인 (Validation)
메신저에서 에이전트가 GIIP 시스템을 인식하고 있는지 확인하려면 다음을 입력하세요.
- **입력**: `giip status`
- **기대 결과**: 에이전트가 메신저 채널을 통해 "GIIP Orchestrator"로서 응답하며, 프로젝트 루트의 `.agent/` 정보를 바탕으로 현재 작업 현황을 브리핑해야 합니다.

### 4. 최신 버전 업데이트 (Update)
OpenClaw 환경에서 GIIP의 최신 규칙을 유지하려면 메신저에서 다음과 같이 요청하세요.

> **업데이트 프롬프트**:
> `https://github.com/LowyShin/giip-dev-agent 저장소의 최신 .agent 폴더와 GEMINI.md 내용을 확인하고, 현재 연결된 워크스페이스의 에이전트 시스템을 최신 상태로 업데이트해줘.`

## 🚀 빠른 시작 (CLI)
1. **설치**: `npm install -g @openclaw/cli@latest`
2. **설정**: `openclaw onboard` (메신저 토큰 및 워크스페이스 경로 설정)
3. **가동**: `openclaw start`

---
*GIIP Agent System은 OpenClaw를 통해 프로젝트의 지식을 메신저로 확장하여 진정한 '주머니 속의 개발팀'을 완성합니다.*
