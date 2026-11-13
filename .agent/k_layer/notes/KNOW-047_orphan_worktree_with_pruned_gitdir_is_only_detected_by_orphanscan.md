# KNOW-047 — 등록정보가 prune 된 고아 워크트리는 `-OrphanScan` 에서만 잡힌다

> 근거: 2026-11-13 CSN 70424 저장소 정비 111차 세션 실측 · 발행: 2026-11-13 · 상태: 검증됨(직접 실측)

## 요지

worktree **등록정보**(`<repo>/.git/worktrees/<name>`)가 prune 된 채 **디렉터리와 `.git` 포인터만 남은** 고아는
`git worktree list` 에도 없고, 정본 정리 도구의 `-RepoPath` · `-RemnantScan` 에도 **구조적으로 도달 불가**하다.
**`-OrphanScan` 만이 이 클래스를 잡는다.**

`git worktree prune` 도 해결책이 아니다 — 방향이 반대다(사라진 **등록정보**를 지우는 쪽이다).

## 근거 — 도구별 도달 가능성 실측 (2026-11-13)

- 대상: `D:\temp\worktrees\giip-fde-agent` 아래 잔여 디렉터리 1건.
  `.git` 파일은 남아 있으나 그 `gitdir:` 포인터가 가리키는 등록정보가 없는 상태였다.

| 탐지 방법 | 결과 |
|---|---|
| `git worktree list` | **미표시**(등록정보가 없으므로) |
| 정본 정리 도구 `-RepoPath` | **미표시**(관리 ref = `git worktree list` 기준) |
| 정본 정리 도구 `-RemnantScan` | **미표시** — 이 모드는 "`.git` 이 **아예 없는** 잔해"를 정의로 삼는다(이 건은 `.git` 이 있음) |
| 정본 정리 도구 `-OrphanScan` | **`상태 OrphanNoAdmin: 1건`** — 탐지됨(회수 대상) |

- 정본 도구(`scripts/gissue/cleanup-worktrees.ps1`)의 자체 문서에도 같은 구조가 명시되어 있다 —
  "등록정보가 사라진 worktree 는 `git worktree list` 에 아예 나타나지 않아 기존 정리 도구 2종이
  **구조적으로 도달 불가**였다".
- 회수 후 재측정: `-OrphanScan` → `.git` 보유 디렉터리 6건 전부 `Registered` · **고아 0건** · `Aborted=False`.

## 부수 교훈 — `git ls-tree` 파일 목록 비교는 `core.quotepath=false` 가 필요하다

잔여 디렉터리의 내용이 "커밋 X 와 동일한가" 를 두 커밋의 파일 목록 집합 비교로 확인하려 했다.
`git ls-tree` 의 **기본 출력은 비ASCII 경로를 `"\345\255\230\234..."` 로 escape** 하여 원래 UTF-8 경로와
문자열 매칭되지 않았다. 그 결과 **"이 커밋에 없는 고유 파일 5건"** 이라는 **거짓 차이**가 계산되었고,
"내용이 유실될 수 있다"는 잘못된 판단(회수 보류 사유)이 생길 뻔했다.

```bash
# 잘못됨 — 비ASCII 경로가 escape되어 집합 비교가 어긋난다
git ls-tree -r --name-only <sha>

# 올바름
git -c core.quotepath=false ls-tree -r --name-only <sha>
```

같은 이유로 Git Bash 에서 `git show origin/main:<경로>` 를 쓸 때는 `MSYS2_ARG_CONV_EXCL="*"` 로
경로 인자 변환을 막아야 한다.

## 규칙 (다음 세션이 지킬 것)

1. 워크트리 인벤토리는 `git worktree list` **하나에 의존하지 말고** `-OrphanScan` 을 항상 함께 돌린다.
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gissue/cleanup-worktrees.ps1 -OrphanScan -DryRun -ScanRoot <경로>
   ```
2. `-OrphanScan` 이 잡은 고아는 등록정보가 없으므로 `git worktree remove` 가 통하지 않는다 →
   **정본 정리 도구로만** 회수한다(원시 `git worktree remove` 는 대량삭제 훅이 deny).
3. 회수 전 내용 보존 확인은 `core.quotepath=false` 를 붙인 `ls-tree` 로 **파일 집합**을 비교한다
   (커밋 동일성 · 고유 파일 0 · 심볼릭 링크 0 의 3축).
4. `-RemnantScan` 은 "`.git` 이 아예 없는" 잔해 전용이며, `.git` 포인터가 끊긴 고아는 잡지 않는다.
