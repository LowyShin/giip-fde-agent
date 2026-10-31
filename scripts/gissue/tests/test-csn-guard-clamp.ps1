# test-csn-guard-clamp.ps1 — 미매핑 CSN 가드의 응답 cSn 대조 회귀 테스트 (giip 4116 / 4139)
#
# 고정하는 것: 서버가 요청 csn 을 홈 csn 으로 클램프해 다른 csn 의 이슈를 돌려줘도(2026-10-22 거짓 양성 사고)
#   가드가 그 행을 요청 csn 의 이슈로 믿지 않는다.
#   (A) cSn == 요청 csn  -> 통과
#   (B) cSn != 요청 csn  -> SKIP-CLAMP 로그 + 버림
#   (C) cSn 없음/빈 값   -> SKIP-NOCSN 로그 + 버림
#   (D) 빈 입력은 빈 결과(침묵)
#
# 실행: powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gissue/tests/test-csn-guard-clamp.ps1

$ErrorActionPreference = 'Stop'
$libPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'lib/csn-guard.ps1'
if (-not (Test-Path $libPath)) { Write-Host "lib 없음: $libPath" -ForegroundColor Red; exit 1 }
. $libPath

$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  ok   $msg" }
    else { Write-Host "  FAIL $msg" -ForegroundColor Red; $script:fail++ }
}

$script:logs = @()
$log = { param($m) $script:logs += $m }

Write-Host '== (A) 응답 cSn 이 요청 csn 과 같으면 통과 =='
$script:logs = @()
$r = Select-GissueRowsMatchingCsn -Rows @([pscustomobject]@{ isn = 1; cSn = 70424 }, [pscustomobject]@{ isn = 2; cSn = '70424' }) -RequestedCsn '70424' -Log $log
Assert (@($r).Count -eq 2) '두 행 모두 통과 (숫자/문자열 cSn)'
Assert ($script:logs.Count -eq 0) '로그 없음(침묵)'

Write-Host '== (B) 클램프된 응답(요청 99999 -> 응답 cSn 47)은 버린다 =='
$script:logs = @()
$r = Select-GissueRowsMatchingCsn -Rows @([pscustomobject]@{ isn = 4026; cSn = 47 }, [pscustomobject]@{ isn = 4007; cSn = 47 }) -RequestedCsn '99999' -Log $log
Assert (@($r).Count -eq 0) '클램프 행 0건 통과 -> 거짓 코멘트 대상 0건'
Assert (@($script:logs | Where-Object { $_ -like '*SKIP-CLAMP*' }).Count -eq 2) 'SKIP-CLAMP 로그 2건'

Write-Host '== (C) cSn 필드 없음/빈 값은 버린다 =='
$script:logs = @()
$r = Select-GissueRowsMatchingCsn -Rows @([pscustomobject]@{ isn = 10 }, [pscustomobject]@{ isn = 11; cSn = $null }, [pscustomobject]@{ isn = 12; cSn = '' }) -RequestedCsn '70424' -Log $log
Assert (@($r).Count -eq 0) 'cSn 없는 행 0건 통과'
Assert (@($script:logs | Where-Object { $_ -like '*SKIP-NOCSN*' }).Count -eq 3) 'SKIP-NOCSN 로그 3건'

Write-Host '== 혼합 =='
$script:logs = @()
$r = Select-GissueRowsMatchingCsn -Rows @([pscustomobject]@{ isn = 1; cSn = 5 }, [pscustomobject]@{ isn = 2; cSn = 47 }, [pscustomobject]@{ isn = 3 }) -RequestedCsn '5' -Log $log
Assert (@($r).Count -eq 1 -and $r[0].isn -eq 1) '요청 csn 과 같은 행만 남는다'

Write-Host '== (D) 빈 입력 =='
$r = Select-GissueRowsMatchingCsn -Rows @() -RequestedCsn '5' -Log $log
Assert (@($r).Count -eq 0) '빈 배열 -> 빈 결과'
$r = Select-GissueRowsMatchingCsn -Rows $null -RequestedCsn '5' -Log $log
Assert (@($r).Count -eq 0) '$null -> 빈 결과'

if ($fail -gt 0) { Write-Host "FAIL $fail" -ForegroundColor Red; exit 1 }
Write-Host 'PASS'
exit 0
