# 🚀 빠른 시작 가이드 (Quick Start Guide)

AI 개발 도구를 처음 접하시는 분들을 위한 친절한 시작 가이드입니다.

> **이 가이드는 누구를 위한 것인가요?**  
> - AI 코딩 도구를 처음 사용하시는 분
> - Antigravity나 Cursor 같은 도구가 무엇인지 모르시는 분
> - 어디서부터 시작해야 할지 막막하신 분

---

## 📚 목차
1. [giip FDE Agent란?](#-giip-fde-agent란)
2. [필요한 도구 준비하기](#-필요한-도구-준비하기)
3. [저장소 다운로드 및 설정](#-저장소-다운로드-및-설정)
4. [AI 도구 선택 및 설치](#-ai-도구-선택-및-설치)
5. [첫 번째 대화 시작하기](#-첫-번째-대화-시작하기)
6. [Slack 봇 연결하기 (giipclaude Bot)](#-slack-봇-연결하기-giipclaude-bot)
7. [다음 단계](#-다음-단계)

---

## 🤔 giip FDE Agent란?

**giip FDE Agent**는 여러분의 PC에 설치되어 상주하는 **포워드 배포형(Forward-Deployed) AI 엔지니어링 팀**입니다. AI가 여러분의 코드 작성을 도와주는 것을 넘어, 계획·구현·검증·최적화를 스스로 수행합니다.

### 무엇을 할 수 있나요?
- ✅ 복잡한 개발 작업을 자동으로 수행
- ✅ 코드 리뷰 및 개선 제안
- ✅ 버그 찾기 및 수정
- ✅ 문서 자동 생성
- ✅ 테스트 코드 작성

### 어떻게 작동하나요?
1. **오케스트레이터(지휘자)**: 여러분의 요청을 받아 분석합니다
2. **전문 에이전트들(전문가들)**: 각자의 전문 분야(개발, 테스트, 리뷰 등)를 담당합니다
3. **협업**: 여러 전문가가 함께 작업하여 최상의 결과를 만들어냅니다

---

## 🛠️ 필요한 도구 준비하기

### 1단계: 기본 도구 설치

모든 사용자가 먼저 설치해야 하는 도구들입니다.

#### Windows 사용자
```powershell
# 1. PowerShell 7 설치 (Windows 10/11)
winget install --id Microsoft.PowerShell --source winget

# 2. Node.js 설치 확인 (없으면 https://nodejs.org 에서 다운로드)
node --version

# 3. Git 설치 확인 (없으면 https://git-scm.com 에서 다운로드)
git --version
```

#### Mac/Linux 사용자
```bash
# 1. Node.js 설치 확인
node --version

# 2. Git 설치 확인
git --version
```

> 💡 **설치가 필요한 경우**: [도구 다운로드 페이지](TOOLS_DOWNLOAD.md)에서 자세한 설치 방법을 확인하세요.

---

## 📥 저장소 다운로드 및 설정

### 방법 1: Git 사용 (권장)

```bash
# 1. 원하는 폴더로 이동
cd 내문서/프로젝트

# 2. 저장소 복제
git clone https://github.com/LowyShin/giip-fde-agent.git

# 3. 폴더로 이동
cd giip-fde-agent
```

### 방법 2: ZIP 파일 다운로드

1. [GitHub 저장소](https://github.com/LowyShin/giip-fde-agent) 방문
2. 녹색 "Code" 버튼 클릭
3. "Download ZIP" 선택
4. 다운로드한 파일 압축 해제
5. 압축 해제한 폴더로 이동

---

## 🤖 AI 도구 선택 및 설치

여러분의 상황에 맞는 도구를 선택하세요!

### 🎯 추천 선택 가이드

#### ⭐ 최우선 추천: Claude Code (Claude CLI)
- **장점**: FDE Agent와 가장 궁합이 좋습니다. 이 저장소의 Slack 봇(**giipclaude**)이 `claude -p` CLI로 동작하도록 설계되어, **Anthropic API Key 없이**(구독 로그인만으로) 에이전트/서브에이전트 실행과 원격 제어까지 바로 이어집니다.
- **비용**: Claude 구독(Pro/Max) 또는 사용량제. `claude` CLI 로그인만으로 사용
- **설치**: [claude.ai/code](https://claude.ai/code) 에서 설치 → `claude --version` 확인 → 최초 1회 로그인
- **다음 단계**: 설치했다면 아래 [Slack 봇 연결하기](#-slack-봇-연결하기-giipclaude-bot)로 바로 원격 조종까지 세팅하세요.

#### 초보자·무료용: Antigravity (무료)
- **장점**: 한국어 지원, 사용하기 쉬움, 무료
- **단점**: 백그라운드 자동화 사용 시 Gemini API Key 필요 (수동 모드는 불필요)
- **다운로드**: [Antigravity Manager](https://agm.littleworld.net/)

#### 전문가용: Cursor ($20/월)
- **장점**: 강력한 기능, 빠른 속도
- **단점**: 유료 (무료 평가판 있음)
- **다운로드**: [Cursor](https://www.cursor.com/)

#### VS Code 사용자: GitHub Copilot ($10/월)
- **장점**: VS Code 완벽 통합
- **단점**: 유료 (학생/오픈소스 기여자 무료)
- **설치**: VS Code 확장 프로그램

> 📖 **더 많은 도구 비교**: [도구 다운로드 페이지](TOOLS_DOWNLOAD.md)에서 전체 목록을 확인하세요.

---

## 🎬 Antigravity로 시작하기 (무료 옵션)

### 1단계: (선택) API Key 발급
> 💡 **자동화 기능을 사용하지 않으려면 이 단계는 건너뛰어도 됩니다.**

1. [Google AI Studio](https://aistudio.google.com/app/apikey) 접속
2. Google 계정으로 로그인
3. "Get API Key" 또는 "API 키 만들기" 클릭
4. 생성된 키 복사 (예: `AIzaSy...`)

### 2단계: Antigravity 설치

1. [Antigravity Manager 다운로드](https://agm.littleworld.net/)
2. 설치 프로그램 실행
3. 설치 완료 후 Antigravity Manager 실행

### 3단계: 프로젝트 설정

#### A. 기존 프로젝트에 적용하기
```bash
# 1. 여러분의 프로젝트 폴더로 이동
cd 내프로젝트폴더

# 2. GIIP Agent 파일 복사 (PowerShell)
# .git 폴더를 제외하고 복사
Copy-Item -Path "giip-fde-agent\.agent" -Destination "." -Recurse -Force
Copy-Item -Path "giip-fde-agent\GEMINI.md" -Destination "." -Force
Copy-Item -Path "giip-fde-agent\.cursorrules" -Destination "." -Force
```

#### B. 새 프로젝트 시작하기
```bash
# GIIP Agent 저장소를 그대로 프로젝트로 사용
cd giip-fde-agent
```

### 4단계: (선택) 자동화를 위한 API Key 설정
> 💡 **수동 모드(클립보드 핸드오프)만 사용할 경우 이 설정은 하지 않아도 됩니다.**

```bash
# 1. settings.json.sample 파일을 복사
cd .agent
copy settings.json.sample settings.json

# 2. settings.json 파일을 열어서 API Key 입력
# "YOUR_GEMINI_API_KEY_HERE"를 여러분의 실제 키로 교체
```

또는 에디터에서 `.agent/settings.json` 파일을 열어 다음과 같이 수정:
```json
{
  "apiKey": "AIzaSy여러분의실제키",
  "model": "gemini-2.0-flash-exp"
}
```

---

## 💬 첫 번째 대화 시작하기

### Antigravity에서

1. Antigravity Manager 실행
2. 프로젝트 폴더 선택 또는 드래그 앤 드롭
3. 채팅창에 다음 메시지 입력:

```
안녕? 넌 오케스트레이터야. 
먼저 이 프로젝트가 무엇을 하는 프로젝트인지 분석해주고,
내가 무엇을 할 수 있는지 알려줘.
```

### 예시 질문들

#### 프로젝트 분석
```
이 프로젝트의 구조를 분석하고 주요 기능을 설명해줘.
```

#### 새 기능 개발
```
넌 오케스트레이터야. 
사용자 로그인 기능을 추가하려고 하는데,
필요한 작업을 분석하고 담당 에이전트에게 위임해줘.
```

#### 버그 수정
```
로그인 시 에러가 발생하는데, 
systematic-debugging 스킬을 사용해서 원인을 찾아줘.
```

#### 코드 리뷰
```
최근에 작성한 코드를 리뷰하고 개선점을 제안해줘.
```

---

## 🎓 기본 사용 패턴

### 1. 오케스트레이터 모드로 시작

```
넌 오케스트레이터야. 
너의 롤을 확인하고 아래 업무를 분석하여 
각 담당자에게 작업을 위임해줘.

-- 업무 내용 --
[여기에 하고 싶은 작업 설명]
```

### 2. PDCA 방법론 활용

복잡한 작업은 단계별로 진행하세요:

```
/pdca plan 사용자인증기능
```
→ 계획 수립

```
/pdca design 사용자인증기능
```
→ 설계 문서 생성

```
/pdca do 사용자인증기능
```
→ 구현

```
/pdca analyze 사용자인증기능
```
→ 검증

### 3. 자동 실행 모드 (고급)

백그라운드에서 자동으로 작업 수행:

```powershell
# PowerShell에서 실행
.\.agent\scripts\launch_subsession.ps1
```

또는 5분마다 자동 실행:
```cmd
.\auto_agent.bat
```

---

## 💬 Slack 봇 연결하기 (giipclaude Bot)

FDE Agent를 **Slack에서 원격으로 조종**할 수 있습니다. `slack-bot/`의 **giipclaude Bot**은 Anthropic API Key 없이 **Claude CLI(`claude -p`)로 동작**하며, 멘션 한 번으로 작업을 분석·실행하고 결과 GitHub URL까지 답신합니다.

### 사전 준비
- **Node.js 18+**
- **Claude CLI** 설치 및 로그인 (`claude --version` 이 동작해야 함) — 위 [최우선 추천: Claude Code](#-ai-도구-선택-및-설치) 참고
- **Socket Mode**를 켠 Slack App (아래 1단계)

### 1단계: Slack App 만들기 (Socket Mode)
1. [api.slack.com/apps](https://api.slack.com/apps) → **Create New App** → **From scratch** → 앱 이름·워크스페이스 선택
2. **Socket Mode** 활성화 → **App-Level Token** 생성(스코프 `connections:write`) → `xapp-...` 복사
3. **OAuth & Permissions → Bot Token Scopes** 추가:
   `app_mentions:read`, `chat:write`, `channels:history`, `channels:read`, `groups:history`, `im:history`, `im:read`, `im:write`, `users:read`
4. **Event Subscriptions** 활성화 → Bot 이벤트 구독: `app_mention`, `message.im`, `message.channels`, `message.groups`
5. **Install to Workspace** → **Bot User OAuth Token** `xoxb-...` 복사
6. 봇을 사용할 채널에 초대: `/invite @<봇이름>`

> ⚠️ 스코프를 바꾼 뒤에는 반드시 **Reinstall** 해야 반영됩니다. Socket Mode라 Request URL은 비워둬도 됩니다.

### 2단계: 설치 & 환경설정
```bash
cd giip-fde-agent/slack-bot
npm install
cp .env.example .env
```
`.env` 최소 설정:
```env
SLACK_BOT_TOKEN=xoxb-...            # 5단계의 Bot User OAuth Token
SLACK_APP_TOKEN=xapp-...            # 2단계의 App-Level Token
WORKSPACE_DIR=/절대경로/내프로젝트     # .agent/ 가 있는 작업 폴더 (git push 대상)

# 선택
# SLACK_CHANNEL_IDS=C0XXXX,C0YYYY   # 특정 채널만 청취 (DM은 항상 동작)
# PROJECTS_ROOT=/절대경로/projects    # 여러 프로젝트 prefix 전환용
# GITHUB_TOKEN=ghp_...              # !issues 명령용 (repo 스코프)
# GITHUB_REPO=owner/repo
```

### 3단계: 실행
```bash
node index.js

# 또는 pm2로 상시 실행 (권장)
npm install -g pm2
pm2 start index.js --name giipclaude-bot
pm2 save
pm2 startup     # 출력된 안내를 따라 부팅 시 자동 시작 등록
```
Socket Mode 연결 성공 로그가 뜨면 준비 완료입니다.

### 사용 예시
```
@giipclaude 설정 페이지에 다크모드 토글 추가해줘
```
→ 봇이 분석 후 **태스크 ID와 계획**을 제시하고 승인을 기다립니다.
```
go 20240601120000     # 승인 → 서브에이전트 실행 → git push → 결과 GitHub URL 답신
tasklist              # 대기 중 태스크 목록
@giipclaude 인증 흐름이 어떻게 되나요?    # K-Layer 지식 기반 Q&A
```

> 📖 상세 스코프·이벤트·트러블슈팅: [slack-bot/SLACK_APP_SETUP.md](slack-bot/SLACK_APP_SETUP.md) · [slack-bot/README.md](slack-bot/README.md)

---

## 🎯 다음 단계

축하합니다! 🎉 첫 번째 AI 에이전트 대화를 시작하셨습니다.

### 더 배우기

1. **[Antigravity 상세 가이드](ANTIGRAVITY_USAGE_GUIDE.md)**: PDCA 방법론과 고급 기능
2. **[프롬프트 예시](prompt_example.md)**: 효과적인 질문 방법
3. **[시스템 가이드](.agent/README.md)**: 에이전트 시스템 심화 학습

### 자주 묻는 질문

#### Q: API 사용료가 걱정됩니다.
A: Google Gemini API는 무료 할당량이 넉넉합니다. 일반적인 개발 용도로는 무료로 충분합니다.

#### Q: 어떤 도구가 가장 좋나요?
A: 
- **FDE Agent 정석 (권장)**: Claude Code (Claude CLI) — Slack 봇 연결까지 그대로 이어짐
- **무료로 시작**: Antigravity + Gemini API
- **전문 개발자**: Cursor 또는 GitHub Copilot
- **VS Code 사용자**: GitHub Copilot

#### Q: 영어를 잘 못하는데 괜찮나요?
A: 네! 이 시스템은 한국어 우선(Korean-First)으로 설계되었습니다. 모든 대화를 한국어로 하실 수 있습니다.

#### Q: 오류가 발생하면 어떻게 하나요?
A: 
1. [Issues 페이지](https://github.com/LowyShin/giip-fde-agent/issues)에 질문 올리기
2. 에러 메시지와 함께 AI에게 물어보기
3. [GIIP 공식 홈페이지](https://giip.littleworld.net/)에서 지원 받기

---

## 💡 유용한 팁

### 1. 명확하게 질문하기
❌ 나쁜 예: "이거 고쳐줘"
✅ 좋은 예: "로그인 버튼을 클릭하면 404 에러가 발생하는데, 원인을 찾아서 수정해줘"

### 2. 단계별로 진행하기
복잡한 작업은 작은 단계로 나누세요.

### 3. 검증 요청하기
```
작업이 끝났으면 테스트를 실행해서 제대로 동작하는지 확인해줘.
```

### 4. 코드 스타일 지정하기
```
이 프로젝트는 TypeScript와 React를 사용하고,
함수형 컴포넌트로 작성해줘.
```

---

## 🆘 도움이 필요하신가요?

- **GitHub Issues**: [문제 보고하기](https://github.com/LowyShin/giip-fde-agent/issues)
- **공식 홈페이지**: [https://giip.littleworld.net/](https://giip.littleworld.net/)
- **커뮤니티**: [GitHub Discussions](https://github.com/LowyShin/giip-fde-agent/discussions)

---

## 🔧 문제 해결 (Troubleshooting)

### PowerShell 실행 정책 오류
```powershell
# 오류: "이 시스템에서 스크립트를 실행할 수 없으므로..."
# 해결:
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### API Key 오류
```
오류: "API Key가 유효하지 않습니다"
해결:
1. API Key를 올바르게 복사했는지 확인
2. 앞뒤 공백이 없는지 확인
3. Google AI Studio에서 Key가 활성화되었는지 확인
```

### Gemini CLI 설치 오류
```bash
# 권한 오류가 발생하면
npm install -g @google/gemini-cli --force

# 또는 관리자 권한으로 실행
```

### 프로젝트 복사 후 작동하지 않을 때
```
확인사항:
1. .agent 폴더가 제대로 복사되었는지 확인
2. settings.json 파일이 존재하고 API Key가 설정되었는지 확인
3. AI 도구가 프로젝트 폴더를 올바르게 인식했는지 확인
```

---

**마지막 업데이트**: 2026-07-03  
**작성**: giip FDE Agent Team

---

## 📝 라이선스

이 프로젝트는 Apache 2.0 라이선스를 따릅니다.
자세한 내용은 [LICENSE](LICENSE) 파일을 참조하세요.
