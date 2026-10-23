# test-recent-comment-filter.ps1 — "최근 코멘트됨" 판정의 회귀 테스트 (giip #3802)
#
# 왜 필요한가 (실사고):
#   review-done-audit.ps1 은 이 판정을 위해 이슈마다 Get-IssueComments 를 불렀다
#   (csn 47 의 DONE 만 1,202건 → 1,202회). giipIssueComments 호출 폭증의 원인이다.
#   목록 응답(pApiGiipIssueListbyAK)에 last_comment_date 가 이미 들어오므로 호출이 필요없다
#   (실측 2026-10-19: 1,202건 중 1,179건에 값이 있고, 없는 23건은 코멘트가 아예 없는 이슈다).
#
#   직전 수정 시도는 "값이 창 밖이면 코멘트 조회로 폴백" 으로 분기를 잘못 잡았다.
#   기본 창은 2시간이라 **대부분이 창 밖**이다(24시간 창으로 재도 창안 18 / 창밖 1,161).
#   그래서 1,202회 중 약 1,184회를 그대로 호출해 개선이 1.5% 에 그쳤다 — 고치려던 증상이 남는다.
#
# 이 테스트가 고정하는 것(양방향):
#   (A) 값이 있으면 호출 0 — 창 안이든 **창 밖이든** 코멘트를 조회하지 않는다(최적화 보존).
#   (B) 값이 없으면 폴백 — 코멘트를 조회해 정확히 판정한다(감사가 조용히 비지 않게).
#   (C) 판정 자체가 맞다 — 창 경계, 파싱 실패, lastCommentDate 별칭.
#
# 실행: powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gissue/tests/test-recent-comment-filter.ps1

$ErrorActionPreference = 'Stop'
$libPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'gissue-audit-lib.ps1'
if (-not (Test-Path $libPath)) { Write-Host "lib 없음: $libPath" -ForegroundColor Red; exit 1 }
. $libPath

$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  ok   $msg" }
    else { Write-Host "  FAIL $msg" -ForegroundColor Red; $script:fail++ }
}

# 호출부의 Parse-Utc 와 같은 역할(ISO8601 -> UTC datetime, 실패 시 $null)
$parseUtc = {
    param($s)
    if (-not $s) { return $null }
    try { return ([datetime]::Parse($s, [Globalization.CultureInfo]::InvariantCulture)).ToUniversalTime() }
    catch { return $null }
}

$now = [datetime]::SpecifyKind([datetime]::Parse('2026-10-19T09:00:00'), 'Utc')
$since = $now.AddHours(-2)   # 기본 창 2시간

# 폴백 호출 횟수를 세는 스크립트블록
$script:fetchCount = 0
$fetch = { $script:fetchCount++; return @(@{ regdate = '2026-10-19T08:30:00Z' }) }

function Run($issue) {
    $script:fetchCount = 0
    $r = Test-GissueRecentComment -Issue $issue -SinceRecent $since -FetchComments $fetch -ParseUtc $parseUtc
    return @{ res = $r; calls = $script:fetchCount }
}

Write-Host '== (A) last_comment_date 가 있으면 코멘트를 조회하지 않는다 =='
$inWindow = Run ([pscustomobject]@{ isn = 1; last_comment_date = '2026-10-19T08:30:00Z' })
Assert ($inWindow.res.HasRecent -eq $true) '창 안 -> 최근으로 판정'
Assert ($inWindow.calls -eq 0) '창 안 -> Get-IssueComments 호출 0회'
Assert ($inWindow.res.UsedFallback -eq $false) '창 안 -> 폴백 안 씀'

$outWindow = Run ([pscustomobject]@{ isn = 2; last_comment_date = '2026-10-01T00:00:00Z' })
Assert ($outWindow.res.HasRecent -eq $false) '창 밖 -> 최근 아님으로 판정'
Assert ($outWindow.calls -eq 0) '창 밖 -> Get-IssueComments 호출 0회 (이 회귀가 핵심이다)'
Assert ($outWindow.res.UsedFallback -eq $false) '창 밖 -> 폴백 안 씀'

Write-Host '== (B) 값이 없으면 코멘트 조회로 폴백한다 =='
$absent = Run ([pscustomobject]@{ isn = 3 })
Assert ($absent.calls -eq 1) '필드 없음 -> Get-IssueComments 1회'
Assert ($absent.res.UsedFallback -eq $true) '필드 없음 -> 폴백 사용 표시'
Assert ($absent.res.HasRecent -eq $true) '필드 없음 + 창 안 코멘트 -> 최근으로 판정'

$emptyStr = Run ([pscustomobject]@{ isn = 4; last_comment_date = '' })
Assert ($emptyStr.calls -eq 1) '빈 문자열은 값 없음으로 보고 폴백'

Write-Host '== (C) 판정 세부 =='
$boundary = Run ([pscustomobject]@{ isn = 5; last_comment_date = '2026-10-19T07:00:00Z' })
Assert ($boundary.res.HasRecent -eq $true) '창 경계(정확히 -2h)는 최근에 포함'

$justOut = Run ([pscustomobject]@{ isn = 6; last_comment_date = '2026-10-19T06:59:59Z' })
Assert ($justOut.res.HasRecent -eq $false) '경계 1초 전은 최근 아님'

$alias = Run ([pscustomobject]@{ isn = 7; lastCommentDate = '2026-10-19T08:00:00Z' })
Assert ($alias.res.HasRecent -eq $true) 'lastCommentDate 별칭도 인식'
Assert ($alias.calls -eq 0) '별칭도 조회 0회'

$garbage = Run ([pscustomobject]@{ isn = 8; last_comment_date = 'not-a-date' })
Assert ($garbage.res.HasRecent -eq $false) '파싱 실패는 최근 아님(조용히 최근 처리하지 않는다)'
Assert ($garbage.calls -eq 0) '파싱 실패도 조회 0회(값은 있었으므로)'

Write-Host ''
Write-Host '== 효과 환산(실측 분포 기준) =='
# 실측: 값 있음 1,179(창안 18 / 창밖 1,161), 값 없음 23
$callsBefore = 1202
$callsBranchAttempt = 1161 + 23      # 창 밖에서 폴백하던 직전 시도
$callsNow = 23                       # 값 없음만 폴백
Write-Host ("  종전 {0}회 -> 직전 시도 {1}회({2:P1} 감소) -> 현재 {3}회({4:P1} 감소)" -f `
    $callsBefore, $callsBranchAttempt, (1 - $callsBranchAttempt / $callsBefore), $callsNow, (1 - $callsNow / $callsBefore))

Write-Host ''
if ($fail -eq 0) { Write-Host 'ALL PASS' -ForegroundColor Green; exit 0 }
Write-Host "$fail FAILED" -ForegroundColor Red; exit 1
