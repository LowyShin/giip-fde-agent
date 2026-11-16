# CSN 70424 저장소·PR 레벨 정비 149차 (2026-11-16 16:07 KST) — [0]/[E]/[F] 0건 · [H] 2h 1/24h 10 전건 TRUE · [H] 재검증 중 발견한 합산 모듈 시간창 Kind 정규화 결함 수정

> 세션 성격: **저장소/PR 레벨 정비** (CSN 70424 저장소 전체 스코프, 단일 이슈 처리가 아니다).
> 규칙상 항상 도는 [0] 병합충돌 · [E] CI/검증 실패 · [F] 오판 stash · [H] 최근 코멘트 논리 재검증 4축을 돈다.
> **이번 회차 산출물: 코드 수정 1건(합산 모듈 시간창 정규화 + 회귀 테스트) · 문서 4건 · 이슈 쓰기 0건 · 상태 전이 0건 · stash drop 0건 · 정정 0건.**

## 세션 성격 — 16:07 슬롯

- 러너 로그(`scripts/gissue/logs/gissue_csn70424.log`) 기준 직전 회차(15:07 슬롯)는 `16:10:33 DONE` 으로 끝났고,
  이 슬롯은 `[2026-11-16 16:12:06] START (cwd=…\giip-fde-agent)` 로 **직전 회차 종료 1분 뒤** 시작했다.
  **이 슬롯의 이전 시도는 없었다**(QUEUED/START/DONE 로그에 16:07 슬롯의 선행 실행 흔적 0건) → 죽은 회차 계승 대상 없다.
- 작업 시작 시점 `origin/main` HEAD = **`67cf653`**(148차 PR #471 머지 커밋)를 base 로 삼았다.
- **회차 번호는 "슬롯" 이 아니라 "기록이 생긴 횟수" 기준**(144·147차 교훈) — 직전 신규 기록이
  `.agent/work_history/20261116_1507_csn70424_repo-maintenance.md`(148차)이므로 신규 기록 번호는 **149차**다.
- 실행 주체: 이 세션은 스케줄러가 직접 띄운 **헤드리스 폴백 워커**이므로 work_history + 코드 수정 + PR 생성을
  **직접 수행**한다(서브에이전트 위임은 MODEL_USAGE_SPEC 상 예외이며 단건 기록 PR 에 불필요하다 — 148차와 동일 판단).
- 사전 락 불요 — `scripts/gissue/csn-projects.json` 실측 기준 CSN 70424 의 프로젝트가 이 저장소
  (giip-fde-agent)이고, lowyworkenv 는 이 세션 CSN 밖의 다른 저장소다. 144~148차와 동일 판단.
- 작업 워크트리 `D:\temp\worktrees\giip-fde-agent\maint-149-1607`
  (브랜치 `chore/csn70424-maint149-20261116-1607`, base = `origin/main` `67cf653`) — 공유 체크아웃은 읽기 전용.
- 참고 — 직전 회차(148차)가 남긴 잔재 워크트리는 **1건도 없다**(148차가 자기 `maint-148-1507` 을 회수 완료).

## [0] PR 병합충돌 — 대상 0건

- `gh pr list --state open --json number,headRefName,title --repo LowyShin/giip-fde-agent`
  → **열린 PR 0건**(빈 배열).
- 열린 PR 이 없으므로 `mergeable=CONFLICTING` 대상도 **0건** → 조용히 건너뜀.
- 루트에 vendored 제품 레포 없음(`git worktree list` 기준 저장소 루트 하나뿐 — 서브모듈은
  `.gemini/extensions/bkit` 1건이며 giip 제품 레포가 아니다). 중첩 레포별 추가 조회 대상도 없다.

## [E] CI/검증 실패 — 대상 0건

- [E] 대상(열린 PR) 이 **0건**이므로 `gh pr checks` 를 돌릴 PR 이 없다.
- 대신 **main push run** 을 조회해 green 을 확인했다 — 최근 6건 run **전건 `completed` / `success`**
  (최신 run 은 148차 머지 커밋 `67cf653` 대상 run 포함).
- 로컬 게이트(`scripts/gissue/run-repo-gates.ps1`)는 **공유 체크아웃(base)** 과 **이번 워크트리** 양쪽에서
  **병렬로** 실행해 "워크트리 green ≠ main green" 을 배제했다(145차가 발견한 GUID 임시 파일명 충돌 결함 재발 여부).
  - 공유 체크아웃(base) — `ps1 44건 / mjs 8건 / 링크스캔 1 / 실패 0건`, **exit 0**.
  - 워크트리 — `ps1 44건 / mjs 8건 / 링크스캔 1 / 실패 0건`, **exit 0**.
  - **양쪽 exit 0** — 145·146·148차와 같은 "양쪽 PASS" 성질이 유지된다.
  - 참고 — 게이트 기대 건수 `ps1 44` 는 이번 회차 이전부터 44다(147차 PR #468 · 148차 PR #471 이 이미 반영).
    이번 회차는 **기대 건수를 건드리지 않았다**(테스트 파일 추가가 아니라 **기존 파일 확장**).

## [F] Orphan auto-unblock stash — 대상 0건

- `git stash list` → **빈 출력**(stash 0건) — 공유 체크아웃 실측.
- 서브모듈 `.gemini/extensions/bkit` 도 `git stash list` **0건**.
- 자동 해제(`auto-unblock `) 메시지 항목 0건 → 조용히 건너뜀.

## [H] 최근 코멘트 논리 재검증 — 2h 1건 / 24h 10건(검증 가능 주장 전건 TRUE) · 정정 0 · 전이 0 · 이슈 쓰기 0

- 조회: `giipprj/giipdb/mgmt/listRecentCommentIssues.ps1 -Csn 70424 -HoursBack 2|24 -Json`(상태 무관).
  이 PC 엔 `pwsh` 가 없어 `powershell`(5.1)로 실행했고, 콘솔 코드페이지로 깨지는 한글 JSON 은
  **저장소 밖 임시 폴더**(`%TEMP%/csn70424-149/`)로 받아 파싱했다(공유 체크아웃 루트에 임시 파일을 쓰면 안 된다 — 133차 교훈).
  **2시간 창 1건** · **24시간 창 10건**.
- 자기 세션이 남긴 코멘트 0건 → 자기코멘트 제외 대상 0건.
- 10건의 **검증 가능한 사실 주장**을 유형별로 나누고, 각 주장을 **직접 조회해** 재확인했다
  (직전 회차의 기록을 인용하지 않고 — 코멘트를 믿지 않고 직접 대조했다).

### 유형 A — 워치독 운영 스킵 통지 6건 : "REVIEW/TESTED 재검증 쿨다운(마지막 재검증 후 4시간 미만, 새 사람 신호 없음)"

- isn 5053 · 4699 · 4556 · 4130 · 4300 · 4211 (author `gissue-scheduler-watchdog`, 마지막 코멘트 2026-11-15T18:33~18:35Z).
- 검증 가능한 주장 3개:
  1. "이 이슈는 처리 자격이 되지만(REVIEW/TESTED)" → 조회 목록 status 와 **6건 전건 REVIEW 로 일치** → TRUE.
  2. "새 사람 신호 없음" → 6건 전체 코멘트를 받아 **최신 regdate 코멘트 이후 사람(author ≠ 워치독) 코멘트 0건**
     을 직접 집계했다 → 6건 **전건 0건** → TRUE.
  3. "마지막 재검증 후 4시간 미만" → 러너 로그에서 이 6건이 매 시간대 `pr-gate-sweep` / `review-done-audit` 로
     **계속 재검증**되는 것을 확인했다(예: 2026-11-16 03:04/03:10 KST pr-gate-sweep 가 isn 5053·4699 를 검사,
     review-done-audit 가 03:22 KST 에 isn 4530·2648·1968 을 감사). 즉 통지 직전 시간대 재검증이 실제로 있었고
     직전 워치독 노트 간격(4.23~4.24h)이 "쿨다운(4h) 내 1회만 남깁니다" 정책과 일치 → TRUE.
- 워치독 노트는 이슈를 잠그는 유형이 아니라 상태 유지를 통지하는 것이므로 상태 전이 대상이 아니다.

### 유형 B — [G] Actionflow 재검증 게이트 SKIP 3건 : "`## Test Procedure` 정확 헤딩 섹션 부재"

- isn 2648 · 1968 · 4530 (author `Lowy Shin`, 마지막 코멘트 2026-11-15T17:55~18:01Z).
- 검증 가능한 주장 = "`## Test Procedure` 라는 **정확한 헤딩**의 섹션이 없다".
- `get-issue.sh` 로 이슈 본문 + 전체 코멘트를 받아 `^[ \t]*##[ \t]+Test[ \t]+Procedure[ \t]*$` 헤딩 라인을
  **직접 파싱**했다(이슈 본문과 코멘트를 구분해 각각 집계).

  | isn | 코멘트 수 | 본문 정확 헤딩 | 코멘트 정확 헤딩 | 일반 문자열 출현 | 백틱 인라인 출현 |
  |---|---|---|---|---|---|
  | 2648 | 32 | **0** | **0** | 7 | 6 |
  | 1968 | 30 | **0** | **0** | 9 | 9 |
  | 4530 | 31 | **0** | **0** | 6 | 6 |

- 일반 문자열(`Test Procedure`) 출현 라인 **전량이 백틱 인라인 인용**(`## Test Procedure` 백틱 인용)이며
  실제 헤딩 라인은 0건 → **주장 참**. 이 유형은 "파일 없음" 식 거짓 블로커가 아니라
  사람 판단 대기 상태라 REVIEW 에 정상 잔존 중이며, [G] 게이트 B 절대규칙에 따라 TESTED 전이 대상이 아니다.

### 유형 C — refinement 완료 통지 1건 (isn 5398) : 토큰 사용량 기록 1단계 구현 완료 보고

- isn 5398 (READY, author `Lowy Shin`, 마지막 코멘트 2026-11-15T22:05:11Z).
- 통지가 주장하는 사실들을 **직접 조회해** 대조했다(PR 메타·코드 위치·게이트 기대 건수·테스트 실행 결과·CSN 귀속).

  | 주장 | 대조 방법 | 결과 |
  |---|---|---|
  | "PR 로 1단계 구현" | `gh pr view 470 --repo LowyShin/giip-fde-agent` | **MERGED** · 2026-11-16T06:36:51Z · mergeCommit `850c8b01` · **9 파일 +214/-3** |
  | "`scheduler_token_usage` 로 전송" | `scripts/gissue/lib/kvs-report.ps1` | `Send-GissueTokenUsageRecord` **:227** · kFactor `scheduler_token_usage` **:245** |
  | "러너 종료 지점에 배선" | `scripts/gissue/run-gissue-claude.ps1` | 합산 호출 **:3883** · 전송 호출 **:3885** (Complete-Run) |
  | "게이트 기대 건수 43→44" | `run-repo-gates.ps1` 기대값 vs 실제 ps1 테스트 파일 수 | 기대 44 · 실제 44 · **일치** |
  | "회귀 테스트 2종 통과" | `test-token-usage.ps1` · `test-kvs-report.ps1` 직접 실행 | **양쪽 exit 0** |
  | "기록 조회로 되읽음은 하지 않는다" | `grep -rn KVSGet scripts/` | **0건** — 기록 전용(append) |

- CSN 귀속 대조 — 러너 배선은 **lowyworkenv** 쪽(`GIIP_GIssue_Claude` → lowyworkenv 러너)이고
  lowyworkenv 저장소에는 `lib/kvs-report.ps1` · `lib/token-usage.ps1` 이 **없으며**, KVS 조회 0건 ·
  기존 `scheduler_run_history`(`Send-GissueRunHistory`, Lssn 71291) 경로가 남아 있고,
  `csn-projects.json` 하트비트 카운트 0건 → "CSN 70424 는 아직 기록 단계(1단계)이며 집계·과금은 확산 단계" 라는
  1단계 범위 한정 주장과 **모순 없음** → TRUE.
- → **주장 전건 TRUE → 거짜 잠금 0건.** 정정·전이·이슈 쓰기 **0건**.

### [H] 결론

- **검증 가능한 사실 주장 전건 TRUE → 거짜 잠금 0건.** [H] §5 "주장이 맞으면 아무 것도 하지 않는다" 에 따라
  이슈 쓰기 · 정정 코멘트 · 상태 전이 **0건**. (권한 범위: READY 복귀까지만 — 이번엔 되돌릴 대상 자체가 없었음)
- 2시간 창에는 isn 5398 **1건만** 걸렸다(직전 회차의 2h 창은 0건). 창은 미끄러지므로 회차마다 실측한다.

## [H] 재검증 중 발견한 실제 결함 — 합산 모듈 `-SinceUtc` 의 `DateTime.Kind` 정규화 (수정 + 회귀 테스트)

- isn 5398 의 대조 과정에서 **직접 실행**한 합산 모듈 호출이 **0건**을 반환했다. 오류가 없고 예외도 없다 —
  "측정값 0" 으로 조용히 오독될 수 있는 형태였다.
- 원인 (PowerShell 5.1 실측) — `DateTime` 비교 연산자는 `Kind` 를 무시하고 **원시 tick 만** 비교한다.
  `[datetime]'2026-11-16T06:00:00Z'` 는 PowerShell 캐스트로 **Kind=Local** 값이 되고(값은 `2026-11-16 15:00 +09:00`),
  `LastWriteTimeUtc`(UTC tick)와 비교하면 **창이 UTC 오프셋(+9h)만큼 밀려** 최근 구간이 전부 탈락한다.
  - 같은 instant 를 `Kind=Utc` 로 넘기면 **rows=2** — 즉시 차이가 드러난다.
  - **UTC+0 호스트에서는 이 결함이 드러나지 않는다** → "green 이면 멀쩡하다" 는 근거가 안 된다.
- 수정 (`scripts/gissue/lib/token-usage.ps1`) — `ConvertTo-GissueUtcDateTime` 헬퍼를 추가해
  `-SinceUtc` 를 함수 **안에서** 정규화한다(Utc=그대로 · Local=`.ToUniversalTime()` · Unspecified=UTC 로 간주),
  두 비교 지점(`Where-Object` 필터 · 레코드 시간 스킵)이 정규화된 값을 쓰게 했다.
- 회귀 테스트 (`scripts/gissue/tests/test-token-usage.ps1`) — 기존 테스트는 `Kind=Utc` 값만 써서
  이 결함을 **구조적으로 잡을 수 없었다**. **같은 instant 를 `Kind=Local` 로 넘겨도 동일 집계가 나오는지** +
  헬퍼 계약 3종을 고정하는 케이스를 추가했다(게이트 기대 건수는 44 그대로 — **파일 추가가 아니라 기존 파일 확장**).
- **수정 전 FAIL / 수정 후 PASS 를 직접 실행으로 증명**했다.
  - 수정 전(origin/main 모듈) — `expected [2] got [0]` 로 **exit 1**.
  - 수정 후(워크트리 모듈) — **exit 0**.
  - 실데이터 재실행 — 두 호출 형태(UTC 문자열 · Local Kind)가 **동일한 2행**을 냈다
    (MiniMax-M3 calls=80 · freshIn=157,359 · cacheCreate=0 · cacheRead=8,069,580 · out=68,664 /
     `<synthetic>` calls=23 · 토큰 0).
- 문서 — `docs/60-operations/token-usage-metering.md` §5 에 "호스트 로컬 합산 호출 규칙" 단락을 추가했다
  (어떤 `Kind` 로 넘겨도 같은 instant 로 정규화된다는 계약 + 정규화 없이는 조용히 0건이 된다는 경고).
- 지식 — k-layer `KNOW-052` 신규 작성 + `INDEX.md` 등록 행 추가.

## tKB 본문 대조 게이트 (정비 회차 관례) — STALE 9건 발견 → 재동기화 후 STALE 0건

- 신규 노트 등록은 "1건 등록" 으로 끝내지 않고 **본문 단위 대조**로 끝낸다
  (tKB 는 등록 시점의 본문만 반영하고, 이후 노트 고침이 따라오지 않는다 — 件수만 맞아도 본문 낡음이 투명하다).
- 조회(`tkb.js list --csn 70424`) → giip-fde-agent 프로젝트 행 **53건**(노트 52 + `INDEX.md`).
  각 행의 본문을 `tkb.js get --kb-sn` 으로 1건씩 받아 **저장소 파일과 정규화(CRLF→LF·행끝공백) 후 비교**했다.
- **첫 판정: OK 41 · STALE 9 · TRUNCATED 4 · MISSING 0.**

  | 분류 | 건수 | 내용 |
  |---|---|---|
  | STALE | 9 | KNOW-001 · 003 · 015 · 021 · 022 · 027 · 039 · 041 · 045 |
  | TRUNCATED | 4 | `INDEX.md` · KNOW-006 · KNOW-014 · KNOW-CSN70424 |

- STALE 9건은 **저장소 파일이 최신이고 tKB 사본이 뒤처진 것**임을 대표 2건으로 확인했다.
  - **KNOW-045** — 파일에만 `## 정정 (2026-11-13) — PR #408 머지 후 스크래치 워크트리 상태 재측정` 절이 있고
    tKB 사본에는 없다(kb-only 라인 0건) → 이후 회차가 파일만 고치고 재 sync 하지 않은 상태.
  - **KNOW-003** — tKB 사본은 `giip #2220`, 파일은 `giip 2220` → **rule 60(issue 링크 형식) 교정이 파일에만 반영**된 상태.
    tKB 사본에 남아 있던 `giip #2220` 은 렌더러가 GitHub 이슈로 자동링크할 수 있는 형태였다.
- 조치 — 해당 **12건(9 STALE + 3 TRUNCATED 노트) + `INDEX.md`** 을 `tkb.js sync-klayer --note <파일>` 로 **재 sync** 했다
  (레포 파일은 손대지 않는다 — tKB 사본만 현재 파일 기준으로 갱신).
- **재 판정: OK 50 · STALE 0 · TRUNCATED 4 · MISSING 0.**
  남은 TRUNCATED 4건은 `pApiKb*bySk` 의 `JSON_VALUE` 가 `nvarchar(4000)` 이라 **API 한계**로 물리적으로 저장 불가하다
  (`tkb.js` 도 "--no-truncate 면 실패 처리" 로 명시). 4건 전부 **저장소 파일의 충실한 접두사**(prefixMatch=true)이며
  절단 trailer 가 원문 경로·원래 길이를 남긴다 → **도구 한계로 남는 정상 상태**다.
- 신규 등록 건 — `KNOW-052` = **kbSn 7213**. 등록 직후 `tkb.js get --kb-sn 7213` 으로 **본문 일치 확인**(일치).
  `INDEX.md` 행의 tKB kbSn 칸도 `7213` 으로 채웠다.
- `INDEX.md` 자체는 15,119자라 tKB 사본에서 4,000자에서 잘린다 → **새로 추가한 행이 색인 사본에서 잘려 사라진다**
  (tKB API `nvarchar(4000)` 한계 · 노트 본문 자체는 kbSn 7213 에 온전히 들어 있다).

## 워크트리/브랜치 인벤토리 (관찰 — 자기 것만 회수)

- 본 세션 소유는 `maint-149-1607` 뿐 → **PR 머지 후 이것만** 정본 도구(`scripts/gissue/cleanup-worktrees.ps1`)로
  회수한다(공유 체크아웃 cwd · `-RepoPath` + `-OnlyPath` 백슬래시 경로 · `-MinIdleMinutes 0` · DryRun 먼저).
- 그 외 워크트리는 "자기가 만든 것만" 원칙에 따라 **미접촉(관찰만)** —
  `maint-118-0545` · `maint-62-2331` · `giip-5054-refine` · `giip-5142-svcguard` · detached `verify-4139-c7` /
  `verify-5054-main` / `verify-5174-main`. 러너의 WORKTREE-CLEANUP(16:17:15)도 이 7건을 MANUAL-REVIEW 로
  분류해 자동 회수 대상이 아님을 확인했다.
- 원격 브랜치 잔재 4건(`chore/csn70424-maint131-20261115-1607` → PR #450 · `docs/flash-default-engine` → PR #469 ·
  `docs/token-usage-metering` → PR #468 · `feat/token-usage-step1` → PR #470)은 **연계 PR 이 전건 MERGED** 라
  잔존 ref 뿐이다 → 3축 안전 검사(`git log origin/main..<branch>` 0건 · `--is-ancestor` TRUE ·
  어떤 워크트리에서도 체크아웃 안 함) 후 **삭제**한다.
- 원격 브랜치 `bot/task-giip-4804` · `4805` · `4806` 는 **이 세션 CSN 밖 소유** → 계승·삭제·쓰기 0건.

## 산출물 목록 (PR 1건)

1. `scripts/gissue/lib/token-usage.ps1` — `-SinceUtc` Kind 정규화 헬퍼 + 비교 지점 적용
2. `scripts/gissue/tests/test-token-usage.ps1` — 회귀 케이스 추가(기존 파일 확장, 기대 건수 44 유지)
3. `docs/60-operations/token-usage-metering.md` — §5 "호스트 로컬 합산 호출 규칙" 단락
4. `.agent/k_layer/notes/KNOW-052_datetime_kind_shifts_the_time_window_to_zero.md` — 지식 노트 신규
5. `.agent/k_layer/notes/INDEX.md` — KNOW-052 등록 행
6. `.agent/work_history/20261116_1607_csn70424_repo-maintenance.md` — 본 기록

- **tKB 등록(csN 70424)** — 신규 `KNOW-052` = **kbSn 7213**(본문 일치 확인) · `INDEX.md` = kbSn 1303 갱신 ·
  기존 노트 13건 재 sync(STALE 9 + TRUNCATED 3 + INDEX 1) → 본문 대조 **STALE 0건** 달성.
  (레포 파일 변경 없음 — tKB 사본만 현재 파일 기준으로 갱신)

- **`docs/WHATS_NEW.md` 는 넣지 않았다** — 저장소 정비 회차의 관례를 실측해 확인했다.
  `git log -- docs/WHATS_NEW.md` 과 최근 정비 PR 의 파일 목록을 대조한 결과:
  - **정비 전용 회차**(대상 0건) — PR #461 · #462 · #463 · #464 · #466 · #467 · #471 은
    **work_history 1건만** 건드리고 `WHATS_NEW.md` 는 건드리지 않았다.
  - **실제 코드·설계 변경이 있는 회차** — PR #465(145차 · 내부 결함 수정 + k-layer) 는
    work_history + 코드 + k-layer 만 넣었고 WHATS_NEW 는 넣지 않았다.
    PR #468 · #469 · #470 은 사용자 노출 기능·설계 변경이라 WHATS_NEW 항목이 들어갔다.
  - 이번 회차는 **내부 결함 수정**이라 145차(#465) 와 같은 모양이다 → WHATS_NEW 미삽입이 정본 관례다.

## 완료 판정 (실행 결과 기준)

- [0] 열린 PR 0건 → 충돌 대상 **0건** · [E] 열린 PR 0건 → 실패 체크 **0건**(main push run 6건 전건 success,
  로컬 게이트 워크트리·공유 체크아웃 **양쪽 exit 0**) · [F] stash **0건** ·
  [H] 2h 1건 / 24h 10건(검증 가능 주장 **전건 TRUE**, 거짜 잠금 0건)
  → 정정·전이·이슈 쓰기 **0건**.
- 산출물 = 코드 수정 1건 + 문서 6건. PR 1개 관례 유지(74차 이후).
- 머지 커밋·CI run id·워크트리 회수 결과 등 확정값은 **본 기록이 아니라 PR 코멘트**로 인계한다(115~148차와 동일).
