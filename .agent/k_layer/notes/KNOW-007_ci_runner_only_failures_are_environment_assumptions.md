# KNOW-007: CI 러너에서만 실패하는 테스트는 "환경 가정"이다 — git identity 부재 + 8.3 단축 경로

- 작업 CSN: 70424
- 관련 파일: `scripts/gissue/tests/test-selfpull-not-on-main.ps1`,
  `scripts/gissue/tests/test-worktree-idle-guard.ps1`,
  `scripts/gissue/tests/test-repo-integrity-gate.ps1`,
  `.github/workflows/repo-gates.yml`
- 근거: 2026-10-24 CSN 70424 저장소 정비 세션 실측 (PR #237 첫 CI 실행)
- 상호링크: [KNOW-006](KNOW-006_repo_gates_not_wired_to_ci.md)(게이트 미결선 축),
  [KNOW-005](KNOW-005_child_process_output_tests_are_console_codepage_dependent.md)(코드페이지 축)

## 1. 현상

PR #237(게이트 CI 결선)의 **첫 실행**에서 ps1 회귀 테스트 3건이 실패했다.
그런데 **로컬(DP01, Windows PowerShell 5.1)에서는 20/20 전부 통과**했다.

| 테스트 | 러너 실패 건 | 로컬 |
|--------|--------------|------|
| `test-selfpull-not-on-main.ps1` | 6건 (B1/C1/C3/D1/D2/D3) | PASS |
| `test-worktree-idle-guard.ps1` | 4건 (B-1b/B-1c/B-1d/B-2) | PASS |
| `test-repo-integrity-gate.ps1` | 4건 (D-0/D-2/D-3/D-4) | PASS |

→ "로컬 green ≠ 러너 green" 의 새 축. [KNOW-005](KNOW-005_child_process_output_tests_are_console_codepage_dependent.md)는
**코드페이지** 축이었고, 이 건은 **그 밖의 환경 가정** 축이다.

## 2. 원인 2종

### (a) git identity 부재

`test-selfpull-not-on-main.ps1` 는 임시 저장소(`repo.git`)에 **커밋**하는데 `user.name`/
`user.email` 을 가정했다. 개발자 PC 에는 전역 설정이 있지만 **GitHub windows-latest 러너에는 없다** →
커밋이 조용히 실패 → `git push -u origin main` 실패 → upstream 없음 → `Test-GissueUpstreamGone`
반전, ancestor 판정 반전 → B1/C1/C3/D1/D2/D3 연쇄 실패.

**재현(로컬)**: `GIT_CONFIG_GLOBAL=<빈 파일>` 로 실행 → **동일 6건 실패**. 확정.

### (b) 8.3 단축 경로 (short path)

러너의 `$env:TEMP` 는 `C:\Users\RUNNER~1\AppData\Local\Temp` — **8.3 단축 경로**다.
엔진(`worktree-safety.ps1`)이 자식 경로를 해석할 때는 **전체 경로**(`C:\Users\runneradmin\...`)가 나오고,
테스트가 비교하는 문자열은 **단축 경로** → 문자열 비교가 어긋난다.

- idle-guard: 로그에 그 경로가 "등장하지 않음" → B-1b/B-1c/B-1d/B-2 실패
- integrity-gate: `ScanRoot 밖 경로` 로 **삭제 거부** → 삭제 자체가 안 되고(그래서 인접 레포의
  HEAD 이동도 없어서) D-0/D-2/D-3/D-4 연쇄 실패

**재현(로컬)**: 8.3 이름을 갖는 디렉터리를 만들고 `TEMP` 를 그 단축 경로로 지정 → **동일 증상**.
확정(`Get-Item` 은 단축 이름을 전체 경로로 풀어 주고 `Resolve-Path` 는 풀어 주지 않는다).

## 3. 조치

1. **테스트가 전역 설정을 가정하지 않게 한다** — 임시 저장소에 **로컬** identity 를 명시.
2. **임시 루트를 전체 경로로 고정** — `(Get-Item -LiteralPath $env:TEMP).FullName` 으로 루트를 만든다.
   (`Get-Item` 과 `Resolve-Path` 의 차이가 핵심이다.)
3. **CI 워크플로는 workflow 레벨 `env`** 로 커밋 identity 를 **1곳만** 지정한다(job 별 복붙 금지).

## 4. 재발 방지

1. **"CI 에 처음 결선" 하면 러너 실행이 반드시 다르다.** 로컬 green 을 근거로 "CI 도 green 일 것" 이라고
   가정하면 안 된다 — 첫 실행이 곧 판정이다.
2. **테스트가 개발자 PC 전역 설정(전역 git identity, 사용자 프로필 경로 형태)에 의존하면 안 된다.**
   전역 설정이 있는 PC 에서만 통과하는 테스트는 **버그가 숨은 테스트**다.
3. **재현 가능한 실패를 만들어 확인한다** — "러너에서만 실패한다" 는 말로 끝내지 말고
   로컬에서 같은 조건(빈 git config, 8.3 TEMP)을 만들어 **동일 증상** 을 확인한 뒤 고친다.
   이번 세션은 그렇게 했다(통제 비교 포함).

## 5. 결과 저장처 / 소비처

- 수정 파일: 위 4개(테스트 3 + 워크플로 1)
- 작업 기록: `.agent/work_history/20261024_061500_csn70424_repo-maintenance.md`
- 소비처: PR 을 만드는 모든 세션(CI 를 빨간 게이트로 쓸 때), 회귀 테스트를 추가·삭제하는 세션

## 6. 관련 규칙

42 · 48 · 35 · 50 · 36 · 37 · 61(k-layer 은 커밋으로 성립)
