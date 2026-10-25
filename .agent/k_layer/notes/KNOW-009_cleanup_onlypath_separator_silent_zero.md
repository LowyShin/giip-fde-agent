# KNOW-009: 정본 정리 도구 `-OnlyPath` 는 경로 구분자를 정규화하지 않는다 — 슬래시 경로를 주면 "조용히 0건"

- 작업 CSN: 70424
- 관련 파일: 정본 도구 `scripts/gissue/cleanup-worktrees.ps1` / 판정 엔진 `scripts/gissue/worktree-safety.ps1`
  (`Invoke-GissueWorktreeCleanupForRepo` 의 `-OnlyPath` 비교부), `.agent/rules/47_auto_cleanup_safety_requirements.md`
- 근거: 2026-10-25 CSN 70424 저장소 정비 46차 세션 실측 (work_history 20261025_182400 / 20261025_184500)
- 상호링크: [KNOW-003](KNOW-003_worktree_safety_dotsource_pitfall.md)(fail-open 삭제 위험 축),
  [KNOW-008](KNOW-008_cleanup_worktrees_classification_and_builtin_idle_gate.md)(판정 Status·idle 가드 축)

## 1. 현상

정본 정리 도구 `cleanup-worktrees.ps1` 는 `-OnlyPath` 로 **대상 워크트리 1건만** 핀포인트로 처리한다.
그런데 이 인자를 **슬래시 경로(`D:/temp/...`)** 로 넘기면 대상이 조용히 걸러진다.

2026-10-25 46차 세션 실측 (동일 저장소·동일 워크트리·동일 옵션, 경로 표기만 다름):

| 호출 | 결과 |
|---|---|
| `-OnlyPath "D:/temp/worktrees/giip-fde-agent/maint-46-1824"` | `Removed {}` · `ManualReview {}` · `SkippedLocked {}` · 제거 **0건**, **경고 0건** |
| `-OnlyPath "D:\temp\worktrees\giip-fde-agent\maint-46-1824"` | `[DRY-RUN] 제거 대상 1건` → `Removed 1건` |

즉 **같은 디렉터리**인데 인자 표기 하나만 바꾸면 "회수 대상 0건"으로 보고된다.

## 2. 원인

판정 엔진 `worktree-safety.ps1` 의 항목 필터는 다음처럼 **문자열 비교**한다.

```powershell
if ($OnlyPath -and (([string]$ePath).TrimEnd('\', '/') -ine ([string]$OnlyPath).TrimEnd('\', '/'))) { continue }
```

`$ePath` 는 `Resolve-Path` 로 얻은 **네이티브(백슬래시) 경로**이므로, `OnlyPath` 도 백슬래시로 주면 일치한다.
반면 `$OnlyPath` 의 슬래시 표기는 `TrimEnd` 만으로는 **구분자 자체가 정규화되지 않아** `-ine` 비교가 항상 참이 되고,
해당 항목은 `continue` 로 **조용히 건너뛴다**. 건너뛴 항목은 `Removed`/`ManualReview`/`SkippedLocked` 어디에도
집계되지 않으므로 사용자는 "0건"을 "이미 정리되어 있다"로 오독하기 쉽다.

## 3. 조치 (이번 세션이 지킨 것)

- **항상 네이티브 백슬래시 경로로 호출한다** — `-RepoPath` 와 `-OnlyPath` 모두 `C:\...` / `D:\...` 형태.
  스크립트가 쓰는 `-OnlyPath` 예시는 저장소 `work_history` 기록들에서 이미 백슬래시 형태다.
- **DryRun 으로 먼저 확인한다** — `[DRY-RUN] 제거 대상 N건` 줄이 실제로 찍혔는지 본 뒤 본 실행한다.
  이 줄이 없는데 결과가 0건이면 **경로 표기 문제일 수 있다**(경고가 안 나오기 때문이다).
- **실행 후 존재 여부를 별도로 확인한다** — 도구 로그 대신 `git worktree list` · 경로 존재 여부로 재확인한다
  ([KNOW-008](KNOW-008_cleanup_worktrees_classification_and_builtin_idle_gate.md) §4 와 동일 원칙).

## 4. 재발 방지

- "`Removed 0건`" 을 "회수 대상 없음"으로 단정하지 말고, **경로 표기**를 먼저 의심한다.
- 정리 회차 기록에 DryRun 결과(제거 대상 건수)를 함께 남겨, 이후 회차에서 "0건"이 나왔을 때
  표기 문제인지 실제 부재인지 구분할 수 있게 한다.
- 판정 엔진 수정(경로 정규화 후 비교, 또는 표기 불일치 시 `ManualReview` 로 승격)은
  **도구 코드 변경 작업**이며 이번 세션 범위 밖이다 — 별도 이슈로 다룬다.

## 5. 결과 저장처 / 소비처

- 수정 파일: 도구 코드 변경 없음(정찰 결과만 기록 — 이번 세션에 `worktree-safety.ps1` ·
  `cleanup-worktrees.ps1` 는 고치지 않았다)
- 작업 기록: `.agent/work_history/20261025_182400_csn70424_repo-maintenance.md`,
  `.agent/work_history/20261025_184500_csn70424_repo-maintenance-post.md`
- 소비처: 자동 정리 세션(핀포인트 회수 호출부), 규칙 47 의 "실행 결과로 판정" 요구에 대한 호출부 주의사항

## 6. 관련 규칙

47 · 48 · 55 · 35 · 36 · 61(k-layer 은 커밋으로 성립)
