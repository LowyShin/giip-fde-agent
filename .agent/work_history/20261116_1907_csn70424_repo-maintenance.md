# CSN 70424 저장소·PR 레벨 정비 150차 (2026-11-16 19:07 KST) — [0]/[E]/[F] 0건 · [H] 2h 2 / 24h 12 전건 TRUE · [H] 재검증 중 발견한 상속 노트 오류 정정(KNOW-053 재작성) + 기준 ref 신선도 노트 신설(KNOW-054)

> 세션 성격: **저장소/PR 레벨 정비** (CSN 70424 저장소 전체 스코프, 단일 이슈 처리가 아니다).
> 규칙상 항상 도는 [0] 병합충돌 · [E] CI/검증 실패 · [F] 오판 stash · [H] 최근 코멘트 논리 재검증 4축을 돈다.
> **이번 회차 산출물: 지식 노트 2건(KNOW-053 재작성 · KNOW-054 신설) + 색인 1건 + 본 기록 1건 · 이슈 쓰기 0건 · 상태 전이 0건 · stash drop 0건 · 정정 0건.**

## 세션 성격 — 19:07 슬롯

- 러너 로그(`scripts/gissue/logs/gissue_csn70424.log`, lowyworkenv 측) 기준 직전 회차 이력:
  - 16:12:06 START → **17:04:21 DONE** (149차 — 본 회차의 직전 기록 `20261116_1607_csn70424_repo-maintenance.md`)
  - **17:10:36 QUEUED → 17:37:34 START → 17:59:44 DONE** (17:07 슬롯 — 산출물 없이 끝난 회차)
  - **18:16:55 START → 18:25:21 DONE** (18:07 슬롯 — 엔진 오류(`unrecognized_model`)로 실질 조치 없는 회차)
  - **19:07:38 QUEUED(동시 실행 상한 4, 활성 4) → 19:38:01 START** ← **본 세션**
  - 20:13:48 `SKIP: 실행 중(lock 36분 전, PID 80552 생존 확인)` — 본 세션이 실행 중이라 다음 슬롯이 건너뛰었다.
- **회차 번호는 "슬롯" 이 아니라 "기록이 생긴 횟수" 기준**(144·147차 교훈) — 직전 신규 기록이
  `.agent/work_history/20261116_1607_csn70424_repo-maintenance.md`(149차)이므로 신규 기록 번호는 **150차**다.
- **죽은 회차의 워크트리를 계승했다** — 17:07 슬롯이 남긴 `D:\temp\worktrees\giip-fde-agent\maint-150-1707`
  (브랜치 `chore/csn70424-maint150-20261116-1907`, base = `origin/main` = `cbd9f38`)를 새로 만들지 않고 그대로 썼다.
  새 워크트리를 만들면 미회수 워크트리가 하나 더 늘어난다(orphan 누적 방지).
  이 워크트리에는 죽은 엔진이 **커밋하지 않은 채로 남긴 노트 2건**이 있었다 — 둘 다 상속 전에 재검증했다(아래 "상속 노트 정정").
- 실행 주체: 이 세션은 스케줄러가 직접 띄운 **헤드리스 폴백 워커**이므로 work_history + 노트 + PR 생성을
  **직접 수행**한다(서브에이전트 위임은 MODEL_USAGE_SPEC 상 예외이며 단건 기록 PR 에 불필요하다 — 149차와 동일 판단).
- 사전 락 불요 — `scripts/gissue/csn-projects.json` 실측 기준 CSN 70424 의 프로젝트가 이 저장소
  (giip-fde-agent)이고, lowyworkenv 는 이 세션 CSN 밖의 다른 저장소다. 144~149차와 동일 판단.
- 공유 체크아웃(`C:\Users\lowys\Downloads\projects\giip-fde-agent`)은 **읽기 전용**으로만 쓴다.
  작업 워크트리는 `D:\temp\worktrees\giip-fde-agent\maint-150-1707`.

## [0] PR 병합충돌 — 대상 0건

- 세션 시작 시점 `gh pr list --state open --json number,headRefName,title,mergeable,statusCheckRollup`
  → 열린 PR **1건**: `#474` ([스케줄러] gissue 코멘트에 사용 AI 모델 표기 의무화, giip 5449, **다른 세션 소유**).
- `#474` 의 `mergeable` = **MERGEABLE**(충돌 아님) → `mergeable=CONFLICTING` 대상 **0건** → 조용히 건너뜀.
  다른 세션 소유 PR 이므로 **수정·병합 시도 없이 조회만** 했다.
- 확인 중 자동 머지 스윕이 `#474` 를 `2026-11-16T11:23:10Z` 에 머지했다 → 확인 시점 열린 PR **0건**.
- 루트에 vendored 제품 레포 없음(저장소 루트 하나뿐 — 서브모듈은 `.gemini/extensions/bkit` 1건이며 giip 제품 레포가 아니다).
  중첩 레포별 추가 조회 대상도 없다.

## [E] CI/검증 실패 — 대상 0건

- [E] 대상(열린 PR) 의 실패 체크 **0건** — `#474` 는 `mergeable=MERGEABLE` + 체크 green 상태였고,
  이후 머지되어 `main` push run `43857287420` 이 `completed/success` 로 마감됐다.
- `gh run list --branch main --limit 6` → 최근 6건 run **전건 `completed` / `success`**
  (최신 = `#474` 머지 커밋 `1895541`, 그 직전 = 149차 기준 `cbd9f38`(PR #473), `9d9e96c`, `67cf653`, `850c8b0`, `bb3ed7e`).
- 로컬 게이트(`scripts/gissue/run-repo-gates.ps1`)는 **공유 체크아웃(base)** 과 **이번 워크트리** 양쪽에서
  **병렬로** 실행해 "워크트리 green ≠ main green" 을 배제했다(145차가 발견한 GUID 임시 파일명 충돌 결함 재발 여부).
  - 공유 체크아웃(base) — `ps1 44건 / mjs 8건 / 링크스캔 1 / 실패 0건`, **exit 0**.
  - 워크트리 — `ps1 44건 / mjs 8건 / 링크스캔 1 / 실패 0건`, **exit 0**.
  - **양쪽 exit 0** — 145·146·148·149차와 같은 "양쪽 PASS" 성질이 유지된다.
  - 참고 — 게이트 기대 건수 `ps1 44` 는 이번 회차 이전부터 44다(149차 PR #472). 이번 회차는
    **기대 건수를 건드리지 않았다**(테스트 파일 추가가 아니라 **문서·노트 추가**).

## [F] Orphan auto-unblock stash — 대상 0건

- `git stash list` → **빈 출력**(stash 0건) — 공유 체크아웃 실측.
- 서브모듈 `.gemini/extensions/bkit` 도 `git stash list` **0건**.
- 자동 해제(`auto-unblock `) 메시지 항목 0건 → 조용히 건너뜀.

## [H] 최근 코멘트 논리 재검증 — 2h 2건 / 24h 12건(검증 가능 주장 전건 TRUE) · 정정 0 · 전이 0 · 이슈 쓰기 0

- 조회: `giipprj/giipdb/mgmt/listRecentCommentIssues.ps1 -Csn 70424 -HoursBack 2|24 -Json`(상태 무관).
  이 PC 엔 `pwsh` 가 없어 `powershell`(5.1)로 실행했고, 콘솔 코드페이지로 깨지는 한글 JSON 은
  **저장소 밖 임시 폴더**(`%TEMP%/h70424/`)로 받아 파싱했다(공유 체크아웃 루트에 임시 파일을 쓰면 안 된다 — 133차 교훈).
  **2시간 창 2건**(isn 5449 · 5438) · **24시간 창 12건**.
- **stdout 파싱 함정 실측 → KNOW-053 으로 노트화**(아래 별도 절).
  `listRecentCommentIssues.ps1` 의 stdout 은 **① `Write-Host` 안내문 1줄 + ② JSON 배열** 이다.
  전체를 `JSON.parse` 에 넣으면 `Unexpected token 'L', "Listing is"... is not valid JSON` 로 실패하고,
  **첫 `[` 부터** 잘라내면 배열 파싱이 성공한다(2시간 창 = len 2).
- 자기 세션이 남긴 코멘트 0건 → 자기코멘트 제외 대상 0건.
- 12건의 **검증 가능한 사실 주장**을 유형별로 나누고, 각 주장을 **직접 조회해** 재확인했다
  (직전 회차의 기록을 인용하지 않고 — 코멘트를 믿지 않고 직접 대조했다).

### 유형 A — 워치독 운영 스킵 통지 6건 (isn 5053 · 4699 · 4556 · 4130 · 4300 · 4211) : "REVIEW/TESTED 재검증 쿨다운(마지막 재검증 후 4시간 미만, 새 사람 신호 없음)"

- **모두 `[SKIP-REASON]` 워치독 노트**(author `gissue-scheduler-watchdog`, type `note`)이고, 이슈 상태는 전건 `REVIEW`다.
- **"새 사람 신호 없음"** — 건별로 마지막 사람 코멘트(Lowy Shin) 시각이 통지보다 수일 앞선다(직접 조회):

  | isn | 워치독 통지(regdate) | 마지막 사람 코멘트 | 상태 |
  |---|---|---|---|
  | 5053 | 2026-11-16T08:04:12Z | 2026-11-13T00:13:13Z | REVIEW |
  | 4699 | 2026-11-16T08:04:10Z | 2026-11-12T13:06:03Z | REVIEW |
  | 4556 | 2026-11-16T08:04:06Z | 2026-11-12T13:41:37Z | REVIEW |
  | 4130 | 2026-11-16T08:04:04Z | 2026-11-12T18:22:45Z | REVIEW |
  | 4300 | 2026-11-16T08:02:21Z | 2026-11-12T13:18:06Z | REVIEW |
  | 4211 | 2026-11-16T08:02:18Z | 2026-11-12T13:15:41Z | REVIEW |

- 통지 뒤에 사람 코멘트가 붙은 사례는 **0건** → 주장 TRUE.

### 유형 B — [G] Actionflow 재검증 게이트 SKIP 3건 (isn 2648 · 1968 · 4530) : "`## Test Procedure` 정확 헤딩 섹션 부재 → REVIEW 유지"

- 3건 모두 마지막 코멘트가 `[ACTIONFLOW 재검증 게이트 — 판단: SKIP, 상태 유지]` / `[gissue-agent] REVIEW 재검증 결과 (REVIEW → REVIEW 유지)` /
  `[G] Actionflow 재검증 게이트 판정: … REVIEW 유지` 다 — 즉 **전이 없음**을 스스로 명시한다.
- **"정확한 헤딩 `## Test Procedure` 섹션 0건"** — 내가 받은 코멘트 전체를 `## Test Procedure`(정확 헤딩) 기준으로
  **재스캔**했다(exact-heading 정규식 `^[ \t]*##[ \t]+Test[ \t]+Procedure[ \t]*$`).

  | isn | 코멘트 총건 | exact heading 0건? | 상태 |
  |---|---|---|---|
  | 2648 | 32 | **0건** (문자열은 백틱 인라인 인용으로만 등장) | REVIEW |
  | 1968 | 30 | **0건** | REVIEW |
  | 4530 | 31 | **0건** (자유서술 "## 테스트 결과" 등만 존재) | REVIEW |

- → 주장 TRUE (세 건 모두 실제로 정확 헤딩이 없고 상태 유지).

### 유형 C — refinement 완료 통지 1건 (isn 5398) : "1단계 5개 요건 충족 · PR #470 MERGED · 회귀 테스트 2종 exit 0 · A축 실측 완료 · B축 성립 불가"

- **"PR #470 MERGED, 2026-11-16T06:36:51Z, 커밋 850c8b0"** — `gh run list --branch main` 에서
  `headSha = 850c8b01c5cbc1596543acf31d40af6262a7fd31` · 제목 "feat: 토큰 사용량 기록 1단계 … (PR #470)" run 이
  `completed/success` 로 실재한다 → **TRUE**.
- **A축(호스트 로컬 합산) 실측 수치** — "MiniMax-M3 calls=41, cacheRead=2,684,508 …" 는 이 세션에서 재현하지 않았다
  (호스트 로컬 산출물이라 저장소/이슈에서 재현 불가 — 본 회차 검증 범위 밖으로 명시).
- **B축(플랫폼 tKVS) "현재 성립 불가"** — 149차가 같은 모듈을 다루며 구조적으로 확인한 영역이라 상충 없음.
  → **검증 가능한 부분 전건 TRUE**, 비검증 가능 부분은 위와 같이 명시했다.

### 유형 D — 2시간 창 2건 (isn 5438 · 5449) : PR #473 / #474 구현 보고

- **isn 5438**(2026-11-16T10:41:15Z 코멘트) — 주장: "① 실측 문서 신설 `docs/60-operations/token-usage-measurements.md` (PR #473 머지 완료) ·
  ② 룰 신설 `.agent/rules/58_engine_call_minimization.md` (같은 PR #473) · ③ WHATS_NEW 반영 + 설계 문서 `token-usage-metering.md` 에 실측 문서 링크 추가".
  → `gh pr view 473 --json files` 실측 = `.agent/rules/58_engine_call_minimization.md` (ADDED) ·
  `docs/60-operations/token-usage-measurements.md` (ADDED) · `docs/60-operations/token-usage-metering.md` (MODIFIED +1/-1) ·
  `docs/WHATS_NEW.md` (MODIFIED +1) → **주장 4항목 전건 TRUE**. 머지 시각 `2026-11-16T10:40:32Z`(mergeCommit `cbd9f38`)는
  코멘트 시각보다 43초 앞서므로 "머지 완료 후 보고" 순서도 성립한다 → **TRUE**.
- **isn 5449**(이슈 본문, 코멘트 0건) — 요구 4항목 ↔ PR `#474` 파일 목록이 **1:1 대응**한다:
  `PROTOCOL_PROGRESS_COMMENT.md`(요구 1) · `run-gissue-claude.ps1`(요구 2) · `gissue-audit-lib.ps1`(요구 3) ·
  `test-checklist-judgement.ps1` + `docs/WHATS_NEW.md`(요구 4) → **TRUE**.
  (본문의 "CSN 47 giip 4902 코멘트 샘플" 항목은 CSN 47 관할이라 본 회차에서 재조회하지 않았다 —
  **검증한 것과 검증하지 않은 것을 구분해 적는** 것이 149차 교훈이다.)

### [H] 결론

- 검증 가능한 주장 **12건 유형 전건 TRUE** — 거짓 잠금(파싱 실패를 "0건" 으로 오독) 0건.
- **정정 0건 · 상태 전이 0건 · 이슈 쓰기 0건.** READY 로 되돌릴 대상도 없다(12건 전건 REVIEW/PENDING 유지).

## [H] 재검증 중 발견한 실제 오류 — 상속 노트 KNOW-053 의 사실 오류 정정

- 죽은 엔진(17:07 슬롯)이 **커밋하지 않은 채** 남긴 `KNOW-053_mgmt_recent_comment_json_is_not_an_array_and_its_timestamp_is_nine_hours_off.md`
  의 내용에는 **사실 오류 2건**이 있었다.
  1. **"조회 JSON 은 배열이 아니다"** → **틀림.** 실제로는 배열 1개다(`[{...},{...}]`). 파싱 실패의 진짜 원인은
     **앞에 붙은 `Write-Host` 안내문 1줄**이며, 실제 에러 메시지도 노트가 인용한 것과 달랐다
     (`Unexpected token 'L', "Listing is"... is not valid JSON` ≠ 노트의 `Unexpected non-whitespace character after JSON`).
  2. **"−9h"** → 이 사실은 맞지만 **이미 [KNOW-026](../k_layer/notes/KNOW-026_giip_issue_regdate_is_utc_but_json_date_is_minus_9h.md) 가
     원인·보정 규칙까지 소유**하고 있다 → 중복 기술이 아니라 **소유권 중복**이다.
- 오류의 위험도는 "문서 오류"가 아니라 **[H] 창 건수를 0건 으로 오독**하는 방향이다 —
  "파싱 실패" 를 "창 안 이슈가 없다" 로 읽으면 정정·전이 대상을 조용히 놓친다.
- 조치 — 잘못된 파일은 **삭제**하고, 같은 번호·같은 제목 슬롯을 **정확한 내용으로 재작성**했다:
  `KNOW-053_mgmt_recent_comment_stdout_has_notice_line_before_json_array.md`.
  새 노트는 ① stdout 구조(안내문 1줄 + JSON 배열) ② 첫 `[` 부터 잘라 파싱 ③ 오진단 주의(괄호 깊이 스캐너를 먼저 짜지 말 것)
  ④ −9h 는 KNOW-026 의 소유(중복 기술 제거) ⑤ **150차가 새로 확정한 사실**(API `regdate` 가 참 UTC) 을 담는다.
- **150차의 추가 확정 — API `regdate` = 참 UTC** (mgmt 표시값과 다른 소스):
  giip 5438 코멘트 `regdate` = `2026-11-16T10:41:15Z` vs GitHub PR #473 `mergedAt` = `2026-11-16T10:40:32Z` → **+43초**
  (PR #473 은 "PR #473 으로 머지 완료" 라고 적는 그 코멘트의 대상 PR 이라 시간 순서가 성립한다).
  같은 instant 의 mgmt 표시값 = `2026-11-16T01:41:15Z` → **정확히 −9h**. 24시간 창 12건 전건에서 같은 −9h 가 재현됐다.
  → **"언제인가" 판정은 API `regdate` 로 한다**(mgmt 표시값을 UTC 로 읽지 않는다).

## [H] 재검증 중 발견한 도구 함정 — 기준 ref `origin/main` 의 신선도 (KNOW-054 신설)

- 세션 시작 시점 `git fetch origin --prune` → 그 시점 `origin/main` = `9d9e96c`.
  직후 자동 머지 스윕이 PR #473 을 `2026-11-16T10:40:32Z` 에 머지 → 새 main = `cbd9f38`.
  그 **사이의 기준 ref** 로 `git cat-file -e origin/main:<path>` 를 돌리면 PR #473 이 추가한 4개 파일 중 **2개가 거짓 MISSING**
  (`docs/60-operations/token-usage-measurements.md` · `.agent/rules/58_engine_call_minimization.md`)으로 나온다.
- 재현(기준 ref 를 명시적으로 지정) — 같은 4개 파일을 두 기준 ref 로 확인:

  | 기준 ref | 실측 문서 | 실측 룰 | KNOW-052 노트 | token-usage 모듈 |
  |---|---|---|---|---|
  | `9d9e96c` (PR #473 머지 전) | **MISSING** | **MISSING** | EXISTS | EXISTS |
  | `origin/main` = `cbd9f38` (머지 후) | EXISTS | EXISTS | EXISTS | EXISTS |

- 위험 — **MISSING 을 "파일 부재" 로 읽으면** 워크트리 회수·파일 사전검사 판정으로 이어져 **되돌릴 수 없는 삭제**가 된다.
  조회에서 끝나면 "도구가 잘못 짚었다" 로 끝나지만, 회수 게이트에서 같은 판단이 나면 파일이 실제로는 있는데 지워진다.
- 조치 — **KNOW-054 신설**(fetch 후 ref 해시를 근거로 남기고, MISSING 1건만으로 삭제·회수를 결정하지 않는다).
  MSYS 경로변환 함정(`MSYS2_ARG_CONV_EXCL`)은 **별개 문제**로 분리해 적었다.

## tKB 본문 대조 게이트 (정비 회차 관례)

- 상속 노트에 **잘못된 사실이 들어 있었다**는 이번 회차의 핵심 발견이므로, tKB 도 **잘못된 행이 남아 있으면**
  "등록 1건" 으로 끝내지 않고 **본문 단위 대조**로 끝낸다.
- 잘못된 노트는 tKB 에 이미 **kbSn 7219** 로 등록되어 있었다 → **삭제**했다(신규 등록이 아니라 정정).
  삭제는 정본 API(`giipApiSk4` → `pApiKbDeletebySk`)로 처리했고 응답은 `RstVal 200 / "KB entry deleted successfully"` 였다.
  (직접 DB 접근 아님 — SK API 경로. rule 54 준수)
- 신규 노트 **KNOW-053 = kbSn 7221** · 갱신 노트 **KNOW-054 = kbSn 7220**(기존 행 갱신) — 두 건 다
  등록/갱신 후 **본문 일치 확인**했다.
- `INDEX.md` 는 저장소 파일(2행 추가)만 갱신했고, tKB 색인 사본(kbSn 1303)은 **색인 파일 최종 상태 기준으로 재 sync** 한다
  (`INDEX.md` 는 4,000자 API 한계로 잘리는 기존 제약이 있어 — 149차와 동일).

## 워크트리/브랜치 인벤토리 (관찰 — 자기 것만 회수)

- 본 세션 소유는 `maint-150-1707` 뿐 → **PR 머지 후 이것만** 정본 도구(`scripts/gissue/cleanup-worktrees.ps1`)로
  회수한다(공유 체크아웃 cwd · `-RepoPath` + `-OnlyPath` 백슬래시 경로 · `-MinIdleMinutes 0` · DryRun 먼저).
- 그 외 워크트리는 "자기가 만든 것만" 원칙에 따라 **미접촉(관찰만)** —
  `maint-118-0545` · `maint-62-2331` · `giip-5054-refine` · `giip-5142-svcguard` · detached `verify-4139-c7` /
  `verify-5054-main` / `verify-5174-main`. 러너의 WORKTREE-CLEANUP(18:30:38)도 이 7건을 MANUAL-REVIEW 로
  분류해 자동 회수 대상이 아님을 확인했다.
- 원격 브랜치 잔재 3건(`bot/task-giip-4804` · `4805` · `4806`)은 **이 세션 CSN 밖 소유** → 계승·삭제·쓰기 0건.

## 산출물 목록 (PR 1건)

1. `.agent/k_layer/notes/KNOW-053_mgmt_recent_comment_stdout_has_notice_line_before_json_array.md` — 지식 노트 **재작성**(상속 노트의 사실 오류 정정)
2. `.agent/k_layer/notes/KNOW-054_origin_main_ref_must_be_refreshed_before_it_is_used_as_the_comparison_base.md` — 지식 노트 **신설**
3. `.agent/k_layer/notes/INDEX.md` — KNOW-053 · KNOW-054 등록 행 2행 추가
4. `.agent/work_history/20261116_1907_csn70424_repo-maintenance.md` — 본 기록

- **tKB 등록(csN 70424)** — 신규 `KNOW-053` = **kbSn 7221** · 갱신 `KNOW-054` = **kbSn 7220** ·
  **잘못된 `KNOW-053` 행 kbSn 7219 삭제**(본문 대조 게이트) · `INDEX.md` = kbSn 1303 재 sync.
- **`docs/WHATS_NEW.md` 는 넣지 않았다** — 저장소 정비 회차의 관례를 실측해 확인했다(149차와 동일 판단):
  정비 전용 회차(PR #461 · PR #462 · PR #463 · PR #464 · PR #466 · PR #467 · PR #471)는 **work_history 1건만**, 내부 결함 수정 회차(PR #465)도
  work_history + 코드 + k-layer 만 넣었다. 이번 회차는 **사용자 노출 변경이 없는 내부 지식 정정**이라 WHATS_NEW 미삽입이 정본 관례다.

## 완료 판정 (실행 결과 기준)

- [0] 열린 PR 1건(PR #474) 중 `mergeable=CONFLICTING` **0건** · [E] 열린 PR 실패 체크 **0건**(main push run 6건 전건 success,
  로컬 게이트 워크트리·공유 체크아웃 **양쪽 exit 0**) · [F] stash **0건** ·
  [H] 2h 2건 / 24h 12건(검증 가능 주장 **전건 TRUE**, 거짜 잠금 0건)
  → 정정·전이·이슈 쓰기 **0건**.
- 산출물 = 지식 노트 2건(신규 1 · 재작성 1) + 색인 1건 + 기록 1건. PR 1개 관례 유지(74차 이후).
- 머지 커밋·CI run id·워크트리 회수 결과 등 확정값은 **본 기록이 아니라 PR 코멘트**로 인계한다(115~149차와 동일).
