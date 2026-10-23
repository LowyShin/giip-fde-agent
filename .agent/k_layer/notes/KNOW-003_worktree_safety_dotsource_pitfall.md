# KNOW-003: worktree-safety 모듈 dot-source 실패 → 링크 선검사 없이 삭제 진행(위험)

- 작업 CSN: 70424
- 관련 파일(정본은 lowyworkenv 소관, 본 레포는 사용처):
  `lowyworkenv/scripts/gissue/worktree-safety.ps1`,
  `lowyworkenv/scripts/gissue/cleanup-worktrees.ps1`,
  `lowyworkenv/.agent/rules/55_destructive_cleanup_incident_gate.md`
- 근거: 2026-10-23 CSN 70424 저장소 정비 세션 실측 (`.agent/work_history/20261023_091900_csn70424_repo-maintenance.md` §부수 정비 T3)

## 1. 현상

다른 디렉터리에 만든 자체 정리 스크립트에서
`lowyworkenv/scripts/gissue/worktree-safety.ps1` 을 dot-source 한 뒤
`Get-GissueWorktreeLinkScan -Path <대상>` 을 호출했더니
**"The term 'Get-GissueWorktreeLinkScan' is not recognized"** 로 실패했다.
dot-source 자체는 오류를 낸 뒤 멈춰 **모듈의 함수 일괄이 미정의** 상태가 되었고,
그 상태에서 `$scan.Links.Count -gt 0` 이 `$null` 이라 **false** 가 되어
**링크 선검사 없이** 삭제 루프가 진행될 수 있었다.

## 2. 원인

모듈 첫머리 주석이 이미 규칙화해 두었다 —
"dot-source 된 파일 안의 함수 본문에서 `$PSScriptRoot` 를 읽으면 **호출자** 스크립트 디렉터리로
해석된다". 그런데 그 폴백은 `$PSScriptRoot` 가 **비었을 때만**(`if (-not $script:GissueWorktreeSafetyDir)`)
`$MyInvocation.MyCommand.Path` 로 대체한다.
호출자 스크립트가 `D:\temp\gissue-csn70424\` 에 있으면 `$PSScriptRoot` 는 **비어 있지 않으므로**
폴백이 발동하지 않고, 모듈 디렉터리가 **호출자 디렉터리로 잘못 고정**된다.
그 결과 모듈의 두 번째 dot-source —
`. (Join-Path $script:GissueWorktreeSafetyDir 'code-freshness.ps1')` — 이 **존재하지 않는 경로**를
가리켜 모듈 로드 전체가 중단된다(함수 정의가 하나도 적재되지 않음).

## 3. 왜 위험한가

rule 55 §1-2 의 핵심은 "재귀삭제 전에 정션/심볼릭 링크를 검사하고, 모르면 지우지 않는다"이다.
giip #2220 사고(giipprj/giipv3 정션 → giipdb 전체·.git 소실)의 재발을 막는 유일한 방어선이
**이 함수**인데, 호출 실수가 곧 그 방어선을 조용히 제거한다.
함수 호출이 실패했을 때 `null` 이 "링크 없음"으로 흘러가면 **가장 위험한 방향(fail-open)** 으로 간다.

## 4. 재발방지

1. **자체 스크립트에서 모듈을 직접 dot-source 하지 말 것** — 정본 도구
   `cleanup-worktrees.ps1`(`-RepoPath`/`-OnlyPath`/`-RemnantScan`/`-OrphanScan`)가
   링크 선검사·항목별 삭제·인접 repo 재검증을 모두 포함한다.
2. 어쩔 수 없이 모듈을 쓸 경우: 호출자 스크립트를 **모듈과 같은 디렉터리**에 두거나,
   dot-source 전에 `$script:GissueWorktreeSafetyDir` 를 모듈의 실제 경로로 재설정한다.
3. 안전 함수 호출 전에 **정의 존재를 먼저 확인**하고, 미정이면 **fail-closed(삭제 중단)** 한다.
   `$scan` 이 `$null` 인 상태를 "링크 0건"으로 취급하지 말 것.
4. upstream 정본 수정은 lowyworkenv 소관 — `worktree-safety.ps1` 의 폴백 조건을
   "`$PSScriptRoot` 가 호출자 디렉터리면(모듈 디렉터리와 다르면) 무조건 `$MyInvocation` 경로로 대체"
   로 바꿔야 한다. 2026-10-23 현재 **미수정**(이 저장소 밖이라 이 세션에서 손대지 않음).

## 5. 결과가 저장되는 곳 / 소비처

- 이 노트: `.agent/k_layer/notes/KNOW-003_worktree_safety_dotsource_pitfall.md` + `INDEX.md` 색인 행.
- 작업 기록: `.agent/work_history/20261023_091900_csn70424_repo-maintenance.md`(T3 절).
- 소비처: worktree/디렉터리 정리를 자체 스크립트로 구현하려는 세션 — 삭제 직전에 반드시 읽을 것.
