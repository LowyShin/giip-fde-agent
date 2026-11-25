# 매시 이슈 처리 스케줄러 표준 스펙

giip issue 상태머신(PENDING→READY→IN_PROGRESS→REVIEW/DONE, +REVIEW→TESTED)을 매시 정해진 분에
무인으로 자동 처리하는 스케줄러의 **이식 가능한 표준 스펙**입니다. 여기가 **정본(canonical spec)**이며,
각 배포 대상(다른 PC, 다른 프로젝트, 다른 CSN)은 자기 경로만 채워 이 스펙을 그대로 참고/이식합니다.

원본 구현: `lowyworkenv/scripts/gissue/run-gissue-claude.ps1`(csn 47, giipprj 대상 실제 운영 인스턴스).
이 문서는 그 구현에서 플랫폼 종속 부분(절대경로, 이 PC 전용 계정)을 걷어내고 남긴 이식 가능한 뼈대입니다.


> 분리 안내 (giip #6329): 상세 절은 주제별 파일로 분리돼 있다. 절 번호는 분리 전과
> 동일하게 유지하며, 전체 구성은 §7을 본다. 이 본문은 핵심만 담는다.

### 5-1) 실행 구조 — "한 세션이 8단계를 순회"가 **아니다** (giip #1472, 2026-08-24 이후)

이 절은 예전에 "매 :07 실행마다 `[0]`,`[A]`~`[H]` 를 순서대로 수행합니다"라고 적혀 있었습니다.
그것은 giip #1472 **이전** 구조입니다. 현재 구현은 다릅니다 — 아래가 실제 실행 구조입니다.

```
:07 태스크 1회
 └─ CSN 마다 Start-Job 1개 (CSN 간 병렬. 이건 예전과 동일)
     ├─ ⓪ 저장소 정비 사전 체크(LLM 호출 0) — 정비 대상 0건이면 ① 전체를 건너뛴다
     ├─ ① 저장소 정비 세션 — 그 CSN 저장소 전체 스코프로 **1회만** 기동
     │      ([0] PR conflict / [E] PR CI 수정 / [F] orphan stash 구조 / [H] 최근 코멘트 재검증)
     └─ ② 이슈별 세션 — 아래 단일 우선순위 큐를 돌며 **이슈 1건마다 별도 프로세스를 개별 기동**
            READY / STALE_IN_PROGRESS(≥1h) / PENDING / REVIEW  ← 하나의 큐, READY 먼저 · 그룹 안에서는 오래 대기한 순
```

바뀐 것은 **실행 구조**이고, 각 단계가 "무엇을 판단하는가"는 §5-2 표 그대로 유효합니다.

- **단일 우선순위 큐**: 상태별로 따로 순회하지 않습니다. `Get-GissueIssueQueue`
  (`run-gissue-claude.ps1`)가 네 상태를 한 큐로 합쳐 대기시간 내림차순으로 정렬합니다.
  STALE_IN_PROGRESS 만 **1시간 이상 경과분만** 큐에 들어갑니다. READY 는 시간 조건 없이 바로 들어갑니다(Lowy님 지시 2026-11-25, giip #6328).
- **이슈마다 별도 프로세스**: 한 세션이 여러 이슈를 이어서 처리하지 않습니다. 이슈 1건 =
  엔진 프로세스 1개이고, 그 이슈의 상태에 맞는 프롬프트 템플릿 1벌만 주입됩니다
  (§5-3). 한 이슈가 망가져도 다음 이슈가 같은 컨텍스트를 물려받지 않습니다.
- **엔진 선택은 이슈 상태별**(`Invoke-GissueEngine` — MiniMax 시도 후 실패 시 **같은 실행 안에서**
  claude 로 폴백하는 재사용 함수):

  | 큐 항목 상태 | 엔진 |
  |---|---|
  | 저장소 정비 세션 | **gair 필수(모델 미고정)** — 실패 시 폴백 없이 오류로 종료 (giip #5671, #6229; `GISSUE_REPO_MAINT_GAIR=0` 이면 종전 MiniMax → claude 경로) |
  | PENDING / READY / STALE_IN_PROGRESS | **허용 CSN(기본: gair 설정이 등록된 플랫폼 CSN)에서는 gair 필수(모델 미고정)** — 실패 시 폴백 없이 오류로 종료 (giip #5671, #6229, §5-1-1 (2)) |
  | **REVIEW** | **MiniMax 시도 없이 곧바로 claude**(사용자 지시 2026-08-23) |
  | TESTED | claude 강제 (giip #1472) |

  `MINIMAX_API_KEY`(env 또는 `slack-bot/.env`)가 **없으면** 전 구간이 claude 단독으로 동작합니다 —
  에러가 아니라 설계된 축퇴 경로입니다. 신규 clone 은 `slack-bot/.env` 가 없으므로 기본이 이쪽입니다.
- **저장소 정비 세션은 사전 체크 게이트를 통과해야 기동한다**(giip #5671, §5-1-1): 정비 대상
  ([0]/[E]/[F]/[H])이 0건이면 엔진 세션 자체를 띄우지 않는다 — 토큰 0. 기록 파일·PR 도 만들지 않는다.
  게이트는 스크립트(LLM 이전) 단계에서 판정하고, 조회 자체가 실패하면 **fail-open** 으로 종전대로
  세션을 띄운다.
- **시간 예산 초과분은 LLM 없이 미룹니다**: 잡 전체 예산(`$RunTimeoutMin`, §8)에서 **마지막 5분을
  오버헤드 여유로 남기고**, 그 선을 넘으면 남은 큐 항목은 엔진을 기동하지 않고 스크립트가 직접
  note 코멘트를 남긴 뒤 다음 `:07` 로 넘깁니다. 큐가 길어도 태스크가 통째로 잘리지 않게 하는 장치입니다.
  (이것이 **하드 예산**이다. 그 앞에 선택적인 **소프트 예산**이 있다 — §8-1.)

> §5-1-1 상세는 분리 문서로 이동했다: [hourly-issue-scheduler-maintenance.md](./hourly-issue-scheduler-maintenance.md)

## 1) 목적/역할

- giip issue API를 CSN(고객사/프로젝트 식별자) 단위로 폴링해, 사람 개입 없이 이슈를 정제→실행→검증까지
  진행시킵니다.
- 목표는 "이슈가 등록된 뒤 방치되는 시간"을 없애는 것 — PENDING을 작업 지시서로 정제하고, READY를
  코드/문서 변경으로 실행하고, 멈춘 IN_PROGRESS를 회수하고, 실패한 PR을 고치고, REVIEW를 재검증합니다.
- CSN마다 별도 프로세스(또는 별도 -OnlyCsn 실행)로 격리되어, 서로 다른 프로젝트 폴더를 침범하지 않습니다.

## 2) 트리거 스펙

- **틱 주기는 배포 형태마다 다르다(giip 3615 정정).** 아래 둘을 섞어 읽지 말 것.

  | 배포 형태 | 틱 주기 | 틱 시각 | 정의 위치 |
  |---|---|---|---|
  | Windows Task Scheduler(`register-hourly-issue-scheduler.ps1`) | **60분**(기본 `-RepetitionMinutes`) | 매시 `:07` | §8 |
  | docker 인스턴스(`docker/entrypoint.sh` 가 만드는 cron) | **20분** | 매시 `:07`, `:27`, `:47` (`7,27,47 * * * *`) | `docker-entrypoint-spec.md` §5.1 |

- 시작 분 `:07` 은 임의로 고른 분이다(정각/일반적인 :00, :05, :10 트리거들과 충돌을 피하기 위한 선택).
- cron 표현식: 60분 주기는 `7 * * * *`, docker 20분 주기는 `7,27,47 * * * *`.
- **틱 주기 ≠ 실행 길이.** 틱은 "실행을 시작해 보는 시각"일 뿐이다. 러너는 큐가 빌 때까지 이슈를 계속 집기 때문에
  백로그가 큰 CSN 은 한 번의 실행이 90분 넘게 CSN 락을 쥔다. 그 사이의 틱은 전부 `SKIP: 실행 중` 으로 버려진다.
  그래서 20분 틱이어도 실제로는 약 2시간에 1번만 일하는 일이 생긴다(실측: 2026-10-06~07 csn 47, `gissue-scheduler-run-history.md`
  "틱 20분 vs 실행 길이"). 이 간극을 줄이는 장치가 아래 **소프트 예산**이다(§8-1).
- Windows Task Scheduler 기준: 최초 트리거 `00:07:00` 시작, `1시간마다 반복`, 사실상 무기한 지속
  (`[TimeSpan]::MaxValue`는 ISO8601 직렬화 시 Task Scheduler XML의 duration 상한을 초과해
  `Register-ScheduledTask`가 거부하므로(HRESULT 0x80041318, giip #1275), 실제로는 유효 범위 내
  충분히 큰 값 — 약 10년(`New-TimeSpan -Days 3650`) — 을 사용).

## 3) 실행 커맨드 템플릿

```powershell
powershell.exe -WindowStyle Hidden -NonInteractive -ExecutionPolicy Bypass `
  -File "<REPO_ROOT>/scripts/gissue/run-gissue-claude.ps1"
```

- `<REPO_ROOT>`: 이 스케줄러 스크립트 세트를 배치한 오케스트레이션 레포의 루트(원본 배포에서는
  lowyworkenv).
- 단일 CSN만 즉시 실행/드라이런하려면 `-OnlyCsn <csn>` 인자를 추가합니다(`-DryRun`과 조합 가능).
- **이슈 번호 지정 실행 `-OnlyIsn <isn>`** (giip 5544): 외부 감지기(예: 5분 간격 폴링)가 "지금 이 이슈"를 지정해 즉시 처리시키는 용도입니다. 지정된 이슈가 보이는 CSN의 잡만 기동되고, 그 잡의 큐는 지정 1건으로 교체됩니다.
  - **우회하는 것**: 큐 우선순위 정렬. (READY 경과 조건은 2026-11-25에 폐지돼 우회할 조건 자체가 없습니다 — giip #6328.)
  - **우회하지 않는 것(안전 게이트)**: CSN 소속 검증(응답 cSn 불일치 시 미실행, giip #1053), NEEDS_DECISION 제외, 신선한 IN_PROGRESS 중복 실행 금지(60분 이상 정체한 IN_PROGRESS는 기존 회수 경로 STALE_IN_PROGRESS로 처리), [OPS] 자동 감지 이슈 제외, REVIEW/TESTED 재검증 쿨다운·회차 상한(잡 루프의 기존 게이트가 그대로 판정).
  - **대상이 아니면 조용히 끝나지 않습니다**: 실행 로그에 `[ONLYISN-SKIP] isn=<n> reason=<코드>`를 남기고, 이슈가 대상 CSN에서 확인된 경우 그 이슈에 사유 운영 코멘트(`[ONLYISN-SKIP] …`)도 남깁니다. 사유 코드: `CSN_MISMATCH` / `AUTO_OPS` / `NEEDS_DECISION` / `IN_PROGRESS_ACTIVE` / `REVIEW_NO_NEW_SIGNAL` / `STATUS_NOT_PROCESSABLE` / `NOT_FOUND` / `LOOKUP_ERROR`.
  - **실행 이력**: 종료 시 tKVS `scheduler_run_history` 값에 `trigger='onlyisn'`, `onlyIsn=<n>`이 함께 기록됩니다(정기 실행은 `trigger='schedule'`, `onlyIsn=0`).
  - 판정 로직의 정본은 `scripts/gissue/lib/only-isn.ps1`(순수 판정 함수 + 단건 조회)이며, 회귀 테스트는 `scripts/gissue/tests/test-only-isn.ps1`입니다. **상세 사양은 §18**, AI 인스턴스용 사용법은 [`only-isn-ai-guide.md`](only-isn-ai-guide.md)를 봅니다.
- Windows Task Scheduler 대신 cron/systemd timer 등 다른 스케줄러로 이식할 경우, 이 커맨드 자체를
  그대로 그 스케줄러의 실행 대상으로 등록하면 됩니다(플랫폼별 셸 래퍼만 다르면 됨).

## 4) 필수 선행조건

- **CSN→프로젝트 매핑 파일** (`scripts/gissue/csn-projects.json`, `csn-projects.json.example`을
  복사해 실제값 채움 — gitignore 대상): 각 CSN을 어느 로컬 프로젝트 폴더에서 처리할지 매핑.
  `enabled: false`인 CSN은 자동 실행에서 건너뜁니다. 새 CSN을 추가하려면 이 파일에 항목 1개를
  추가하면 됩니다. **`restBranch`(선택)**: 이 프로젝트의 상시 작업 브랜치가 git 원격의 기본
  브랜치(main/master)와 다르면(예: dev-first 원칙으로 `dev`가 상시 작업 브랜치인 프로젝트) 반드시
  지정합니다 — 안 그러면 busy-check가 이를 매번 "다른 프로세스가 쓰는 중"으로 오판해 30분 대기 후
  강제 언블록(stash+base 체크아웃)을 매 `:07`마다 반복합니다(실측 확인·재현).
  **`reviewTestedMaxAgeHours`(선택)**: 0보다 크면 REVIEW/TESTED 이슈 중 elapsed(최신 코멘트 시각,
  없으면 등록일 기준)가 이 시간을 넘은 것은 큐에서 뺍니다. 오래된 REVIEW/TESTED 백로그가 READY 신규 작업을
  큐 뒤로 밀어내는 CSN에서 씁니다. 생략하거나 0이면 제한 없음(기존 동작)입니다.
  **출력 언어(설정 불필요)**: 각 CSN 회사의 언어(GIIP `tCorp.cLang`)를 자동 조회해 이슈 프롬프트 맨 앞에
  `[OUTPUT LANGUAGE]` 지시(커밋·PR·GIIP 코멘트·문서를 그 언어로 작성)를 넣습니다. 조회 결과는
  `slack-bot/.csn-lang-cache.env`(Slack 봇과 공유, 24시간)에 캐시됩니다. 조회 실패 시 지시를 넣지 않습니다(기존 동작).
  상세: `.agent/rules/52_project_language_from_csn.md`.
  **최상위(csn 바깥) 선택 키 3개**(giip #2645 — 러너에서 이 PC 전용 절대경로를 제거하면서 배포별
  설정으로 외부화한 값들입니다. 전부 생략 가능하고, 생략하면 해당 기능만 조용히 비활성됩니다):
    - `forcedUnblockExcludeRepoNames`: 강제 언블록(병합 여부 불확실해도 stash+base 복귀) 대상에서
      제외할 nested 레포 **폴더명** 배열. 성역 레포가 있는 배포에서 지정합니다. 병합이 "확인된"
      안전한 자동 해제(`[AUTO-UNBLOCK]`)는 이 예외와 무관하게 계속 적용됩니다.
    - `guardRepos`: Phase -2 nested-repo 무결성 가드(giip #1365) 대상 배열
      (`{ path, expectedRemoteSuffix, requiredFiles[], requiredPsDir, validateDbConfig }`).
      `path`가 상대경로면 레포 루트 기준입니다. 미설정이면 검증 대상 없음으로 건너뜁니다.
    - `heartbeat`: 스케줄러 자신의 liveness/실행이력 발행 설정
      (`{ lssn, hostname, skFile }` — `skFile`은 `sk = "..."` 형식의 agent cfg 경로).
      미설정이면 heartbeat/실행이력 발행을 하지 않습니다(스케줄러 본연 동작에는 영향 없음).
- **giip issue API 접근용 SK(Secret Key)**: CSN별 계정 SK가 필요합니다(`slack-bot/.secrets/
  giip-accounts.json`의 `channels[*].sk`를 CSN으로 매칭해 조회, `.sample.json`을 복사해 준비). 이
  파일은 git 비추적 시크릿이므로 배포 대상마다 별도로 준비해야 합니다.
- **AI 엔진 키**: 이 스케줄러는 이슈 처리 본체를 `claude -p`(헤드리스, 컨펌 없이 자율 실행)로
  실행합니다. `MINIMAX_API_KEY`가 있으면 MiniMax를 우선 시도하고, 실패/한도 초과 시 같은 실행
  안에서 즉시 `claude`로 폴백합니다(키가 없으면 기존처럼 항상 claude만 사용).
- **로그 디렉터리**: `scripts/gissue/logs/`에 CSN별 로그(`gissue_csn<csn>.log`)와 lock 파일을
  남깁니다(gitignore 대상, 자동 생성).
- **giip issue 조회/코멘트/상태변경 도구(이 레포에 기본 내장, DB 직접 접근 불필요)**:
  `scripts/gissue/list-issues.js`(CSN+상태별 이슈 목록 조회, giipfaw API 경유)와
  `scripts/gissue/get-issue.sh --comment-file`/`--status`(단건 조회/코멘트/상태전이)를 그대로 쓰면
  됩니다. 러너 자신이 쓰는 **우선순위 큐**는 `list-issues.js --csn <N> --queue --json` 한 번으로
  얻습니다(giip #2645) — READY(시간 조건 없음) / IN_PROGRESS≥60분(라벨 `STALE_IN_PROGRESS`) / PENDING /
  REVIEW·TESTED(최신 코멘트가 `[ACTIONFLOW-TEST]`로 시작하면 제외)를 합쳐
  `qprio → is_user_req DESC → has_comment ASC → elapsedMin DESC` 순으로 정렬해 돌려줍니다.
  qprio 는 READY(0) → STALE_IN_PROGRESS(1) → PENDING(2) → REVIEW·TESTED(3) 이며, REVIEW·TESTED 재확인은
  실작업이 모두 끝난 뒤에 처리됩니다.
  **자동 감지 이슈는 작업 큐의 대상이 아니다**(giip #4907). `[OPS] gissue 처리 무소식 감지` 는
  자동 등록되는 **감지 기록**이지 "작업"이 아니므로, `--queue` 결과에서 제외된다(제목 접두사 기준 —
  제목에 `[OPS]` 가 *포함*된 후속 이슈는 정상 작업 항목이라 빠지지 않는다). 제외는
  **조회(큐) 계층 한정**이다 — `--status <S>` 직접 조회와 `check-gissue-liveness.ps1` 의
  `find()`(열린 감지 이슈에 회복 코멘트 후 DONE 으로 닫는 경로)는 영향받지 않는다.
  이는 lowyworkenv 운영 러너가 giipdb 직접접속(단일 T-SQL, giip #1472/#1560/#1564/#1651)으로 뽑던
  큐와 **같은 정렬 계약**을 API로 재현한 것입니다. 후속 이슈 자동 등록(시간박스 초과 시)은
  `scripts/gissue/register-issue.js`가 담당합니다. CSN 교차오염 방지 게이트(giip #1053/#1079)가 내장돼 있어 별도 조치가 필요 없습니다.
  한글/이모지가 섞인 코멘트 본문은 반드시 UTF-8 파일로 저장한 뒤 파일 경로(`--comment-file`)로
  전달해야 합니다(커맨드라인 리터럴 직접 전달은 headless 실행 체인에서 시스템 기본 코드페이지로
  mojibake가 나는 사고가 재현 확인됨, giip #1030). 이 두 도구가 없는 프로젝트(예: `giipprj`처럼
  DB 직접 접근용 `giipdb/mgmt/*.ps1`만 있는 배포)를 이식할 때는, 그 DB-direct 스크립트들을 그대로
  재사용해도 되고, 이 두 API 기반 도구로 교체해도 됩니다 — 단 **혼용 이식은 금지**: 프롬프트 템플릿의
  이슈 조회/쓰기 커맨드가 실제로 그 프로젝트에 존재하는 도구를 가리키는지 이식 후 반드시
  `-DryRun`으로 확인합니다(존재하지 않는 경로를 참조하면 매 실행이 그 단계에서 조용히 실패합니다).

## 5) 상태머신 개요 (8단계)


- 실행 구조(§5-1 — 내부 처리 순서)는 문서 맨 위로 올려 뒀다. 처리 순서를 먼저 보고 이 절로 온다.

### 5-2) 8단계 — 각 단계가 무엇을 판단하는가

"세션" 열이 그 단계가 **저장소 정비 세션**에 속하는지 **이슈별 세션**에 속하는지를 가릅니다.

| 단계 | 세션 | 이름 | 한 줄 요약 |
|---|---|---|---|
| [0] | 저장소 정비 | PR conflict 우선 해결 | 이슈 처리 착수 전, 담당 프로젝트(+nested repo)의 열려있고 conflict 난 PR을 먼저 해소 |
| [A] | 이슈별 | 슬래시 커맨드 즉시 실행 | 제목/본문/최신 코멘트가 `/`로 시작하면 상태·나이 무관하게 즉시 해당 워크플로우 기동 |
| [B] | 이슈별 | PENDING 정제 | 내용을 분석해 작업 지시서 코멘트를 남기고 READY로 전이(실행까지는 안 함) |
| [C] | 이슈별 | READY 실행 | READY인 것 전부(시간 조건 없음), IN_PROGRESS로 선점 후 실제 처리(PR 완료 게이트 + Actionflow 테스트 게이트 통과 시 DONE) |
| [D] | 이슈별 | IN_PROGRESS 회수(reclaim) | 1시간 이상 활동 없는 IN_PROGRESS를 원인 분석 후 이어받아 완수 — 죽은/멈춘 세션 복구 |
| [E] | 저장소 정비 | PR CI 실패 점검 | 이슈 유무와 무관하게 매번, 열린 PR 중 CI/검증 실패한 것을 원인 규명 후 로컬 재검증 통과 시에만 수정 push |
| [F] | 저장소 정비 | Orphan stash 구조 | 이전 실행이 안전하게 stash해둔 "죽은 세션 잔해"를 이슈와 매칭시켜 구조(확신 없으면 사람에게 위임) |
| [G] | 이슈별 | REVIEW 재검증 | REVIEW 이슈를 Actionflow로 재테스트해 SUCCESS면 TESTED로(자동 DONE은 하지 않음 — 최종 종결은 사람) |
| [H] | 저장소 정비 | 최근 코멘트 논리 재검증 | 최근 2시간 내 코멘트의 "검증 가능한 사실 주장"을 직접 재확인해, 틀렸으면 정정 코멘트+상태 복구 |

### 5-3) 프롬프트 템플릿 6종과 단계의 대응

단계는 프롬프트 **블록**으로 구현되고, 큐 항목의 상태에 따라 블록을 조합한 템플릿 1벌이 주입됩니다
(`run-gissue-claude.ps1`). 이 대응이 §5-1 의 "이슈마다 별도 세션"을 코드에서 확인하는 지점입니다.

| 템플릿 | 포함 단계 블록 | 언제 쓰이나 |
|---|---|---|
| `$RepoMaintenancePromptTemplate` | `[0]` `[E]` `[F]` `[H]` | 저장소 정비 세션(CSN 당 1회) |
| `$PendingIssuePromptTemplate` | `[A]` `[B]` | 큐 항목이 PENDING |
| `$ReadyIssuePromptTemplate` | `[A]` `[C]` | 큐 항목이 READY |
| `$StaleIssuePromptTemplate` | `[D]` `[C]` `[B]` | 큐 항목이 STALE_IN_PROGRESS(≥1h) |
| `$ReviewIssuePromptTemplate` | `[G]` | 큐 항목이 REVIEW |
| `$TestedIssuePromptTemplate` | TESTED 전용 블록 | 큐 항목이 TESTED |

각 단계 상세 규칙(선점/코멘트 프로토콜, 3회 defer 상한, PR 완료 게이트, Actionflow 테스트 게이트 등)은
이 레포 `scripts/gissue/run-gissue-claude.ps1`의 위 템플릿 전문을 참고합니다(본문 복제
금지 — 상세 로직이 자주 갱신되므로 이 문서는 개요만 유지). Actionflow 테스트 게이트는 프로젝트
자체 Actionflow 스크립트가 있으면 그것을, 없으면(대부분의 배포) HTTP_CHECK을 직접 재현하는 방식으로
자동 폴백합니다 — SQL_CHECK이 필요한데 DB 접근 수단이 없으면 자동 DONE 대신 REVIEW로 넘깁니다.

## 6) 절대 규칙 — 성역(sanctuary) 보호

이 스케줄러가 처리하는 프로젝트 중 하나 이상에 **절대 코드 수정 금지 성역**이 존재할 수 있습니다.
원본 배포의 대표 사례: `giipfaw`(및 그 하위 `giipApiSk2/run.ps1`)는 어떤 이유로도 스케줄러가 직접
수정하지 않습니다 — 필요한 로직 변경은 SP(저장 프로시저)나 프로젝트 코드 내에서만 해결합니다.

이식 시 반드시 확인할 것:
- 이 배포 대상이 처리할 CSN/프로젝트 각각에 성역 파일/디렉터리가 있는지 사전 조사(CSN→프로젝트
  매핑 파일의 `note` 필드에 프로젝트별 성역 여부를 기록하는 관례를 따르는 것을 권장합니다).
- 성역이 있으면, 해당 파일 수정이 불가피한 이슈는 자동 처리를 포기하고 REVIEW로 전이 +
  "성역 파일 수정 필요, 사람 확인 요청" 코멘트로 넘기도록 CSN별 규칙에 명시합니다.
- 강제 언블록(정지된 브랜치 자동 해제) 로직을 이식할 경우, 성역 레포는 그 대상에서 제외해야
  합니다 — 병합 여부가 불확실한 상태에서 성역 레포를 강제로 건드리는 것보다, 경고+코멘트 후
  포기하는 경로가 더 안전하다는 것이 원본의 판단 근거입니다.

## 7) 정본 위치

이 문서(`giip-fde-agent/docs/60-operations/hourly-issue-scheduler.md`)가 이 스케줄러 표준의
**정본**입니다. 다른 배포 대상(다른 PC, 다른 레포)은 이 문서를 참고해 자기 환경에 맞게 이식하되,
이 문서 자체를 각자 복제해 따로 관리하지 말고 이 경로를 가리키는 포인터만 남기는 것을 권장합니다.

등록 스크립트: `giip-fde-agent/scripts/register-hourly-issue-scheduler.ps1`(파라미터화된 Windows
Task Scheduler 등록 스크립트, 이 문서의 §2~§3 스펙을 그대로 구현).


분리 구성 (giip #6329 — 500라인 초과 분리): 이 본문이 정본이며, 상세 절은 아래
주제별 파일로 분리해 둔다. 절 번호는 분리 전과 동일하게 유지한다.
- 정비 상세(§5-1-1·§10·§13-2): `./hourly-issue-scheduler-maintenance.md`
- 등록·배포 상세(§8·§9·§13·§21): `./hourly-issue-scheduler-registration.md`
- 감사·판정 상세(§12·§13-1·§13-3·§13-3-1·§13-4): `./hourly-issue-scheduler-audit.md`
- 실행·감시 상세(§13-5·§16·§17·§18): `./hourly-issue-scheduler-runtime.md`
- 가드·로딩 상세(미매핑 CSN 가드·slack-bot 보고 절·§19·§20): `./hourly-issue-scheduler-guards.md`

> §8 상세는 분리 문서로 이동했다: [hourly-issue-scheduler-registration.md](./hourly-issue-scheduler-registration.md)

## 8-1) 소프트 예산 `softBudgetMin` — "새 이슈를 시작해도 되는 시간" (giip 3615)

| 구분 | 하드 타임아웃 | 소프트 예산 |
|---|---|---|
| 변수/키 | `$RunTimeoutMin` = 105 (코드 상수, 이 문서 §8) | `softBudgetMin`(csn-projects.json 최상위) / 환경변수 `GISSUE_SOFT_BUDGET_MIN` |
| 뜻 | 잡을 강제로 죽이는 시간 | 이 시간이 지나면 **새 이슈 세션을 시작하지 않는 시간** |
| 진행 중 이슈 | 죽는다(`TIMEOUT`) | **끝까지 마친다**(중간에 죽이면 `IN_PROGRESS` 가 남고 60분 뒤에야 회수되므로) |
| 기본값 | 105 | **비활성**(생략/0 = 기존 동작과 완전히 동일) |

동작:
1. 이슈 1건을 시작하기 **직전**에만 판정한다. 실행 시작(잡이 workdir 를 확보한 시각)부터 경과가 `softBudgetMin` 이상이면 큐 순회를 멈춘다.
   이미 시작한 이슈 세션은 기존 시간박스(`IssueEngineDeadlineMin` 40분 / REVIEW·TESTED `ReviewEngineDeadlineMin`)까지 끝까지 기다린다.
2. **한 실행에서 최소 1건은 시작한다.** 저장소 정비 세션이 예산을 다 써도 실행이 "0건 처리"로 끝나는 기아를 막는다.
3. 남은 큐는 다음 틱이 이어받는다. 이때 **코멘트를 남기지 않는다.** 하드 예산의 `[BUDGET]` 경로는 3회 연속 미착수 이슈에 note 를 다는데,
   소프트 예산은 20분마다 정상적으로 반복되는 동작이라 같은 note 가 계속 쌓여 이슈가 오염된다. 로그 한 줄(`[SOFT-BUDGET] ... 남은 N건은 다음 틱으로: isn=...`)만 남기고,
   미착수 카운터(`budget_skip_state.json`)도 올리지 않는다.
4. 하드 타임아웃, 락 파일 로직, 이슈/PR 처리 로직은 바뀌지 않는다.

설정(우선순위: **csn-projects.json 의 `softBudgetMin` > 환경변수 `GISSUE_SOFT_BUDGET_MIN` > 비활성**):
- csn-projects.json 값이 환경변수보다 우선하는 이유: docker entrypoint 가 20분 cron 에 기본값(15)을 환경변수로 주입하는데, 이미지 재빌드 없이 파일만 고쳐
  그 기본값을 바꾸거나(`0` 이면 끔) 덮어쓸 수 있어야 하기 때문이다.
- 숫자가 아니거나 음수인 값은 무시한다(다음 우선순위로 넘어감).
- 시작 직후 로그에 설정값이 찍힌다: `[SOFT-BUDGET] 설정 = ...` (`-DryRun` 에서는 `[DryRun][SOFT-BUDGET] 설정 = ...`).
- 구현·단위 테스트: `scripts/gissue/lib/soft-budget.ps1`, `scripts/gissue/tests/test-soft-budget.ps1`.

권장값: 틱 주기의 약 3/4. 20분 틱이면 15분(docker 기본값), 60분 틱(Windows)이면 비활성 유지(기존 인스턴스에 영향 없음).

**기아 점검(제안만, 미구현)**: 큐 정렬이 `READY → STALE_IN_PROGRESS → PENDING → REVIEW/TESTED` 라서 예산이 짧으면 큐 뒤쪽 REVIEW 재검증이 계속 뒤로 밀릴 수 있다.
실측 근거와 제안은 `gissue-scheduler-run-history.md` "틱 20분 vs 실행 길이" 참고.

**사후 점검과 다음 틱의 동시 실행**: 락은 `Complete-Run` 첫머리에서 풀리고 그 뒤에 사후 점검(`pr-gate-sweep`, `review-done-audit`, `pr-attribution-sweep`, worktree 정리, 로그 전송)이 돈다.
즉 소프트 예산으로 실행이 짧아지면 다음 틱이 사후 점검과 겹쳐 시작한다. 코드로 확인한 내용은 `gissue-scheduler-run-history.md` 에 있다.

> §9 상세는 분리 문서로 이동했다: [hourly-issue-scheduler-registration.md](./hourly-issue-scheduler-registration.md)

> §10 상세는 분리 문서로 이동했다: [hourly-issue-scheduler-maintenance.md](./hourly-issue-scheduler-maintenance.md)

## 11) 운영 함정 — **PR 머지 ≠ 스케줄러가 새 코드로 도는 것** (반드시 숙지)

**GitHub에서 PR을 머지해도, Windows Task Scheduler가 실제로 실행하는 파일은 그 태스크가 가리키는
로컬 워킹카피(§8 등록 시의 `-RepoRoot`/`-RunnerRelativePath`가 가리키는 로컬 경로)다.** 원격
`main`이 갱신됐다는 사실 자체는 로컬 체크아웃에 아무 영향을 주지 않는다 — **그 로컬 디렉터리에서
`git pull`을 실행하기 전까지, 스케줄러는 다음 `:07` 사이클에도, 그 다음 사이클에도 계속 머지 전 옛
코드로 돈다.** CI가 green이고 PR이 머지됐다는 사실만으로 "다음 실행부터는 반영됐겠지"라고 가정하지
말 것.

**실제 사고 사례(2026-08-26, lowyworkenv)**: giip #1544(위 §10의 orphan-worktree 정리 fix) PR을
GitHub에서 머지했지만, 그 PR을 병합한 세션이 로컬 `lowyworkenv` 체크아웃에서 `git pull`을 깜빡했다.
그 결과 **11:07 사이클이 머지된 새 코드가 아니라 머지 전 옛 코드로 그대로 실행됐다** — 스케줄러
자신은 아무 에러도 내지 않고 "정상적으로" 옛 로직을 돌렸을 뿐이라, 로그만 봐서는 문제를 알아채기
어렵다(태스크 State/LastTaskResult 모두 정상으로 보인다).

**따라서: 이 스케줄러가 실행하는 스크립트(`run-gissue-claude.ps1` 자신, 또는 그것이 참조하는
`lib/*.js`, 프롬프트 템플릿 등)를 수정하는 PR을 머지한 뒤에는, 그 즉시 해당 로컬 체크아웃에서
`git pull`까지 실행해야 다음 `:07` 사이클부터 실제로 반영된다.** PR 머지만으로 배포가 끝났다고
보고하지 말 것 — `git pull` 완료(그리고 가능하면 `git log -1`로 반영된 커밋 해시 확인)까지가 "이
변경이 실제로 스케줄러에 배포됐다"의 완료 정의다.

> **[giip #6214] 2026-11-23 이후 — 위 수작업을 러너가 대신한다.**
> 위 절차는 **사람이 매번 pull 하는 구조**였고, 실제로 그게 빠지면 §11 의 사고가 그대로 재발한다
> (실측: 원격 main 에 반영된 코드가 호스트에 닿지 않은 채 며칠씩 옛 코드로 돌았다).
> 이제 러너는 **기동 초입에 스스로** 정본 체크아웃을 fetch → fast-forward 하고, 실행 위치가 체크아웃과
> 다르면 `scripts/gissue` 를 동기화한다. 상세·안전 계약·실패 시 동작은
> [`./gissue-scheduler-run-history.md`](./gissue-scheduler-run-history.md) §"자동 반영(자기 갱신)" 에 있고,
> §17-5 와 §17-7 에서도 다룬다.
> **단, §11 의 함정은 "닫혔다"가 아니라 "러너가 대신 한다"로 바뀌었다** — 사람이 pull 을 잊는 사고는
> 줄지만, (a) 러너가 **체크아웃 밖의 복사본**에서 돌면 자동 반영이 닿지 않고(§13-2 의 복사본 격차),
> (b) **추적(tracked) 파일에 로컬 변경이 있는 체크아웃**에서는 pull 이 보류되고(§17-7 표),
> (c) **이번 실행이 시작된 뒤**에 머지된 코드는 그 실행에 반영되지 않는다(러너 본체는 기동 시점에 이미
> 파싱되어 메모리에 올라가므로 — 다음 회차부터 반영. code-freshness 가드도 파괴적 작업을 다음 회차로 미룬다).
> 반영 여부는 실행 기록의 코드 버전(§17-7)으로 확인한다.

> §12 상세는 분리 문서로 이동했다: [hourly-issue-scheduler-audit.md](./hourly-issue-scheduler-audit.md)

> §13 상세는 분리 문서로 이동했다: [hourly-issue-scheduler-registration.md](./hourly-issue-scheduler-registration.md)

> §13-2 상세는 분리 문서로 이동했다: [hourly-issue-scheduler-maintenance.md](./hourly-issue-scheduler-maintenance.md)

> §13-1 상세는 분리 문서로 이동했다: [hourly-issue-scheduler-audit.md](./hourly-issue-scheduler-audit.md)

> §13-3 상세는 분리 문서로 이동했다: [hourly-issue-scheduler-audit.md](./hourly-issue-scheduler-audit.md)

> §13-3-1 상세는 분리 문서로 이동했다: [hourly-issue-scheduler-audit.md](./hourly-issue-scheduler-audit.md)

> §13-4 상세는 분리 문서로 이동했다: [hourly-issue-scheduler-audit.md](./hourly-issue-scheduler-audit.md)

> §13-5 상세는 분리 문서로 이동했다: [hourly-issue-scheduler-runtime.md](./hourly-issue-scheduler-runtime.md)

## 14) 연결 문서

- **이슈 번호 지정 실행(`-OnlyIsn`) AI 인스턴스용 유저가이드**: `./only-isn-ai-guide.md` (사양은 본 문서 §18)
- **Docker 배포(auto clone + csn/sk/login_id 자동 등록 + Linux/pwsh 이식)**: `./docker-deployment.md`
- **보조 시간별 스케줄러 5종 + 태스크 등록 게이트**: `./aux-hourly-schedulers.md` (§15 참고)
- 이슈 처리 세션 안전 규칙 색인: `../../.agent/rules/41_issue_session_safety_index.md`
- 진행 코멘트/상태전이 코멘트 프로토콜: `../../.agent/rules/PROTOCOL_PROGRESS_COMMENT.md`
- KPI 표준: `./ai-native-kpi.md`
- 장애/롤백 플레이북: `./incident-rollback-playbook.md`
- 원본 운영 인스턴스 제어법(이 PC 전용): `lowyworkenv/scripts/gissue/SCHEDULER_CONTROL.md`

- 스케줄러 사양서 분리 파일 5종 (절 번호는 본문과 동일): 정비 `./hourly-issue-scheduler-maintenance.md` · 등록/배포 `./hourly-issue-scheduler-registration.md` · 감사/판정 `./hourly-issue-scheduler-audit.md` · 실행/감시 `./hourly-issue-scheduler-runtime.md` · 가드/로딩 `./hourly-issue-scheduler-guards.md`

## 15) 보조 시간별 스케줄러 (giip #2645)

정본은 `./aux-hourly-schedulers.md` 다 — 보조 스케줄러 목록·태스크 등록 게이트·BOM
규칙은 거기서만 관리한다. 이전에는 목록 표를 이 절에 복사해 뒀으나 정본과 어긋나 낡은
상태였으므로, giip #6329로 복사본을 제거하고 이 링크로 대체했다.

> §16 상세는 분리 문서로 이동했다: [hourly-issue-scheduler-runtime.md](./hourly-issue-scheduler-runtime.md)

> 미매핑 CSN 가드 상세는 분리 문서로 이동했다: [hourly-issue-scheduler-guards.md](./hourly-issue-scheduler-guards.md)

> slack-bot 완료 보고 절 상세는 분리 문서로 이동했다: [hourly-issue-scheduler-guards.md](./hourly-issue-scheduler-guards.md)

> §17 상세는 분리 문서로 이동했다: [hourly-issue-scheduler-runtime.md](./hourly-issue-scheduler-runtime.md)

> §18 상세는 분리 문서로 이동했다: [hourly-issue-scheduler-runtime.md](./hourly-issue-scheduler-runtime.md)

> §19 상세는 분리 문서로 이동했다: [hourly-issue-scheduler-guards.md](./hourly-issue-scheduler-guards.md)

> §20 상세는 분리 문서로 이동했다: [hourly-issue-scheduler-guards.md](./hourly-issue-scheduler-guards.md)

> §21 상세는 분리 문서로 이동했다: [hourly-issue-scheduler-registration.md](./hourly-issue-scheduler-registration.md)
