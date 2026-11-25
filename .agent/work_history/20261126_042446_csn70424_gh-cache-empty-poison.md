# gh-cache 빈 집합 오염 방지 (2026-11-26 04:24 JST)

## 읽은 파일
- giip-fde-agent `AI_MUST_READ.md`
- role `.agent/roles/developer.md`
- rules `.agent/rules/00_core_principles.md`, `39_conduct_toward_customers.md`, `28_response_report_rule.md`, `42_completion_by_execution_evidence.md`, `43_delegation_safety_block.md`, `55_information_lookup_order_and_feedback.md`, `59_documentation_sync_with_work.md`, `35_commit_push_per_task.md`, `57_worktree_cleanup_on_completion.md`, `11_structured_commit.md`, `50_bot_pr_scope_discipline.md`
- `AGENTS.md` (정본·이식 양쪽)

## 배경·실측
- 02:07 회차(시작 단계 수정 PR #1571 적용 후 첫 회차)는 시작 단계를 통과해 정리 단계까지
  도달했으나 슬롯 기록 없이 또 멈췄다. 마지막 로그 03:18:53, 같은 네 개 lowyworkenv
  워크트리 평가 줄에서 31분 침묵, 종료 기록 없음 (CQE mslsn 8262, 03:50 실행).
- 결정적 단서: 로그에 처음으로 `[GH-CACHE]` 줄이 남았다 —
  `[2026-11-26 03:18:52] [CSN 33] [WORKTREE-CLEANUP] [GH-CACHE] HIT LowyShin/Lowyworkenv (0 branches, age 6m)`.
  캐시 파일 실측 (CQE mslsn 8263, 03:55 실행): `LowyShin__Lowyworkenv.merged.json`
  len=140, mtime 03:12:28, 내용 `{"ownerRepo": "LowyShin/Lowyworkenv",
  "fetchedAt": "2026-11-25T18:12:28.1048765Z", "branches": []}` — 0개.
  같은 시간대 giipdb(len=135)·lwweb02(len=136)·front-fde-agent(len=144)도 같은 크기라
  비어 있을 가능성이 크다.
- 호스트 로그 대조 (CQE mslsn 8264, 04:05 실행): 03:10–03:19 창에서 해당 레포의 조회
  결과 줄("N개 조회 완료"·"gh pr list 실패")은 0건, HIT 줄 1건뿐. 즉 빈 캐시 파일은
  CSN 33 잡의 로그에 흔적이 없는 시점에 쓰였다 — 캐시 디렉터리를 공유하는 다른 CSN
  잡이 쓴 것으로 보이며, 코드 경로는 모든 잡이 공유한다.
- 이 VM에서 같은 시각 직접 확인: `gh pr list --repo LowyShin/Lowyworkenv --state merged
  --json headRefName --limit 1000` 실행 시 종료코드 1, 빈 stdout, stderr
  `GraphQL: API rate limit already exceeded for user ID 20239203.` — 이 형태는
  기존 실패 경로(캐시 미기록)로 처리된다. 같은 시각 `gh api rate_limit` 은
  GraphQL remaining 3,695 / 5,000을 보고해 끝점 수치와 실제 거부가 어긋난다
  (2차 한도 또는 카운터 시차로 보이나 미확인).

## 오염 경로 특정 (파일:줄, 구 코드 기준)
- 유일한 생산 호출 지점: `scripts/gissue/worktree-safety.ps1:1029-1030`
  (`Get-GissueMergedBranchSet` 성공 분기) — `git grep` 으로 확인, 다른 생산
  호출 지점은 없다. 빈 캐시 파일은 이 분기에서만 쓰일 수 있다.
- `worktree-safety.ps1:1019-1031` (구 코드): `ExitCode -eq 0` 이면 빈 stdout 도
  `ConvertFrom-Json` 가드 뒤에 빈 집합으로 파싱해 `Ok=$true` 로 만들고
  `Write-GissueMergedBranchDiskCache` 로 쓴다. 주석이 "빈 stdout은 빈 집합으로
  취급한다"고 명시하고 있었다.
- `lib/gh-cache.ps1:84` (구 `Write-GissueMergedBranchDiskCache`): 받은 집합을
  그대로 쓴다 — 빈 집합도 유효한 파일로 쓴다.
- `lib/gh-cache.ps1:49` (구 `Read-GissueMergedBranchDiskCache`): 빈 집합 파일도
  TTL 안이면 히트(비어 있지 않은 집합 객체)로 돌려준다.
- 재현 (구 코드, pwsh 7.4.6): R1 빈 집합 Write 시 파일 생성됨(`branches: []`),
  R2 Read 시 HIT(0개), R3 gh 스텁(종료코드 0 + 빈 stdout) 시 `Ok=$true`·0개·
  캐시 파일 기록됨, R4 L1 비우고 재호출 시 gh 미호출로 HIT 0개·`Ok=$true` —
  오염이 다음 실행까지 이어짐을 증명했다.

## 수정 (정본)
- `scripts/gissue/lib/gh-cache.ps1`
  - `Write-GissueMergedBranchDiskCache`: 빈 집합 쓰기 거부 — `$false` 반환,
    기존 파일 유지. 성공 시 `$true` 반환.
  - `Read-GissueMergedBranchDiskCache`: 빈 집합 파일은 `$null` 로 거른다
    (오염 치유). `-AllowStale` 스위치 추가 — TTL 상한만 풀고 빈 집합은
    여전히 거른다.
- `scripts/gissue/worktree-safety.ps1` (`Get-GissueMergedBranchSet`)
  - 빈 결과(빈 stdout·`[]`)는 조회 실패로 취급: WARN 로그, `Ok=$false`,
    캐시 미기록.
  - 조회 실패 시 최후 수단: TTL이 지났어도 비어 있지 않은 마지막 유효 캐시를
    `[GH-CACHE] STALE` 로 임시 사용한다.
  - 한도 초과 실패는 `[GH-RATE-LIMIT]` 으로 구분해 로그에 남긴다
    (stderr에 `rate limit` 포함 시).
- 문서(rule 59): `docs/60-operations/hourly-issue-scheduler-runtime.md`
  gh-cache 절에 빈 집합 오염 방지 항목 추가, `docs/WHATS_NEW.md` 2026-11-26
  항목 추가.
- 테스트: `scripts/gissue/tests/test-gh-cache.ps1` 에 F(빈 집합 오염 방지 9건)·
  G(빈 결과 실패 처리·STALE 폴백·한도 초과 구분 12건) 구간 추가 — 21건 → 42건.

## 테스트 결과
- 신규 테스트 `test-gh-cache.ps1`: **42/42 PASS** (수정 코드).
- 신규 테스트 음성 대조군 (구 코드 + 신규 테스트, /tmp/oldcode): F-1~F-6 FAIL,
  F-8에서 `-AllowStale` 파라미터 부재로 중단 — 신규 테스트가 구 코드를
  검출함을 확인했다. G 구간의 구 코드 결함은 단독 재현 스크립트 R3·R4로
  증명했다(구 코드 `Ok=$true`·캐시 기록·HIT 0개).
- 회귀 (정본, 수정 코드): test-bounded-process 44/44, test-worktree-cleanup-timebox
  60/60, test-worktree-merge-gate-failclosed 18/18, test-job-init-audit-lib-guard
  PASS, test-gair-gate ALL PASS, test-gair-judges ALL PASS, test-stale-code-guard
  18/18, test-repo-integrity-gate 30/30. 파스 검사 3/3 통과(구문+BOM).
- 테스트 중 F-2 실패 1건을 내 테스트 코드 버그로 확인하고 수정했다
  (E 구간에서 쓴 파일이 남아 있어 파일 부재 전제를 어긴 것 — 코드 결함이 아님).

## PR
- 정본 PR #569 (아래 "## PR" 절에 번호·SHA 기록 예정 — 머지 확인 후 기재)

## 호스트 효과 검증 방법
- 다음 :07 회차에서 `[GH-CACHE] HIT` 줄의 브랜치 수가 0이 아닌지, `[GH-CACHE] STALE`
  줄이 뜨는지, `[RUN-END-SUMMARY]` 와 슬롯 기록이 도착하는지 확인한다.
- 이미 디스크에 있는 빈 캐시 파일은 이 수정이 적용된 다음 실행부터 Read 가
  $null 로 거르므로, 별도 삭제 작업 없이 치유된다.

## 범위 밖·후속
- 빈 stdout 이 생긴 gh 측 원인(출력 배수·빈 배열·한도 초과 시의 종료코드 형태)은
  이 수정 범위를 벗어난다 — 코드 측에서는 어떤 경우에도 빈 결과를 성공으로
  취급하지 않게 막았다.
- 같은 최상위 `Get-Command` 패턴이 있는 `lib/unmapped-csn-guard.ps1:36,39`,
  `page-feedback-analyze.ps1:60` 은 잡 init 경로가 아니라 스윕·독립 스크립트에서만
  닷소싱되므로 이번 범위 밖이다.
- CSN 33 SK 미등록은 별개 결함이며 이번 범위 밖이다.

## Bkit Feature Usage
- Used: (없음 — 본 작업은 코드 수정·테스트·문서이며 Bkit 기능 호출 없음)
- Not Used: 해당 없음
- Recommended: 해당 없음
