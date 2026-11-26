# 머지목록 파싱 붕괴 — 워크트리 정리 대상이 항상 0건이던 근본 결함 (2026-11-26 15:32 JST)

## 읽은 파일
- giip-fde-agent `AI_MUST_READ.md`, `CLAUDE.md`
- role `.agent/roles/orchestrator.md`
- rules `.agent/rules/47_auto_cleanup_safety_requirements.md`, `.agent/rules/57_worktree_cleanup_on_completion.md`,
  `.agent/rules/35_commit_push_per_task.md`, `.agent/rules/10_karpathy_guidelines.md`,
  `.agent/rules/PROTOCOL_PROGRESS_COMMENT.md`, `.agent/rules/11_structured_commit.md`
- `scripts/gissue/worktree-safety.ps1`, `scripts/gissue/lib/gh-cache.ps1`, `scripts/gissue/cleanup-worktrees.ps1`,
  `scripts/gissue/tests/test-gh-cache.ps1`, `scripts/gissue/pr-attribution-lib.ps1`
- `docs/60-operations/hourly-issue-scheduler-runtime.md`, `docs/WHATS_NEW.md`

## 배경·실측
- 이슈: giip #6354(원본 #5175) — `.claude/worktrees` 서브에이전트 worktree 가 정리 도구 대상에서 항상
  제외돼 무한 누적. 본 세션은 2차 회수(reclaim)였다(직전 회수: gicSn 51952, 13:20:50).
- 직전 회수 노트의 진단("머지된 PR 8건 전부를 '머지 PR 없음'으로 오판")은 **방향이 맞았다** — 그러나
  "오염된 디스크 캐시를 무효화하면 된다"는 결론은 정확하지 않았다. 오염은 손으로 만든 결과가 아니라
  **정본 코드 경로가 매 회차 새로 만든다**(캐시 파일만 지우면 다음 회차에 그대로 재생성됨).
- 결정을 뒷받침한 실측 4건:
  1. 라이브 스케줄러 로그(`gissue_csn70424.log`): 2026-11-25 20:13:45 `[GH-CACHE] HIT ... (539 branches)`
     → 21:21:26 `머지된 PR 브랜치 1개 조회 완료`. 이후 매 회차 "1개" 또는 빈 결과로 고정.
  2. 디스크 실측: lowyworkenv 캐시 20건 중 비어 있지 않은 **15건 전부** `branches` 가 원소 1개짜리
     배열(공백 결합 문자열, 길이 117~32619) — 전 레포 전부 오염.
  3. PS 5.1 직접 실측: `@('[{"headRefName":"a"},{"headRefName":"b"}]' | ConvertFrom-Json)` 의 Count 는
     **1** 이고 원소 타입은 `Object[]` — 즉 **중첩 배열**. `$p.headRefName` 은 멤버 열거로 `String[]`
     가 되고 `HashSet<string>.Add(<String[]>)` 는 공백 결합 문자열 1개를 넣는다(실측: `'feat/alpha fix/beta'`).
  4. 이 저장소의 `pr-attribution-lib.ps1` 은 **이미** 같은 함정을 문서화해 "먼저 변수에 대입해 배열로
     만든 뒤 @() 로 감싼다"는 규칙을 쓰고 있었다 — `worktree-safety.ps1` 만 지키지 않았다.

## 결함 경로 (파일:줄, 구 코드 기준)
- `scripts/gissue/worktree-safety.ps1` `Get-GissueMergedBranchSet`:
  `$parsed = @("$($ghCall.StdOut)" | ConvertFrom-Json)` → 중첩 배열 → `foreach ($p in @($parsed))` 의
  `$p` 가 배열 → `$p.headRefName` 이 String[] → `HashSet<string>.Add()` 가 공백 결합 1개로 붕괴 →
  `Contains(<브랜치>)` 항상 false → 전 worktree '미머지' 오판 → 정리 대상 0건.
- `scripts/gissue/lib/gh-cache.ps1` `Write-GissueMergedBranchDiskCache`: 파이프라인 기반 정규화 —
  중첩 배열이 들어오면 같은 붕괴가 캐시 파일에 기록된다(공백 결합 문자열 1개짜리 배열).
- `scripts/gissue/lib/gh-cache.ps1` `Read-GissueMergedBranchDiskCache`: 그런 파일을 정상 캐시로 읽어
  모든 worktree '미머지' 판정을 만든다.

## 수정 (정본)
- `scripts/gissue/worktree-safety.ps1`: 파이프라인을 `@()` 로 감싸지 않고 **변수에 직접 대입**한 뒤 순회.
  추가로 `$p` 가 아직 배열이면 원소 단위로 펼치고, `headRefName` 자체가 배열이면 원소 단위로 넣는다.
- `scripts/gissue/lib/gh-cache.ps1`:
  - Read — 공백이 든 항목이 하나라도 있으면 그 파일을 깨진 파일로 보고 `$null` 로 거른다(오염 자동 치유).
    git ref 이름에는 공백이 들어갈 수 없으므로 안전하다.
  - Write — 공백이 든 항목은 거부한다(fail-closed). 기존 파일을 덮어쓰지 않는다.
- `scripts/gissue/tests/test-gh-cache.ps1`: H 구간 9건 추가.
- `docs/60-operations/hourly-issue-scheduler-runtime.md`, `docs/WHATS_NEW.md` 갱신.

## 테스트 결과
- `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gissue/tests/test-gh-cache.ps1`
  - 수정 전(원본 코드로 되돌려 실행): **PASS=44 FAIL=7**, 종료코드 1. H-2 는 `expected [2] got [1]`,
    H-5 는 `expected [feat/h-one] got [feat/h-one fix/h-two]` — 붕괴가 그대로 재현된다.
  - 수정 후: **PASS=51 FAIL=0**, 종료코드 0.
- 실제 정리 게이트 DryRun(수정본, `gh` 한도 정상 상태): 정리 대상 **0건 → 3건**.
  - 삭제 예정: `.claude/worktrees/agent-ad280829a8db83b78`, `giip-5175-exitcode`, `giip-6351`
  - 수동확인(정확히 미머지): `giip-4116-guard-live`, `giip-5054-refine`, `giip-5142-svcguard`,
    `giip-5449-model-notation`, `maint-62-2331` — 5건
- 실제 정리 실행(rule 57 절차): `.claude/worktrees/agent-ad280829a8db83b78` **삭제됨**
  (머지 PR 확인 · 마지막 활동 13,728분 전 · clean · 링크 없음 · 인접 레포 무결성 재검증 통과).
  로컬/원격 브랜치 `docs/giip-5438-rule58-index` 삭제. `git worktree list` 9건 → 8건, 저장소 HEAD 불변.
- 미커밋 변경이 있던 `giip-5175-exitcode`(추적되지 않은 `gates-run*.txt` 2건)와 `giip-6351`
  (추적되지 않은 `scratch/`)는 rule 57 §1 에 따라 **삭제하지 않고 보고만** 한다. 정리는 그 두 건의
  미커밋 산출물을 보존한 채 1건만 지웠다.

## 범위 밖·후속
- **`worktree-safety.ps1` 의 `--force` 재시도 결함(별건)**: `git worktree remove` 가 dirty 때문에 실패하면
  코드가 `--force` 로 재시도한다(line ~1714). 이는 rule 57 금지사항("`git worktree remove --force` 를
  정리 수단으로 사용")과 어긋나 타 세션의 미커밋 산출물을 지울 수 있다. 이번 세션은 `-ProtectFile` 로
  해당 2건을 보호해 그 경로에 진입하지 않았고, **이번 PR 에서는 손대지 않았다**(이슈 스코프 밖).
  후속 별도 이슈 등록 대상.
- **lowyworkenv 배포 포트 미이식**: 라이브 스케줄러는 lowyworkenv 포트(타 CSN)에서 실행되며
  그쪽 `scripts/gissue/lib/gh-cache.ps1`·`worktree-safety.ps1` 에 같은 결함이 있다(동일 코드). 본 세션은
  이 레포의 CSN 라운드 규칙(rule 76)에 따라 다른 CSN 저장소를 수정하지 않았다 — 배포측 이식은 그쪽 몫.
- **동일 함정의 잔존 site**: `scripts/gissue/run-gissue-claude.ps1:4616` 의
  `$rows = @($json | ConvertFrom-Json)` (overtime FindOpenChildren 경로) 도 같은 패턴이다. 이번 이슈
  스코프(워크트리 정리 게이트) 밖이라 수정하지 않았고, 별도 이슈 등록 대상.
- `scripts/gissue/tests/test-scope-gate-pr-identification.ps1:55` 가 이 함정 자체를 회귀 고정하고 있다.

## Bkit Feature Usage
- 사용한 기능: `jikji find` 대신 Glob/Grep 으로 정본 파일 특정(레포에 jikji 미설치), `test-driven-development`
  (수정 전 실패 확인 → 수정 후 통과), `writing-plans`(작업 범위 확정), `subagent-driven-development` 불필요.
- 미사용: `Codex`/`Antigravity` 연동(별도 트리거 없음).
