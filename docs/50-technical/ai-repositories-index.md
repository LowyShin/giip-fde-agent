# 외부 AI 도구 및 레포지토리 목록 (External AI Repositories)

AI 에이전트 시스템과 연동하거나 활용할 수 있는 외부 유용한 레포지토리 및 도구 모음입니다.

## 🤖 AI 에이전트 및 유지관리 도구

### [ClawSweeper](https://github.com/openclaw/clawsweeper) ([소개 페이지](../../docs/50-technical/clawsweeper-intro.md))
- **한줄 소개**: AI를 이용해 대규모 GitHub 레포지토리의 이슈와 PR을 자동으로 분석하고 정리하는 유지관리 봇입니다.

### [awesome-agents](https://github.com/kyrolabs/awesome-agents)
- **한줄 소개**: AI 에이전트 프레임워크, 도구 및 관련 연구 리소스를 선별한 큐레이션 목록입니다.

### [figaro](https://github.com/byt3bl33d3r/figaro)
- **한줄 소개**: Claude Code 등 에이전트를 다양한 환경에서 오케스트레이션하고 관리하는 도구입니다.

### [claude-squad](https://github.com/smtg-ai/claude-squad)
- **한줄 소개**: 여러 AI 터미널 에이전트를 동시에 관리하고 병렬 작업을 수행하는 애플리케이션입니다.

### [cmux](https://github.com/craigsc/cmux)
- **한줄 소개**: 여러 개의 Claude 에이전트를 효율적으로 병렬 실행 및 관리할 수 있도록 도와주는 도구입니다.

### [gstack](https://github.com/garrytan/gstack) ([분석 리포트](../../docs/50-technical/gstack-analysis.md))
- **한줄 소개**: Garry Tan의 23가지 전문 에이전트 도구 모음으로, CEO, 디자이너, 보안 담당자 등 다양한 역할을 수행하게 돕습니다.

### [LLM Wiki](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f) ([분석 리포트](../../docs/70-LowyOpinion/capacydiagram.md))
- **한줄 소개**: Andrej Karpathy가 제안한 AI 에이전트 기반의 지속적인 지식 축적 및 위키 관리 패턴(K-Layer의 원형)입니다.

### [SkillOpt](https://github.com/microsoft/SkillOpt)
- **한줄 소개**: 가중치 학습 없이 에이전트의 스킬 지침 파일(SKILL.md)을 미니배치, 학습률(텍스트 편집 예산), 검증 게이트를 통해 최적화하는 텍스트 공간 스킬 학습 프레임워크입니다.


## 🎨 디자인 및 문서화 도구

### [Open Design](https://github.com/nexu-io/open-design) ([소개 페이지](../../docs/50-technical/open-design-intro.md))
- **한줄 소개**: Claude Design의 오픈소스 대안으로, Claude Code·Codex·Cursor·Copilot 등 주요 AI 에이전트와 MCP로 연동되며 150개의 브랜드 DESIGN.md 시스템과 261개 플러그인을 제공하는 에이전트 네이티브 디자인 워크스페이스입니다.

### [designmd.ai](https://designmd.ai)
- **한줄 소개**: AI 개발을 위한 고품질 DESIGN.md 파일과 CLI 도구를 제공하는 플랫폼입니다.

## 🔬 과학·연구 전용 스킬 (선택적 다운로드)

> ⚠️ **이 섹션의 스킬은 과학·연구 관련 프로젝트에서만 선택적으로 다운로드하세요.**
> 일반 개발 프로젝트에는 포함하지 않습니다.

### [scientific-agent-skills](https://github.com/K-Dense-AI/scientific-agent-skills)
- **한줄 소개**: 암 유전체학, 신약-표적 결합, 분자동역학, RNA velocity, 지리공간 과학, 시계열 예측, 78개 이상의 과학 데이터베이스 등을 포함하는 147개의 과학·연구 전용 에이전트 스킬 모음입니다.
- **적용 대상**: 생물학, 화학, 의학, 지구과학 등 과학·연구 관련 프로젝트
- **호환 도구**: Cursor, Claude Code, Codex, Google Antigravity 등 Agent Skills 표준을 지원하는 모든 AI 에이전트
- **다운로드 방법**: 해당 프로젝트 루트에서 `git clone https://github.com/K-Dense-AI/scientific-agent-skills` 후 필요한 스킬 파일만 `.agent/skills/`에 복사

---
*작업 이력: 20260429 01:23:55: 외부 AI 레포지토리 리스팅 페이지 생성*
*작업 이력: 20260618: scientific-agent-skills 과학·연구 전용 섹션에 추가 (이슈 #17)*
*작업 이력: 20260618: open-design 디자인 도구 섹션에 추가 (이슈 #19)*
