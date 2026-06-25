# Open Design - 에이전트 네이티브 오픈소스 디자인 워크스페이스

Open Design(OD)은 Anthropic의 Claude Design에 대응하는 **로컬 우선 오픈소스 디자인 도구**입니다. 기존 AI 에이전트(Claude Code, Codex, Cursor, GitHub Copilot, Gemini CLI 등)와 MCP(Model Context Protocol)로 연동되며, 브라우저 없이 로컬 데스크탑에서 실행됩니다.

## 🚀 주요 기능

- **에이전트 네이티브**: 이미 설치된 Claude Code, Codex, Cursor, Copilot, Gemini CLI 등 21개 이상의 코딩 에이전트 CLI를 직접 실행 엔진으로 사용
- **150개 브랜드 DESIGN.md 시스템**: Stripe, Vercel, Apple 등 프로 수준의 디자인 시스템을 즉시 적용
- **261개 플러그인**: 다양한 기능 확장 지원
- **100개 이상 스킬**: 바로 사용 가능한 에이전트 스킬 내장
- **다양한 아티팩트 생성**: 웹/데스크탑/모바일 프로토타입, 라이브 대시보드, 슬라이드 덱, 이미지, HyperFrames 모션 그래픽
- **다중 모델 지원**: GPT, Claude, Gemini, DeepSeek 등 AMR(Agentic Model Router)을 통해 20개 이상의 모델 활용
- **내보내기 형식**: HTML, PDF, PPTX, MP4

## 🔌 에이전트 MCP 연동

OD는 `od` CLI를 통해 에이전트별 MCP 서버를 한 줄로 연결합니다:

```bash
od mcp install claude      # Claude Code
od mcp install codex       # Codex CLI
od mcp install cursor      # Cursor
od mcp install copilot     # VS Code + GitHub Copilot
od mcp install gemini      # Gemini CLI
od mcp install antigravity # Google Antigravity
```

## 🛠️ 설치 및 시작

### Docker (권장)
```bash
cd deploy
cp .env.example .env
# OD_API_TOKEN 설정 (openssl rand -hex 32 로 생성)
docker compose up -d
# http://localhost:7456 에서 접속
```

### 개발 모드 (Node.js 24 + pnpm 10.33.x)
```bash
corepack enable
pnpm install
pnpm tools-dev run web
```

## 🎯 giip-dev-agent와의 활용

- `.agent/skills/open-design/SKILL.md` 스킬을 통해 에이전트가 Open Design의 DESIGN.md 시스템을 자동 적용
- 프로토타입, 슬라이드, 대시보드 생성 워크플로우에 통합 가능
- 디자인 시스템 계약(`DESIGN.md`)을 팀 공유 문서로 관리

## 🔗 관련 링크

- **GitHub Repository**: [nexu-io/open-design](https://github.com/nexu-io/open-design)
- **공식 웹사이트**: [open-design.ai](https://open-design.ai)
- **AMR(모델 라우터)**: [open-design.ai/amr](https://open-design.ai/amr/)
- **Discord**: [discord.gg/9ptkbbqRu](https://discord.gg/9ptkbbqRu)
- **라이선스**: Apache 2.0

---
*작업 이력: 20260618: Open Design 소개 페이지 생성 (이슈 #19)*
