# test-gate-debounce.ps1 — 게이트 디바운스(Get-IssueActivityDebounce) 회귀 테스트 (giip #4300)
#
# 왜 필요한가(실사고): 3회 누적 에스컬레이션이 작업 세션이 활발히 움직이던 구간의 체크에도 가산돼,
#   세션의 정상 handoff 와 게이트의 NEEDS_DECISION 강제 전이가 1분 4초 차로 레이스했다.
#
# 고정하는 것:
#   (A) 마지막 "작업 코멘트"가 창 안이면 Active — 스트라이크/에스컬레이션을 미룬다.
#   (B) 창 밖이면 Active=false — 정상 판정(무한 미룸 없음).
#   (C) 게이트 자신의 코멘트(되돌림/에스컬레이션/감사/verify 로그)는 활동으로 치지 않는다 — 게이트가
#       코멘트를 남길 때마다 스스로 디바운스를 연장하는 자기참조 루프 방지.
#   (D) MinIdleMinutes<=0 이면 꺼짐, 코멘트 없음/파싱 실패는 Active=false.
#
# 실행: powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gissue/tests/test-gate-debounce.ps1

$ErrorActionPreference = 'Stop'
$libPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'gissue-gate-tally-lib.ps1'
if (-not (Test-Path $libPath)) { Write-Host "lib 없음: $libPath" -ForegroundColor Red; exit 1 }
. $libPath

$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  ok   $msg" }
    else { Write-Host "  FAIL $msg" -ForegroundColor Red; $script:fail++ }
}

$now = [datetime]::SpecifyKind([datetime]::Parse('2026-10-31T06:59:10'), 'Utc')
function C($minAgo, $text) { [pscustomobject]@{ content = $text; regdate = $now.AddMinutes(-$minAgo).ToString('yyyy-MM-ddTHH:mm:ssZ') } }
$revMarker = '[PR-GATE-' + 'REVERT]'
$escMarker = '[PR-GATE-' + 'HUMAN-REVIEW]'

Write-Host '(A) 창 안의 작업 코멘트 -> Active'
$r = Get-IssueActivityDebounce @((C 30 '착수'), (C 1 '구현 진행 중')) 10 $now
Assert $r.Active '1분 전 작업 코멘트 -> Active'
Assert ($r.IdleMinutes -eq 1) 'IdleMinutes=1'

Write-Host '(B) 창 밖 -> 정상 판정'
$r = Get-IssueActivityDebounce @((C 11 '구현 진행 중')) 10 $now
Assert (-not $r.Active) '11분 전 작업 코멘트 -> Active 아님'

Write-Host '(C) 게이트 자신의 코멘트는 활동이 아니다'
$r = Get-IssueActivityDebounce @((C 60 '구현 완료'), (C 1 "$revMarker 대응 PR 없음")) 10 $now
Assert (-not $r.Active) '1분 전 되돌림 코멘트는 무시, 60분 전 작업 코멘트 기준'
$r = Get-IssueActivityDebounce @((C 60 '구현 완료'), (C 1 "$escMarker 에스컬레이션")) 10 $now
Assert (-not $r.Active) '에스컬레이션 코멘트 무시'
$r = Get-IssueActivityDebounce @((C 60 'x'), (C 1 '[REVIEW-AUDIT:WARN] 감사'), (C 1 '[VERIFY-RUN] out')) 10 $now
Assert (-not $r.Active) '감사/verify 로그 무시'

Write-Host '(D) 경계'
Assert (-not (Get-IssueActivityDebounce @((C 1 '작업')) 0 $now).Active) 'MinIdleMinutes=0 -> 끔'
Assert (-not (Get-IssueActivityDebounce @() 10 $now).Active) '코멘트 없음 -> Active 아님'
Assert (-not (Get-IssueActivityDebounce @([pscustomobject]@{ content = 'x'; regdate = 'garbage' }) 10 $now).Active) '시각 파싱 실패 -> Active 아님'

if ($fail -gt 0) { Write-Host "FAILED: $fail" -ForegroundColor Red; exit 1 }
Write-Host 'ALL PASS'
