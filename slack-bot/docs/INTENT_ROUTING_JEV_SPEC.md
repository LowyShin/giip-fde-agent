# Slack 봇 의도 분류(task / question) — Jev 활용 권장 구조 사양서

> 상태: **제안(미구현)**. 이 문서는 구현 전 설계이며 코드 변경을 포함하지 않는다.
> 작성: 2026-10-27 · 기준: `origin/main` (PR #322 **머지 완료** 후. 읽기 전용 조회 결정적 경로 포함)
> 이 레포는 PUBLIC 범용 레포다([규칙 54](../../.agent/rules/54_generic_agent_no_customer_info.md)). 사례는 일반화했고 고객 식별 정보는 없다.
> Jev 게이트웨이의 정본 설계는 giipdb 의 `SPEC_JEV_SQLI_DETECTION.md`(§2 개요, §6 질문 설계, §7 게이트 판정, §12 이식 설계,
> §16 키 관리, §17 게이트웨이 요청 스키마)다. PUBLIC 레포이므로 **링크하지 않고 파일명만** 언급하며 내용을 베끼지 않는다.

---

## 1. 목적과 문제 정의

### 1.1 목적
Slack 메시지가 **작업(task: 디스크의 파일을 만들거나 고쳐야 하는 요청 → giip 이슈 등록)** 인지
**질문(question: 파일 변경 없이 답만 하면 되는 요청 → 채널 즉답)** 인지를 가르는 판정을,
secwatch 가 이미 쓰고 있는 Jev(형 지정 질문에 값+신뢰도를 구조화해 돌려주는 모델)로 보강한다.
"작업이면 giip 이슈 등록" 경로(`giip-task.js` 의 `maybeCreateIssue`)는 이미 있으므로 **새로 만드는 것은 판정 단계뿐**이다.

### 1.2 문제(일반화한 오분류 사례)
| 유형 | 사용자 메시지(일반화) | 기대 | 실제 |
|---|---|---|---|
| A. 질문이 작업으로 | "이슈 N 의 처리 결과 파일의 저장소 URL 찾아서 보여줘" | question | task → 불필요한 새 giip 이슈 발급 |
| B. 작업이 질문으로 | "이번 달 예상 금액을 계산해서 보여줘" | task(코드 변경 필요) | question → 이슈·PR 없이 질문 경로에서 직접 편집 |
| C. 문서 갱신이 질문으로 | "이 문서 일본어로 업데이트 해줘" | task | question → 파일이 미커밋으로 남음 |

- A 의 원인(PR #322 에서 수정됨): `WRITE_INTENT_MARKERS` 가 명사(`파일`/`처리`/`폴더`)를 쓰기 의도로 취급해 결정적 question
  fast-path 를 막고, 결과적으로 비결정적인 LLM 분류기(`claude -p`)로 넘어갔다.
- B·C 는 `intent.js` 주석에 기록된 기존 사고이며 `FORCE_TASK_PATTERNS` 에 패턴을 **하나씩 추가**해 막아 왔다.
  패턴 추가 방식은 "새 표현이 나올 때마다 사고 후 수정"이라는 한계가 있다(§2.4).
- 공통점: 규칙이 못 가른 메시지가 **flaky 한 LLM 분류기**로 가고, 그 분류기의 오류·한도 초과는 모두 `question` 으로 떨어진다.

---

## 2. 현재 동작 (파일:행, `origin/main` 5d8552b 기준)

### 2.1 결정적 경로 — `slack-bot/intent.js`
| 순서 | 함수 | 행 | 동작 |
|---|---|---|---|
| 1 | `isForceTaskCmd` (`FORCE_TASK_PATTERNS`) | 28 / 57 | 태스크 등록·구현/수정 명령형·`…계산해서 보여줘` 등 → 무조건 task |
| 2 | `classifyRequest` 선두 정규식 | 105~ | `git push/pull…`, 태스크 목록 조회 등 → question |
| 3 | `isConfirmationQuery` (`CONFIRM_QUERY_MARKERS`, `isReadOnlyLookup`, `WRITE_INTENT_MARKERS`) | 70 / 96 / 90 | 쓰기 동사가 없고 확인·조회 표지 또는 `URL/경로/내용 + 찾아/보여/알려/확인` 이면 LLM 없이 question (`classifyRequest` 112행) |
| 4 | LLM 분류기 | 161 | `spawnAsync('claude', ['-p','--model', classifierModel()])`, 60초 타임아웃, stdin 프롬프트 |

### 2.2 LLM 분류기의 실패 처리
- 종료코드 ≠ 0, 예외(타임아웃 포함) → **모두 `'question'`** (`intent.js` 171~177행). 사용 한도 메시지는 `accounts.noteUsageLimit` 로 기록만 한다.
- 출력이 `task` 로 시작하면 task, 그 외는 question. **신뢰도 개념이 없다.**
- 모델은 `model-config.js` 의 `classifierModel()` (환경변수 `MODEL_CLASSIFIER`, 기본은 standard 티어 폴백, 65행).

### 2.3 라우팅 호출 지점 (`slack-bot/handlers.js`, 모두 `isForceTaskCmd` 먼저 → 아니면 `classifyRequest`)
| # | 행 | 상황 | 결과 |
|---|---|---|---|
| 1 | 1362 | 메시지가 기존 task ID 를 언급(ID 외 지시 포함) | question → `answerInChannel`, task → 기존 태스크 갱신(`reuseTaskId`) |
| 2 | 1395 | 메시지가 기존 giip 이슈 번호를 언급 | task → 새 이슈를 만들지 않고 그 이슈에 연결(`linkedIsn`) |
| 3 | 1437 | 일반 메시지 | question → `answerInChannel`(116행), task → 분석 → `maybeCreateIssue` |
- 1·2 에서 확정한 의도는 `preIntent` 로 3 에서 재사용한다(이중 분류 방지). **신규 구조도 이 재사용 규칙을 유지해야 한다.**
- 이슈 등록: `handlers.js` 약 1503행 `gt.maybeCreateIssue(channelId, taskTitle, planContent, csn)` → `giip-task.js` 51행. 이미 연동된 경로이며 이 사양에서 바꾸지 않는다.

### 2.4 한계 요약
1. 규칙 밖의 새 표현은 신뢰도 없는 LLM 호출 1회에 의존한다.
2. 분류기 장애 = 항상 question → B·C 유형(작업이 묻힘)이 장애 시 조용히 발생한다.
3. 판정 결과·근거가 어디에도 남지 않아 재보정 자료가 없다(`console.log` 한 줄뿐, 1438행).

---

## 3. 권장 구조 (확정)

**원칙: 결정적 규칙 → Jev → 기존 LLM 분류기 → 안전 기본값.** Jev 는 규칙이 못 가른 메시지에만 쓴다.
secwatch 와 같은 역할 분담(결정론 1차 + Jev 2차)이다.

```
Slack 메시지
  │
  ├─ ① 결정적 규칙 (LLM·Jev 호출 없음)
  │     isForceTaskCmd(text)            ── true ──▶ task   (강제 task)
  │     선두 git/태스크조회 정규식        ── true ──▶ question
  │     isConfirmationQuery(text)       ── true ──▶ question (읽기 전용 조회 fast-path)
  │
  └─ ② 위에서 확정 못 한 메시지만
        │  (JEV_INTENT_ENABLED=1 일 때만, 아니면 ③ 으로 직행)
        ├─ maskString(text) 적용 후 게이트웨이 호출 (sk 인증, 키는 봇에 없음)
        │     ├─ 응답 OK 이고 신뢰도 ≥ 임계값  ──▶ 그 intent 채택 (task | question)
        │     ├─ intent = ambiguous 또는 신뢰도 부족 ──▶ ③ 으로
        │     └─ 오류 / 타임아웃 / 스위치 꺼짐      ──▶ ③ 으로
        │
        ③ 기존 LLM 분류기 classifyRequest 의 LLM 단계 (claude -p, 현행 그대로)
              ├─ 성공  ──▶ task | question
              └─ 실패(종료코드≠0·타임아웃)  ──▶ question + 안내문
                    (안내: "작업 요청이면 '태스크 등록 …' 으로 다시 보내 주세요")
```

핵심 결정:
1. **①은 Jev 보다 우선**한다. 결정적 규칙은 비용 0·지연 0·설명 가능하고, `isForceTaskCmd` 는 "사용자의 명시적 의사"이므로 모델 판정이 뒤집으면 안 된다.
2. **Jev 는 ①이 못 가른 것만** 받는다. 호출 빈도를 줄여 비용·지연·외부 송신량을 최소화한다.
3. **Jev 실패는 장애가 아니라 폴백 사유**다. 기존 동작(③)으로 그대로 내려가므로 Jev 도입이 현행보다 나빠지는 경로가 없다.
4. **③까지 실패하면 question 이되 안내를 붙인다.** 현행은 조용히 question 이라 작업이 묻힌다(§2.4-2). 안내문 문구는 구현 이슈에서 확정(`i18n-ui.js` 키 신설 필요 여부는 미확인).
5. 호출 지점 3곳(§2.3)은 **개별로 바꾸지 않고** `classifyRequest` 내부(③ 앞)에 Jev 단계를 넣어 한 곳에서 처리한다. 호출부 시그니처는 유지한다(§9 B).
6. 봇은 Jev 를 **직접 호출하지 않는다**. 반드시 giip 게이트웨이 경유(§4).

---

## 4. 게이트웨이 계약 (신설분 — 모두 **제안**)

### 4.1 현재 게이트웨이와 신설 필요성
- 구현 위치: giipfaw 레포 `giipJevGateway/run.ps1`, `giipJevGateway/function.json` (**`origin/main` 에서 확인**. 로컬 작업 트리는 다른 브랜치라 파일이 보이지 않으니 `git show origin/main:giipJevGateway/run.ps1` 로 읽는다).
  공유 보조: `shared/SecSignal.ps1` (용도는 미확인).
- 호출 규약(기존 에이전트 `scripts/secwatch/secevt_agent.py` 31~48행 기준): `POST` form-urlencoded, 필드 `token`(=sk), `jsondata`(JSON).
  기본 URL 은 환경변수 `GIIP_JEV_GATEWAY_URL` 로 덮어쓸 수 있다. Jev 키는 게이트웨이 앱설정 `TYPESAFE_API_KEY` 에만 있다.
- 이 게이트웨이는 **SQL 인젝션 전용**이다: `src` 를 `secevt_*` 4종으로 매핑(`run.ps1` 92~103행), 질문 세트 고정(117행~), 결과를 보안 결과 테이블에 적재(211행 부근),
  `lssn` 을 요구(10행 주석). secwatch 문서도 "범용 분석기가 아니다"라고 명시한다(`docs/60-operations/secwatch-ai-onboarding.md` §0).
  → **의도 분류를 이 경로에 억지로 넣으면 안 된다**(모든 행이 의미 없는 판정으로 떨어지고 보안 결과 테이블이 오염된다).
- 따라서 신설 대상: ① 의도 분류용 **입력 타입** ② **질문 세트** ③ 보안 결과 테이블에 쓰지 않는 응답 경로.
  같은 Function 에 `kind` 분기로 넣을지 별도 Function 으로 둘지는 **(A) 이슈에서 결정**한다(권장은 별도 라우트: 보안 적재 로직과 분리).

### 4.2 입력 타입(제안): `intent_route`
secwatch 의 `secevt_*` 와 구분되는 이름. 결과 테이블 적재 없음(§6.2).

### 4.3 요청 스키마(제안, v1) — 기존 요청 스키마(정본 §17.2)와 같은 스타일
```json
{
  "v": 1,
  "kind": "intent_route",
  "ts": "ISO8601",
  "text_masked": "maskString() 통과한 메시지 본문 (최대 N자로 절단 — N 은 (A)에서 확정)",
  "lang": "ko|ja|en|unknown",
  "in_thread": true,
  "mentions_task_id": false,
  "mentions_issue_ref": false,
  "prefilter": { "force_task": false, "readonly_lookup": false, "confirmation_query": false }
}
```
- 필드는 전부 제안이다. `prefilter` 는 ①에서 이미 거른 결과(항상 전부 false 일 때만 Jev 에 오므로 사실상 상수) — 넣을지는 (A)에서 결정.
- **넣지 않는 것**: 채널/사용자 ID, 스레드 원문 전체, 파일 경로, 토큰류(마스킹 후에도 남은 의심 문자열이 있으면 절단 우선).
- 인증: `token` = sk (secwatch 에이전트와 같은 방식). **Jev 키는 봇 설정·환경에 두지 않는다**(정본 §16 의 원칙).

### 4.4 형 지정 질문 세트(제안)
| 이름 | type | 내용 |
|---|---|---|
| `intent` | `choice` | `task`(파일·코드·설정을 만들거나 고쳐야 충족되는 요청) / `question`(질문·상태 확인·기존 결과 조회, 파일 변경 불필요) / `ambiguous` |
| `requires_file_change` | `noul` | "이 요청을 충족하려면 디스크의 파일을 만들거나 수정해야 한다" (0~1 확률) |
| `is_status_or_lookup` | `noul` | "기존 결과·URL·경로·상태를 조회하는 요청이다" (0~1) |

- type 의 의미(`choice`=선택지+confidence, `noul`=확률 0~1·confidence 없음)는 정본 §2 의 라이브 검증 결과를 따른다. **`noul` 에는 confidence 가 없어** 확률값 자체로 분기한다.
- `criteria` 문구(각 선택지 설명)는 한국어·일본어·영어 메시지가 섞이므로 영어로 쓰되 한국어 예시를 포함할지는 (C) 평가로 결정.

### 4.5 응답(제안)
```json
{
  "success": true,
  "intent": "task|question|ambiguous",
  "intent_confidence": 0.0,
  "requires_file_change": 0.0,
  "is_status_or_lookup": 0.0,
  "processed_at": "ISO8601",
  "usage": { "input_tokens": 0, "output_tokens": 0 }
}
```
- 동기 응답. 봇 쪽 호출 타임아웃은 짧게(초기 제안 3초 — **근거 없는 초기값**, 정본 §2 가 Jev 응답을 70~500ms 로 적었으나 미검증이므로 (C)에서 실측).

---

## 5. 신뢰도 라우팅 (임계값은 평가 후 확정)

**초기값은 제안일 뿐 근거가 없다.** (C)의 코퍼스 평가로 확정한다.

| 조건 | 동작 |
|---|---|
| `intent`=task 이고 `intent_confidence` ≥ T_hi **그리고** `requires_file_change` ≥ P_hi | task 채택 |
| `intent`=question 이고 `intent_confidence` ≥ T_hi **그리고** `requires_file_change` ≤ P_lo | question 채택 |
| 위 외(ambiguous·경계값·두 신호가 서로 모순) | ③ 기존 LLM 분류기로 폴백 |
| 오류·타임아웃·응답 형식 불일치 | ③ 으로 폴백 |

- 초기 제안: T_hi = 0.8, P_hi = 0.7, P_lo = 0.3. (정본 §7 의 게이트가 `is_injection` ≥0.9 / 0.4~0.9 경계 / ≤0.1 로 나눈 것과 같은 모양이라는 점만 참고했고, 숫자는 이 문제에 대해 검증된 것이 아니다.)
- **비대칭 비용 고려**: 질문을 task 로 보내면 불필요한 이슈가 생기고(사고 유형 A), 작업을 question 으로 보내면 작업이 묻힌다(B·C). 어느 쪽이 더 비싼지는 운영 판단이므로 임계값을 분리(task 쪽/question 쪽)해 (C)에서 오류율을 보고 정한다.
- 정본 §3 의 "Jev 의 정상 판정만으로 통지를 멈추지 않는다"에 대응하는 원칙: **Jev 의 question 판정만으로 `isForceTaskCmd` 를 뒤집지 않는다**(①이 항상 우선).

---

## 6. 데이터 취급과 로깅

### 6.1 데이터 취급 — 별도 심사 게이트를 두지 않는다
- secwatch 는 실데이터 투입 전에 송신 데이터의 **보존·학습 이용·소재지 심사**(정본 §9, `docs/60-operations/secwatch-agent.md` §1 선행조건 2)를 요구한다.
  **이 기능에는 그 심사를 별도 게이트·블로커로 두지 않는다. 사용자 결정(2026-10-27):** "Slack 메시지는 외부 SaaS 로 나가는 데이터이지만,
  일반적인 외부 AI 챗봇의 방침과 동일하게 한다."
- 근거(코드로 확인한 사실): 이 봇은 이미 사용자 메시지를 외부 AI 에 보낸다.
  - 의도 분류: `intent.js` 161행 `claude -p`(프롬프트에 `Message: "${text}"` 로 원문 삽입).
  - Q&A·작업: `claude-cli.js` 88행 `callClaude` 등.
  Jev 로의 송신은 **같은 종류의 외부 AI 송신이 하나 늘어나는 것**이므로 새 심사 단계를 만들지 않는다.
- 적용하는 방침:
  1. 송신 전 `secret-mask.js` 의 **`maskString(text)`** 을 통과시킨 값만 `text_masked` 에 담는다. 호출 지점은 Jev 어댑터(`intent.js` 내 신설 함수) 한 곳.
     `maskString` 이 지우는 것은 토큰·키 등 **알려진 비밀 패턴**(Slack/Anthropic/GitHub/JWT/AWS 키, `KEY=VALUE` 형 .env, JSON 의 `password`/`sk`/`authorization` 필드, Authorization 헤더)이다.
     개인정보·일반 업무 문장은 지우지 않는다(`secret-mask.js` 머리 주석: "완벽한 탐지가 아니라 알려진 형태를 확실히 지우는 것").
  2. 별도 승인 단계·사전 심사 문서·실데이터 투입 차단은 없다.
- **사실 확인(중요, 기존 코드 기준)**: 현재 `maskString`/`maskDeep` 의 호출처는 `cost-tracker.js`, `progress-events.js`, `retry-checkpoint.js`, `task-evidence.js` 등
  **디스크에 남기는 로그·체크포인트**다. 현행 `classifyRequest` 의 LLM 프롬프트와 `callClaude` 경로에는 `maskString` 호출이 **없다**(`grep` 확인).
  즉 "기존 외부 AI 송신이 이미 마스킹된다"는 서술은 **사실이 아니다**. 이 사양은 새 Jev 송신에 한해 `maskString` 을 적용하도록 정하며,
  기존 외부 AI 송신 경로(`classifyRequest` LLM·`callClaude`)에 마스킹을 소급 적용할지는 **이 사양의 범위 밖**이다(미결 §10-1).
- 외부 SaaS 로서의 Jev 의 보존·학습 이용·소재지 조건은 정본 §2·§9 에서 **미확인**으로 남아 있다. 이 사양은 그것을 해소했다고 주장하지 않는다.

### 6.2 로깅(재보정용)
- 판정 결과(최종 intent, 어느 단계가 결정했는지: `rule|jev|llm|fallback`, Jev 응답값·confidence, 지연 ms)를 남겨야 (C) 의 재보정이 가능하다.
- **저장 위치: 미정 — 구현 이슈에서 결정한다.** 후보는 기존 `console.log`(`handlers.js` 1438행) 확장, 기존 비용·진행 로그 파일(`cost-tracker.js`) 재사용이나 giip 측 저장이다. 새 저장소를 이 문서에서 창작하지 않는다.
- 어느 쪽이든 **원문이 아니라 `maskString` 통과본**(또는 해시)만 남긴다.
- 게이트웨이 쪽에는 보안 결과 테이블에 적재하지 않는다(§4.1). 게이트웨이 로그 보존은 (A)에서 확인.

---

## 7. 롤아웃

| 항목 | 제안 |
|---|---|
| 스위치 | 환경변수 `JEV_INTENT_ENABLED` (**제안명**). 기본 `0`(꺼짐) |
| 꺼짐 동작 | ② 를 건너뛰고 현행과 완전히 동일(① → ③) |
| 게이트웨이 주소 | 기존 secwatch 와 같은 `GIIP_JEV_GATEWAY_URL` 규약 재사용 여부는 (B)에서 결정(의도 분류는 다른 라우트일 수 있음) |
| 인증 | 이 봇의 giip 계정 sk (`giip-accounts` 해석, `giip-task.js` 의 `accounts.resolve(channelId)` 와 같은 방식). 채널에 계정이 없으면 Jev 단계 생략 → ③ |
| 타임아웃 | 짧게(초기 3초 제안, §4.5). 초과 시 ③ 으로 |

- **기본 끔은 단계적 배포용**이다(평가 전 임계값이 미확정이므로 켜기 전에 (C) 결과를 본다). 데이터 취급 심사 게이트가 아니다(§6.1).
- 켜는 순서: (A) 게이트웨이 배포 → (B) 봇 코드 머지(꺼짐 상태) → (C) 섀도 모드 평가 → 임계값 확정 → 스위치 ON.
- **섀도 모드(제안)**: 스위치와 별개로 "Jev 를 호출해 로그만 남기고 결과는 쓰지 않는" 모드를 둘지 (B)/(C)에서 결정 — 켜기 전에 실제 트래픽으로 Jev 와 LLM 분류기를 대조할 수 있다.

---

## 8. 정확도 평가 계획

1. **코퍼스**: 실제 오분류 사례(§1.2 의 A·B·C 유형 및 `intent.js` 주석·`tests/intent.test.js` 의 기존 question/task 케이스)를 **일반화**해 만든다.
   고객 식별 정보·실제 이슈 번호·경로는 넣지 않는다. 한국어·일본어·영어를 모두 포함(봇 사용 언어). 규모·확보 방법(운영 로그에서 추출 시 마스킹)은 (C)에서 확정 — **현재 코퍼스는 없다**.
2. **대조군**: ① 현행(결정적 규칙 + 기존 LLM 분류기) ② 결정적 규칙 + Jev ③ 권장 구조 전체(규칙 → Jev → LLM).
3. **지표**: 정확도, task 재현율(작업을 question 으로 보낸 비율 — 사고 B·C), question 정밀도(질문을 task 로 보낸 비율 — 사고 A), 폴백 비율, 지연(p50/p95), 호출당 토큰, 동일 입력 반복 시 판정 일치율(flaky 여부 — 기존 분류기는 반복 실행 시 판정이 갈린 사례가 `intent.js` 주석에 있다).
4. **임계값 확정**: 위 지표에서 task 재현율과 question 정밀도의 허용 기준을 사용자가 정하고, 그에 맞는 T_hi/P_hi/P_lo 를 정한다.
5. 평가 결과는 이 문서 §5 에 반영하고, 평가 스크립트·코퍼스 위치는 (C) 이슈에 기록한다.
6. 기존 단위 테스트(`node --test slack-bot/tests/intent.test.js`)는 LLM 을 호출하지 않는다. 신규 테스트도 Jev 호출은 모킹한다.

---

## 9. 하위 작업 분해 (서브 이슈 대응표)

| ID | 작업 | 대상 레포·경로 | 선행 |
|---|---|---|---|
| A | 게이트웨이에 의도 분류 입력 타입(`intent_route`)·질문 세트·응답 경로 추가(보안 결과 테이블 미적재) + 정본 사양서(`SPEC_JEV_SQLI_DETECTION.md` 또는 별도 SPEC) 보강 | giipfaw `giipJevGateway/`(또는 신규 Function), giipdb `docs/30_Specs/` | — |
| B | 봇 연동: `intent.js` 에 Jev 어댑터, 폴백(③), 스위치, 안내문, 판정 로그, 테스트 | giip-fde-agent `slack-bot/intent.js`, `slack-bot/tests/` | A (테스트는 모킹이라 병행 가능) |
| C | 정확도 평가·임계값 확정 | giip-fde-agent(코퍼스·스크립트 위치는 이슈에서 결정) | A, B |
| D | lowyworkenv `MODEL_USAGE_SPEC.md` 에 예외 항목 등록 | lowyworkenv(별도 PR 로 진행 중) | — |

D 의 배경: 이 저장소 정책상 새 AI 호출 지점은 `MODEL_USAGE_SPEC.md`(lowyworkenv 정본)에 예외 사유를 남겨야 한다
(기본값은 MiniMax 메인 → Claude 폴백/QA). Jev 는 그 기본 경로가 아니므로 사유("형 지정 질문에 신뢰도 있는 구조화 응답, 자유문 생성 불필요")를 적는다.
**lowyworkenv `MODEL_USAGE_SPEC.md` 에 계획 항목 등록 필요 — 별도 PR 로 진행 중.**

### 완료조건 (기계 검증 가능한 형태 — 이슈 본문 ` ```verify ` 블록용 초안)

**A. 게이트웨이**
```
# 의도 분류 입력이 질문 세트로 판정되어 응답한다 (sk 는 환경변수로 주입, 출력에 노출 금지)
curl -s -X POST "$GIIP_JEV_GATEWAY_URL" --data-urlencode "token=$GIIP_SK" \
  --data-urlencode 'jsondata={"v":1,"kind":"intent_route","text_masked":"이슈 N 의 결과 파일 URL 찾아서 보여줘","lang":"ko"}'
# 기대: success=true, intent 가 task|question|ambiguous 중 하나, intent_confidence 수치 존재
# 보안 결과 테이블 미적재 확인: 호출 전후 해당 테이블 행 수 동일 (조회 방법은 A 이슈에서 명시)
git -C <giipfaw> grep -n "intent_route" origin/main -- giipJevGateway   # 기대: 1건 이상
```

**B. 봇**
```
node --test slack-bot/tests/        # 기대: 전부 pass (Jev 호출은 모킹, 네트워크 0)
# 스위치 꺼짐 동작 동일성: JEV_INTENT_ENABLED 미설정 시 classifyRequest 결과가 현행과 같음을 단위 테스트로 검증
# 폴백: 모킹한 Jev 오류/타임아웃/ambiguous → ③ LLM 단계 호출됨, 모두 실패 시 question + 안내문
git grep -n "isForceTaskCmd" slack-bot/intent.js slack-bot/handlers.js   # 기대: 호출 3곳(§2.3)에서 여전히 먼저 평가됨
git diff origin/main -- slack-bot/handlers.js | grep -c '^[+-]'          # 기대: 호출부 변경 최소(0 이 이상적, 변경 시 사유)
```

**C. 평가**
```
node <평가 스크립트> --corpus <코퍼스 경로>    # 경로·이름은 C 이슈에서 확정
# 기대 출력: 대조군 3종 × 지표(정확도·task 재현율·question 정밀도·폴백율·지연 p50/p95)와 확정 임계값 T_hi/P_hi/P_lo
```

**D. 사용 정책**
```
git -C <lowyworkenv> grep -n -i "jev" origin/main -- MODEL_USAGE_SPEC.md   # 기대: 의도 분류용 Jev 항목 1건 이상(사유 포함)
```

---

## 10. 미결·리스크 (확인하지 못한 것은 "미확인")

1. **기존 외부 AI 송신의 마스킹 부재**: 현행 `classifyRequest` LLM 프롬프트·`callClaude` 에는 `maskString` 이 적용되지 않는다(§6.1). 신규 Jev 송신만 마스킹하면 경로 간 불균형이 생긴다. 소급 적용 여부는 사용자 결정 사항 — 미결.
2. **Jev 한국어·일본어 의도 분류 정확도: 미확인.** 정본 §2 도 "한국어·SQL·로그 형식 정확도"를 미확인으로 남긴다. (C) 전에는 정확도를 주장하지 않는다.
3. **`confidence` 교정(calibration) 정의: 미확인**(정본 §2). 임계값이 모델 버전(`jev-latest`)에 따라 흔들릴 수 있다 — 버전 고정 여부는 (A)에서 확인.
4. **Jev 송신 데이터의 보존·학습 이용·소재지: 미확인.** 사용자 결정으로 별도 심사 게이트는 두지 않았으나(§6.1), 사실이 확인된 것은 아니다.
5. **게이트웨이 레이트리밋·요청당 질문 수: 미확인**(정본 §2). 봇 트래픽이 secwatch 와 같은 Function/키 한도를 공유하면 보안 경보에 영향을 줄 수 있다 → 별도 라우트·별도 한도 검토 필요.
6. **`shared/SecSignal.ps1` 의 용도와 `giipJevGateway` 의 현재 배포 상태(앱설정 `TYPESAFE_API_KEY` 포함): 미확인.**
7. **봇의 giip 계정/sk 해석**: 채널에 계정이 없는 배포(`accounts.resolve` 가 null)에서는 Jev 단계가 항상 생략된다. 범용 배포에서 Jev 를 쓰려면 sk 가 필요하다는 의미 — 영향 범위 미확인.
8. **`i18n-ui.js` 안내문 키 신설 필요 여부, 스레드 문맥(이전 메시지)을 state 에 넣을지: 미확인/미결.** 스레드 원문 전송은 데이터량·민감도 증가 때문에 초기 버전에서는 제외했다(§4.3).
9. **`slack-bot-minimax/`, `slack-bot-openclaw/` 변형의 분류 경로**: 이 사양은 `slack-bot/` 만 다룬다. 변형의 동일 로직 여부는 `slack-bot/docs/BOT_VARIANTS.md` 로 확인 필요 — 미확인.
10. 이 사양의 임계값·필드·환경변수명은 모두 **제안**이며 (A)~(C) 에서 확정되기 전에는 구현 근거로 인용하지 않는다.

---

## 11. 관련 파일

- 판정 로직: `slack-bot/intent.js`, 라우팅: `slack-bot/handlers.js`, 이슈 등록: `slack-bot/giip-task.js`, 마스킹: `slack-bot/secret-mask.js`, 모델 설정: `slack-bot/model-config.js`
- 현행 규칙 설명: `slack-bot/README.md` "의도 분류(task / question) 결정적 경로"
- secwatch: `docs/60-operations/secwatch-agent.md`, `docs/60-operations/secwatch-ai-onboarding.md`, `scripts/secwatch/README.md`, `scripts/secwatch/secevt_agent.py`
- 게이트웨이: giipfaw `giipJevGateway/run.ps1` · 정본 설계: giipdb `SPEC_JEV_SQLI_DETECTION.md` (파일명만 인용)
- 규칙: `.agent/rules/54_generic_agent_no_customer_info.md`, `.agent/rules/55_information_lookup_order_and_feedback.md`, `.agent/rules/56_deliverable_placement_docs_vs_deployable_source.md`
