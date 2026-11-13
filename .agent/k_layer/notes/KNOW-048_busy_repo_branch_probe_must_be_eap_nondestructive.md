# KNOW-048 — 네이티브 stderr 를 `2>$null` 로만 감싼 probe 는 EAP=Stop 에서 예외를 던진다

> 근거: giip 5180 · 발행: 2026-11-13 · 상태: 검증됨(수정 전 FAIL / 수정 후 PASS 를 직접 실행으로 확인)

## 요지

`git rev-parse` 같은 **네이티브 명령의 stderr** 를 `2>$null` 로만 감싸면, Windows PowerShell 5.1 +
`$ErrorActionPreference='Stop'` 환경에서는 **NativeCommandError 로 throw** 된다.
`2>$null` 은 "에러 메시지를 화면에 안 찍는다"만 하지, "에러를 만들지 않는다"가 아니다.

이 함정은 **같은 함수 안의 다른 호출부**에서 반복해서 짚혀 나왔다. 결정적인 교훈은 이렇다:

> **EAP 안전은 "함수"의 속성이 아니라 "호출부(구문)"의 속성이다.**
> 저장소 후보 수집 함수를 EAP 비파괴로 만들어도, **그 바로 다음에 오는 호출부**가 같은 probe 를
> `2>$null` 로 두면 그쪽에서 여전히 러너가 죽는다. "수집 단계가 안전하다"는 사실이 "그 다음 단계가
> 안전하다"를 보장하지 않는다.

## 현상

러너(`scripts/gissue/run-gissue-claude.ps1`)가 매 CSN 처리 시 "이 저장소가 지금 다른 세션이 쓰는 중인가"
를 판정한다(`Get-GissueBusyRepo` → busy-wait/auto-unblock). 이 판정이 `git rev-parse --abbrev-ref HEAD` 를
`2>$null` 로 감싼 채 호출되고 있었고, 대상 저장소 중 하나가

- 커밋 0건(unborn HEAD) — `git init` 만 된 잔여 스캐폴드, 또는
- `.git` 이 깨진 디렉터리(gitdir 링크가 존재하지 않는 clone 잔여)

인 경우 probe 가 stderr 와 함께 실패(rc != 0)하면서 **러너/잡 전체가 예외로 종료**됐다.
저장소 후보 수집(`Get-GissueGitRepoPaths`)은 EAP 비파괴화돼 있어 통과했는데, **그 다음 단계의
busy 판정에서 죽었다** — 위 교훈의 실제 사례다.

## 원인 — PS 5.1 + EAP=Stop + 네이티브 stderr

- Windows PowerShell 5.1 은 네이티브 명령의 stderr 를 **오류 레코드(NativeCommandError)** 로 만든다.
- `$ErrorActionPreference='Stop'` 이면 그 오류 레코드는 **terminating** 이 되고, `2>$null` 로
  리디렉션했어도 throw 는 막히지 않는다.
- `git rev-parse --abbrev-ref HEAD` 의 실패는 두 경우 모두 stderr 를 남긴다:
  - unborn HEAD → `fatal: ambiguous argument 'HEAD': unknown revision or path not in the working tree.` (rc=128)
  - repo 아님 → `fatal: not a git repository (or any of the parent directories): .git` (rc=128)

직접 실측(PS 5.1, EAP=Stop):

| 대상 | `2>$null` + EAP=Stop | `2>&1` + EAP=Continue + `$LASTEXITCODE` |
|---|---|---|
| 커밋 0건 저장소 | **throw** (RemoteException) | rc=128 → 무시하고 건너뜀 |
| `.git` 깨진 디렉터리 | **throw** (RemoteException) | rc=128 → 무시하고 건너뜀 |
| 정상 저장소 | 통과 | rc=0 → stdout 의 브랜치 이름 사용 |

`2>&1` 로 받아들이면 PS 5.1 은 stderr 를 **ErrorRecord** 로 넣는다. 그래서 성공 여부는
`$LASTEXITCODE` 로만 판정하고, 문자열은 `$_ -is [string]` 로 걸러 낸다.

## 재발방지

1. **네이티브 probe 를 호출하는 구문은 아래 형태로 통일한다.** (함수 시그니처·반환 계약은 그대로 두고
   호출 구간만 감싼다.)

   ```powershell
   $value = $null
   $prevEap = $ErrorActionPreference
   try {
       $ErrorActionPreference = 'Continue'
       $out = @(git -C <path> <args> 2>&1)
       if ($LASTEXITCODE -eq 0) { $value = ($out | Where-Object { $_ -is [string] } | Select-Object -First 1) }
   } finally { $ErrorActionPreference = $prevEap }
   ```

   - `try/finally` 로 원복을 보장한다(예외가 나도 EAP 가 원복돼야 뒤쪽 호출이 오염되지 않는다).
   - 판정 근거는 **종료 코드**다 — stderr 텍스트로 판정하지 않는다.
   - `$ErrorActionPreference` 는 함수-local 이므로 호출부 컨텍스트를 건드리지 않는다.

2. **"이 함수가 EAP 안전한가"를 호출부 단위로 판정한다.** 함수 하나에 probe 가 여러 개 있으면
   **각 probe 를 따로** 본다. `Get-GissueGitRepoPaths` 는 EAP 안전하지만, 같은 파일의
   `Get-GissueBusyRepo` 는 아니었다.

3. **회귀 테스트는 배포본 소스에서 함수 본문을 그대로 추출해 검사한다**(AST `Parser::ParseFile`).
   사본이 여러 개면 **전부** 검사한다 — 하나만 고치면 나머지 사본에서 FAIL 한다.

4. **neg 컨트롤을 반드시 둔다.** "검사기가 0건을 검사하고 PASS" 를 막으려면, 비파괴화 **전** 형태를
   검사기에 넣었을 때 **FAIL** 하는지(패턴 판정)와 **실제로 throw** 하는지(동작 판정)를 둘 다 확인한다.
   이 노트의 D 그룹은 두 가지를 모두 확인한다.

## 남은 동일 유형 — 이번 범위 밖(후속 후보)

`scripts/gissue/run-gissue-claude.ps1` 의 `Invoke-GissueSelfPullNotOnMainCheck` 안에도
`git rev-parse --abbrev-ref HEAD 2>$null` 호출이 남아 있다. 다만 그 호출 대상은 **에이전트 자신의
저장소**(`$AgentRepo`)로 고정되어 있어, 커밋 0건/깨진 `.git` 상태가 정상적으로 성립하지 않는다.
이번 PR 은 busy 판정 사본(2곳)만 다루고, 이 호출부는 범위 밖으로 남겼다.

## 결과가 저장되는 곳 / 소비처

- 이 노트: `.agent/k_layer/notes/KNOW-048_busy_repo_branch_probe_must_be_eap_nondestructive.md`
  + `INDEX.md` 색인 행.
- 수정 대상: `scripts/gissue/run-gissue-claude.ps1` 의 `Get-GissueBusyRepo` 2사본
  (러너 메인 스코프 + `Start-Job` 잡 스코프).
- 회귀 테스트: `scripts/gissue/tests/test-git-repo-paths.ps1` D 그룹(기존 파일에 그룹 추가).
- 사양: `docs/60-operations/hourly-issue-scheduler.md` §13-1-4.
- 소비처: 네이티브 명령을 EAP=Stop 환경에서 호출하는 스크립트를 작성·수정하는 세션,
  그리고 "수집 단계는 통과했는데 다음 단계에서 죽는다" 는 증상을 다루는 세션.
