# KNOW-055 — 외부 프로세스 종료 코드를 판정으로 쓸 때는 핸들을 캐시해야 한다 (그렇지 않으면 항상 0)

> 근거: giip 5175 (2026-11-26) · 발행: 2026-11-26 · 상태: 검증됨(직접 실측 + 회귀 테스트 고정)
>
> 관련 파일: 실행기 `scripts/gissue/lib/bounded-process.ps1` · 판정 엔진 `scripts/gissue/worktree-safety.ps1`
> · 회귀 테스트 `scripts/gissue/tests/test-bounded-process.ps1`
> · 관련: [KNOW-049](KNOW-049_claude_isolation_worktree_family_is_not_unconditionally_excluded.md)(격리 worktree 안전 판정)

## 요지

`Start-Process -PassThru` 로 띄운 자식 프로세스의 **종료 코드**를 판정에 쓰려면, 프로세스가
끝나기 전에 `$proc.Handle` 로 **핸들을 한 번 캐시**해야 한다. 캐시하지 않으면 .NET Framework
(Windows PowerShell 5.1)에서 자식이 종료된 뒤 `Process.ExitCode` 가 **항상 0(=성공)** 으로 읽힌다.

이것은 "가끔 헷갈리는 API" 가 아니라 **fail-open 으로 번지는 결함**이다 — 종료 코드 0 은
"성공"을 뜻하므로, 실패를 뜻하는 종료 코드(1 등)가 성공으로 뒤집히면 **삭제 금지 판정이
"삭제 허용" 으로 넘어간다.**

## 실측 (2026-11-26, PS 5.1 / Windows)

`git merge-base --is-ancestor <비조상 커밋> <기준>` — 비조상이면 종료 코드 1 이어야 한다.

| 경로 | 관측 종료 코드 | 판정 |
|---|---|---|
| 직접 호출 (`& git ...` + `$LASTEXITCODE`) | **1** | 정상 |
| `Start-Process -PassThru` → `WaitForExit()` → `$proc.ExitCode` (핸들 미캐시) | **0** | ✗ **fail-open** |
| `Start-Process -PassThru` → `$null = $proc.Handle` → `WaitForExit()` → `$proc.ExitCode` | **1** | 정상 |

핸들을 캐시하면 프로세스 객체가 그 핸들을 붙들어 종료 코드가 정상 전달된다.

## 번진 범위 (실측, 2026-11-26)

`lib/bounded-process.ps1` 의 `Invoke-GissueBoundedProcess`(2026-11-25 외부 호출 타임아웃 도입 시
함께 들어옴)가 exit code 를 0 으로 고정 → **`worktree-safety.ps1` 의 `Invoke-GissueExternalCall`
경유 호출 전부의 종료 코드 판정이 무력화**됐다. 특히 두 곳이 위험했다:

1. **워크트리 삭제 가드 (fail-open)** — `Test-GissueWorktreeContentInMain` 은
   `git merge-base --is-ancestor` 의 종료 코드로 "HEAD 가 `origin/main` 의 조상인가"를 판정한다.
   비조상(종료 코드 1 = 미반영 커밋 있음)이 0(=조상)으로 도착해 **미반영 커밋이 있는
   `.claude/worktrees` 격리 worktree 가 삭제 대상**으로 넘어갔다 — giip 5175 / PR #428 의
   안전 게이트가 무력화됐다.
2. **`rev-parse --verify` 실패 → dead code** — 존재하지 않는 ref 는 종료 코드 1 이어야 하는데
   0(=존재)으로 도착해, "MainRef 없음 → 판정 불가(fail-closed)" 분기가 **도달 불가능**했다.

같은 결함으로 CI(Repo Gates)가 `test-bounded-process`·`test-repo-integrity-gate`·
`test-worktree-claude-session-guard` 3건 적색이었다(main HEAD 8e6bf42).

## 규칙 (다음 세션이 지킬 것)

1. **종료 코드를 판정依据로 쓸 때는 핸들을 캐시한다** — `Start-Process -PassThru` 직후
   `$null = $proc.Handle`. 이미 만들어진 실행기가 이 패턴을 쓰지 않으면 **그 실행기가
   fail-open** 이라고 가정하고 사용처부터 Audit 한다.
2. **"성공(0)" 으로 고정된 판정은 fail-open** — timeout·오류·비존재 ref 가 모두 0(=성공)으로
   도착하면, 그 값을 "확인 성공" 으로 읽는 코드는 안전 판정을 뒤집는다. 파생 안전장치
   (fail-closed 분기)가 **dead code** 가 되는지도 함께 확인한다.
3. **회귀 테스트는 판정 결과까지 고정한다** — 종료 코드만 보지 말고 "그 종료 코드가
   어떤 판정으로 이어지는가"(여기서는 `InMain=false` 삭제 금지 + 없는 ref → 판정 불가)를
   함께 검증한다. 종료 코드만 고정하면 판정 로직이 뒤집혀도 테스트가 green 이다.
4. **환경 가정성 실패를 "기존 결함"으로 넘기지 않는다** — CI 에서만 나는 실패(KNOW-007)라 해도
   로컬에서 재현·근본 규명되면 **main 을 적색으로 둔 채 방치하지 않는다.**
5. Windows 전용 비교는 경로 구분자(정방향/역슬래시)를 정규화한다 — git 은 Windows 에서도
   경로를 **정방향 슬래시**로 출력한다(검증 대상이 경로 형식이 아니라 인자 전달이면
   비교 전에 정규화한다).
