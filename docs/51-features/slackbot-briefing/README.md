# 슬랙봇 및 자동 브리핑 모듈 (Slackbot Briefings & OpenClaw Integration) 💬🤖

이 모듈은 사내 메신저인 슬랙(Slack)과 에이전트를 연동(OpenClaw 사용)하여, 매일 아침 일정을 브리핑해 주고 저녁 6시에는 깃허브(GitHub) 커밋 데이터를 자동 요약한 개발 보고서를 제공합니다.

---

## 🛠️ 주요 기능

1. **아침 일정 브리핑**: 사내 일정 DB(`docs/51-features/_data/schedule.json`)를 참조해 오늘의 일정 및 할 일(Todo) 목록을 채널에 브리핑합니다.
2. **저녁 개발 진행 보고**: 최근 Git/GitHub 커밋 이력을 자동으로 파싱하여, 개발팀의 하루 업무 진행 내역을 요약하여 보고합니다.
3. **OpenClaw 기반 대화형 원격 제어**: 슬랙 대화를 통해 에이전트에게 실시간 지시나 쿼리를 수행할 수 있습니다.

---

## 🚀 사용법

### 1. 테스트 실행 (아침/저녁 메시지 및 슬랙 발송 테스트)
```powershell
node docs/51-features/slackbot-briefing/slackbot_briefing.js --test
```

### 2. 아침 일정 브리핑 발송
```powershell
node docs/51-features/slackbot-briefing/slackbot_briefing.js --morning
```

### 3. 저녁 6시 개발 보고서 발송
```powershell
node docs/51-features/slackbot-briefing/slackbot_briefing.js --evening
```

---

## ⚙️ OpenClaw 및 스케줄러 연동 가이드

이 브리핑을 매일 자동으로 수행하고 슬랙봇 대화를 활성화하려면 **OpenClaw**와 **스케줄러**를 연동해야 합니다.

### A. OpenClaw 슬랙봇 연동 방법
1. 기존 연동 가이드인 [OpenClaw Slack 메신저 연동 가이드](../../../docs/50-technical/openclaw-slack-integration.md)에 따라 슬랙 앱 생성 및 토큰 발급을 완료합니다.
2. `openclaw onboard` 명령어로 연동 설정을 저장하고 `openclaw start`를 실행해 에이전트를 대기 상태로 활성화합니다.
3. 슬랙 대화창에서 에이전트를 소환(`@GIIP Agent`)하여 업무를 할당할 수 있습니다:
   - *슬랙 명령 예시*: `@GIIP Agent 5월 23일 오후 2시에 "바이브 인베스팅 백테스트 코드 검토" 일정을 이지원 담당으로 등록해줘.`
   - 에이전트는 OpenClaw의 파일 수정 도구를 사용하여 `docs/51-features/_data/schedule.json` 파일을 자동 업데이트하고 등록 완료 피드백을 전달합니다.

### B. 매일 정기 브리핑 자동 발송 (Windows 작업 스케줄러 설정)
Windows 환경에서 아침 9시와 저녁 6시에 자동으로 스크립트가 실행되도록 등록합니다.

#### 1. 아침 브리핑 작업 등록 (PowerShell 명령어)
```powershell
$Action = New-ScheduledTaskAction -Execute "node.exe" -Argument "docs/51-features/slackbot-briefing/slackbot_briefing.js --morning" -WorkingDirectory "c:\Users\lowys\Downloads\Projects\giip-dev-agent"
$Trigger = New-ScheduledTaskTrigger -Daily -At 9:00AM
Register-ScheduledTask -TaskName "GIIP_Morning_Briefing" -Trigger $Trigger -Action $Action -Description "Daily morning briefing for slackbot"
```

#### 2. 저녁 보고서 작업 등록 (PowerShell 명령어)
```powershell
$Action = New-ScheduledTaskAction -Execute "node.exe" -Argument "docs/51-features/slackbot-briefing/slackbot_briefing.js --evening" -WorkingDirectory "c:\Users\lowys\Downloads\Projects\giip-dev-agent"
$Trigger = New-ScheduledTaskTrigger -Daily -At 6:00PM
Register-ScheduledTask -TaskName "GIIP_Evening_Briefing" -Trigger $Trigger -Action $Action -Description "Daily evening development report summary"
```
