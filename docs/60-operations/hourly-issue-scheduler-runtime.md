# 매시 이슈 처리 스케줄러 표준 스펙 — 실행·감시 상세

> 본문(정본): [hourly-issue-scheduler.md](./hourly-issue-scheduler.md) 에서 분리된 절
> 모음이다 (giip #6329 — 500라인 초과 분리). 절 번호는 본문과 동일하게 유지한다.
> 담는 절: §13-5 2시간 초과 실행 · §16 처리 무소식 알람 · §17 본체 비AI 원칙/tKVS · §18 이슈 번호 지정 실행

## 13-5) 2시간 초과 실행 처리 규칙 — 러너 자기 마감시각 + 원인 보고/분할/종료/DONE (giip 4429)

> 근거 이슈: giip 4428(복구 후 실가동 검증에서 발견된 강제 종료 원인 조사) → giip 4429(규칙 구현).
> 코드: `scripts/gissue/lib/overtime-split.ps1`(순수 로직 + 포트 주입), `scripts/gissue/run-gissue-claude.ps1`(Phase 2 `Invoke-GissueOvertimeCheck`),
> `scripts/gissue/gissue-audit-lib.ps1`(`Test-HasSplitCloseMarker`), `scripts/gissue/review-done-audit.ps1`(감사 면제).
> 테스트: `scripts/gissue/tests/test-overtime-split.ps1`.

### 왜 필요한가 (실측)

매시 :07 인스턴스가 작업 스케줄러 `ExecutionTimeLimit=PT2H` 에 걸려 **외부에서** 강제 종료됐다(이벤트 329, 완료 코드 `0x8007050B`).
외부 종료는 러너가 CSN 락·클레임을 정리할 기회가 없다. 원인은 세 가지가 겹친 구조 결함이었다.

1. **마감 기준 어긋남** — CSN 잡 마감 `RunTimeoutMin`(105분)은 *잡 launch 시각* 기준인데 작업 스케줄러 제한은 *프로세스 시작 시각* 기준이다.
   launch 전 사전 단계(자기 갱신, guard, merge-sweep, reaper)가 인스턴스마다 1~21분 걸려 마감이 제한보다 늦게 걸렸다.
2. **직렬 후처리가 TIMEOUT 판정을 막음** — Phase 2 는 한 CSN 이 끝나면 `Complete-Run`(게이트 스윕·감사·귀속 스윕·worktree 정리)을 직렬로 돌린다.
   그 동안 다른 CSN 잡의 마감 판정이 멈춘다.
3. **저장소 정비 세션에는 시간 캡이 없다** — 이슈별 40분 캡(`[TIMEBOX]`)은 이슈 순회에만 걸려 있다.

### 알려진 결함과 수정 — 포트 출력 혼입 (2026-11-02, giip 4429 후속)

러너의 Log 포트(`Write-Log`)가 `Write-Output` 으로 줄을 흘리면 `Invoke-GissueOvertimeSplit` 의 반환이 `[문자열..., 결과]` 배열이 되어, 러너 로그의 `[OVERTIME] 결과 ... errors=` 가 실제 오류가 없는데도 1 로 찍히고 내용 없는 `[OVERTIME][WARN] ` 줄이 따라왔다(쓰기 0건이라 피해는 없었다). 수정: 포트 호출(`Log`/`StopJob`/`RemoveLocks`)은 `$null = & $Ports.X` 로 출력을 버리고, `Invoke-GissueOvertimeGuard` 는 결과를 `Steps` 를 가진 객체 1개로 고정하며, 러너는 빈 `Errors` 항목에도 원인 안내 문구를 담는다. 순서(원인 코멘트 -> 서브 이슈 -> 종료/락 정리 -> `[SPLIT-CLOSE]` -> DONE)와 fail-closed 조건은 불변. 테스트: `tests/test-overtime-split.ps1` [M2].

### 규칙 (사용자 지시 2026-11-02)

1. 단일 이슈 처리 실행이 한도를 넘기면 먼저 **원인을 그 이슈 코멘트에 보고**한다(무엇을 하다 어디서 시간이 걸렸는지, 모르면 "미상").
2. 남은 작업을 나눌 수 있으면 **서브 이슈로 쪼개 등록**한다(원본 체크리스트 잔여 항목 기준, 최대 5건, 제목 `(원본 giip <isn> 분해 i/N)`,
   `## 완료조건` 에 ` ```verify ` 블록). 같은 원본의 미해결 서브/후속 이슈가 이미 있으면 새로 만들지 않는다(rule 69-4). 기존 서브 이슈 조회가
   실패하면 중복 등록 위험이 있으므로 분할을 보류한다(fail-closed). 나눌 수 없으면 사유 코멘트(`[OVERTIME-NOSPLIT]`) 후 **READY 로 복귀**하고 DONE 하지 않는다.
3. 그 뒤 **과시간 잡을 종료(Stop-Job)** 하고 이 러너가 만든 락만 정리한다: CSN 락 파일은 *락의 PID 가 이 러너 프로세스일 때만*,
   repo 락은 holder 가 `gissue-csn<이 CSN>:<pid>` 이고 pid 가 죽었을 때만(또는 이 잡 소유일 때만). 다른 CSN·다른 인스턴스(생존 PID)의 락과
   worktree 는 건드리지 않는다.
4. 원본에 **서브 이슈 번호를 코멘트로 달고 DONE** 한다. 코멘트 첫 줄은 `[SPLIT-CLOSE]`, 본문에 "분할 이전" 문구와 서브 이슈 번호를 반드시 넣는다.

실행 순서는 **원인 코멘트 → 서브 이슈 등록 → 잡 종료·락 정리 → 원본 `[SPLIT-CLOSE]` 코멘트 → DONE** 이며, 앞 단계가 실패하면 DONE 으로 가지 않는다
(원인 코멘트 실패 시 분할·DONE 보류, 서브 이슈 일부 등록 실패 시 DONE 보류, 종결 코멘트 실패 시 DONE 보류; 종료·락 정리는 항상 수행).

**rule 57("완료 판정은 실행 결과로만")과의 관계**: 이 DONE 은 "구현 완료"가 아니라 "남은 작업이 DB 에 등록된 서브 이슈로 이전됨"이다.
rule 69-5 가 분해 완료 판정을 *DB 에 실제로 등록된 자식 이슈*로 하도록 정했으므로, 원본 DONE 의 근거는 자식 이슈의 존재다.
각 서브 이슈는 자신의 verify 블록으로 rule 57 을 따로 통과해야 한다(원본에 verify 블록이 있으면 승계하고, 없으면 *의도적으로 실패하는* 블록을 넣어
착수 세션이 교체하게 한다 — 검증 없이 DONE 되는 것을 막기 위해서다).

**감사 면제**: `review-done-audit.ps1` 이 DONE + `[SPLIT-CLOSE]`(첫 줄 마커 + "분할 이전" + 서브 이슈 번호 참조, 3조건)를 확인하면 PR 유무·체크리스트
재판정 *전에* 반환한다. 면제하지 않으면 "PR 없음"으로 되돌려져 분할 → DONE → 되돌림 → 재처리 무한루프가 된다(`[NO-PR-REASON]` 선례, giip 2415).

### 모드와 설정값

| 설정 | 기본값 | 근거 |
| --- | --- | --- |
| `-OvertimeSplitMode` / `GISSUE_OVERTIME_SPLIT_MODE` | `Shadow` | `Off` / `Shadow` / `Live`. 알 수 없는 값은 Shadow. **Live 는 사람이 명시적으로 켠다.** |
| `GISSUE_OVERTIME_RUN_DEADLINE_MIN` | 105 | 태스크 제한 120분에서 직렬 후처리·정리용 15분을 뺀 값(giip 1572 의 105 와 같은 근거). **프로세스 시작 시각** 기준 |
| `GISSUE_OVERTIME_ISSUE_MIN` | 105 | 이슈 1건 처리 시작(`[ISSUE-T0]`) 기준 경과 임계 |
| `GISSUE_TASK_LIMIT_MIN` | 120 | 작업 스케줄러 `ExecutionTimeLimit` 을 러너에 알려준다. 위 두 값은 `제한 - 10분` 이하로 강제 보정된다 |

- **Shadow(기본)**: 검사는 수행하되 `[OVERTIME] 결과 mode=Shadow …` / `[OVERTIME-SHADOW] would: …` 로그만 남긴다. 코멘트·서브 이슈 등록·종료·락 정리·상태전이 쓰기는 0건이다.
  기존 `RunTimeoutMin`/TIMEOUT/ZOMBIE 경로는 그대로 동작한다.
- **Live**: 자기 마감시각에 규칙 1~4 를 수행한다. 처리 중인 이슈가 없으면(저장소 정비·대기 단계) 규칙 1·2·4 대상이 없으므로 원인만 기록하고,
  기존 TIMEOUT 경로가 *외부 강제 종료보다 먼저* 같은 회차에서 잡을 종료한다.
- 처리 중 이슈는 잡 출력의 `[ISSUE-T0] isn=<n> status=<S> utc=<iso>` / `[ISSUE-END] isn=<n>` 표식으로 안다(`Receive-Job -Keep`).

### 운영 가이드 (유저가이드)

- 켜기(사람 결정): 작업 스케줄러 실행 환경에 `GISSUE_OVERTIME_SPLIT_MODE=Live` 를 주거나 러너에 `-OvertimeSplitMode Live` 를 준다. 먼저 Shadow 로 며칠 돌려
  `[OVERTIME-SHADOW] would:` 로그가 의도와 맞는지 확인한 뒤 전환한다.
- Live 전환 전 확인할 것: ① `[OVERTIME] 결과` 로그의 `steps`/`final` ② 서브 이슈 verify 블록이 자동 생성 불가한 경우 *의도적 실패 블록*이 들어가므로 착수 세션이 교체해야 함
  ③ 분할이 잔여 체크리스트 항목 단위의 *결정적 분할*이라 항목 간 독립성은 보장하지 않음.
- 이 규칙은 태스크 정의(`ExecutionTimeLimit`, `MultipleInstancesPolicy`)를 바꾸지 않는다.
- **위 세 한계는 giip 4431(4429 후속)에서 모두 해소됐다** — 아래 §13-5-1 참조.

### 13-5-1) 2시간 강제 종료 잔여 원인 해소 (giip 4431, 4429 후속)

> 근거 이슈: giip 4428(원인 판정) → giip 4429(러너 자기 마감시각 규칙) → **giip 4431**(4429 범위 밖으로 남겼던 구조 결함 3건 해소 + 조사 2건).

giip 4429 의 "한계(알려진 미해결)" 3건을 각각 독립 PR 로 해소했다.

| 항목 | 문제 | 해법 | 코드 / 테스트 |
| --- | --- | --- | --- |
| **1. 직렬 `Complete-Run` 이 마감 판정을 막음** | 한 CSN 의 사후 스윕(게이트·감사·귀속·worktree 정리) 5~7개가 동기로 연달아 돌아 1시간+ 걸리면(CSN 47 실측 02:50~04:09) 그동안 다른 잡의 과시간/TIMEOUT/좀비 판정이 통째로 멈췄다 | `Complete-Run` 은 선점 해제·종료 기록만 즉시 하고 `$r.Done=$true` 후 사후 스윕을 큐에 쌓는다. Phase 2 `while` 루프가 매 바퀴 **반복당 시간예산**(기본 90초, 최소 1건 보장) 안에서 큐를 펌프하고 양보 — 한 스윕이 길어도 다음 바퀴의 마감 판정을 막지 않는다. 루프 종료 후 `-Drain` 으로 잔여 전부 처리(Option A) | `lib/run-finalize.ps1`(순수 로직 + 포트), `run-gissue-claude.ps1`(`Invoke-GissuePostProcessStep`/`Invoke-GissuePostProcessPump`). 테스트 `tests/test-complete-run-nonblocking.ps1`(이 이슈 verify 블록). 예산 상수 `GISSUE_POSTPROC_BUDGET_SEC`(기본 90) |
| **2. REPO-MAINT 세션에 시간 캡 없음** | 이슈별 40분 캡은 이슈 순회에만 있었다. TIMEOUT(105분)으로 회수된 잡 출력이 전부 저장소 정비 세션의 엔진 호출 줄에서 끝났다 | 정비 세션의 `Invoke-GissueEngine` 호출을 이슈 순회와 **동일한 내부 `Start-Job` + `Wait-Job -Timeout` 폴링**으로 감싸 캡(기본 20분)을 둔다. 초과 시 `Stop-Job`/`Remove-Job` 후 이슈 순회로 진행(정비 세션은 멱등) | `run-gissue-claude.ps1` REPO-MAINT 블록. 캡 상수 `$RepoMaintDeadlineMin`(기본 20, `GISSUE_REPO_MAINT_CAP_MIN` 로 덮어씀) |
| **3. 외부 종료·마감 정리 시 잡 출력 유실** | `Receive-Job`→`out.log` 가 `Complete-Run` 에서만 호출돼 정상 종료 경로에서만 `gissue_csn<N>.out.log` 가 채워졌다. 외부 PT2H 종료로 러너가 죽으면 그 CSN 내부 단계가 사후에 전혀 남지 않았다 | Phase 2 `while` 루프가 running 잡마다 매 바퀴 `Receive-Job -Keep` 결과를 `out.log` 에 **증분 append**. `-Keep` 은 매번 전체 버퍼를 돌려주므로 `OutLogWritten` 카운터로 아직 안 쓴 꼬리만 골라 이중 기록 방지. `Complete-Run` 은 `-Final`(버퍼 소비)로 최종 flush — 증분 경로로 일원화 | `lib/job-out-tail.ps1`(순수 로직 `Split-GissueJobOutTail`), `run-gissue-claude.ps1`(`Write-GissueJobOutIncremental`). 테스트 `tests/test-job-out-incremental.ps1` |

**조사 항목(코드/조치 근거는 이슈 코멘트에 기록)**:
- **항목 4 — 06:07 인스턴스 120분 무기록 구간**: guard 이후 로그가 없던 구간. 1차 가설은 (a) 엔진(claude) 호출이 로그인/connectors 경고에서 블록, (b) `Start-Job` 출력 유실, (c) 외부 PT2H 종료가 `Receive-Job` 전에 발생. (c)는 **항목 3 구현으로 증분 보존돼 다음 회차부터 사후 재구성이 가능**해졌다 — 무기록 구간의 실제 원인 좁히기는 운영(lowyworkenv) 런타임 로그가 필요하다.
- **항목 5 — reaper 직렬 종료가 사전 단계를 5~9분 늘림**: Phase 0 reaper 가 외부 종료가 남긴 claude 고아 10~15개를 순회 처리. 병목은 `Stop-Process` 자체가 아니라 PID 당 조상/자손/커맨드라인 조회(하위 프로세스 호출)다. 이미지명 기준 일괄 종료는 금지(PID 지정 `Stop-Process -Id` 만, giip #2673). 조치 후보는 reaper 사전 단계 시간 상한 — 상세는 이슈 코멘트 참조.

**운영 이식**: 정본은 giip-fde-agent 이고 lowyworkenv 는 운영 사본이다. 위 3건은 정본에 먼저 머지됐고(PR #373/#375/#378), 운영 이식은 정본 머지 이후 추적 항목이다.

## 16) 처리 무소식 알람 — 처리 로그 신선도 점검 (giip 4411)

**실사고**: 스케줄 태스크가 이슈 처리 본체(`run-gissue-claude.ps1`)가 아닌 다른 스크립트를 가리키도록 일괄 변경돼,
처리 본체가 6일 넘게 한 번도 돌지 않았다. 태스크는 매시 2초 만에 정상 종료(`LastTaskResult=0`)라 아무도 몰랐다.
**"스케줄러가 돈다"는 사실은 Task Scheduler 결과코드로 알 수 없다 — 처리 산출물이 신선한지를 본다.**

| 항목 | 내용 |
|---|---|
| 용도 | CSN 별 처리 로그가 일정 시간 갱신되지 않으면 "무소식"으로 알린다 |
| 스크립트 | `scripts/gissue/check-gissue-liveness.ps1` (판정 함수는 `scripts/gissue/lib/gissue-liveness-lib.ps1`) |
| 읽는 곳 | `scripts/gissue/logs/gissue_csn<N>.log` 의 mtime, `gissue_csn<N>.lock`(`PID\|시작\|마지막로그`), 대상 CSN 은 `csn-projects.json` 의 `enabled` CSN(없으면 로그 파일명) |
| 쓰는 곳 | 기본은 **없음(읽기 전용)**. `-Notify -OpsCsn <csn>` 일 때만 giip 이슈 DB 의 `[OPS] gissue 처리 무소식 감지` 이슈 1건(= 무소식 에피소드)과 `logs/gissue_liveness_state.json`(에피소드 상태) |
| 소비처 | 종료코드(0 정상 / 1 무소식·판정 불가)는 점검 태스크의 `LastTaskResult`, `-Json` 은 대시보드·사람, `[OPS]` 이슈는 **사람이 보는 알림 채널**이지 작업 큐가 아니다(giip #4907 — §4 참고) |
| 등록 | `scripts/gissue/register-gissue-liveness-task.ps1` (매시 :37, 태스크명 `GIIP_GissueLiveness_Hourly`). **사람이 실행한다** — 스케줄러 변경은 자동화하지 않는다 |
| 이슈 도구 | `scripts/gissue/lib/liveness-ops-issue.js` (열린 이슈 찾기 / 진행 보고 코멘트 / 회복 시 DONE 닫기 / 최초 등록 — stdout 은 JSON 1줄, 실패는 `ok=false`+종료코드 1) |
| 테스트 | `scripts/gissue/tests/test-gissue-liveness.ps1` (가짜 로그 디렉터리 + mtime 픽스처 + 스텁 도구 주입 — 중복 방지·진행 보고·회복 종료·조회 실패 미등록·쓰기 CSN 계약·에피소드 외부 종료 가드), `scripts/gissue/tests/test-liveness-ops-issue.mjs` (제목 매칭·조회 후보 CSN·조회 SK 선택 규칙 + `find()` 조회 흐름 — 네트워크 주입으로 후보 CSN·SK 선택·응답 cSn 가드·실패 전파 고정), `scripts/gissue/tests/test-queue-ops-exclude.mjs` (자동 감지 `[OPS]` 이슈의 **작업 큐 제외** — 제목 접두사 판정 + `check-gissue-liveness.ps1` 의 `$title` 과의 커플링 + `--queue`/`--status` 두 경로의 출력 차이) |

**판정**
- CSN 별: `OK`(최근 `-MaxSilentHours` 이내 로그 갱신, 기본 3h = 스케줄 1h + 긴 실행 상한 105분 여유) /
  `RUNNING`(살아있는 락 = 처리 중. 로그가 잠잠해도 오탐하지 않는다) /
  `SILENT`(로그가 기준보다 오래됨; 죽은 PID 락이나 `-StaleLockHours`(기본 2h) 이상 묵은 락이면 사유에 표시) /
  `NO_LOG`(로그 파일 없음).
- 전체: `OK` / `PARTIAL_SILENT`(일부 CSN 만 — 스케줄러는 도는데 해당 CSN 만 건너뜀) /
  `ALL_SILENT`(전부 — **스케줄러 자체 정지 의심**, 태스크 대상 스크립트부터 확인) /
  `NO_TARGETS`(대상 0건 — 판정 불가이며 정상으로 치지 않는다).
- 처리 본체는 CSN 마다 매 실행 `Write-Log` 를 남기므로(이슈 0건이어도) 정상 가동이면 로그는 매시 갱신된다.

**알림 정책(무소식 = 에피소드 1건)**: 기본은 출력만(`-Notify` 없음 = DRYRUN). `-OpsCsn`(또는 환경변수
`GISSUE_LIVENESS_OPS_CSN`)이 없으면 알림 없이 종료코드만 남긴다. 대상 CSN 은 이 배포가 쓰기 권한을 가진 작업 CSN
이어야 한다(남의 CSN 에 쓰지 않는다). 선례는 미매핑 CSN 가드(`GISSUE_CSNGUARD_OPS_CSN`)다.

- **열린 같은 제목 이슈가 있으면 새로 만들지 않는다.** 대신 그 이슈에 **진행 보고 코멘트**를 누적한다 —
  상태 서명(전체/일부 + 무소식 CSN 목록) · 침묵 중인 CSN 목록 · 침묵 시작 시각(추정) · 경과를 본문에 남긴다.
  조용히 생략하면 "침묵이 얼마나 이어졌는지"가 아무 데도 안 남는다.
- **에피소드 정체는 상태 파일의 에피소드 기록이 안다.**(`logs/gissue_liveness_state.json` 의 `episode`).
  에피소드 이슈가 **열려 있지 않으면**(처리 스케줄러가 가져가 종료했거나 사람이 닫은 경우) 침묵이 계속되는
  중에도 **새 이슈를 만들지 않는다** — 만들면 "한 침묵에 여러 이슈" 가 되어 중복 등록 사고(2026-11-11)가
  그대로 재발한다. 에피소드 기록은 **회복 시점에 정리**되므로, 그다음 침묵부터 새 에피소드가 시작된다.
- **회복(처리 흔적 복귀)이면 열린 이슈에 회복 코멘트를 달고 `DONE` 으로 닫는다.** 닫는 경로가 없으면
  `PENDING`·코멘트 0건 이슈가 계속 쌓인다. 이미 이 경로가 종료한 이슈(`closedIsns`)는 다시 건드리지
  않는다(사후감사 게이트가 `DONE` 을 되살려 "코멘트+종료" 가 매시간 반복되지 않게 하기 위한 안전장치).
- **진행 보고 주기**: 상태 서명이 바뀌면(침묵 CSN 이 늘/줄) 즉시, 같으면 `-CooldownHours`(기본 6h) 마다 1회.
- **목록 조회가 실패하면 등록하지 않는다**(`LIST-FAIL`). 중복 등록 방지 우선이 안전 쪽이다.
- **조회 후보가 불완전하면 등록하지 않는다.** 등록 주체(default) 계정에 `csn` 이 없으면 "홈 CSN" 을 알 수 없어
  클램프된 등록 결과까지 볼 수 없다 → 조회 없이 등록하면 중복이 된다. `default.csn` 을 실제 값으로 채워야 한다.

**★ 근본 원인 — 중복 등록이 뚫렸던 이유(2026-11-11, #4870 05:36 / #4874 12:37)**: 등록과 중복 조회가
**서로 다른 주체·CSN 스코프**를 쓰고 있었다.

| 경로 | 쓰던 주체/범위 | 결과 |
|---|---|---|
| 등록(이전 `register-issue.js`) | default 계정 SK(AK 경유), `csn=<OpsCsn>` 요청 | 서버(`pApiGiipIssuePutbyAK`)가 "요청자가 그 CSN 의 멤버가 아니면 **홈 CSN 으로 클램프**" → 이슈는 홈 CSN 에 생성됨 |
| 중복 조회(이전 `list-issues.js --csn <OpsCsn>`) | 그 CSN 의 SK, `i.cSn = <OpsCsn>` 인 줄만 | 홈 CSN 에 생긴 이슈는 **보이지 않음** → "같은 제목 이슈 없음" 으로 오판 |

⇒ 매 시간 "중복 없음" 으로 판단해 등록했다. 6h 쿨다운이 6시간 동안만 이 사실을 가려서 05:36(#4870) →
12:37(#4874) 로 7시간 간격(쿨다운 1회분)으로 드러났다. 제목 매칭 자체는 정상이었다(`[[]` 이스케이프 +
접두 일치). **조회 대상 CSN 과 등록 CSN 이 어긋난 것**이 원인이었다.

**수정**: 등록·조회·코멘트·종료를 **같은 주체(default 계정)** 로 수행하고(`lib/liveness-ops-issue.js`),
조회 후보 CSN 을 **{OpsCsn, default 계정의 csn}** 둘 다 본다. 응답 행의 실제 `cSn` 이 후보 밖이면 버린다
(남의 CSN 이슈에 손대지 않는다). 코멘트·상태변경은 **그 이슈가 실제 위치한 CSN 의 SK** 로만 한다
(`pApiGiipIssueCommentPutbyAK` 의 인가 게이트 = "이슈의 cSn = SK 의 CSN").
**조회에만** SK 폴백이 있다 — 그 CSN 의 계정이 없으면 등록 주체(default) 계정의 SK 로 조회한다. 서버가
"멤버가 아니면 홈 CSN 으로 클램프"하므로 홈 CSN(등록 결과가 놓이는 곳)의 이슈는 반드시 보이고, 멤버라면
클램프가 없어 그 CSN 의 이슈도 보인다. ⇒ 계정 항목이 없는 배포에서도 조회가 죽지 않는다(중복 위험은 없다 —
등록할 수 없는 CSN 이기 때문이다). **쓰기에는 폴백이 없다**(타 CSN 쓰기 금지 가드 유지).
제목·본문은 **파일**로 넘긴다(한글을 커맨드라인 인자로 주면 Windows PowerShell 5.1 콘솔 코드페이지로 깨진다).

**설계 원칙 — 감시자는 감시 대상과 독립 태스크여야 한다.** 이 점검을 `GIIP_Gissue_Claude` 에 끼우거나 `run-gissue-claude.ps1`
안에서 돌리면, 이번 사고처럼 처리 경로가 통째로 죽을 때 감시도 같이 죽어 아무도 알리지 못한다. 그래서 별도 태스크
(`GIIP_GissueLiveness_Hourly`)로 등록하고, 처리 본체(:07)와 30분 어긋난 :37 에 돌린다. 점검기는 처리 본체의 어떤 파일도
import 하지 않는다(로그·락 파일만 읽는다).

**사람이 하는 일(등록)**: 정상 체크아웃(worktree 아님)에서
`powershell -NoProfile -ExecutionPolicy Bypass -File scripts\gissue\register-gissue-liveness-task.ps1 [-OpsCsn <csn>]`.
해제는 `-Unregister`.

### 16-1) 이식 단위 = 스크립트 2종 — 부분 이식이 "조용한 퇴행"이 된다

**무소식 에피소드 관리(§16 "알림 정책")는 스크립트 2개가 한 쌍이다.** 한쪽만 이식하면 조용히 퇴행한다.

| 파일 | 역할 | 이식 시 |
|---|---|---|
| `scripts/gissue/check-gissue-liveness.ps1` | 판정 + 통지 오케스트레이션 | 필수 |
| `scripts/gissue/lib/liveness-ops-issue.js` | 이슈 등록 · 진행 보고 · 회복 종료 (node 도구) | **같이 복사** |

`lib/liveness-ops-issue.js` 없이 스크립트만 이식하면 **방향이 반대인 두 가지 침묵** 중 하나가 된다 — 둘 다 조용해서
사람이 알아채기 어렵다.

| 이식 상태 | 실제 동작 | 위험 |
|---|---|---|
| 구버전 스크립트 + 도구 없음 | 옛 경로(`list-issues.js` 중복 조회 + `register-issue.js` 등록)로 계속 등록 | **침묵 중 쿨다운(기본 6h)마다 새 `[OPS]` 이슈** — 2026-11 실제 6시간 간격 24건 누적 |
| 신버전 스크립트 + 도구 없음 | 도구 호출 실패 → `LIST-FAIL` → **등록 자체를 하지 않음** | 무소식 알림이 침묵(중복은 없지만 알림도 없음) |

구버전 스크립트는 등록을 `list-issues.js`(중복 조회) + `register-issue.js`(등록)로 나누어 호출하는데, 이 둘은
**서로 다른 주체·CSN 스코프**를 써서 "중복 없음" 을 잘못 판단한다(§16 "근본 원인"). 현행 스크립트는 두 경로를
`lib/liveness-ops-issue.js` 하나로 대체했다 — **따라서 "스크립트만 갱신"은 어느 방향으로도 안전하지 않다.**

**드리프트 확인 — 파일 단위로** (폴더 전체 비교는 "차이가 있으나" 까지만 좁혀지고, 어떤 파일이 무소식 등록 경로인지까지
는 가르지 못한다):

```powershell
# 배포 대상 경로에서 실행 (정본이면 scripts\gissue\ 아래)
(Select-String -Path scripts\gissue\check-gissue-liveness.ps1 -Pattern 'Get-LivenessEpisode' | Measure-Object).Count
Test-Path scripts\gissue\lib\liveness-ops-issue.js
```

- `Get-LivenessEpisode` **0회** + 도구 파일 **없음** → 구버전 **미이식**(중복 등록 위험 상태).
- 스크립트만 최신이고 도구만 없음(또는 그 반대)도 **부분 이식** — 어느 한쪽이 빠져도 1건 정책이 성립하지 않는다.

**반영 순서**: 정본 머지 → 배포 대상 소관자가 위 **2개 파일을 함께** 반영 → 위 명령으로 `Get-LivenessEpisode` ≥ 1회
+ 도구 파일 존재를 확인. 반영이 끝나기 전까지 새 `[OPS]` 이슈가 계속 등록될 수 있다 — 그것은 **새로운 사건이 아니라
미이식 상태의 증상**이다.

**스냅샷(2026-11-13)**: 정본은 반영 완료. 운영 사본(원본 저장소, §13-2)은 `Get-LivenessEpisode` 0회 · 도구 파일
없음 = **미이식 상태**. 반영은 운영 사본 소관 영역이므로 정본 세션이 대신 쓰지 않는다(타 CSN 쓰기 금지) — 반영
여부는 위 확인 명령으로 언제든 다시 확인한다.

## 17) 스케줄러 본체 비AI 원칙 + tKVS 시작/알람/리포트 (giip 5345)

### 17-1) 원칙 — 본체는 처음부터 AI 를 쓰지 않는다

- 스케줄러 본체(`run-gissue-claude.ps1`)는 기동 · 자기 갱신 · 큐 조회 · 잠금 · 감시 · 기록까지 전부 결정적 코드로 수행하고, AI(엔진 claude/MiniMax)는 **이슈 처리 단계에서만** 호출한다.
- 이유: 보고 · 알람 경로가 AI 를 거치면, 정작 알려야 할 순간 — limit 도달로 AI 가 죽은 순간 — 에 전송 자체가 불가능해진다. "AI 가 죽었다"는 사실은 AI 가 아닌 본체가 알려야 한다.
- 따라서 시작 로깅 · 알람 · 리포트는 전부 본체의 순수 코드 경로(`scripts/gissue/lib/kvs-report.ps1`)로 GIIP tKVS 에 직접 기록한다. 이 경로의 실패는 본 실행을 멈추지 않는다(fail-open — WARN 로그만 남긴다).

### 17-2) 기록 4종 + 기존 1종

전부 키 공간은 기존 실행 이력과 동일하게 `kType='lssn'`, `kKey=<LSSN>` 이고, 전송은 giipApiSk4 + `KVSPut` 이다(전송 본체의 정본은 `Send-GissueKvsPut` — 기존 `Send-GissueRunHistory` 도 이 경유로 전송한다).

| 시점 | kFactor | 내용 |
| :--- | :--- | :--- |
| 자기 갱신(self-pull) 직후 · 엔진 호출 전 | `scheduler_run_start` | runId, at, hostname, ips, csns, agentCommit, pid |
| CSN 잡 종료(Complete-Run) | `scheduler_run_report` | csn, status, processed/skipped/failed, runId, hostname, ips |
| 비정상 판정 시(Complete-Run) | `scheduler_alarm` | kind(`LIMIT`/`TIMEOUT`/`ZOMBIE`/`OVERTIME`/`RUN_FAIL`), csn, status, detail(500자 절단) |
| CSN 잡 종료(Complete-Run) | `scheduler_token_usage` (giip 5398) | csn, runId, hostname, ips, engines(모델별 calls/freshIn/cacheCreate/cacheRead/out) — 토큰 4분류 원형, 합산은 `lib/token-usage.ps1`, 설계는 [token-usage-metering.md](token-usage-metering.md) §3. `calls` 는 "4분류 중 하나라도 계수된 엔진 호출 수"(4분류 합계 0 인 로컬 생성 레코드 `<synthetic>` 제외 — §3.2), 합산 구간은 선택적 `-UntilUtc` 로 닫힌 구간 `[SinceUtc, UntilUtc)` 지정 |
| 실행 종료 집계(finally) | `scheduler_run_history` (기존, giip #2384) | 건수 + hostname + **ips + CSN별 내역** (5345 에서 확장) |

### 17-3) 머신 식별 — hostname + IP 를 항상 함께

같은 CSN 을 두 머신에서 실행하는 구성이 있으므로 모든 기록에 hostname 과 IP 목록을 함께 남긴다. 시작 기록의 `agentCommit` 으로는 "그 머신이 어느 코드로 돌았는가"까지 대조할 수 있다 — GitHub 에 올린 수정이 실제 머신에 닿았는지는, 시작 기록의 agentCommit 이 최신 main 과 같은지로 확인한다.

### 17-4) limit 알람 판정

- 판정의 정본은 `lib/kvs-report.ps1` 의 `Test-GissueLimitSignature` / `Get-GissueAlarmKind` 한 곳뿐이다(rule 48 — 판정을 복붙하지 않는다).
- Complete-Run 이 잡 출력에서 limit 서명(`429` · `rate limit` · `quota` · `usage limit` · `Token Plan` · `token revoked` · `사용량 한도` 등)을 검출하면, 종료 상태가 DONE 이어도 `kind=LIMIT` 알람을 남긴다. TIMEOUT/ZOMBIE/OVERTIME/그 외 비정상 종료도 각각 알람이 된다.
- 엔진 시도 내부의 폴백 판정(MiniMax → Claude)과는 목적이 다르다: 폴백은 "계속 일할 수 있는가"의 판정이고, 이쪽은 "GIIP 에 알릴 것인가"의 판정이다.

### 17-5) 최신 코드 수신(자기 갱신)과의 관계

- 러너는 시작 시 self-pull 로 에이전트 레포를 최신화하고(giip #2386), NOT-ON-MAIN 상태면 조건 충족 시 main 복귀를 시도한다. 실행 도중의 코드 변경은 code-freshness 가드(giip #2471)가 파괴적 작업을 다음 실행으로 미루는 방식으로 방어한다.
- 즉 GitHub main 에 머지된 수정은 다음 :07 실행부터 각 머신의 정본 체크아웃에 전파되고, 전파 여부는 §17-3 의 agentCommit 대조로 확인한다. 단 §11 의 함정(PR 머지 ≠ 즉시 반영)과 §13-2 의 복사본 배포 격차는 그대로 유효하다 — self-pull 대상은 정본 체크아웃에서 도는 러너뿐이다.

> **[giip #6214] 2026-11-23 정정 — 위 "시작 시 self-pull"은 문서에만 있었다.**
> 정본 러너에는 `main` 체크아웃에서 도는 **실제 pull 이 없었다**(유일한 `git pull` 이 NOT-ON-MAIN 복귀
> 경로 안에 있었고, 그 경로는 HEAD 가 `main` 이면 아무 것도 하지 않는다). 그래서 §17-3 의 agentCommit
> 대조는 "항상 옛 커밋"을 가리켰고, 호스트마다 사람이 pull 하는 구조가 남았다.
> 이제 러너 기동 초입에 자동 반영 단계가 실제로 돈다(§17-7). 위 문장의 "self-pull"은 이제 가시적인
> 동작이므로, 전파 여부는 §17-7 의 실행 기록(코드 버전)으로도 확인한다.

### 17-6) 테스트

- `scripts/gissue/tests/test-kvs-report.ps1` — 판정(limit 서명 · 알람 종류)과 페이로드(kType/kKey/kFactor/kValue, hostname/IP 포함)를 네트워크 없이 검증한다(전송 포트를 가짜로 교체). 게이트 기대 건수에 포함된다.

### 17-7) 자동 반영(자기 갱신) 단계 + 실행 기록 확장 (giip #6214)

**배선 위치** — 러너 기동 초입(어떤 CSN 잡도 시작하기 전). 순서 계약이 있다.

| 순서 | 하는 일 | 왜 이 위치인가 |
| :--- | :--- | :--- |
| 1 | `lib/code-sync.ps1`·`lib/run-summary.ps1` 적재 | 이후 단계가 쓰는 순수 로직 |
| 2 | **자동 반영** — 대상 결정 → 상태 조회 → `fetch` → `merge --ff-only` → 실행 위치 `scripts/gissue` 동기화 | `worktree-safety.ps1` 닷소싱과 code-freshness 스냅샷보다 **앞**이어야 한다. 뒤에 오면 새 코드가 메모리에 안 올라가고, 가드가 즉시 "낡음"으로 latch 된다 |
| 3 | `worktree-safety.ps1` 닷소싱 → `code-freshness.ps1` 초기화(기준 해시 스냅샷) | 스냅샷이 새 코드 기준이어야 가드가 오탐하지 않는다 |
| 4 | NOT-ON-MAIN 체크(기존) → tKVS 시작 기록 | 시작 기록의 `agentCommit` 은 **자동 반영 후** HEAD 다. 자동 반영 결과 자체도 `codeSync` 키로 함께 실린다 |

**자동 반영이 멈추는 경우(전부 fail-open — 실행은 계속되고 사실만 기록된다)**

| 상태 | 이유 | 다음 |
| :--- | :--- | :--- |
| `already-current` | 이미 최신 | — |
| `updated` | 원격 반영 완료 | 이번 실행은 새 코드로 돈다(러너 **본체**는 다음 회차부터 — 아래 "이번 회차 vs 다음 회차") |
| `skipped-dirty` | **추적(tracked) 파일**의 로컬 변경 있음 | **pull 하지 않는다**(사람의 작업 보존). 사람이 정리해야 한다 |
| `skipped-not-main` | HEAD 가 `main` 이 아님 | NOT-ON-MAIN 경로가 복귀를 시도한다(그 회차는 옛 코드로 돈다) |
| `failed` | fetch/merge 실패 | 옛 코드로 계속. 사유가 실행 기록에 남는다 |
| `skipped-no-target` | 정본 체크아웃을 찾지 못함 | `GIIP_FDE_REPO_ROOT` 를 지정하거나 정본 체크아웃에서 실행 |

- untracked 파일(로그 디렉터리·운영자가 채운 `csn-projects.json` 등)만 있는 상태는 **정상**이다 — pull 을 막지 않는다
  (`git status --porcelain --untracked-files=no` 로 **추적 파일만** "변경"으로 센다).
- **이번 회차 vs 다음 회차** — 러너 본체는 프로세스 기동 시점에 이미 파싱되어 메모리에 올라가므로, 그 실행
  중에 pull 로 내려받은 본체 코드는 **다음 회차부터** 반영된다. 기동 시점에 닷소싱되는 부분(정리 엔진·
  작업 라이브러리·잡이 읽는 `lib/*`)은 이번 회차에 새 코드로 돈다. 그래서 실행 기록의 코드 버전은
  "그 회차가 실제로 도는 코드"의 기준이 된다(머지 직후 회차의 버전이 옛 것이어도 오류가 아니다).

**설정값**

| 이름 | 기본 | 뜻 |
| :--- | :--- | :--- |
| `GIIP_FDE_REPO_ROOT` | (없음) | 자동 반영 대상 = 정본 체크아웃 경로. 러너가 체크아웃 밖의 복사본에서 돌 때 지정한다 |
| `GISSUE_GAIR_CSNS` / `GISSUE_GAIR` | 기존 값 | 엔진 경로(gair/종전) — §17-7 의 "엔진 경로 요약"이 이 결과다 |

**실행 기록 확장** — `SchedulerAgentRunEnd` 의 `@summary` 에 다음이 함께 들어간다(500자 절단).
정본과 상세는 [`./gissue-scheduler-run-history.md`](./gissue-scheduler-run-history.md) §"실행 기록 확장".

| 순서 | 항목 | 예시 |
| :--- | :--- | :--- |
| 1 | 종료 상태 | `DONE` |
| 2 | **기록 호출 실패** | `기록호출실패 2건(예: heartbeat: …)` |
| 3 | 실행 코드 버전 | `코드 abc1234(main)` — 실행 체크아웃의 HEAD 7자 + 브랜치 |
| 4 | 엔진 경로 요약 | `엔진경로 gair=3(실패=1) 종전=5 claude강제=2 \| 프로브 정비=성공,일반=성공 \| 폴백사유 gair호출실패=1` |
| 5 | 자동 반영 결과 | `자동반영 updated(aaaaaaa→bbbbbbb)` |

- **"기록 호출 실패"가 2번째인 이유** — 전체를 한꺼번에 자르면 뒤 항목이 통째로 사라진다. 그 신호가 잘리면
  "기록 실패"가 조용히 사라진다. 2번째에 두면 어떤 길이 제한에서도 살아남는다(항목별 길이 상한 있음).
- 엔진 경로 요약은 엔진이 이미 남기는 `[GAIR]`·`[ENGINE]` 줄을 **집계**해서 만든다(새 계측 지점을 만들지 않는다).
- 없는 값은 추정하지 않는다 — `알수없음` / `엔진경로 기록없음` / `없음` 으로 명시한다.
- 기록 호출 실패가 있으면 잡 로그의 `[SchedulerState][FAIL]` 줄과 실행 기록의 `기록호출실패 N건` 에 **둘 다** 남는다.
- **SK 자체가 없어 기록을 시도할 수 없었던 경우**도 실패로 드러난다(잡 출력의
  `[WARN][SchedulerState-<동작>] 실패: SK 없음 …`, 종료 시 `[SchedulerState-runEnd] 실패: SK 없음 …`).

**회귀 테스트**

- `scripts/gissue/tests/test-code-sync.ps1` — 자동 반영 판정·동기화·스크립트 디렉터리 복사(로컬 전용 파일 보존)·
  러너 소스의 순서 계약(자동 반영이 정리 엔진 닷소싱·가드 스냅샷보다 앞, `-FunctionsOnly` 에서 미실행).
  네트워크 없이 **로컬 bare 저장소를 "원격"으로** 쓴다.
- `scripts/gissue/tests/test-run-summary.ps1` — 마커 판정·집계·요약 문구·기록 실패 추출·러너 배선.

## 18) 이슈 번호 지정 실행 `-OnlyIsn` (giip 5544)

> 요약은 §3 실행 커맨드 템플릿의 `-OnlyIsn` 항목, **AI 인스턴스용 사용 가이드는 [`only-isn-ai-guide.md`](only-isn-ai-guide.md)** 를 본다. 이 절이 사양의 정본이다.

### 18-1) 목적

정기 실행(:07, 우선순위 큐)이 닿기까지 최대 1시간 걸리는 구조에서, 외부 감지기(예: 5분 간격 폴링)나 운영자가 "지금 이 이슈"를 지정해 즉시 처리시키기 위한 표준 진입점이다. 호스트 로컬 래퍼가 아니라 러너 본체 파라미터로 두어, 모든 배포 인스턴스가 self-pull 로 같은 동작을 받는다.

### 18-2) 파라미터

| 파라미터 | 형 | 기본값 | 의미 |
|---|---|---|---|
| `-OnlyIsn` | int | 0 (미지정) | 지정 실행할 이슈 번호(isn). 0이면 기존 정기 실행과 완전히 동일하게 동작한다 |
| `-OnlyCsn` | string | '' | 함께 쓰면 그 CSN만 대상으로 한다. 없이 쓰면 매핑된 전 CSN 중 지정 이슈가 보이는 CSN의 잡만 기동된다 |
| `-DryRun` | switch | — | 조합 가능. 잡을 띄우지 않고 CSN별 판정(`[DryRun][ONLYISN] … 판정=RUN/SKIP 사유=<코드>`)만 로그에 남긴다 |

### 18-3) 처리 흐름

1. **Phase 1 (기동 판정)** — CSN마다 지정 이슈를 단건 조회(`list-issues.js --status` 직접 조회)한다. 이슈가 보이지 않는 CSN은 잡을 띄우지 않고 `[ONLYISN] isn=<n> 이 CSN에서 찾지 못함 — 잡 미기동`을 로그에 남긴다. 응답 cSn이 그 CSN과 다르면 `[ONLYISN] … 소속 불일치` 로그 후 미기동. 스케줄러 비활성(`enabled: false`) CSN도 명시 지정 실행에서는 `-OnlyCsn`과 같은 면제를 받는다.
2. **잡 (큐 교체)** — 잡은 평소처럼 일반 큐를 조회한 뒤, 판정 정본 `lib/only-isn.ps1` 의 `Get-GissueOnlyIsnVerdict` 로 지정 1건의 RUN/SKIP을 판정한다. RUN이면 큐를 그 1건으로 교체하고, 이후 처리(프롬프트 선택·엔진 실행·상태별 시간 추적)는 일반 경로와 동일하다.
3. **종료** — 실행 이력(§17 표의 `scheduler_run_history`)에 `trigger`/`onlyIsn` 필드가 함께 기록된다(18-6).

### 18-4) 판정표 — 우회하는 것과 우회하지 않는 것

**우회**: 큐 우선순위 정렬. 큐에 없는 이슈를 행으로 만들어 실행하는 지점이 유일한 우회다. (READY 경과 조건은 2026-11-25 폐지 — giip #6328.)

**유지(안전 게이트)** — 아래 중 하나라도 걸리면 SKIP이며, 사유 코드가 판정의 정본이다:

| 사유 코드 | 조건 | 비고 |
|---|---|---|
| `CSN_MISMATCH` | 단건 조회의 응답 cSn ≠ 대상 CSN | giip #1053 가드. 실행하지 않는다 |
| `AUTO_OPS` | 제목이 `[OPS] gissue 처리 무소식 감지`와 정확히 같거나 그로 시작 | 자동 감지 기록은 작업이 아니다(giip #4907). 판정 문자열은 `list-issues.js`의 `AUTO_OPS_TITLE_PREFIX`와 커플링 — 한쪽만 바꾸면 테스트가 실패한다 |
| `NEEDS_DECISION` | 상태가 NEEDS_DECISION | 사람의 결정이 먼저다. 큐 포함 여부와 무관하게 게이트가 우선한다 |
| `IN_PROGRESS_ACTIVE` | IN_PROGRESS인데 일반 큐에 없음(=60분 미만 신선) | 다른 실행이 처리 중 — 중복 실행 금지. 60분 이상 정체 건은 큐 라벨 `STALE_IN_PROGRESS`로 일반 회수 경로를 탄다 |
| `REVIEW_NO_NEW_SIGNAL` | REVIEW/TESTED인데 큐에서 빠짐 | [ACTIONFLOW-TEST] dedup 또는 최대 경과 초과로 큐가 제외한 상태 |
| `STATUS_NOT_PROCESSABLE` | DONE 등 처리 대상 상태가 아님 | 대상 상태는 PENDING/READY/IN_PROGRESS/REVIEW/TESTED뿐 |
| `NOT_FOUND` | 대상 CSN 스코프에서 조회되지 않음 | 타 CSN 소속이거나 없는 번호 |
| `LOOKUP_ERROR` | 단건 조회 자체가 실패 | 잡 단계에서만 발생(Phase 1 실패는 잡 미기동으로 끝남) |

REVIEW/TESTED의 **재검증 쿨다운(기본 4시간)과 회차당 상한은 판정 대상이 아니다** — 큐에 들어온 행을 잡 루프의 기존 게이트가 그대로 판정한다. 즉 지정 실행으로도 쿨다운을 우회할 수 없다.

### 18-5) 로그와 운영 코멘트

- RUN: 잡 출력에 `[ONLYISN] isn=<n> 지정 실행 — 큐 우선순위·READY 경과 조건 우회(안전 게이트는 기존 경로 그대로 적용)`.
- SKIP: 잡 출력에 `[ONLYISN-SKIP] isn=<n> reason=<코드> status=<상태>`. 이슈가 대상 CSN에서 확인된 경우, 그 이슈에 운영 코멘트 `[ONLYISN-SKIP] isn=<n> 번호 지정 실행을 건너뜁니다 — <사유 설명>`도 남긴다(조용한 종료 금지). `NOT_FOUND`/`LOOKUP_ERROR`는 코멘트를 남길 대상을 확정할 수 없어 로그만 남긴다.
- 코멘트 문구의 정본은 `lib/only-isn.ps1` 의 `Get-GissueOnlyIsnSkipNote` 다.

### 18-6) 실행 이력 기록

종료 시 tKVS `scheduler_run_history` 값에 아래 필드가 추가된다(§17-2 표의 기존 필드와 함께):

| 필드 | 정기 실행 | 지정 실행 |
|---|---|---|
| `trigger` | `'schedule'` | `'onlyisn'` |
| `onlyIsn` | `0` | 지정한 isn |

### 18-7) 호출 예시

```powershell
# 특정 CSN의 이슈 1건을 즉시 처리
powershell.exe -File "<REPO_ROOT>/scripts/gissue/run-gissue-claude.ps1" -OnlyCsn 47 -OnlyIsn 5544

# CSN을 모를 때: 매핑된 CSN 중 이슈가 보이는 곳만 기동
powershell.exe -File "<REPO_ROOT>/scripts/gissue/run-gissue-claude.ps1" -OnlyIsn 5544

# 판정만 먼저 확인(잡 미기동)
powershell.exe -File "<REPO_ROOT>/scripts/gissue/run-gissue-claude.ps1" -DryRun -OnlyIsn 5544
```

동시 실행 주의: 지정 실행도 CSN별 lock을 쓰는 일반 실행과 같은 자원 경합 규칙을 따른다. 정기 실행이 같은 CSN을 처리 중이면 lock 대기로 밀릴 수 있고, 그 경우에도 지정 이슈가 신선한 IN_PROGRESS로 보이면 `IN_PROGRESS_ACTIVE`로 중복 실행되지 않는다.

### 18-8) 테스트

- `scripts/gissue/tests/test-only-isn.ps1` — 판정(RUN 5건·CSN 차단·게이트 유지 9건), 스킵 코멘트 문구, [OPS] 접두사와 `list-issues.js`의 커플링을 네트워크 없이 검증한다. 게이트 기대 건수에 포함된다.

## 머지 집합 디스크 캐시 (gh-cache) — gh 중복 호출 제거

머지판정(`worktree-safety.ps1` 의 `Get-GissueMergedBranchSet`)은 레포마다 `gh pr list --state merged --limit 1000` 를 부른다. 이 조회는 GitHub GraphQL 예산(계정 전체 공유)을 먹는데, 프로세스 내 캐시만으로는 매시 러너·CSN별 잡·스윕이 같은 레포를 각자 다시 조회한다. 예산이 소진되면 조회가 전부 실패해 머지판정이 fail-closed 로 닫히고 MANUAL-REVIEW 가 폭증한다.

- **구현**: `scripts/gissue/lib/gh-cache.ps1` — 성공한 조회 결과만 디스크에 남겨 프로세스 너머로 공유한다. 실패는 절대 캐시하지 않으므로 fail-closed 동작은 그대로다.
- **위치**: 레포당 1개 `<owner>__<repo>.merged.json` (`{ ownerRepo, fetchedAt, branches }`). 기본 디렉터리는 `<gissue 폴더>/logs/gh-cache`, 환경변수 `GISSUE_GH_CACHE_DIR` 로 재정의 가능.
- **TTL**: 기본 50분, 환경변수 `GISSUE_GH_CACHE_TTL_MIN`(양의 정수, 분)으로 재정의. 파일 없음·만료·JSON 손상은 예외 없이 미스로 처리하고 gh 재조회로 떨어진다.
- **쓰기**: 임시 파일에 쓴 뒤 원자적으로 교체한다. 쓰기 실패는 조용히 무시한다(캐시는 최적화일 뿐이다).
- **무효화**: `merge-standing-prs.ps1` 이 PR 머지 성공 직후 그 레포의 캐시를 지운다. 러너의 busy 해제 판정(`run-gissue-claude.ps1`)도 같은 집합을 먼저 보며, 집합에 있을 때만 긍정 판정하고 없거나 실패면 기존 per-branch `gh pr list --head` 호출 그대로다.
- **로그**: 캐시 히트 시 `[GH-CACHE] HIT <owner/repo> (<n> branches, age <m>m)` 를 남긴다.
- **테스트**: `scripts/gissue/tests/test-gh-cache.ps1` — 라운드트립·TTL·손상 JSON·Clear·캐시 히트 시 gh 미호출을 검증한다.
