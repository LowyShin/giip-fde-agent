# OpenClaw Slack 메신저 연동 가이드 💬

이 문서는 **OpenClaw**를 사용하여 GIIP Agent System의 지식을 Slack 메신저에서 제어하고 쿼리할 수 있도록 설정하는 방법을 설명합니다. 이 설정을 완료하면 외부에서도 모바일이나 PC의 Slack 앱을 통해 레포지토리의 정보를 확인하고 작업을 명령할 수 있습니다.

---

## 🛠️ 사전 준비 (Prerequisites)

이 가이드를 따라하기 전, 다음이 설치되어 있어야 합니다:
1. **Node.js**: v18 이상 (LTS 권장)
2. **GIIP Agent System**: 이 레포지토리가 로컬 PC에 존재해야 함

---

## 🏗️ 1단계: Slack 앱 설정 (Slack App Setup)

OpenClaw는 Slack의 **Socket Mode**를 사용하므로, 별도의 포트 포워딩이나 공인 IP 없이도 방화벽 뒤에서 안전하게 동작합니다.

### 1.1 Slack App 생성
1. [Slack API 대시보드](https://api.slack.com/apps)에 접속하여 **"Create New App"**을 클릭합니다.
2. **"From an app manifest"**를 선택합니다.
3. 앱을 설치할 **Workspace**를 선택합니다.
4. 아래의 YAML 매니페스트를 복사하여 붙여넣습니다 (이름은 자유롭게 변경 가능).

```yaml
display_information:
  name: GIIP Agent
  description: Autonomous Agent for Repository Control
  background_color: "#1a1a1a"
features:
  bot_user:
    display_name: GIIP Agent
    always_online: true
  slash_commands:
    - command: /ask
      description: Ask the agent a question about the repo
      usage_hint: "[question]"
      should_localize: false
oauth_config:
  scopes:
    bot:
      - chat:write
      - commands
      - im:history
      - app_mentions:read
      - groups:history
      - channels:history
settings:
  event_subscriptions:
    bot_events:
      - app_mention
      - message.im
  interactivity:
    is_enabled: true
  socket_mode_enabled: true
```

### 1.2 토큰(Token) 발급
앱 생성이 완료되면 두 가지 핵심 토큰이 필요합니다.
1. **App Level Token**: `Settings > Basic Information > App-Level Tokens`에서 생성합니다.
   - 이름: `OpenClawToken`
   - 스코프: `connections:write` 추가
   - 생성된 토큰(`xapp-...`)을 복사해 둡니다.
2. **Bot User OAuth Token**: `Features > OAuth & Permissions`에서 **"Install to Workspace"**를 클릭한 후 생성됩니다.
   - 생성된 토큰(`xoxb-...`)을 복사해 둡니다.

---

## 🚀 2단계: OpenClaw CLI 설치 및 온보딩

자주 사용하는 PC에 OpenClaw를 설치하면, ai와 이야기 한 모든 이력을 PC에 저장하여 관리할 수 있습니다. 개인정보를 읽게 하고 싶지 않다면 VM또는 깨끗한 다른 PC를 준비하여 필요한 정보만 복사해 놓는 것도 좋은 방법입니다.
이것으로 여러분의 에이전트는 지속적으로 학습하여 여러분 만의 전문 에이전트로 발전할 수 있습니다.

### 2.1 CLI 설치

터미널(PowerShell 또는 Bash)에서 아래 명령어를 실행합니다.

```powershell
npm install -g @openclaw/cli@latest
```

### 2.2 온보딩 실행
설치를 마친 후 아래 명령어를 입력하여 설정 마법사를 시작합니다.

```powershell
openclaw onboard
```

- **Select Provider**: 사용 중인 LLM (Gemini, Claude 등)을 선택하고 API Key를 입력합니다.
- **Configure Slack**: 앞서 복사한 **App Token (xapp-...)**과 **Bot Token (xoxb-...)**을 입력합니다.
- **Workspace Path**: 이 레포지토리의 절대 경로를 입력합니다.

---

## 🧠 3단계: 레포지토리 지식 연결

OpenClaw가 이 레포지토리의 `.agent` 지식을 이해하게 하려면, OpenClaw의 워크스페이스를 이 프로젝트 폴더로 지정해야 합니다.

1. `~/.openclaw/config.json` (또는 프로젝트 루트의 `openclaw.json`) 파일을 열어 `workspace` 경로가 올바른지 확인합니다.
2. OpenClaw는 기본적으로 워크스페이스 내의 파일들을 검색할 수 있습니다.
3. **지식 쿼리 예시**: Slack에서 에이전트에게 이렇게 물어보세요.
   - `@GIIP_Agent 현재 레포지토리의 핵심 규칙(GEMINI.md)에 대해 요약해줘.`
   - `/ask "최근에 진행된 K-Layer 업데이트 내용이 뭐야?"`

---

## 🏃 4단계: 가동 및 테스트

### 4.1 서비스 시작
터미널에서 아래 명령어를 실행하면 에이전트가 온라인 상태가 됩니다.

```powershell
openclaw start
```

### 4.2 Slack에서 확인
1. Slack 앱을 열고 앱 목록에서 생성한 **GIIP Agent**를 찾습니다.
2. 에이전트에게 "안녕"이라고 보내거나 레포지토리 관련 질문을 던져보세요.
3. 에이전트가 `ripgrep`이나 파일 읽기 도구를 사용해 답변을 생성하는지 확인합니다.

---

## ⚠️ 주의사항 및 팁
- **보안**: Slack 대화 내용은 OpenClaw를 통해 설정된 LLM으로 전송됩니다. 민감한 데이터가 포함되지 않도록 주의하세요.
- **백그라운드 실행**: OpenClaw를 계속 켜두려면 `pm2`나 Windows 작업 스케줄러를 사용하는 것이 좋습니다.
- **명령어 제어**: OpenClaw는 파일 수정 권한도 가질 수 있습니다. 불안하다면 읽기 전용 스코프로 제한하시기 바랍니다.

---
> [!TIP]
> 이제 야외에서도 내 프로젝트의 상태를 체크하고 간단한 코드 수정을 지시할 수 있습니다!
