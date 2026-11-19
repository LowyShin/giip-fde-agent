# REPO-MAINT(저장소 정비) 세션 "스크립트 사전 체크 게이트" 검증 (giip #5671).
# 실행: powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gissue/tests/test-repomaint-gate.ps1
# 네트워크/파일 쓰기 없음. lib/repomaint-gate.ps1 의 순수 함수(가짜 OpenPrs/StashList/RecentCommentIssueCount
# 포트)와, 러너 소스의 배선(게이트 호출·생략 메시지·gair 스위치·프롬프트 문구)이 맞는지 확인한다.
$ErrorActionPreference = 'Stop'
. (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../lib/repomaint-gate.ps1')).Path

$fail = 0
function Check($name, [bool]$ok, $detail) {
    if ($ok) { Write-Output "[PASS] $name" } else { $script:fail++; Write-Output "[FAIL] $name - $detail" }
}

# ── 가짜 포트 ──────────────────────────────────────────────────────────────────────────
# 열린 PR 목록(mergeable + statusCheckRollup) / stash 목록 출력 줄 / 최근 2시간 코멘트 이슈 수.
$script:openPrs = @()
$script:stashLines = @()
$script:recentCount = 0
$ports = @{
    OpenPrs                 = { $script:openPrs }
    StashList               = { $script:stashLines }
    RecentCommentIssueCount = { $script:recentCount }
}

function New-FakePr($number, $mergeable, $rollup) {
    return [pscustomobject]@{ number = $number; mergeable = $mergeable; statusCheckRollup = $rollup }
}
$noRollup = @()

# ── (A) 전부 0건 → 합계 0, Needed=false ──
$script:openPrs = @(); $script:stashLines = @(); $script:recentCount = 0
$resA = Get-RepoMaintTargetCounts -Ports $ports
Check 'A1 전부 0 → 합계 0' ($resA.Total -eq 0) "Total=$($resA.Total)"
Check 'A2 전부 0 → 단계별 0' (($resA.Stage0 -eq 0) -and ($resA.StageE -eq 0) -and ($resA.StageF -eq 0) -and ($resA.StageH -eq 0)) "S0=$($resA.Stage0) SE=$($resA.StageE) SF=$($resA.StageF) SH=$($resA.StageH)"
Check 'A3 전부 0 → Needed=false' (-not (Test-RepoMaintNeeded -Counts $resA)) ''

# ── (B) [0] conflict PR 1건 → Stage0=1, Needed=true ──
$script:openPrs = @(New-FakePr 101 'CONFLICTING' $noRollup); $script:stashLines = @(); $script:recentCount = 0
$resB = Get-RepoMaintTargetCounts -Ports $ports
Check 'B1 mergeable=CONFLICTING 1건 → Stage0=1' ($resB.Stage0 -eq 1) "Stage0=$($resB.Stage0)"
Check 'B2 [0] 만 존재 → 다른 단계 0' (($resB.StageE -eq 0) -and ($resB.StageF -eq 0) -and ($resB.StageH -eq 0)) "SE=$($resB.StageE) SF=$($resB.StageF) SH=$($resB.StageH)"
Check 'B3 [0] 1건 → Needed=true' (Test-RepoMaintNeeded -Counts $resB) ''

# ── (C) [E] CI 실패 PR 1건 → StageE=1 ──
$script:openPrs = @(New-FakePr 102 'MERGEABLE' @([pscustomobject]@{ __typename = 'CheckRun'; name = 'build'; status = 'COMPLETED'; conclusion = 'FAILURE' })); $script:stashLines = @(); $script:recentCount = 0
$resC = Get-RepoMaintTargetCounts -Ports $ports
Check 'C1 statusCheckRollup conclusion=FAILURE 1건 → StageE=1' ($resC.StageE -eq 1) "StageE=$($resC.StageE)"
Check 'C2 [E] 만 존재 → Stage0=0' ($resC.Stage0 -eq 0) "Stage0=$($resC.Stage0)"

# ── (C-2) StatusContext(state=FAILURE) 도 [E] 로 잡는다 ──
$script:openPrs = @(New-FakePr 103 'MERGEABLE' @([pscustomobject]@{ __typename = 'StatusContext'; context = 'ci'; state = 'FAILURE' }))
$resC2 = Get-RepoMaintTargetCounts -Ports $ports
Check 'C3 StatusContext state=FAILURE 도 StageE 로 집계' ($resC2.StageE -eq 1) "StageE=$($resC2.StageE)"

# ── (C-3) 성공만 있는 체크는 [E] 대상 아님 ──
$script:openPrs = @(New-FakePr 104 'MERGEABLE' @([pscustomobject]@{ name = 'build'; status = 'COMPLETED'; conclusion = 'SUCCESS' }))
$resC3 = Get-RepoMaintTargetCounts -Ports $ports
Check 'C4 conclusion=SUCCESS 는 StageE 로 집계되지 않는다' ($resC3.StageE -eq 0) "StageE=$($resC3.StageE)"

# ── (D) [F] orphan stash ──
$script:openPrs = @()
$script:stashLines = @(
    'stash@{0}: auto-unblock 2026-11-20 10:00: rescued from merged branch bot/task-giip-1234',
    'stash@{1}: WIP on branch: main: 일반 작업 잔해',
    'stash@{2}: auto-unblock-forced 2026-11-20 09:00: timeout-busy on bot/task-giip-1234'
)
$script:recentCount = 0
$resD = Get-RepoMaintTargetCounts -Ports $ports
Check 'D1 auto-unblock 접두사 stash 1건만 집계' ($resD.StageF -eq 1) "StageF=$($resD.StageF)"
Check 'D2 auto-unblock-forced 는 접두사 ''auto-unblock '' 가 아니므로 미집계' ($resD.StageF -eq 1) "StageF=$($resD.StageF)"

# ── (E) [H] 최근 코멘트 이슈 수 ──
$script:stashLines = @(); $script:recentCount = 3
$resE = Get-RepoMaintTargetCounts -Ports $ports
Check 'E1 최근 2시간 코멘트 이슈 3건 → StageH=3' ($resE.StageH -eq 3) "StageH=$($resE.StageH)"
Check 'E2 [H] 만 존재 → 다른 단계 0' (($resE.Stage0 -eq 0) -and ($resE.StageE -eq 0) -and ($resE.StageF -eq 0)) "S0=$($resE.Stage0) SE=$($resE.StageE) SF=$($resE.StageF)"

# ── (F) 단계별 1건씩 → 합계 4, Needed=true ──
$script:openPrs = @(
    New-FakePr 201 'CONFLICTING' $noRollup
    New-FakePr 202 'MERGEABLE' @([pscustomobject]@{ conclusion = 'FAILURE' })
)
$script:stashLines = @('stash@{0}: auto-unblock 2026-11-20 10:00: rescued from merged branch x')
$script:recentCount = 1
$resF = Get-RepoMaintTargetCounts -Ports $ports
Check 'F1 단계별 1건씩 → 합계 4' ($resF.Total -eq 4) "Total=$($resF.Total)"
Check 'F2 단계별 1건씩 → Needed=true' (Test-RepoMaintNeeded -Counts $resF) ''
Check 'F3 단계별 값 1/1/1/1' (($resF.Stage0 -eq 1) -and ($resF.StageE -eq 1) -and ($resF.StageF -eq 1) -and ($resF.StageH -eq 1)) "S0=$($resF.Stage0) SE=$($resF.StageE) SF=$($resF.StageF) SH=$($resF.StageH)"

# ── (G) 합계 계산: 2+3+1+4 = 10 ──
$script:openPrs = @(
    New-FakePr 301 'CONFLICTING' $noRollup
    New-FakePr 302 'CONFLICTING' $noRollup
    New-FakePr 303 'MERGEABLE' @([pscustomobject]@{ conclusion = 'FAILURE' })
    New-FakePr 304 'MERGEABLE' @([pscustomobject]@{ state = 'FAILURE' })
    New-FakePr 305 'MERGEABLE' @([pscustomobject]@{ conclusion = 'FAILURE' })
)
$script:stashLines = @('stash@{0}: auto-unblock x')
$script:recentCount = 4
$resG = Get-RepoMaintTargetCounts -Ports $ports
Check 'G1 합계 계산 2+3+1+4=10' ($resG.Total -eq 10) "Total=$($resG.Total) S0=$($resG.Stage0) SE=$($resG.StageE) SF=$($resG.StageF) SH=$($resG.StageH)"

# ── (H) 러너 소스 배선 점검 ──
$src = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../run-gissue-claude.ps1') -Raw -Encoding UTF8
Check 'H1 잡 스코프에서 lib/repomaint-gate.ps1 를 소싱한다' ($src -match "lib/repomaint-gate\.ps1") ''
Check 'H2 Get-RepoMaintTargetCounts 를 포트로 호출한다' ($src -match 'Get-RepoMaintTargetCounts\s+-Ports') ''
Check 'H3 Test-RepoMaintNeeded 로 판정한다' ($src -match 'Test-RepoMaintNeeded\s+-Counts') ''
Check 'H4 대상 0건이면 세션 기동 생략 메시지를 출력한다' ($src -match ([regex]::Escape('정비 대상 0건 — 세션 기동 생략(스크립트 사전 체크)'))) ''
Check 'H5 게이트 환경변수 GISSUE_REPO_MAINT_GATE 스위치가 있다' ($src -match 'GISSUE_REPO_MAINT_GATE') ''
Check 'H6 gair 환경변수 GISSUE_REPO_MAINT_GAIR 스위치가 있다' ($src -match 'GISSUE_REPO_MAINT_GAIR') ''
Check 'H7 gair 베이스 URL 을 쓴다' ($src -match ([regex]::Escape('https://giipfaw.azurewebsites.net/api/gair'))) ''
Check 'H8 gair 는 모델을 고정하지 않는다(--model 미지정)' (($src -match 'NoFixedModel') -and ($src -match 'ANTHROPIC_CUSTOM_HEADERS')) ''
Check 'H9 AK 파생에 정본 경로 get-ak.sh 를 쓴다' ($src -match ([regex]::Escape("get-ak.sh"))) ''
Check 'H10 [0]/[E] 조회에 gh pr list --json number,mergeable,statusCheckRollup 를 쓴다' ($src -match ([regex]::Escape('number,mergeable,statusCheckRollup'))) ''
Check 'H11 [F] 조회에 git stash list 를 쓴다' ($src -match ([regex]::Escape('git -C $repo stash list'))) ''
Check 'H12 [H] 조회에 list-issues.js --hours-back 2 를 쓴다' ($src -match ([regex]::Escape('--hours-back 2'))) ''
Check 'H13 게이트 실패는 fail-open 으로 세션을 띄운다' ($src -match 'fail-open') ''
Check 'H14 프롬프트에 0건 종료 규칙(기록 파일·PR 미생성)이 있다' (($src -match 'work_history 기록 파일을') -and ($src -match '만들지 말고, PR도 열지 말고, 조용히 종료하라')) ''
Check 'H15 정비 세션 캡($RepoMaintDeadlineMin)은 그대로다' ($src -match 'Invoke-GissueCappedJobWait \$repoMaintDeadlineMin') ''

if ($fail -gt 0) { Write-Output "FAILED: $fail"; exit 1 }
Write-Output 'ALL PASS'
