# 매시 이슈 처리 스케줄러 표준 스펙

giip issue 상태머신(PENDING→READY→IN_PROGRESS→REVIEW/DONE, +REVIEW→TESTED)을 매시 정해진 분에
무인으로 자동 처리하는 스케줄러의 **이식 가능한 표준 스펙**입니다. 여기가 **정본(canonical spec)**이며,
각 배포 대상(다른 PC, 다른 프로젝트, 다른 CSN)은 자기 경로만 채워 이 스펙을 그대로 참고/이식합니다.

원본 구현: `lowyworkenv/scripts/gissue/run-gissue-claude.ps1`(csn 47, giipprj 대상 실제 운영 인스턴스).
이 문서는 그 구현에서 플랫폼 종속 부분(절대경로, 이 PC 전용 계정)을 걷어내고 남긴 이식 가능한 뼈대입니다.

## 1) 목적/역할

- giip issue API를 CSN(고객사/프로젝트 식별자) 단위로 폴링해, 사람 개입 없이 이슈를 정제→실행→검증까지
  진행시킵니다.
- 목표는 "이슈가 등록된 뒤 방치되는 시간"을 없애는 것 — PENDING을 작업 지시서로 정제하고, READY를
  코드/문서 변경으로 실행하고, 멈춘 IN_PROGRESS를 회수하고, 실패한 PR을 고치고, REVIEW를 재검증합니다.
- CSN마다 별도 프로세스(또는 별도 -OnlyCsn 실행)로 격리되어, 서로 다른 프로젝트 폴더를 침범하지 않습니다.

## 2) 트리거 스펙

- **매시 :07** 시작(임의로 고른 분 — 정각/일반적인 :00, :05, :10 트리거들과 충돌을 피하기 위한 선택).
- cron 표현식(다른 플랫폼/Linux 참고용): `7 * * * *`
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
  얻습니다(giip #2645) — PENDING / READY≥60분 / IN_PROGRESS≥60분(라벨 `STALE_IN_PROGRESS`) /
  REVIEW·TESTED(최신 코멘트가 `[ACTIONFLOW-TEST]`로 시작하면 제외)를 합쳐
  `qprio → is_user_req DESC → has_comment ASC → elapsedMin DESC` 순으로 정렬해 돌려줍니다.
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

### 5-1) 실행 구조 — "한 세션이 8단계를 순회"가 **아니다** (giip #1472, 2026-08-24 이후)

이 절은 예전에 "매 :07 실행마다 `[0]`,`[A]`~`[H]` 를 순서대로 수행합니다"라고 적혀 있었습니다.
그것은 giip #1472 **이전** 구조입니다. 현재 구현은 다릅니다 — 아래가 실제 실행 구조입니다.

```
:07 태스크 1회
 └─ CSN 마다 Start-Job 1개 (CSN 간 병렬. 이건 예전과 동일)
     ├─ ① 저장소 정비 세션 — 그 CSN 저장소 전체 스코프로 **1회만** 기동
     │      ([0] PR conflict / [E] PR CI 수정 / [F] orphan stash 구조 / [H] 최근 코멘트 재검증)
     └─ ② 이슈별 세션 — 아래 단일 우선순위 큐를 돌며 **이슈 1건마다 별도 프로세스를 개별 기동**
            PENDING / READY(≥1h) / STALE_IN_PROGRESS(≥1h) / REVIEW  ← 하나의 큐, 오래 대기한 순
```

바뀐 것은 **실행 구조**이고, 각 단계가 "무엇을 판단하는가"는 §5-2 표 그대로 유효합니다.

- **단일 우선순위 큐**: 상태별로 따로 순회하지 않습니다. `Get-GissueIssueQueue`
  (`run-gissue-claude.ps1`)가 네 상태를 한 큐로 합쳐 대기시간 내림차순으로 정렬합니다.
  READY / STALE_IN_PROGRESS 는 **1시간 이상 경과분만** 큐에 들어갑니다.
- **이슈마다 별도 프로세스**: 한 세션이 여러 이슈를 이어서 처리하지 않습니다. 이슈 1건 =
  엔진 프로세스 1개이고, 그 이슈의 상태에 맞는 프롬프트 템플릿 1벌만 주입됩니다
  (§5-3). 한 이슈가 망가져도 다음 이슈가 같은 컨텍스트를 물려받지 않습니다.
- **엔진 선택은 이슈 상태별**(`Invoke-GissueEngine` — MiniMax 시도 후 실패 시 **같은 실행 안에서**
  claude 로 폴백하는 재사용 함수):

  | 큐 항목 상태 | 엔진 |
  |---|---|
  | 저장소 정비 세션 | MiniMax 우선 → 실패 시 claude 폴백 |
  | PENDING / READY / STALE_IN_PROGRESS | MiniMax 우선 → 실패 시 claude 폴백 |
  | **REVIEW** | **MiniMax 시도 없이 곧바로 claude**(사용자 지시 2026-08-23) |
  | TESTED | claude 강제 (giip #1472) |

  `MINIMAX_API_KEY`(env 또는 `slack-bot/.env`)가 **없으면** 전 구간이 claude 단독으로 동작합니다 —
  에러가 아니라 설계된 축퇴 경로입니다. 신규 clone 은 `slack-bot/.env` 가 없으므로 기본이 이쪽입니다.
- **시간 예산 초과분은 LLM 없이 미룹니다**: 잡 전체 예산(`$RunTimeoutMin`, §8)에서 **마지막 5분을
  오버헤드 여유로 남기고**, 그 선을 넘으면 남은 큐 항목은 엔진을 기동하지 않고 스크립트가 직접
  note 코멘트를 남긴 뒤 다음 `:07` 로 넘깁니다. 큐가 길어도 태스크가 통째로 잘리지 않게 하는 장치입니다.

### 5-2) 8단계 — 각 단계가 무엇을 판단하는가

"세션" 열이 그 단계가 **저장소 정비 세션**에 속하는지 **이슈별 세션**에 속하는지를 가릅니다.

| 단계 | 세션 | 이름 | 한 줄 요약 |
|---|---|---|---|
| [0] | 저장소 정비 | PR conflict 우선 해결 | 이슈 처리 착수 전, 담당 프로젝트(+nested repo)의 열려있고 conflict 난 PR을 먼저 해소 |
| [A] | 이슈별 | 슬래시 커맨드 즉시 실행 | 제목/본문/최신 코멘트가 `/`로 시작하면 상태·나이 무관하게 즉시 해당 워크플로우 기동 |
| [B] | 이슈별 | PENDING 정제 | 내용을 분석해 작업 지시서 코멘트를 남기고 READY로 전이(실행까지는 안 함) |
| [C] | 이슈별 | READY 실행 | READY로 1시간 이상 경과한 것만, IN_PROGRESS로 선점 후 실제 처리(PR 완료 게이트 + Actionflow 테스트 게이트 통과 시 DONE) |
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
| `$ReadyIssuePromptTemplate` | `[A]` `[C]` | 큐 항목이 READY(≥1h) |
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

## 8) 등록 스크립트 상세 (`register-hourly-issue-scheduler.ps1`)

`scripts/register-hourly-issue-scheduler.ps1`은 이 문서 §2~§3 스펙을 그대로 구현하는, 파라미터화된
Windows Task Scheduler 등록/해제/확인 스크립트다. `-Action` 셋(기본값 `Status`) 3가지:

- **`Register`**: `-RepoRoot`(필수 — 이 스케줄러 스크립트 세트를 배치한 오케스트레이션 레포 루트,
  원본 배포는 `lowyworkenv`)를 받아 `-RunnerRelativePath`(기본
  `scripts/gissue/run-gissue-claude.ps1`)와 조합해 실제 러너 경로를 확인(`Test-Path`, 없으면 즉시
  에러)한 뒤, 다음을 등록한다:
  - **Action**: `powershell.exe -WindowStyle Hidden -NonInteractive -ExecutionPolicy Bypass -File
    "<runner경로>"`
  - **Trigger**: `-StartTime`(기본 `00:07:00`)에 1회 시작해 `-RepetitionMinutes`(기본 60분)마다
    반복. `-RepetitionDuration`을 `[TimeSpan]::MaxValue`로 주면 ISO8601 직렬화 시 Task Scheduler
    XML의 duration 상한을 넘어 등록 자체가 거부되므로(HRESULT 0x80041318, giip #1275 실측), 대신
    `New-TimeSpan -Days 3650`(약 10년)으로 사실상 무기한 반복을 구현한다.
  - **Settings**: `AllowStartIfOnBatteries`+`DontStopIfGoingOnBatteries`(배터리 전원과 무관하게
    실행/지속), `StartWhenAvailable`(예정 시각에 PC가 꺼져 있었으면 켜지는 즉시 실행),
    `MultipleInstances Parallel`(여러 인스턴스 동시 실행 허용), `ExecutionTimeLimit` 2시간.

    **러너 자신의 타임아웃은 `$RunTimeoutMin` = 105분이다** (`run-gissue-claude.ps1` 134행).
    Windows 쪽 `ExecutionTimeLimit`(2시간)보다 **15분 먼저** 만료되도록 일부러 낮춘 값이다 —
    이 15분 간격이 이 설정의 전부이므로 둘 중 하나만 바꾸지 말 것.

    **왜 120 이 아니라 105 인가(giip #1572, 2026-08-27 실측 사고)**: 원래 120분이었는데, 그러면
    Windows Task Scheduler 의 `ExecutionTimeLimit`(2시간)과 사실상 같아 여유가 전혀 없다. CSN47 잡이
    01:00:48 까지 정상적으로 작업하고 있었는데 01:07:00 에 **Windows 가 먼저 프로세스를 강제종료**해,
    스크립트 자신의 우아한 정리(`Complete-Run`, 락 해제)가 한 줄도 실행되지 못했고 `.lock` 파일이
    고아로 남았다. 즉 "러너가 자기 타임아웃으로 스스로 접는 경로"가 아예 도달 불가였다. 그래서
    러너를 Windows 보다 15분 먼저 만료시키도록 105 로 낮췄고, `ExecutionTimeLimit` 2시간은
    **"그 내부 정리마저 실패했을 때"의 최후 안전망**으로 남겨 두었다(제거하면 안 된다).

    **`MultipleInstances Parallel`로 바꾼 이유(giip #1562, 2026-08-26 실측 사고)**: 원래
    `IgnoreNew`였는데, csn 47(백로그 큼) 처리가 오래 걸려 16:07 인스턴스가 2시간 가까이 살아있는 동안
    17:07/18:07 정기 트리거가 "이전 인스턴스 실행 중"이라는 이유로 통째로 스킵됐다(이벤트 ID 322,
    18:07:05에 ExecutionTimeLimit 초과로 강제 종료 — 이벤트 ID 329). 오케스트레이터가 CSN별로
    Start-Job을 띄우고 전체 job이 끝날 때까지 기다리는 구조라, 하나의 태스크 인스턴스가 가장 느린 CSN
    하나 때문에 몇 시간씩 살아있으면 그동안 csn 47과 무관한 다른 모든 CSN(2, 33, 70335, 70374 등)의
    정기 처리까지 함께 멈췄다. 각 CSN은 이미 자체 파일 락(§9의 `gissue_csn<N>.lock`, 2시간 초과 시
    stale 자동제거)으로 "같은 CSN을 여러 인스턴스가 동시 처리"하는 것을 막고 있다는 전제 하에,
    `Parallel`로 바꿔 다음 트리거가 통째로 스킵되지 않도록 했다 — CSN별 중복 처리 방지는 계속 그
    파일 락이 담당한다.
  - **실행 계정**: 기본값은 현재 로그온 사용자(`$env:USERDOMAIN\$env:USERNAME`), `RunLevel Limited`.
    `-Password`를 넘기면 PSCredential로 비밀번호 인증 등록을 해 그 계정이 로그오프 상태여도(재부팅
    후 로그인 안 해도) 스케줄이 동작한다 — 넘기지 않으면 `Register-ScheduledTask`가 최초 등록 시
    대화형 자격증명 프롬프트를 띄울 수 있어 무인 등록(원격 세션 등)에서는 걸릴 수 있다.
  - **`-TaskName`**(기본 `GIIP_Gissue_Claude`): 같은 PC에 여러 배포를 동시에 등록하려면(예: 서로
    다른 오케스트레이션 레포/CSN 세트) 배포마다 고유한 이름을 지정해야 한다 — 기본값 그대로 두 번
    등록하면 `-Force`로 앞선 등록을 덮어쓴다.
- **`Unregister`**: 해당 `-TaskName`의 태스크를 확인 프롬프트 없이(`-Confirm:$false`) 제거. 이미
  없으면 에러 대신 안내 메시지만 출력(멱등).
- **`Status`**(기본값, `-RepoRoot` 불필요): `Get-ScheduledTask`+`Get-ScheduledTaskInfo`로 태스크
  이름·State·Enabled·등록된 Action 문자열·LastRunTime·LastTaskResult·NextRunTime을 한 번에 출력한다.

## 9) 등록 확인 방법

등록 스크립트의 `-Action Status`가 가장 빠른 확인 경로다:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\register-hourly-issue-scheduler.ps1 -Action Status -TaskName GIIP_Gissue_Claude
```

직접 표준 cmdlet으로 확인해도 동일하다:

```powershell
Get-ScheduledTask -TaskName GIIP_Gissue_Claude
Get-ScheduledTaskInfo -TaskName GIIP_Gissue_Claude | Select-Object LastRunTime, LastTaskResult, NextRunTime
```

`LastTaskResult`가 `0`이면 프로세스 자체는 정상 종료됐다는 뜻이지만(러너 내부는 CSN별로 try/catch로
감싸 개별 실패를 삼키므로 스크립트가 통째로 비정상 종료하는 경우는 드물다), **그것만으로 "이슈 처리가
실제로 진행되고 있다"를 확인했다고 보지 말 것** — 등록/기동 성공과 실제 큐 처리 진행은 별개다. 반드시
로그를 직접 열어 최근 사이클이 실제로 돌았는지 확인한다:

```powershell
Get-Content -Tail 20 -Encoding UTF8 .\scripts\gissue\logs\gissue_csn<CSN번호>.log
```

- `gissue_csn<N>.log`: `Write-Log`가 남기는 사람이 읽는 이벤트 로그. 정상 사이클이면 `START
  (cwd=...)`로 시작해(잡이 실제로 기동됐다는 뜻) 잡 종료 시 `DONE`(또는 타임아웃 시 `TIMEOUT`류
  메시지)으로 끝난다. `SKIP: ...`만 반복되면(workdir 없음/lock 미해제/스케줄러 비활성 등) 원인을
  그 SKIP 사유 문자열에서 바로 확인할 수 있다.
- `gissue_csn<N>.out.log`: claude/MiniMax 잡의 원시 stdout(프롬프트에 대한 실제 응답, 무엇을
  처리했는지 서술). 이슈가 실제로 처리됐는지 세부를 보려면 여기를 본다.
- `gissue_csn<N>.lock`: 실행 중 표시용 파일(내용은 PID). `$LockMaxAgeHr`(2시간)보다 오래됐으면 다음
  실행이 stale로 간주해 자동 제거하고 이어서 실행한다 — 사람이 수동으로 지울 필요는 보통 없다.

"최근 사이클이 실제로 새 코드로 돌았는지"까지 확인하려면(아래 §11 참고) 로그 타임스탬프가 최근
`git log`/`git pull` 이후인지 대조한다.

## 10) orphan `.worktrees` 자가정리 — 왜 존재하는가 (giip #1540/#1544/#1547)

`run-gissue-claude.ps1`은 각 CSN 처리마다(Phase 1 busy-wait 대기보다 먼저) `Remove-GissueOrphanWorktrees`
함수로 담당 프로젝트(+nested repo) 안의 `.worktrees/` 디렉터리를 스캔해, **git worktree로 정식
등록되지 않은(orphan) + 이슈 상태가 DONE이거나 이슈 자체가 없는 + 24시간 이상 방치된** 디렉터리만
안전하게 삭제한다. 존재 이유:

- **giip #1540** (2026-08-26): lowyworkenv의 동일 러너에서, 이미 DONE 처리된 이슈의 `.worktrees/`
  잔해 안에 orphan `node_modules`(pnpm 구조, 매우 깊은 경로)가 남아 있어 Windows git이
  "Filename too long"을 반복 발생시켰다. 이 러너의 `[F]` orphan-stash 자동언블록(`stash -u`) 로직이
  이 잔해를 건드릴 때마다 실패해, 그 실패가 **20,236회** 반복되며 CSN47 이슈 큐 전체가 완전히
  마비됐다(어떤 이슈도 처리되지 못함).
- **giip #1544**: 위 인시던트의 재발 방지로, lowyworkenv 쪽 러너 자신에게 이 결정적(비-LLM)
  PowerShell 정리 로직을 추가했다(`Get-GissueIsnStatusMap`/`Remove-GissueOrphanWorktrees`, DB
  직접 조회 경로 사용).
- **giip #1547** (이 변경): 이 레포(`giip-fde-agent`)의 `run-gissue-claude.ps1`도 동일한
  `[F]`/`stash -u`/AUTO-UNBLOCK 구조를 그대로 갖고 있어 같은 취약점에 노출될 수 있으므로, 원본
  레포 자신에도 동일 취지의 방어 로직을 이식했다. 이 레포는 DB 직접 접근이 없어(§4 참고), isn 상태
  조회를 giipfaw API(`scripts/gissue/lib/get-isn-status.js`, 신규)로 대체한 것이 lowyworkenv 판과의
  유일한 구조적 차이다.

READY/PENDING/IN_PROGRESS/REVIEW/TESTED 상태의 이슈에 연결된 워크트리, 그리고 `git worktree list`에
정식 등록된 워크트리는 이 로직이 **절대** 건드리지 않는다 — 사람이 지금 그 워크트리에서 작업 중일 수
있기 때문이다. 삭제 자체도 Windows `MAX_PATH`(260자) 제한을 우회하기 위해 robocopy 빈 폴더 `/MIR`
미러 트릭을 쓴다(`Remove-Item` 단독으로는 깊은 pnpm 경로 등에서 실패할 수 있다 — 이번 인시던트 수동
조치에서 실제로 쓴 방법). 실행 로그에서 `[ORPHAN-CLEANUP]` 접두어로 필터링하면 무엇을 왜 지웠는지(또는
왜 보류했는지) 바로 확인할 수 있다.

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

## 12) 이슈 처리 세션에 반드시 주입할 안전 규칙 (giip #2465)

§5 상태머신이 "무엇을 할지"를, §11이 "그 코드가 실제로 도는지"를 다룬다면, 이 절은 **세션이
처리하는 동안 지켜야 할 안전 규칙을 어떻게 세션에게 전달하는가**를 다룹니다.

### 12-1) 배경 — 문서에만 있는 규칙은 지켜지지 않았다

2026-09-14 하루 동안 같은 계열 사고 10건이 실측으로 확인됐고, **공통점은 전부 "규칙은 문서에 있는데
매번 기억해서 지켜야 하는" 형태**였습니다. 세션 프롬프트에 주입되거나 훅으로 강제된 규칙만 실제로
지켜졌습니다(giip #2442에서 실증 — 규칙을 만든 당사자 세션이 자기가 만든 훅에 차단당했습니다).

따라서 규칙 본문의 정확성만으로는 부족하고, **전달 경로(주입)** 가 스펙의 일부입니다.

### 12-2) 정본 위치와 주입 계약

- 규칙 정본: `.agent/rules/41_issue_session_safety_index.md`(색인)와 그것이 가리키는
  `42_`~`50_` 파일들, 그리고 `.agent/rules/PROTOCOL_PROGRESS_COMMENT.md`(코멘트 시각 규정 포함).
- **프롬프트 템플릿은 이 색인 파일 1개만 가리키면 됩니다.** 규칙 본문을 프롬프트에 복제하지
  마십시오(본문 복제 금지 — §5의 상태머신 상세와 같은 원칙).
- 이 레포의 러너(`scripts/gissue/run-gissue-claude.ps1`)는 `$PromptTemplate` 안의 `{AGENT_REPO}`
  치환자로 이 색인 파일이 있는 레포 루트를 세션에 알려줍니다.

| 규칙 | 한 줄 요약 | 근거 giip |
|---|---|---|
| 42 완료 판정은 실행 결과로만 | 등록/머지는 근거가 아니다. `LastTaskResult=0`도 아니다 | #2415 #2425 #2429 #2431 #2436 |
| 43 위임 안전 블록 | worktree 격리 / install 금지+`mklink /J` / 링크 후에도 worktree 안 pnpm 의존성 변경 금지(write-through) / `--no-verify` 금지 / 자기 worktree 정리 금지 | #2390~#2397 #2432 #2442 #2476 #2487 #2497 |
| 44 `[NO-PR-REASON]` | PR이 성립 불가한 이슈의 탈출구 | #2415 #2425 |
| 45 3회 캡 이후 `NEEDS_DECISION` | 4분기 재판정, 예·아니오 질문 1개 | #2415 #2425 |
| 46 타 CSN 쓰기 금지 | 읽기는 되고 쓰기는 안 된다 | #1053 #1079 |
| 47 자동 정리 안전 요건 | idle 가드 / locked 스킵 / 링크 게이트 / 항목별 검증 / 로그 | #2432 #2445 #2463 #1540 |
| 48 안전 판정 공용 함수 1개 | 복붙 중복 금지(코드와 프롬프트 문단 양쪽) | #2440 #2463 #2425 |
| 49 문구 매칭 오탐 방지 | 주어·시제 구분. 애매하면 잡지 않는다 | #2424 #2457 |
| 50 봇 PR 범위 규율 | `git add -A` 금지, 머지 전 `--json files` 확인 | #2424 #2459 |

### 12-3) ⚠️ 주입 블록은 프롬프트에 **단 한 번만** 둔다

원본 구현(`lowyworkenv/scripts/gissue/run-gissue-claude.ps1`)의 프롬프트 템플릿에는 **같은 안전
문단이 2벌 존재**했습니다 — `[C]` READY 처리용 1벌, `[D]` stale IN_PROGRESS 회수용 1벌. 한쪽만
고쳐진 결과, 어느 단계를 타느냐에 따라 규칙이 적용되기도 하고 안 되기도 했습니다(giip #2425 실측).

**따라서 이식할 때는 주입 블록을 `[0]`~`[H]` 각 단계가 아니라 템플릿 최상단(모든 단계 공통 영역)에
한 번만 넣습니다.** 각 단계는 "위 [안전 규칙 로드] 그대로 따른다"로 참조만 합니다.

> 이미 2벌 이상이 존재하는 이식본을 고칠 때는 **양쪽을 모두 검색해 함께 고치거나 한 벌로
> 합칩니다.** 한쪽만 고친 PR은 "고쳤다"고 보고되지만 실제로는 절반만 동작합니다.
> 자기 이식본에 블록이 몇 벌인지 먼저 세어 보십시오(블록 헤더가 줄 맨 앞에 오는 것만 셉니다 —
> 본문 안의 `"위 [안전 규칙 로드] 그대로 따른다"` 같은 참조는 세지 않습니다):
>
> ```powershell
> (Select-String -Path .\scripts\gissue\run-gissue-claude.ps1 -Pattern '^\[안전 규칙 로드\]').Count
> ```
>
> 기대값은 **1**입니다. 2 이상이면 §12-3 위반이므로 한 벌로 합친 뒤 진행하십시오.

### 12-4) 주입이 실제로 됐는지 확인하는 방법

프롬프트에 문구를 넣은 것만으로는 확인이 아닙니다(규칙 42). 아래까지 해야 "주입됐다"입니다.

1. `-DryRun -OnlyCsn <csn>`으로 실행해, 생성된 프롬프트에서 `{AGENT_REPO}`가 **실제 경로로
   치환됐는지** 확인한다(치환자가 그대로 남아 있으면 실패).
2. 그 경로에 `.agent/rules/41_issue_session_safety_index.md`가 **실제로 존재하는지** 확인한다
   (러너만 복사하고 규칙 파일을 빠뜨린 이식은 여기서 걸린다).
3. 한 사이클을 실제로 돌린 뒤, 세션이 남긴 착수 코멘트의 로드 목록에 그 규칙 파일이 적혀 있는지
   확인한다(`.agent/rules/PROTOCOL_PROGRESS_COMMENT.md` §"남기는 시점 1) 착수" 규정).

## 13) 배포 절차(신규 CSN/PC — 복사만으로 이식)

이 레포 자체가 이제 실행 가능한 구현체입니다(스펙 문서만이 아님). 새 프로젝트/PC에 이식하려면:

1. 이 레포(`giip-fde-agent`)를 그 PC에 clone(또는 이미 있으면 pull).
2. `scripts/gissue/csn-projects.json.example`을 `csn-projects.json`으로 복사 후 자기 CSN/워크디렉터리
   (+필요시 `restBranch`)만 채운다.
3. `slack-bot/.secrets/giip-accounts.sample.json`을 `giip-accounts.json`으로 복사 후 실제 SK를 채운다.
4. **안전 규칙 파일이 함께 복사됐는지, 프롬프트가 그것을 로드하는지 확인한다(§12, giip #2465)**:
   - `.agent/rules/41_issue_session_safety_index.md`와 그것이 링크하는 `42_`~`50_`,
     `.agent/rules/PROTOCOL_PROGRESS_COMMENT.md`가 이 clone 안에 실제로 존재하는지 확인한다
     (러너 스크립트만 골라 복사하는 이식은 여기서 걸린다).
   - 러너의 프롬프트 템플릿에 `[안전 규칙 로드]` 블록이 있고, 그것이 **정확히 1벌**인지 확인한다
     (§12-3의 카운트 명령). 2벌 이상이면 한쪽만 고쳐지는 사고의 조건이므로 먼저 합친다.
   - 복사만으로 이식되는 구조를 깨지 말 것 — 규칙을 다른 레포로 옮기거나 프롬프트에 본문을
     복제하면, 다음 이식 대상은 규칙 없이 도는 러너를 받게 된다.
5. `-DryRun -OnlyCsn <csn>`으로 먼저 실행해 워크디렉터리 인식·SK 해석·busy-check(BUSY 오판 없음)·엔진
   선택, 그리고 **프롬프트의 `{AGENT_REPO}` 치환 결과**(§12-4)까지 로그로 확인한다(실제 claude 미기동).

   **2~3단계를 건너뛰고 5단계를 먼저 실행해도 예외 스택트레이스가 나오지 않는다**(giip #2645):
   러너가 시작 직후 `Phase -3` 전제조건 preflight 를 돌려, 빠진 것을 행동지시로 알려준다.

   | 상태 | 러너의 반응 | 종료코드 |
   |---|---|---|
   | `csn-projects.json` 없음 | `[PREFLIGHT-FAIL]` + 복사할 명령·채울 항목·재실행 명령·이 절 링크 | 2 |
   | JSON 문법 오류 | `[PREFLIGHT-FAIL]` + 실패 사유 + 문법 힌트 | 2 |
   | `.example` 를 복사만 하고 값 미기입 | `[PREFLIGHT-FAIL]` + **어느 항목이 왜 잘못됐는지 항목별로** 제시 | 2 |
   | 일부 CSN 항목만 잘못됨 | `[PREFLIGHT-WARN]` + 그 항목만 건너뛰고 나머지는 정상 처리 | 0 |
   | `giip-accounts.json` 없음 | `[PREFLIGHT-WARN]` + 복사 명령(이슈 관련 단계는 전부 SKIP 됨) | 0 |
   | `node` / `gh` 미설치 | `[PREFLIGHT-WARN]` + 각 도구의 용도 | 0 |
   | bash 해석 성공 | `[PREFLIGHT] bash 해석됨: <절대경로>` (경고 아님) | 0 |
   | bash 후보 전부 실패 | `[PREFLIGHT-WARN]` + 설치 URL + 죽는 단계 명시 | 0 |

   설계 근거: 이 절의 5단계가 신규 PC 사용자의 **첫 명령**이다. 여기서 .NET 예외가 나오면
   "클론만으로 동일 작업 가능"이라는 이 배포의 전제가 깨진다. 따라서 **신규 clone 에 없는 것을 읽는
   모든 지점은 (a) 치명적이면 행동지시 + 비0 종료, (b) 아니면 행동지시 WARN 후 계속**이어야 한다 —
   조용한 예외/스택트레이스는 둘 다 아니다. 러너를 고칠 때 이 원칙을 깨지 말 것.

   검증도 같은 조건에서 해야 한다: "내 작업 폴더에서 돌아갔다"는 신규 clone 검증이 아니다.
   **gitignore 대상 설정 파일이 하나도 없는 상태**와 **채운 상태** 두 가지를 모두 돌려 확인한다.

   **bash 는 러너가 스스로 찾는다 — PATH 에 없어도 된다**(giip #2645). `powershell -File` 로 기동되는
   이 러너에서 `Get-Command bash` 가 실패하는 것은 **Git for Windows 기본 설치의 정상 상태**다:
   설치 프로그램은 `<Git>\cmd`(=`git.exe`)만 PATH 에 올리고 `bash.exe` 는 `<Git>\bin` 과
   `<Git>\usr\bin` 에 둔다. 그래서 러너는 PATH 존재 여부로 판정하지 않고 `Resolve-GissueBashExe`
   공용 함수로 아래 순서를 훑는다.

   | 순서 | 후보 |
   |---|---|
   | 1 | PATH 의 `bash`(사용자가 의도적으로 넣은 경우 최우선) |
   | 2 | `git.exe` 위치 역산 — `<Git>\bin\bash.exe`, `<Git>\usr\bin\bash.exe`(한 단계 위까지) |
   | 3 | `%ProgramFiles%` / `%ProgramFiles(x86)%` / `%LOCALAPPDATA%\Programs\Git` / `C:\Git` / `D:\Git` |

   Git 설치 위치가 어디든(기본 경로, `C:\Git`, scoop/winget, x86) 2번이 따라갑니다. 해석에 성공하면
   경고 대신 이 줄이 나옵니다(이 PC 실측):

   ```text
   [PREFLIGHT] bash 해석됨: C:\Program Files\Git\bin\bash.exe
   ```

   **모든 후보가 실패할 때만** 경고가 나오며, 그때는 설치 URL과 "어떤 단계가 죽는지"(이슈 코멘트 게시 /
   상태 전이 — 실패하면 이슈가 IN_PROGRESS·REVIEW 에 박혀 큐가 정체된다)를 함께 안내합니다.
   같은 해석 로직이 `verify-runner.mjs`(VERIFY-GATE)에도 들어가 있습니다 — 거기서 bash 를 못 찾으면
   ```` ```verify ```` 의 bash 블록이 전부 거짓 FAIL 이 되기 때문입니다.

   > 이전 판(PR #86 시점)은 이 절에 "시스템 PATH 에 `Git\bin` 을 추가하라"고 적혀 있었습니다.
   > 그 조치는 이제 **불필요**합니다. 러너가 스스로 찾습니다.
6. 문제 없으면 `register-hourly-issue-scheduler.ps1 -Action Register -RepoRoot <이 clone 경로>`로
   Windows 스케줄러에 등록한다(태스크 이름은 배포 대상마다 고유하게 `-TaskName`으로 지정).

   ⚠️ **태스크 등록은 반드시 정상 체크아웃에서 한다 — worktree 안에서 실행하면 거부된다.**
   등록기들은 `Register-ScheduledTask` 직전에 `task-target-guard.ps1` 의 3중 게이트를 통과해야 하는데,
   게이트 3 이 대상 `.ps1` 경로가 `\temp\worktrees\` 또는 `\.claude\worktrees\` 하위인지 검사해
   해당하면 등록을 중단한다(§15). worktree 경로를 태스크에 박으면 그 worktree 를 지우는 순간
   태스크가 존재하지 않는 파일을 가리키며 조용히 죽기 때문이다(giip #2431). 실제 거부 출력:

   ```text
   [TASK-GUARD][3/3][FAIL] 임시 worktree 경로(패턴 '\temp\worktrees\') 하위 — 등록 거부
   [TASK-GUARD][BLOCKED] <TaskName> 등록을 중단합니다(1건):
   ```

7. **(선택) 보조 시간별 스케줄러 5종을 등록한다.** 메인 태스크만으로도 동작하므로 필요할 때만
   등록하면 된다. 5종의 목록·주기·등록기 이름과 각 등록기의 파라미터는 **정본 유저가이드**
   [`./aux-hourly-schedulers.md`](./aux-hourly-schedulers.md) 를 따른다(§15 에 목록 요약).
   등록기도 6단계와 같은 3중 게이트를 쓰므로 **정상 체크아웃에서 실행해야 한다.**

   ```powershell
   # 5종 모두. 태스크 이름을 바꾸려면 각 등록기의 -TaskName 을 쓴다.
   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\gissue\register-stale-pending-task.ps1
   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\gissue\register-stale-review-task.ps1
   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\gissue\register-audit-review-prs-task.ps1
   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\gissue\register-gate-escalation-task.ps1
   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\gissue\register-slackbot-restart-task.ps1
   ```

   등록 전에 러너 5종을 직접 1회 돌려 보는 것을 권장한다(등록기는 파싱만 보고 실행 결과는 보지 않는다).
8. 등록 후 **한 사이클을 실제로 돌려** 세션 착수 코멘트의 로드 목록에 규칙 파일이 나타나는지
   확인한다 — 등록 성공 메시지나 `LastTaskResult=0`은 근거가 아니다(§9, `.agent/rules/42_`).

**주의**: 스케줄러가 처리할 workdir가 사람이 대화형으로 동시에 쓰는 작업 폴더와 같으면, `restBranch`를
지정해도 busy-check의 "다른 세션이 지금 쓰는 중" 신호와 실제 사람의 동시 작업을 근본적으로 구분할
수 없어, 사람이 작업 중인 워킹트리에 강제 언블록(stash+체크아웃)이 실행될 위험이 남는다. 대화형으로도
자주 쓰는 저장소라면, 스케줄러 전용 별도 clone을 workdir로 쓰는 것을 권장한다(원본 저장소와는 git
remote로만 연결된, 완전히 독립적인 워킹트리).

## 13-2) 원본(`lowyworkenv`)과의 파일 격차 — 무엇이 이식되지 않았는가 (giip #2645 작업 D)

**이 문서는 다른 PC 가 clone 해 쓰는 계약서입니다. 알려진 결손을 숨기지 않습니다.**

2026-09-17 신규 clone(`origin/main` `2df478a`) 실측: `scripts/gissue` 최상위 파일이 원본 54개 대
이 레포 43개입니다. 차이 14건 + gitignore 대상 `csn-projects.json` 1건 = 15건이며, 전부 아래 표에
있습니다. 반대로 이 레포에만 있는 파일도 3건 있습니다(`csn-projects.json.example` /
`list-issues.js` / `stale-issue-scan-lib.ps1` — 이식 과정에서 신설).

### 13-2-1) 이식하지 않는 것이 맞는 것 (후속 불요)

| 파일 | 판단 근거(파일을 열어 확인한 내용) |
| :-- | :-- |
| `README.md` / `SPEC.md` | 이 스케줄러 표준의 **정본은 이 문서**입니다(§7). 원본의 두 문서를 복제하면 정본이 둘이 됩니다. |
| `SCHEDULER_CONTROL.md` | "이 PC(Lowy-DP01) 운영 인스턴스"의 제어법이라 배포 대상마다 무의미합니다. §14 가 원본 경로를 링크로만 가리킵니다. |
| `SLACKBOT_AUTO_RESTART.md` | 같은 내용이 이 레포의 `./aux-hourly-schedulers.md`(slackbot 재시작 스케줄러 절)로 재작성돼 있습니다. |
| `csn-projects.json` | 시크릿성 로컬 설정(CSN·절대경로). `csn-projects.json.example` 로 대체되며 배포마다 직접 채웁니다(§13 2단계). |
| `_scan_tp.cjs` (17줄) | 하드코딩된 isn 5개(`1966,1968,1971,1972,2040`)를 `/tmp/g70424/c_*.json` 에서 읽는 1회용 조사 스크립트. 재사용 경로 없음. |
| `extract_sk70427.ps1` (2줄) | csn 70427 의 SK 1건을 콘솔에 덤프하는 2줄짜리 일회성 스크립트. 시크릿을 표준출력으로 내보내므로 이식 대상이 아닙니다(`.agent/rules/49_no_plaintext_credential_persist.md`). |
| `verify-1665-oneshot.ps1` (186줄) | 헤더에 "giip #1671 단발성(1회) 검증"이라 명시돼 있고, 실행 끝에 자기 태스크를 `Unregister-ScheduledTask` 로 지웁니다. 2026-08-29 14:07 실행 1회로 역할이 끝났습니다. |
| `review-done-audit.ps1.bak_1570_20260828094004` | 파일명 그대로 2026-08-28 편집 백업본. |
| `test-cd-worktree-hook.ps1` (190줄) | `.claude/hooks/check-ps1-parse.sh`(원본 PC 의 훅 배치)를 대상으로 하는 회귀 테스트라, 그 훅이 없는 배포에서는 대상 자체가 없습니다. |
| `register-interactive-session.ps1` (330줄) | Claude Code **대화형 세션**을 `tSchedulerAgent` 에 등록하는 훅 연동 스크립트(giip #1645). `:07` 스케줄러 동작과 무관하고, 원본 PC 의 훅·`CLAUDE_CODE_BRIDGE_SESSION_ID` 환경에 의존합니다. |
| `register-issue.ps1` (37줄) | 같은 디렉터리 `register-issue.js` 를 부르는 **PowerShell 래퍼**일 뿐입니다. `register-issue.js` 는 이식돼 있고, 이 레포의 러너·감사 스크립트는 전부 `.js` 를 직접 호출합니다(`run-gissue-claude.ps1` 109행, `review-done-audit.ps1` 101행). 기능 결손 없음. |

### 13-2-2) DB 직접접속 전용 — 이식 대상 아님 (이 레포는 API 경로만 쓴다)

이 레포의 배포 대상에는 `giipdb/mgmt/dbconfig.json`(DB 자격증명)이 없습니다. §13-1-3 의 "쓰기 경로가
API 하나뿐" 이라는 설계와 같은 이유로, 아래 3건은 의도적으로 제외했습니다.

| 파일 | 하는 일 | 이식하지 않은 결과 |
| :-- | :-- | :-- |
| `giipdb-locate.ps1` | nested `giipdb/mgmt`(= `execSQLFile.ps1` + `dbconfig.json`) 위치 탐색 헬퍼 | DB 적재를 안 하므로 호출부가 없습니다. **이 레포의 어떤 스크립트도 이 파일을 참조하지 않습니다**(전수 grep 확인). |
| `sync-csn-mapping-from-db.ps1` | `dbo.tGissueCsnMapping` 을 정본으로 보고 `csn-projects.json` 을 DB 에서 덮어씀(giip #2363) | 이 레포는 `csn-projects.json` **파일 자체가 정본**입니다(§13 2단계). 원본과 정본 방향이 다르다는 점만 알고 있으면 됩니다. 참조부 없음. |
| `sync-ai-actor-credentials.ps1` | AI 행위자 계정의 AK 를 giipdb → `slack-bot/.secrets/giip-accounts.json` 으로 직접 이동(giip #2613) | AK 를 **수동으로** 채워야 합니다. 절차서 `scripts/gissue/AI_ACTOR_ACCOUNTS.md` §3-3 이 이미 이 항목을 `미이식` 로 표기하고 있습니다. |

⚠️ **`scripts/gissue/ai-actors.json` 의 `_comment` 가 이 미이식 파일을 가리킵니다** —
"`sync-ai-actor-credentials.ps1` 이 DB 에서 그리로 직접 옮긴다"고 쓰여 있으나 **그 파일은 이 레포에
없습니다.** 신규 PC 에서는 그 문장을 따라갈 수 없으므로, AK 는 `AI_ACTOR_ACCOUNTS.md` 의 절차대로
직접 기입하십시오. (문구 교정은 이 문서 작업의 범위 밖이라 후속 이슈 소관입니다 — 로직·설정 파일을
건드리지 않고 사실만 여기 남깁니다.)

### 13-2-3) ⚠️ 알려진 결손 — 고쳐야 하지만 아직 안 고쳐진 것

**아래 2건은 "이식됐지만 원본과 동등하지 않은" 상태입니다. 후속 이슈 소관입니다.**

| 항목 | 실측 내용 | 신규 PC 에 미치는 영향 |
| :-- | :-- | :-- |
| `scripts/gissue/pr-gate-sweep.ps1` 이 **구버전** | 이 레포 19,753 바이트 vs 원본 43,108 바이트. 원본에만 있는 함수: `Format-PrEvidence` / `Invoke-GateEscalate` / `Set-IssueNeedsDecision` | **게이트 에스컬레이션 / NEEDS_DECISION 전이 경로가 없습니다.** 게이트 실패가 사람에게 올라가지 않고 그대로 머무를 수 있습니다. |
| `scripts/gissue/get-issue.sh` 에 **`--role` 플래그 없음** | 원본은 `--role` 로 구조화 필드 `loadedRole` 을 채웁니다(giip #1324/#1452). 이 레포의 `get-issue.sh` / `post-comment.js` / `comment-api.js` 에는 그 경로 자체가 없습니다(`role` 문자열 출현 0회 vs 원본 8회). | 이 레포가 남기는 코멘트는 **`loadedRole=null`** 이 됩니다. 어느 역할로 처리했는지가 이슈에 기록되지 않습니다. |

### 13-2-4) 해소된 결손 (giip #2645 — 이력)

PR #86 시점에 이 절이 "알려진 결손"으로 적어 둔 것 중 아래 2건은 **고쳐졌습니다.** 같은 증상을
다시 만났을 때 "원래 그런 것"으로 오인하지 않도록 이력을 남깁니다.

| 항목 | 그때 상태 | 지금 |
| :-- | :-- | :-- |
| `bash` 를 PATH 에서 못 찾음 | 문서가 "시스템 PATH 에 `Git\bin` 을 추가하라"고 안내했고, 러너의 두 상태전이 호출부는 맨 `bash` 를 불러 **이 PC 에서도 항상 실패**하면서 `Out-Null` + 빈 `catch {}` 로 흔적조차 남기지 않았습니다(실패 시 이슈가 IN_PROGRESS 에 박힘) | `Resolve-GissueBashExe` 공용 함수가 PATH → `git.exe` 역산 → 알려진 설치 위치 순으로 해석합니다. PATH 조치 불필요. 상태 전이는 종료코드를 확인해 `[STATUS-OK]` / `[STATUS-FAIL]` 로 **반드시** 기록합니다. `verify-runner.mjs` 의 `spawnSync('bash')` 도 같은 해석을 씁니다 |
| `test-verify-gate-exit-contract.ps1` 가 clone 직후 FAIL | `-LiveCsn` 기본값이 원본 PC 의 **33** 이라 `PASS=23 FAIL=1` | 기본값 `0` → `csn-projects.json` 의 첫 enabled CSN 자동 선택, 정할 수 없으면 사유를 밝히고 SKIP. 인자 없이 exit 0 |

## 13-1) 감사·스윕·가드 스크립트와 공용 lib (giip #2645)

`:07` 본체(`run-gissue-claude.ps1`)가 부르는 **무결성 가드 / PR 감사 / 스윕** 계열이 이 레포에
들어와 있습니다. 아래는 그 목록과, 원본(`lowyworkenv`)과 **동작이 다른 지점**입니다 — 다른
지점만 적습니다. 나머지는 원본과 동일하게 동작합니다.

### 13-1-1) 무결성·안전 가드

| 파일 | 역할 |
| :-- | :-- |
| `scripts/gissue/verify-nested-repo.ps1` | nested 체크아웃 무결성 6종 검사(경로 존재 / 유효 git 레포 / **bare 아님** / origin 접미사 일치 / `-RequiredFiles` 존재 / `-RequiredPsDir` 안 `*.ps1` 1개 이상). 마지막 줄은 항상 `RESULT: PASS` 또는 `RESULT: FAIL: <사유>…`, exit 0/1 |
| `scripts/gissue/worktree-safety.ps1` | worktree 판정·삭제 엔진 정본(rule 55 절차 내장) |
| `scripts/gissue/cleanup-worktrees.ps1` | 위 엔진의 CLI 진입점(`-RepoPath` / `-AllRepos` / `-OrphanScan` / `-RemnantScan`) |
| `scripts/gissue/code-freshness.ps1` | "지금 메모리의 코드가 낡았는가" 가드. 낡았으면 파괴적 작업을 건너뛰고 다음 `:07` 에 넘긴다 |

`verify-nested-repo.ps1` 은 **의도적으로 detect-and-halt 전용**입니다. 자동 재clone / 자동 복구를
추가하지 마세요 — 애초에 "무언가 잘못된 레포를 자동으로 clone 했다"가 giip #1365 사고의 원인이고
그 프로세스는 아직 특정되지 않았습니다. 복구는 사람이 판단합니다.

`cleanup-worktrees.ps1` 의 orphan 정리는 **(a) git worktree 로 정식 등록되지 않았고 (b) 이슈가
DONE 이거나 이슈 자체가 없고 (c) 24시간 이상 방치된** 것만 지웁니다. READY/PENDING/IN_PROGRESS/
REVIEW/TESTED 이슈에 연결된 워크트리와 `git worktree list` 에 정식 등록된 워크트리는 **절대**
건드리지 않습니다(사람이 그 안에서 작업 중일 수 있습니다). 배경은 §10 과 giip #1540 입니다.

**실행 셸**: 이 레포의 배포 대상에는 PowerShell 7(`pwsh`)이 없을 수 있습니다. 문서 예시와 실제
호출은 전부 `powershell -NoProfile -ExecutionPolicy Bypass -File "<경로>"`(Windows PowerShell 5.1)
로 씁니다 — `pwsh` 로 부르면 `command not found` 로 **아무 일도 하지 않고** 끝납니다(giip #2559).

**인코딩**: 이 레포의 `.ps1` 은 전부 **UTF-8 with BOM** 으로 저장합니다. PowerShell 5.1 은 BOM 이
없는 파일을 시스템 ANSI 코드페이지로 읽습니다 — BOM 없는 `.ps1` 6개가 파서 검사를 "6개 전부 통과"
받고도 `powershell -File` 실행에서는 파서 에러 7건으로 한 줄도 실행되지 않은 실측이 있습니다
(giip #2590/#2591). BOM 3바이트를 붙이자 정상이 됐습니다.

### 13-1-2) PR 감사·스윕

| 파일 | 역할 |
| :-- | :-- |
| `scripts/gissue/review-done-audit.ps1` | REVIEW/DONE 완료위조 감사 + 상태전이 + 후속 이슈 생성 |
| `scripts/gissue/pr-attribution-lib.ps1` / `pr-attribution-sweep.ps1` | 머지 PR 의 타-이슈 파일 혼입 귀속 판정·코멘트 |
| `scripts/gissue/gissue-gate-tally-lib.ps1` | 게이트 되돌림 **전체 합산** 집계(에스컬레이션 판단용) |
| `scripts/gissue/audit-review-prs.mjs` | REVIEW 이슈의 PR 존재 여부 감사(Node) |
| `scripts/gissue/verify-runner.mjs` | 이슈 본문 ` ```verify ` 블록 실행기(exit 0=PASS/1=FAIL/2=블록없음/3=조회실패) |
| `scripts/gissue/lib/pr-lookup.mjs`, `lib/pr-lookup-cli.mjs`, `lib/audit-repos.mjs` | PR 탐지/감사대상 레포 탐색 공용 lib |
| `scripts/gissue/lib/check-comment-timestamp.js`, `lib/resolve-actor.js` | 코멘트 시각 검증, AI 행위자 자격증명 해석 |
| `scripts/gissue/register-issue.js` | 후속 이슈 등록 |

### 13-1-3) ⚠️ 원본과 다른 점 — 쓰기 경로가 API 하나뿐이라 생긴 차이

이 레포에는 DB 직접접속 수단이 없습니다(§4 "혼용 이식은 금지"). 그래서 원본이
`giipdb/mgmt/addIssueComment.ps1` / `updateIssueStatus.ps1` 로 하던 쓰기를 전부 API 로 바꿨습니다:

- 코멘트 등록 → `scripts/gissue/lib/post-comment.js`(등록 → 즉시 재조회 → mojibake 검증 → 1회 재시도).
  본문은 반드시 UTF-8 파일로 넘깁니다(giip #1030).
- 상태 전이 → `PUT <ApiBaseUrl>/giipIssues` (status-only. 제목/본문은 SP 가 ISNULL 로 보존).
- 따라서 `-MgmtDir` 파라미터는 `review-done-audit.ps1` / `pr-attribution-sweep.ps1` 에 **없습니다**.

**그 결과 되돌림/감사 코멘트 판정이 author 기반에서 마커 기반으로 바뀌었습니다.** API 경로에서는
author 를 클라이언트가 지정할 수 없고 서버(`pApiGiipIssueComment*byAK`)가 인증 주체의
`tCorpUser.uname` 으로 강제합니다. `author -eq 'gissue-review-audit'` 같은 AND 조건을 그대로 두면
이 레포에서는 **자기 과거 코멘트를 한 건도 못 찾아** 멱등성·loop guard·3회 캡·전체 합산
에스컬레이션이 통째로 무력화되고 같은 이슈에 코멘트가 무한히 쌓입니다. 그래서 다음 판정은 전부
마커 문자열만 봅니다(`pr-gate-sweep.ps1` 은 원래부터 그랬습니다):

- `gissue-audit-lib.ps1`: `Test-AlreadyRevertedByMarker`, `Get-GateRevertAttemptCount`,
  `Get-GateRevertHistorySummary`
- `gissue-gate-tally-lib.ps1`: `Get-GateRevertTally`
- `review-done-audit.ps1`: `Test-IsAuditComment`(author 일치 **또는** `[REVIEW-AUDIT:` 마커 포함)

마커는 게이트마다 고유하고, `gissue-gate-tally-lib.ps1` 상단의 "카운팅 오염 방지" 규약이
"이 파일이 만들어 내는 어떤 문자열에도 마커 원문을 넣지 않는다"를 보장하므로 마커 단독으로
충분히 변별됩니다. **이 규약을 깨고 에스컬레이션 본문에 마커 원문을 넣으면 그 코멘트 자신이
다음 회차 카운트를 부풀립니다.**

### 13-1-4) 시크릿 파일 위치 — `GIIP_ACCOUNTS_FILE`

`slack-bot/.secrets/giip-accounts.json` 은 git 비추적이라 **워크트리 체크아웃에는 없습니다**.
원본은 이 PC 절대경로를 폴백으로 박아 뒀지만 이 레포는 그럴 수 없으므로, 환경변수
`GIIP_ACCOUNTS_FILE` 로 그 파일 경로를 지정할 수 있게 했습니다(지정하면 그쪽이 우선).
`lib/resolve-actor.js` 와 `audit-review-prs.mjs` 가 같은 규칙을 씁니다.

```bash
GIIP_ACCOUNTS_FILE=/path/to/giip-accounts.json node scripts/gissue/lib/resolve-actor.js --json
```

AK 자체는 이 레포에서 발급/조회할 수 없습니다(DB 전용). 절차는
`scripts/gissue/AI_ACTOR_ACCOUNTS.md` §0-1 의 절별 가부 표를 보세요.

### 13-1-5) PR 탐지 범위 — `audit-extra-repos.json` (giip #2504)

어느 프로젝트 폴더 아래에도 clone 되지 않은 레포(예: `LowyShin/giipAgentLinux`)의 PR 은 워크디렉터리
스캔으로는 절대 안 잡혀, PR-gate 가 "PR 없음"으로 REVIEW 를 되돌립니다. `audit-extra-repos.json`
의 `slugs` 에 `OWNER/REPO` 를 적으면 로컬 clone 없이 `gh pr list --repo <slug>` 로 직접 조회합니다.

**PowerShell(`Get-ExtraAuditRepoSlugs` in `gissue-audit-lib.ps1`)과 Node(`loadExtraRepoSlugs` in
`lib/audit-repos.mjs`)가 반드시 같은 파일을 읽습니다 — 한쪽만 넓히면 같은 오탐이 계속 납니다**
(giip #2464 의 교훈). 이 단일 출처 구조를 깨지 마세요.

### 13-1-6) 감사 대상 workdir 지정 — `audit-review-prs.mjs --workdir`

원본은 감사 대상 컨테이너 이름을 `giipprj` 로 하드코딩했습니다. 이 레포는 다음 우선순위로 찾습니다:

1. `--workdir <경로>` (명시 지정)
2. `csn-projects.json` 의 `csn[<--csn>].workdir`
3. `<projects>/giipprj` (기존 배포 호환)

```bash
GIIP_ACCOUNTS_FILE=<...> node scripts/gissue/audit-review-prs.mjs --csn <csn> --json
```

### 13-1-7) 회귀 테스트 — 이식/수정 후 반드시 돌린다

```powershell
# 먼저 레포 전체 .ps1 의 구문 + BOM 일괄 검사
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\gissue\check-ps1-parse.ps1 -All

# PowerShell 테스트 9종
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\gissue\tests\test-repo-integrity-gate.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\gissue\tests\test-worktree-idle-guard.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\gissue\tests\test-stale-code-guard.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\gissue\tests\test-scope-gate-pr-identification.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\gissue\tests\test-pr-attribution-noop.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\gissue\tests\test-humanconfirm-signal.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\gissue\tests\test-task-cadence-guard.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\gissue\tests\test-verify-runner-korean-encoding.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\gissue\tests\test-verify-gate-exit-contract.ps1
```

```bash
# Node 테스트
node scripts/gissue/tests/test-pr-lookup.mjs
```

**전부 인자 없이 실행해 exit 0 이어야 합니다.** 각 테스트는 마지막 줄에 `결과: PASS=N FAIL=0`
형태의 집계를 냅니다. 호스트 환경에 따라 일부 케이스는 `SKIP` 으로 표시될 수 있습니다
(예: `giipprj` 컨테이너 배치가 없는 PC) — SKIP 은 실패가 아니며 exit 0 을 유지합니다.

**`test-verify-gate-exit-contract.ps1` 은 대상 CSN 을 스스로 정합니다**(giip #2645). 라이브 케이스
A-3b 는 `-LiveCsn` 기본값(`0`)일 때 `csn-projects.json` 의 **첫 번째 enabled CSN** 을 읽습니다.
설정 파일이 아직 없는 clone 직후에는 그 케이스를 건너뛰되 **사유를 반드시 출력**합니다.

| 상태 | 결과 (실측, 2026-09-17) |
|---|---|
| 설정 없는 clone 직후 | `SKIP A-3 … csn-projects.json 이 없습니다` → `PASS=22 FAIL=0`, exit 0 |
| `csn-projects.json` 채운 뒤 | 첫 enabled CSN 자동 선택 → `PASS=24 FAIL=0`, exit 0 |
| 특정 CSN 을 강제 | `-LiveCsn <CSN>` |
| 라이브 조회 자체를 생략 | `-SkipLive` → `PASS=22 FAIL=0` |

> 이전 판(PR #86 시점)은 기본값이 **33**(원본 PC 의 CSN)이라 다른 배포에서는 clone 직후부터
> `PASS=23 FAIL=1` 로 반드시 실패했습니다. 이식된 레포의 테스트가 clone 직후 실패하면 사람이
> "원래 실패하는 테스트"로 학습해 **진짜 실패를 놓치므로**, 기본값 자체를 고쳤습니다.
> A-3b 의 판정도 하위 도구의 메시지 문자열(`조회 실패`) 매칭에서 **종료코드 판정**으로 바꿨습니다
> (`verify-runner.mjs` 의 계약: 0=PASS / 1=FAIL / 2=verify 블록 없음 / 3=판정 불가).

## 14) 연결 문서

- **Docker 배포(auto clone + csn/sk/login_id 자동 등록 + Linux/pwsh 이식)**: `./docker-deployment.md`
- **보조 시간별 스케줄러 5종 + 태스크 등록 게이트**: `./aux-hourly-schedulers.md` (§15 참고)
- 이슈 처리 세션 안전 규칙 색인: `../../.agent/rules/41_issue_session_safety_index.md`
- 진행 코멘트/상태전이 코멘트 프로토콜: `../../.agent/rules/PROTOCOL_PROGRESS_COMMENT.md`
- KPI 표준: `./ai-native-kpi.md`
- 장애/롤백 플레이북: `./incident-rollback-playbook.md`
- 원본 운영 인스턴스 제어법(이 PC 전용): `lowyworkenv/scripts/gissue/SCHEDULER_CONTROL.md`

## 15) 보조 시간별 스케줄러 (giip #2645)

이 문서가 다루는 메인 태스크 외에, **별도 러너 + 별도 Task Scheduler 항목**으로 분리 등록되는 보조
스케줄러가 이 레포에 함께 들어 있습니다. 정본은 `./aux-hourly-schedulers.md` 이며, 목록만 옮깁니다.

| 기본 태스크 이름 | 주기 | 러너 | 등록기 |
|---|---|---|---|
| `GIIP_StalePending_Hourly` | 매시 :07 | `scripts/gissue/run-list-stale-pending.ps1` | `register-stale-pending-task.ps1` |
| `GIIP_StaleReview_Hourly` | 매시 :07 | `scripts/gissue/run-list-stale-review.ps1` | `register-stale-review-task.ps1` |
| `GIIP_AuditReviewPrs_Hourly` | 매시 :07 | `scripts/gissue/run-audit-review-prs.ps1` | `register-audit-review-prs-task.ps1` |
| `GIIP_GateEscalation_Hourly` | 매시 :07 | `scripts/gissue/run-gate-escalation-recheck.ps1` | `register-gate-escalation-task.ps1` |
| `GIIP_SlackbotRestart_Hourly` | 매시 :37 | `scripts/gissue/run-slackbot-restart-check.ps1` | `register-slackbot-restart-task.ps1` |

이 보조 스케줄러들과 함께 다음 두 가지가 이 레포에 들어왔습니다. §13 배포 절차를 마친 뒤 필요에
따라 추가로 등록합니다(메인 태스크만으로도 동작하며, 보조는 선택입니다).

- **태스크 등록 3중 게이트** — `scripts/gissue/task-target-guard.ps1` + `check-ps1-parse.ps1`:
  대상 `.ps1` 의 존재 / 구문·BOM / **임시 worktree 경로가 아님** 을 `Register-ScheduledTask` 직전에
  검사해, 하나라도 실패하면 등록하지 않습니다. `register-hourly-issue-scheduler.ps1` 도 앞으로 같은
  게이트를 쓰도록 맞추면 이 문서 §8/§9 의 "등록 성공 메시지는 근거가 아니다" 가 기계적으로 보장됩니다.
- **태스크 주기 게이트** — `scripts/gissue/task-cadence-guard.ps1` (+ 회귀 테스트
  `scripts/gissue/tests/test-task-cadence-guard.ps1`): 이름이 `_Hourly` 인데 트리거에 `PT1H` 반복이
  없어 **하루 1회만 돌던** 사고를 등록 전에 막습니다.

또한 이 레포의 모든 `.ps1` 은 **UTF-8 with BOM** 으로 저장합니다 — BOM 이 없으면 Windows PowerShell
5.1 이 시스템 ANSI 코드페이지로 읽어, 검사만 통과하고 실행에서 죽습니다(근거·실측은
`./aux-hourly-schedulers.md` §2).

```powershell
# 레포 전체 .ps1 의 구문 + BOM 일괄 검사
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\gissue\check-ps1-parse.ps1 -All
```
