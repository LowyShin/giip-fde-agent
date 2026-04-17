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

## 🚀 빠른 시작 (CLI)
1. **설치**: `npm install -g @openclaw/cli@latest`
2. **설정**: `openclaw onboard` (메신저 토큰 및 워크스페이스 경로 설정)
3. **가동**: `openclaw start`

---
*GIIP Agent System은 OpenClaw를 통해 프로젝트의 지식을 메신저로 확장하여 진정한 '주머니 속의 개발팀'을 완성합니다.*
