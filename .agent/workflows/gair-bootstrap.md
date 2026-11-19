---
description: 이 PC의 Claude를 gair(giip ai api router) 경유로 붙인다 — 전제확인·AK파생·별도설정·스모크테스트. "gair 붙여" / /gair-bootstrap 로 기동.
---

# Custom Workflow: /gair-bootstrap ("gair 붙여")

이 PC에서 Claude Code를 **gair(giip ai api router)** 경유로 설정·검증하는 부트스트랩.
토큰 소비가 gair의 라우팅·사용량 로깅을 거치게 하는 것이 목적.

> **정본은 `docs/60-operations/gair-bootstrap.md`.** 이 워크플로우는 그 절차의 실행 순서를
> 옮긴 것이며, "왜/전제/트러블슈팅"은 정본을 본다. 절차를 바꿀 땐 정본을 먼저 고친다.
> 근거: CSN 47 <https://giip.littleworld.net/ko/admin/giip-issues/5671> lowy-dp01 시험 결과 +
> 라이브 `slack-bot/gair-accounts.js`(#5858).

## 트리거

- 슬래시: `/gair-bootstrap <csn>`
- 자연어: "gair 붙여" (대상 CSN을 함께 말하거나, 이 PC의 기본 프로젝트 CSN으로 해석)

## 하드 규칙 (어길 수 없음)

1. **SK·AK·함수 키 값을 출력·파일·이슈·커밋·로그 어디에도 적지 않는다.** 값은 env/변수로만,
   보고는 상태코드·유무·마스킹된 요약만.
2. 적용 범위는 **CSN 단위**. csn은 반드시 인자로 받고, CSN 전용 분기를 공유 코드에 넣지 않는다.
3. 기존 세션 설정(`~/.claude`)을 건드리지 않는다 — 별도 `CLAUDE_CONFIG_DIR` 사용.
4. 소스/문서 변경이 생기면 신규 브랜치 → 수정 파일만 명시 스테이징 → 커밋 → PR(main 직접 push 금지).

## 단계

### 1. 전제 확인 (하나라도 불충족이면 §5 형식으로 중단·보고)

- **대상 CSN 결정**: 인자 `<csn>` 또는 이 PC의 기본 프로젝트 CSN. 이후 모든 단계에 이 csn을 인자로 넘긴다.
- **SK 존재**: `slack-bot/.secrets/giip-accounts.json` 의 `.channels[*]` 중 이 csn 계정에 `sk`가
  있는지 **유무만** 확인(값 읽지 않음).
- **함수 키 존재**: `GAIR_FUNCTION_KEY` env가 비어 있지 않은지 확인. **비어 있으면 중단** —
  gair 라우트는 `authLevel=function` 이라 함수 키 없이는 유효 AK가 있어도 401(빈 본문)이다
  (#5671 lowy-dp01 실측). "gair 함수 키 미주입 — 운영자에게 발급 요청"으로 보고.
- **웹콘솔 gair 설정**: 직접 조회하지 않는다(운영자 책임). 스모크에서 503(키 없음)이 나오면 역진단.
- **claude CLI 설치** 확인.

### 2. AK 파생 (SK → AdminGetAK) — 기존 스크립트 재사용, 새 구현 금지

```bash
scripts/gissue/get-ak.sh <csn> --json   # ak만 변수에 담고 화면에 찍지 않는다. SK는 출력 안 됨.
```

### 3. 설정 + 스모크 (멱등 헬퍼 1줄 권장)

```bash
# 전제확인 + AK파생 + 별도 설정 디렉터리 + 스모크 테스트를 한 번에 (비밀값 미출력)
scripts/gair/gair-bootstrap.sh <csn>
```

헬퍼를 쓰지 않고 수동으로 할 때의 env (gair 전용 셸에서만):

```bash
unset ANTHROPIC_API_KEY ANTHROPIC_MODEL   # 잔존 auth/model 소스 제거 (우선순위 충돌 방지)
export CLAUDE_CONFIG_DIR="$HOME/.claude-gair-<csn>"          # 기존 세션 불간섭
export ANTHROPIC_BASE_URL="https://giipfaw.azurewebsites.net/api/gair"
export ANTHROPIC_AUTH_TOKEN="<파생 AK>"                       # Bearer. (대안: ANTHROPIC_API_KEY 에 AK → x-api-key, 하나만)
export ANTHROPIC_CUSTOM_HEADERS="x-functions-key: $GAIR_FUNCTION_KEY"   # 필수 — authLevel=function
claude -p 'ping이라고만 답해줘' --output-format json
```

### 4. 판정

- **HTTP 200** + Anthropic 형식 `content` 응답 → **성공**. gair가 처리했고 사용량 로그에 판정
  근거·선택 모델이 남는다. 이 env를 가진 셸에서 이후 `claude` 를 띄우면 gair 경유다.
- **HTTP 401** → 함수 키 또는 AK 미충족. §5 전문 보고.
- **HTTP 503 "키 없음"** → 웹콘솔 category=gair upstream key 미등록. 그 CSN 운영자에게 보고.
- **Claude Code 무응답 타임아웃** → 거의 401(빈 본문). 먼저 직접 POST로 상태코드를 확정한다
  (정본 §4.4 curl).

### 5. 실패 보고 형식 (오류 전문 그대로, 비밀값 마스킹)

```
## gair 스모크 실패 — CSN <csn>
- 단계: <전제확인 | AK파생 | 직접POST | ClaudeCode왕복>
- HTTP status: <코드>
- 응답 본문(전문, 비밀값 마스킹): <원문 그대로>
- 환경: ANTHROPIC_BASE_URL=<...>, 인증헤더=<Bearer|x-api-key>, x-functions-key 주입=<yes/no>
- 추정 원인: <401=함수키/AK | 503=웹콘솔 upstream key | timeout=401 재시도>
```

## 참조

- 정본/트러블슈팅: `docs/60-operations/gair-bootstrap.md`
- AK 파생: `scripts/gissue/get-ak.sh`
- 헬퍼: `scripts/gair/gair-bootstrap.sh`
- gair 본체 이슈: <https://giip.littleworld.net/ko/admin/giip-issues/5671>
