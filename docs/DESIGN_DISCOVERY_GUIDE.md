# Design Discovery & Integration Guide (design-md) 🎨

GIIP Agent System은 단순한 코딩을 넘어, 전문 디자이너의 감각을 프로젝트에 즉시 이식할 수 있는 **멀티 소스 디자인 탐색 시스템**을 내장하고 있습니다. 

본 가이드는 `designmd.ai`, `designmd.app`, `getdesign.md`, `designmd.me` 등 4가지 주요 플랫폼을 활용하여 최적의 `DESIGN.md`를 찾고 에이전트에게 지시하는 방법을 설명합니다.

---

## 🚀 4대 디자인 플랫폼 활용 매트릭스

사용자의 의도에 따라 에이전트가 최적의 소스를 선택합니다.

| 플랫폼 | 주요 용도 | 특징 | 에이전트 동작 |
| :--- | :--- | :--- | :--- |
| **[designmd.ai](https://designmd.ai)** | **자동화 & 표준 SaaS** | CLI 지원, 전문 AI 개발용 키트 | `npx designmd` 자동 다운로드 |
| **[designmd.app](https://designmd.app)** | **커뮤니티 라이브러리** | 423+개 파일, 에이전트 설정 가이드 | `CLAUDE.md`, `.cursorrules` 생성 |
| **[getdesign.md](https://getdesign.md)** | **브랜드 복제 (Branding)** | Stripe, Vercel, Notion 등 유명 브랜드 | `npx getdesign add <brand>` |
| **[designmd.me](https://designmd.me)** | **커스텀 디자인 추출** | URL/텍스트로 디자인 시스템 자동 생성 | 특정 사이트 디자인 즉시 추출 |

---

## 🛠️ 주요 사용법 (How to Use)

### 1. 브랜드 스타일 적용하기 (Brand Cloning)
유명 서비스와 유사한 고품질 디자인 시스템을 즉시 적용하고 싶을 때 사용합니다.
- **명령어 예시**: "Stripe 스타일로 프로젝트 디자인을 잡아줘."
- **에이전트 동작**: `npx getdesign add stripe` 실행 후 `DESIGN.md` 생성.

### 2. 최신 트렌드 디자인 탐색하기 (Discovery)
새로운 프로젝트를 시작할 때 어울리는 디자인을 추천받고 싶을 때 사용합니다.
- **명령어 예시**: "핀테크 대시보드에 어울리는 디자인 몇 개만 추천해 줘."
- **에이전트 동작**: `designmd.ai` 및 `designmd.app`을 검색하여 후보 리스트와 미리보기 링크 제공.

### 3. 특정 사이트 디자인 가져오기 (Live Extraction)
참고하고 싶은 웹사이트의 URL만 있으면 해당 사이트의 색상, 폰트, 레이아웃을 마크다운으로 추출합니다.
- **명령어 예시**: "https://example.com 사이트 디자인을 마크다운으로 추출해 줘."
- **에이전트 동작**: `designmd.me`를 통해 디자인 시스템 생성 및 저장.

### 4. 에이전트별 최적화 설정 (Agent Steering)
선택된 디자인이 각 개발 도구(Cursor, Claude Code 등)에서 완벽하게 작동하도록 설정 파일을 생성합니다.
- **에이전트 동작**: `designmd.app/guides`를 참조하여 `.cursorrules` 또는 `CLAUDE.md` 자동 업데이트.

---

## 💡 팁 및 주의사항

- **API Key**: `designmd.ai`에서 고유한 키트를 다운로드하려면 API Key가 필요할 수 있습니다. 에이전트가 안내하는 환경 변수(`DESIGNMD_API_KEY`) 설정을 참조하세요.
- **DESIGN.md 우선순위**: 프로젝트 루트에 `DESIGN.md`가 생성되면, 이후 모든 UI 컴포넌트 개발 시 에이전트가 이 파일의 토큰을 최우선으로 준수합니다.
- **미리보기 활용**: 에이전트가 제공하는 링크를 클릭하여 웹에서 미리 시각적 결과물을 확인한 후 적용을 결정하세요.

---
© 2026 GIIP Design Integration Team. Optimized for AI-Native Development.
