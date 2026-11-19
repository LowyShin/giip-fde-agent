# gair 부트스트랩 — 각 PC의 Claude가 스스로 gair를 거치게 하기 (정본)

> 이 문서는 **정본(SSOT)** 이다. 워크플로우 `.agent/workflows/gair-bootstrap.md` 와
> 헬퍼 `scripts/gair/gair-bootstrap.sh` 는 이 문서의 절차를 실행 가능한 형태로 옮긴 것이며,
> 절차의 "왜/전제/트러블슈팅"은 여기를 참조한다.
>
> 근거: CSN 47 <https://giip.littleworld.net/ko/admin/giip-issues/5671> 의 lowy-dp01
> gair 시험 결과(코멘트, 2026-11-19)와, 라이브 slack-bot `slack-bot/gair-accounts.js`
> (머지됨, CSN 70424 #5858). 이 문서의 env/헤더 컨벤션은 그 라이브 코드와 일치시킨다.

## 1. gair란 / 목적

- **gair** = giip ai api router. 호출자의 Anthropic(Claude) 형식 요청을 받아 작업 성격에
  맞는 모델로 라우팅하는 게이트웨이. 엔드포인트:
  `POST https://giipfaw.azurewebsites.net/api/gair/v1/messages` (Anthropic Messages 형식).
- **목적**: 각 PC에서 Claude Code를 띄우고 이 레포(giip-fde-agent)를 읽힌 뒤 "gair 붙여"라고
  지시하면, 그 Claude가 **스스로** 정해진 절차대로 Claude Code를 gair 경유로 설정·검증해,
  그 PC의 토큰 소비가 gair를 거치게(= gair의 라우팅·사용량 로깅을 받게) 한다.
- 모델은 **고정하지 않는다**. gair가 JEV 판정 + 프로파일→모델 매핑으로 정한다. 따라서
  `ANTHROPIC_MODEL`을 고정하지 않고, 호출 시 `--model`을 붙이지 않는다.

## 2. 인증 모델 (반드시 이해할 것)

gair 라우트에 요청이 "닿아서 처리되려면" **두 가지**가 모두 필요하다. 하나라도 없으면 401이다.

1. **Azure Function 키** (`x-functions-key` 헤더 또는 `?code=`)
   - `giipAiRouter/function.json` 의 `authLevel` 이 `function` 이다. 즉 이 라우트는 Azure
     플랫폼 레벨에서 Function 키를 먼저 요구하고, **키가 없으면 함수 본문(run.ps1의 AK 검증)에
     도달하기도 전에 플랫폼이 HTTP 401 + 빈 본문으로 거부**한다.
   - **실측(#5671 lowy-dp01, 2026-11-19)**: 유효한 AK를 Bearer로 넣고 직접 POST 했는데도
     401(빈 본문)이 떴고, Claude Code는 401에서 응답 없이 150초 타임아웃으로 종료됐다.
     원인이 바로 이 함수 키 부재였다. **이 단계를 빠뜨리면 어느 PC에서든 동일하게 401이 난다.**
   - 이 키는 비밀값이므로 레포/문서/이슈/로그에 적지 않는다. 호스트 env `GAIR_FUNCTION_KEY`
     로만 주입한다(발급은 Azure 포털 > giipAiRouter > 함수 키, 또는 운영자 전달).
   - (주의) `scripts/gissue/get-ak.sh` 가 쓰는 `GIIP_AZURE_CODE` 는 **giipApi 디스패처용**
     공개 Function 접근키로, gair 라우트의 함수 키와 **다르다**. get-ak.sh의 code를 gair에
     재사용하지 말 것(#5671에서 "함수별 키가 다르다"로 확인).

2. **파생 AK** (`Authorization: Bearer <AK>`, 보조로 `x-api-key`)
   - 호출자 인증은 AK다. 라우터(run.ps1)가 AK로 호출자 CSN을 확정한다.
   - **AK는 SK에서 파생**한다. SK(`tCorpUser.uSecretKey`)가 인스턴스에 보관하는 정본
     자격증명이고, `AdminGetAK`(SK + uloginid 2요소)로 24h 활성 AK를 파생/재사용한다.
   - 웹콘솔 프로필 페이지의 AK는 로그인 세션용(세션 종료 시 소멸)이라 인스턴스에는 쓰지 않는다.

> 라이브 `gair-accounts.js` 컨벤션: `ANTHROPIC_API_KEY` 에 AK 주입 (gair는 Bearer/x-api-key 양쪽
> 수용) + `ANTHROPIC_CUSTOM_HEADERS=x-functions-key: <GAIR_FUNCTION_KEY>`. 이 문서는 그와
> 일치시킨다. Claude Code에서 Bearer를 명시적으로 쓰려면 `ANTHROPIC_AUTH_TOKEN=<AK>`가
> `Authorization: Bearer`를 보낸다(`ANTHROPIC_API_KEY`는 `x-api-key`). 둘 다 gair가 받으므로
> 어느 쪽이든 되지만, 하나만 설정한다.

## 3. 전제 (bootstrap 착수 전 확인, 못 갖추면 중단·보고)

1. **대상 프로젝트(CSN)의 gair 값이 웹콘솔에 설정돼 있을 것**
   - giip 웹콘솔 시스템 파라미터(category=`gair`)에 `upstream.<engine>.key` 등이 등록돼
     있어야 gair가 실제 상류 모델을 호출한다. 없으면 gair가 503(키 없음)을 돌려준다.
   - CSN 47은 2026-11-19 등록 완료. **다른 CSN은 그 CSN의 운영자가 먼저 등록해야 한다.**
2. **이 PC에 그 프로젝트의 SK가 있을 것**
   - `slack-bot/.secrets/giip-accounts.json` 의 해당 csn 계정(`.channels[*]`)에 `sk`가 있어야
     AdminGetAK로 AK를 파생할 수 있다.
3. **이 PC에 gair 함수 키(`GAIR_FUNCTION_KEY`)가 주입돼 있을 것** — §2-1 참조. 없으면 401.
4. **Claude Code CLI(`claude`)가 설치돼 있을 것** — 스모크 테스트에 사용.

## 4. 절차

> 적용 범위는 **CSN 단위**다. 프로젝트(CSN)마다 웹콘솔 gair 설정과 SK가 **따로** 있어야 한다.
> csn은 항상 인자로 받고, CSN 전용 분기를 공유 코드에 하드코딩하지 않는다.

### 4.0 요약 (헬퍼 1줄)

```bash
# 전제확인 + AK 파생 + 별도 설정 디렉터리 + 스모크 테스트를 멱등 실행 (비밀값 미출력)
scripts/gair/gair-bootstrap.sh <csn>
```

아래는 그 헬퍼가 내부에서 하는 일을 사람이 읽을 수 있게 펼친 것이다.

### 4.1 전제 확인

- SK 존재: `giip-accounts.json` 에서 그 csn 계정의 `sk` 유무 확인(값은 읽지 않고 유무만).
- 함수 키 존재: `GAIR_FUNCTION_KEY` env가 비어 있지 않은지 확인. 비어 있으면 **중단**하고
  "gair 함수 키 미주입 — 운영자에게 발급 요청" 으로 보고(§6 실패 보고 형식).
- 웹콘솔 gair 설정: 이 절차에서 직접 조회하지 않는다(운영자 책임). 스모크 테스트에서
  503(키 없음)이 나오면 이 전제 미충족으로 역진단한다.

### 4.2 AK 파생 (SK → AdminGetAK)

- **기존 스크립트를 재사용한다. 새 구현 금지.**
  ```bash
  scripts/gissue/get-ak.sh <csn>          # ak/usn/csn 만 출력, SK는 절대 출력 안 함
  ```
- 헬퍼 안에서는 `--json` 으로 받아 `ak` 만 변수에 담고 화면에 찍지 않는다.

### 4.3 Claude Code 설정 (기존 세션 불간섭)

- **별도 설정 디렉터리**: 기존 `~/.claude` 세션을 건드리지 않도록 `CLAUDE_CONFIG_DIR` 를
  gair 전용 경로로 지정한다. 예: `~/.claude-gair-<csn>` (lowy-dp01 시험은 `.claude-gair-test` 사용).
- **환경변수** (이 gair 전용 셸/프로세스에서만):
  - `ANTHROPIC_BASE_URL=https://giipfaw.azurewebsites.net/api/gair`
    — SDK가 `/v1/messages` 를 덧붙여 `.../api/gair/v1/messages` 로 POST 한다.
  - `ANTHROPIC_AUTH_TOKEN=<파생 AK>` (→ `Authorization: Bearer`) **또는**
    `ANTHROPIC_API_KEY` 에 파생 AK (→ `x-api-key`). 하나만. gair는 양쪽 수용.
  - `ANTHROPIC_CUSTOM_HEADERS=x-functions-key: <GAIR_FUNCTION_KEY>` — §2-1 함수 키. **필수.**
  - `ANTHROPIC_MODEL` 은 **설정하지 않는다**(라우터가 모델을 정한다). 기존 셸에 있으면 비운다.
- **충돌 주의(MiniMax 실패 로그 재발 방지)**: 기존 `ANTHROPIC_API_KEY`/`ANTHROPIC_AUTH_TOKEN`
  등 다른 auth 소스가 환경에 남아 있으면 우선순위에 걸려 gair 설정이 무시되거나 claude.ai
  커넥터가 비활성화된다. gair 전용 셸에서 쓰지 않는 auth 변수를 먼저 **비우고**(`unset`) 실행한다.

### 4.4 스모크 테스트 (사소한 프롬프트 1건)

- 가장 가벼운 확인(네트워크/인증만): 직접 POST 1회.
  ```bash
  # AK/함수키 값은 변수로만, 출력 금지. 상태코드만 본다.
  curl -sS -o /dev/null -w '%{http_code}' \
    -X POST "https://giipfaw.azurewebsites.net/api/gair/v1/messages" \
    -H "Authorization: Bearer ${AK}" \
    -H "x-functions-key: ${GAIR_FUNCTION_KEY}" \
    -H "anthropic-version: 2023-06-01" \
    -H "Content-Type: application/json" \
    -d '{"model":"claude-sonnet-5-5","max_tokens":16,"messages":[{"role":"user","content":"ping이라고만 답해줘"}]}'
  ```
- Claude Code 왕복(실제 사용 형태) 확인:
  ```bash
  CLAUDE_CONFIG_DIR=~/.claude-gair-<csn> \
  ANTHROPIC_BASE_URL=https://giipfaw.azurewebsites.net/api/gair \
  ANTHROPIC_AUTH_TOKEN=${AK} \
  ANTHROPIC_CUSTOM_HEADERS="x-functions-key: ${GAIR_FUNCTION_KEY}" \
  claude -p 'ping이라고만 답해줘' --output-format json
  ```
- **판정 기준**:
  - HTTP **200** + 본문에 모델 응답(Anthropic 형식 `content`) → 성공. gair가 요청을 처리했고
    사용량 로그에 판정 근거·선택 모델이 남는다.
  - HTTP **401** → §2의 인증 두 요건 중 하나 미충족(함수 키 또는 AK). §6으로 전문 보고.
  - HTTP **503** + "키 없음" 사유 → §3-1 웹콘솔 gair 설정(upstream key) 미등록. 운영자에게 보고.
  - Claude Code가 **무응답으로 타임아웃** → 거의 항상 401(플랫폼이 빈 본문 401을 주면 클라이언트가
    재시도/대기) → 먼저 위 직접 POST로 상태코드를 확정한다.

### 4.5 성공 후

- 그 PC의 gair 전용 작업은 위 env를 가진 셸/런처에서 `claude` 를 띄우면 된다. 기존 세션은
  `CLAUDE_CONFIG_DIR` 분리로 영향받지 않는다.

## 5. 하드 규칙 (절대)

- **SK·AK·함수 키 값을 출력·파일·이슈·커밋·로그 어디에도 적지 않는다.** 설정은 env/별도
  config로만, 값은 마스킹. 헬퍼는 값을 찍지 않고 상태코드/유무만 보고한다.
- 적용 범위는 **CSN 단위**. 프로젝트(CSN)마다 웹콘솔 gair 설정과 SK가 별도. CSN 전용
  분기·하드코딩을 공유 코드에 넣지 않는다(csn은 인자).
- 변경은 신규 브랜치 → (수정 파일 경로만 명시 스테이징) 커밋 → PR. main 직접 push 금지.

## 6. 실패 보고 형식 (오류 전문 그대로)

실패 시 다음을 **그대로** 보고한다(추측으로 덮지 말 것). 자격증명 값은 마스킹.

```
## gair 스모크 실패 — CSN <csn>
- 단계: <전제확인 | AK파생 | 직접POST | ClaudeCode왕복>
- HTTP status: <코드>
- 응답 본문(전문, 비밀값 마스킹): <원문 그대로>
- 환경: ANTHROPIC_BASE_URL=<...>, 인증헤더=<Bearer|x-api-key 중 무엇을 썼는지만>,
        x-functions-key 주입 여부=<yes/no>
- 추정 원인(있으면): <401=함수키/AK | 503=웹콘솔 upstream key 미등록 | timeout=401 재시도 ...>
```

## 7. 트러블슈팅 빠른표

| 증상 | 가장 흔한 원인 | 조치 |
|---|---|---|
| HTTP 401, 빈 본문 | `GAIR_FUNCTION_KEY`(x-functions-key) 미주입 | 함수 키 발급·env 주입 후 재시도 |
| HTTP 401, JSON 에러 본문 | AK 파생 실패/만료/CSN 불일치 | `get-ak.sh <csn>` 재실행, csn 계정 확인 |
| HTTP 503, "키 없음" | 웹콘솔 category=gair upstream key 미등록 | 그 CSN 운영자가 웹콘솔에 등록 |
| Claude Code 무응답 타임아웃 | 플랫폼 401(빈 본문) | 직접 POST로 상태코드 확정 후 위 행 적용 |
| "claude.ai connectors disabled / API key takes precedence" | 기존 `ANTHROPIC_API_KEY` 등 잔존 | gair 전용 셸에서 해당 env unset 후 실행 |

## 8. 관련

- gair 본체: <https://giip.littleworld.net/ko/admin/giip-issues/5671>
- 이 부트스트랩 이슈: <https://giip.littleworld.net/ko/admin/giip-issues/5857>
- 라이브 참조 구현: `slack-bot/gair-accounts.js` (CSN 70424 #5858)
- AK 파생 스크립트: `scripts/gissue/get-ak.sh`
