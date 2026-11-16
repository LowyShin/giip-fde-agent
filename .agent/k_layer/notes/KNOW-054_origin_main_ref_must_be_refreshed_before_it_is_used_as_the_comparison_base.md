# KNOW-054 — 기준 ref 인 `origin/main` 도 stale 하다: 비교 전에 fetch 하고 ref 해시를 근거로 남긴다

> 근거: 2026-11-16 CSN 70424 저장소 정비 150차 세션 실측 (work_history 20261116_1907) · 발행: 2026-11-16 · 상태: 검증됨(재현 완료)
>
> 관련 파일: `scripts/gissue/cleanup-worktrees.ps1` · `scripts/gissue/run-repo-gates.ps1`

## 요지

`origin/main` 을 "최신 상태" 로 **가정하면** 방금 머지된 PR 의 파일이 **존재하지 않는 것(MISSING)** 으로 보인다.

`git fetch` 는 PR 머지 **이전**에 실행될 수 있다. 그 직후의 `origin/main` 은 아직 그 머지 커밋을 모른다.
이 상태에서 `git cat-file -e origin/main:<path>` 를 돌리면 **방금 머지된 PR 이 추가한 파일이 MISSING** 으로 나온다.

**위험은 "MISSING" 을 파일 부재로 오독하는 데 있다** — 파일 삭제·워크트리 회수 판정으로 이어지면
되돌릴 수 없는 삭제가 된다. 조회만 하는 실측에서는 "도구가 잘못 짚었다" 로 끝나지만,
회수 게이트에서 같은 판단이 나면 **파일이 실제로는 있는데 지워진다**.

## 실측 (2026-11-16)

- 세션 시작 시점 `git fetch origin --prune` → `origin/main` = `9d9e96c`.
- 직후 자동 머지 스윕이 PR #473 을 `2026-11-16T10:40:32Z` 에 머지 → 새 main = `cbd9f38`.
- 그 시점의 기준 ref 로 `git cat-file -e origin/main:<path>` 실행 → PR #473 이 추가한 4개 파일 중 **2개가 거짓 MISSING**
  (`docs/60-operations/token-usage-measurements.md` · `.agent/rules/58_engine_call_minimization.md`).
- `git fetch origin --prune` 재실행 → `origin/main` = `cbd9f38` → **4개 전건 EXISTS**.

**재현(기준 ref 를 명시적으로 지정)** — 같은 4개 파일을 두 기준 ref 로 확인한 결과:

| 기준 ref | 실측 문서 | 실측 룰 | KNOW-052 노트 | token-usage 모듈 |
|---|---|---|---|---|
| `9d9e96c` (PR #473 머지 전) | **MISSING** | **MISSING** | EXISTS | EXISTS |
| `origin/main` = `cbd9f38` (머지 후) | EXISTS | EXISTS | EXISTS | EXISTS |

→ **MISSING 은 "파일이 없다" 가 아니라 "기준 ref 가 그 파일을 모른다"** 를 뜻한다.

## 규칙

1. **기준 ref 을 쓰기 전에 fetch 한다** — 비교·존재 확인·회수 판정 전에 `git fetch origin --prune`.
2. **판정 근거에 ref 해시를 남긴다** — "origin/main" 이 아니라 **`origin/main` = `<해시>`** 로 적는다.
   해시가 없으면 그 기준이 몇 시의 것인지 알 수 없다.
3. **MISSING 1건만으로 삭제·회수를 결정하지 않는다** — PR 목록·머지 기록과 교차 확인하고,
   fetch 후에도 MISSING 이면 그때는 실제 부재로 본다.
4. **MSYS 경로변환 함정을 별도로 배제한다** — `git cat-file`/`git show` 의 `ref:path` 인자는
   `MSYS2_ARG_CONV_EXCL="*"` 로 경로변환을 막는다. 이 문제(경로변환)와 본 문제(stale ref)는 **별개**다.

## 적용

- 워크트리 회수·파일 사전검사·링크 사전검사 등 **"있나/없나" 판정**은 fetch 후의 ref 로만 한다.
- 세션 기록에 "기준 ref" 를 적을 때는 **해시를 함께** 적고, 해시가 바뀌면 판정을 다시 한다.

## 관련

- 작업 기록: [150차 저장소 정비](../../work_history/20261116_1907_csn70424_repo-maintenance.md)
- 짝지음 — [KNOW-050](KNOW-050_stale_worktree_reclaim_check_must_target_origin_main.md): 대조 **기준** 은 `origin/main` 이라야 한다.
  본 노트는 그 기준 ref **자체의 신선도** 문제다.
