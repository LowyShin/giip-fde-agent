# Slack Bot — OpenClaw 버전

> `slack-bot`(Claude CLI 직접 spawn)이나 `slack-bot-minimax`(MiniMax 우선 폴백)와 달리, 이 변형은
> 자체 코드를 작성하지 않고 [OpenClaw](https://docs.openclaw.ai/)라는 멀티 프로바이더 에이전트
> 게이트웨이 프레임워크를 그대로 설치해 Slack 채널 플러그인으로 구동한다.
>
> **여기 담긴 것은 OpenClaw 프레임워크 소스 자체가 아니라, 그 위에서 이 Slack 봇을 재현하기 위한
> 설정 템플릿 + 설치/기동 스크립트다.** OpenClaw 본체는 npm/pnpm 의존성으로 설치하고, 실제 소스는
> 건드리지 않는다(수백 개 파일 규모의 별도 오픈소스 모노레포라 vendoring 대상이 아님).

## 왜 이 폴더가 별도인가

- `slack-bot`/`slack-bot-minimax`는 Node.js로 직접 짠 코드가 `claude` CLI를 spawn하는 구조.
- OpenClaw는 완전히 다른 런타임(자체 Gateway 프로세스 + 플러그인 시스템 + 멀티 프로바이더 모델 라우팅)이라
  코드 구조 자체가 호환되지 않는다. 억지로 "공통 서비스"로 묶으면 과거 사고(다른 봇 코드가 섞여
  들어와 실행 로직이 몰래 치환된 사례, PR #416 in `lowyworkenv`)와 같은 위험이 재발할 수 있어
  **의도적으로 독립 폴더로 분리**했다.

## 사전 준비

```bash
# OpenClaw 설치(전역)
npm install -g openclaw
# 또는 pnpm add -g openclaw

openclaw --version
```

## 설정

1. `openclaw.json.example`을 실제 설정 위치로 복사한다(기본: `~/.openclaw/openclaw.json`).
   ```bash
   openclaw setup   # 최초 1회: ~/.openclaw 초기화
   # 이후 openclaw.json.example 내용을 참고해 models.providers.minimax / agents.defaults.model 등을 채운다
   ```
2. `openclaw.json.example`의 플레이스홀더를 실제 값으로 교체한다:
   - `channels.slack.botToken` / `appToken` — Slack App(Socket Mode) 발급값
   - `models.providers.minimax.apiKey` — MiniMax Token Plan Subscription Key(`sk-cp-` 접두, 종량제 API Key와 다름)
   - `gateway.auth.token` — 게이트웨이 로컬 인증 토큰(임의 생성)
3. 비대화형으로 MiniMax 인증만 추가하고 싶다면:
   ```bash
   openclaw onboard --non-interactive --accept-risk \
     --auth-choice minimax-api --minimax-api-key <sk-cp-...> \
     --skip-channels --skip-daemon --skip-skills --skip-ui --skip-health
   ```
   (채널/데몬/스킬 설정은 건드리지 않고 인증 프로필만 추가 — 이미 운영 중인 게이트웨이가 있으면
   `--skip-*` 없이 돌리지 말 것. 전체 마법사가 채널/데몬 설정까지 재구성할 수 있다.)

## 기동

```bash
openclaw gateway install   # 최초 1회: OS 서비스(schtasks/launchd/systemd) 등록
openclaw gateway start
openclaw gateway status    # 확인
```

로컬에서 포그라운드로 바로 띄우려면:
```bash
openclaw gateway run
```

## 모델 우선순위(이 템플릿 기준)

`openclaw.json.example`은 MiniMax를 1순위로 설정해뒀다(사용자 지정):

```
agents.defaults.model.primary   = minimax/MiniMax-M2.7
agents.defaults.model.fallbacks = [기존 provider들...]
```

MiniMax가 한도 소진되면 OpenClaw 자체 라우팅이 fallbacks 순서대로 다음 provider로 넘어간다
(`slack-bot-minimax`처럼 별도 쿨다운 로직을 우리가 짤 필요 없음 — OpenClaw가 provider 단위로
이미 처리한다).

## GIIP lssn 자동등록 + 상태보고 (giip #2349)

`slack-bot`/`slack-bot-minimax`는 자체 Node 런타임(index.js) 안에서 기동 시 lssn 을 자동등록하고
메시지 처리 지점마다 상태를 보고한다(각 폴더 `lssn-agent.js`). 이 openclaw 변형은 외부 게이트웨이를
그대로 구동할 뿐 우리가 훅을 넣을 런타임 코드가 없고, 위 §"왜 이 폴더가 별도인가"대로 OpenClaw 본체
소스는 건드리지 않는다. 그래서 "매 메시지 처리마다"의 세밀한 보고는 이 변형에서는 제공하지 않으며,
대신 게이트웨이와 나란히 띄우는 **companion 스크립트 `lssn-heartbeat.js`** 로 기동 시 1회 등록 +
주기적(기본 60초) 생존/대기 상태 보고를 제공한다.

```bash
# 환경변수로 이 배포의 SK/CSN 을 주입(하드코딩 금지). tool-slug 기본값은 'openclaw'.
GIIP_SK=<이 배포의 SK> GIIP_CSN=<csn> node lssn-heartbeat.js        # 60초 주기로 상시 실행
GIIP_SK=<...> HEARTBEAT_SEC=0 node lssn-heartbeat.js                # 등록만 1회 하고 종료(cron 용)
```

- OS 서비스로 상시 구동하려면 `openclaw gateway start` 와 동일한 방식(schtasks/launchd/systemd)으로
  이 스크립트를 함께 등록한다. best-effort 설계라 등록/보고 실패는 로그만 남기고 게이트웨이 동작에
  영향을 주지 않는다.
- API 규약은 https://giip.littleworld.net/ko/guides/giip-agent-api 참조.

## 참고

- MiniMax Anthropic 호환 엔드포인트: https://platform.minimax.io/docs/api-reference/text-anthropic-api
- OpenClaw MiniMax 프로바이더 문서: https://docs.openclaw.ai/providers/minimax
- OpenClaw CLI 문서: https://docs.openclaw.ai/cli/
