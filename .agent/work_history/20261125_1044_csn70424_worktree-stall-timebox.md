# 작업 기록 — gissue worktree 정리 시간 한도(타임박스) + stall 마커 (Lowy님 지시)

- 일시: 2026-11-25 10:44 JST (Lowy님 지시, 코디네이터 경유)
- 지시: "멈추는 구조가 있으면 캐치해서 처리 완료 되도록 처리 플로우를 개선해줘" (2026-11-17)
- 계기: 운영 호스트 실측 — 사후 스윕 WorktreeCleanup이 시간 한도 없이 동기 실행돼
  한 단계가 수십 분간 멈추고 러너 전체가 붙잡혔다. 마지막 종료 요약이 수일 전에서
  멈춘 채, 같은 단계의 로그만 수천 줄 쌓이는 상태였다.

## 감사 결과 실측 (설계 전 코드 대조 — 지시서의 파일:행과 일치함을 확인)

- `scripts/gissue/run-gissue-claude.ps1:2155` `Invoke-GissueWorktreeCleanup`에 시간
  한도 파라미터가 없고, post-process 호출부(`'WorktreeCleanup'`, 약 4425행)도
  시간 제한 없이 부른다. 엔진 `Invoke-GissueWorktreeCleanupForRepo`
  (`scripts/gissue/worktree-safety.ps1:1210`)에도 경과 확인이 없다. 레포마다
  `gh pr list --state merged --limit 1000`(타임아웃 없음) 1회 + 항목마다 링크
  스캔·활동 판정·`git status`·삭제·무결성 재검증을 무제한 반복한다.
- 사후 스윕 큐(`scripts/gissue/lib/run-finalize.ps1`, giip 4431)는 반복당 예산
  (기본 90초, env `GISSUE_POSTPROC_BUDGET_SEC`)으로 양보하지만, 동기 단계 하나를
  중간에 끊지 못한다 — 파일 자체 주석이 "한 스윕이 예산보다 오래 걸려도 그 1건만
  처리하고 즉시 반환"이라 명시한다. 그래서 반복당 예산은 WorktreeCleanup 한
  단계를 묶지 못한다. 감사 결과와 일치.
- **감사 지시 1건 정정 — `lib/claude-worktree-cleanup.ps1`은 정본에 없다.**
  지시서는 "lib/claude-worktree-cleanup.ps1 (Phase 0.7 CLAUDE cleanup)이 항목
  사이에서 `$sw.Elapsed.TotalSeconds -ge $TimeBudgetSec`을 확인하고
  '시간 한도 도달 — 나머지는 다음 실행'으로 멈춘다 (~512행)"고 했으나, 정본
  레포 전수 검색 결과 해당 파일이 없고 "시간 한도 도달" 문자열도 어디에도 없다.
  따라서 복사할 기존 구현이 없어, 같은 패턴을 이번 변경에서 새로 도입했다
  (엔진·래퍼·테스트가 그 문구를 고정한다). 지시대로 맹목 구현하지 않고
  파일:행 근거로 정정한다.
- `Test-GissueRepoMerged` 중복(지시서 항목 5)은 정본에 해당 함수가 아예 없어
  손댈 것이 없다 — lowyworkenv 쪽만의 중복으로 판단하고 정본에서는 건드리지 않았다.
- `$RunTimeoutMin = 105`(run-gissue-claude.ps1:160), 스케줄러 ExecutionTimeLimit
  120분은 그대로 둔다. 강제종료 시 Complete-Run이 돌지 않아 종료 기록·락 해제가
  안 되는 구조는 이번 변경이 마커로 우회한다(아래).

## 설계

- **A. 단계별 시간 한도** — `Resolve-GissueWorktreeCleanupBudgetSec`(신규,
  `worktree-safety.ps1`): 명시값 > env `GISSUE_WORKTREE_CLEANUP_BUDGET_SEC` >
  기본값 180초. 180초 근거: 항목 1건당 수십 ms~1초 수준이면 100건 규모도
  100초 안팎에 끝나고, 병목 시에도 한 단계가 러너를 3분 넘게 붙잡지 못하게
  한다(RunTimeoutMin 105분·사후 스윕 반복당 예산 90초와 견줘도 한 단계의 최악
  블로킹이 작게 묶인다). 하루 1회 전체 스윕은 대상이 전 레포라 기본 600초
  (env `GISSUE_WORKTREE_SWEEP_BUDGET_SEC`).
- 엔진은 `-TimeBudgetSec`([double] — 테스트에서 0.05초 같은 작은 한도를 줄 수
  있게)을 받아 항목 경계마다 확인하고, 한도에 걸리면 `TimeBudgetExpired=true`·
  처리/남음 건수와 함께 "시간 한도 도달 — 나머지는 다음 실행" 한 줄을 남기고
  **throw 없이 정상 반환**한다(`Aborted`는 세우지 않는다 — CRITICAL 중단과
  구분). 래퍼는 단계 전체에 스톱워치 1개를 두고 레포마다 남은 예산을 나눠 준다.
  한 항목 안의 작업과 `gh pr list` 조회 1회는 동기라 중간에 끊을 수 없어
  한도로 막지 못한다 — 코드 주석에 명시했다.
- **B. stall-생존 기록** — 신규 `scripts/gissue/lib/stall-marker.ps1`:
  한도에 걸린 단계는 멈추는 즉시 stall 마커(JSON,
  `gissue_csn<csn>-stall-<단계>.json`)를 로그 디렉터리에 남긴다(CSN·단계·경과·
  처리/남음·예산·실행 ID). 다음 :07 실행 시작 시(긴 단계 전) 러너가 마커를
  읽어 CSN 로그에 `[STALL-PREV]`로 남기고, 그 실행의 Complete-Run이
  `[RUN-END-SUMMARY]`에 실어 `tSchedulerAgentRun.summary`로 올린다 — 기존
  #6214 실행 기록 경로(`Format-GissueRunEndSummary`에 `-StallNotes` 추가,
  summary에서 2번째 자리)를 재사용하고 새 API는 만들지 않는다. 마커 삭제는
  종료 기록 시도 **뒤에만** 한다(기록 전 삭제는 강제종료 시 stall 사실 소실).
  SK가 없어 종료 기록을 못 남긴 실행은 마커를 남겨 다음 실행에 다시 표면화한다.
  `-DryRun`은 Phase 2 전에 return하므로 마커를 소비하지 않는다(읽기+로그만 한다).
- **C. 테스트** — 신규 `scripts/gissue/tests/test-worktree-cleanup-timebox.ps1`
  (60건): A. 한도 해석 9건 / B. 엔진 시간 한도(실제 git 레포 + worktree 16건,
  DryRun, 머지판정만 스텁) 17건 / C. 멈춘 단계 뒤 다음 레포 진행 2건 /
  D. 마커 왕복(run N → run N+1 요약·소비·깨진 JSON 건너뜀·fail-open) 12건 /
  E. 러너 소스 배선 13건. `git worktree list`는 주 worktree도 항목으로 세므로
  전체 항목 수는 16+1=17건으로 고정했다.
- **D. 문서·게이트** — `docs/WHATS_NEW.md`에 2026-11-25 항목 + 기준일 갱신.
  `run-repo-gates.ps1` 기대 건수 53 → 54(신규 테스트 1건).
  (주의: 실재 ps1 테스트는 56건으로 기대값보다 2건 많다 — 53 고정 이후 기대값
  상향 없이 들어온 테스트 2건의 기존 슬랙이며, 이번 변경 범위가 아니라 그대로
  두고 주석에 남겼다. 게이트는 "기대보다 적을 때만" 실패한다.)

## 검증 (이 VM, pwsh 7.4.6 — Linux라 PS 5.1이 없어 설치해서 돌림. 최종 판정은
## Windows CI(powershell 5.1)의 repo-gates다)

- 신규 테스트: `test-worktree-cleanup-timebox.ps1` **60/60 PASS** (exit 0).
  초회 57/60에서 3건은 테스트 자체의 결함이었다(주 worktree 항목 수 17건으로
  정정 1건, 이중따옴표 패턴의 `$csn` 보간으로 E-4/E-5 오탐 2건 — 본체 무변경).
- 정본 게이트: `check-ps1-parse.ps1 -All` **120개 전부 통과**(구문 + BOM).
- 회귀(변경 파일 관련): `test-run-summary` 64/64, `test-worktree-idle-guard`
  18/18, `test-worktree-merge-gate-failclosed` 18/18,
  `test-worktree-claude-session-guard` 18/18, `test-complete-run-nonblocking`
  ALL PASS, `test-scheduler-state` PASS — 전부 기준 main 체크아웃과 동일 결과.
- 전수 ps1 스위트 worktree vs 기준 main 대조: **동일**(차이는 신규 테스트 1건
  PASS뿐). worktree 56건 중 46건 PASS·10건 FAIL, 기준 main 55건 중 45건
  PASS·10건 FAIL — FAIL 10건 목록이 양쪽 완전히 동일(test-git-repo-paths,
  test-pr-attribution-evidence·test-pr-link-evidence(이상 120초 타임아웃),
  test-repo-integrity-gate, test-scope-gate-pr-identification,
  test-stash-unblock-lib, test-svcguard-restart-on-memory,
  test-task-cadence-guard, test-temp-filename-collision,
  test-verify-gate-exit-contract). 전부 이 VM의 Linux/pwsh 환경에서만 나는
  기존 실패로, 내 변경과 무관함을 기준 대조로 확인했다. 최종 판정은
  Windows CI(powershell 5.1)의 repo-gates다.

## 변경 파일

- `scripts/gissue/worktree-safety.ps1` — `Resolve-GissueWorktreeCleanupBudgetSec`
  + 엔진 `-TimeBudgetSec`·항목 경계 확인·결과 필드(TimeBudgetExpired·
  ProcessedCount·RemainingCount·TotalEntries·TimeBudgetSec)
- `scripts/gissue/lib/stall-marker.ps1` (신규) — 마커 쓰기/읽기/요약/소비
- `scripts/gissue/lib/run-summary.ps1` — `Format-GissueRunEndSummary`에
  `-StallNotes`(summary 2번째 자리)
- `scripts/gissue/run-gissue-claude.ps1` — stall-marker 라이브러리 적재·실행
  시작 시 이전 마커 표면화·두 래퍼의 예산 전달 + 마커 쓰기·Complete-Run의
  `-StallNotes` 전달 + 기록 뒤 마커 소비
- `scripts/gissue/tests/test-worktree-cleanup-timebox.ps1` (신규, 60건)
- `scripts/gissue/run-repo-gates.ps1` — 기대 건수 53 → 54
- `docs/WHATS_NEW.md` — 2026-11-25 항목

## 의도적으로 안 한 것

- `Test-GissueRepoMerged` 통합(지시서 항목 5): 정본에 해당 함수가 없어 대상 없음.
- 스케줄러 태스크 등록/삭제/비활성화·gair 라우팅·엔진 선택·#6214 기록 형식
  변경 없음(`-StallNotes`는 summary 조립의 선택 파라미터 추가뿐).
- `gh pr list` 조회 자체의 타임아웃: 동기 호출이라 한도로 끊을 수 없어
  이번 변경 범위 밖(주석에 한계로 명시). 조회가 길어지면 그 시간은 한도로
  막지 못한다.
- 일일 스윕의 스탬프는 시간 한도로 멈춘 스윕에도 찍힌다(종전 동작 유지) —
  남은 레포는 다음 날 스윕이 처리한다. 스윕 순서가 고정돼 있으면 꼬리 레포가
  늦어질 수 있는 점은 알려진 한계로 남긴다(CSN별 정리가 각 CSN 자신의 레포는
  매 실행 처리하므로 일일 스윕은 스코프 갭 레포의 백스톱).
- `docs/WHATS_NEW.md` 7일 초과분 이관(rule 36 prune): 기준일 2026-11-25 기준
  11-17 이전 섹션이 남아 있는 기존 드리프트가 있어, 이번 변경은 항목 추가 +
  기준일 갱신만 했다. 이관은 별도 정리 대상(파일 형식이 HISTORY.md의 bullet
  로그와 달라 단순 이동이 아니다).
- 사양서(`docs/60-operations/hourly-issue-scheduler.md`) §10/§13 갱신은 이번
  작업 지시 범위(Docs = WHATS_NEW만)에 없어 넣지 않았다 — 후속 포팅 시
  함께 반영할 것.

## 적용한 role/rule 파일

- `.agent/roles/developer.md` (구현), `.agent/roles/tester.md` (회귀 검증)
- `.agent/rules/35_commit_push_per_task.md` (작업마다 커밋·push, PR로 제출)
- `.agent/rules/36_whats_new_maintenance.md` (WHATS_NEW 갱신 — 단, 7일 초과분
  이관은 위 사유로 보류하고 보고서에 명시)
- `.agent/rules/54_generic_agent_no_customer_info.md` (public 레포 — 추가한
  줄에 고객정보 0건 자가 검사: CSN 숫자는 정본 자신의 70424와 #6214 참조만,
  호스트명·고객 CSN 없음)
- `.agent/rules/57_worktree_cleanup_on_completion.md` (종료 시 자기 worktree·
  브랜치 정리 — PR 머지 전이라 아직 종료가 아니므로, 작업 종료 판정 뒤에 정리)
- `.agent/rules/47_auto_cleanup_safety_requirements.md` (정리 엔진의 안전 요건 —
  시간 한도가 삭제 판정 자체를 바꾸지 않음을 확인: 한도는 멈춤만 하고,
  머지·링크·idle·dirty 게이트는 그대로)
- `.agent/rules/11_structured_commit.md` (커밋 메시지 트레일러)
