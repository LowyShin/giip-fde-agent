# test-unmapped-csn-guard.ps1 — 미매핑 CSN 가드 판단 로직 회귀 테스트 (giip 4116 / 4139)
#
# 고정하는 것(네트워크 없음 — 스텁만 쓴다):
#   (A) 정본 판정 3값: MAPPED(등록+활성) / UNMAPPED(정본에 없음·비활성) / UNKNOWN(조회 실패)
#   (B) 응답 cSn 대조 게이트: 응답 cSn 이 요청 csn 과 다르면 SKIP-CLAMP, cSn 없으면 SKIP-NOCSN
#   (C) fail-closed: 정본 조회가 UNKNOWN 이면 **아무것도 쓰지 않는다**(수정 요구 2)
#   (D) 게시 단위: 원 이슈에 코멘트를 남기지 않고 csn 1건 운영 이슈만(게시 스위치 없으면 침묵)
#
# 실행: powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gissue/tests/test-unmapped-csn-guard.ps1

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$libDir = Join-Path $repoRoot 'scripts/gissue/lib'
. (Join-Path $libDir 'unmapped-csn-guard.ps1')

$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  ok   $msg" }
    else { Write-Host "  FAIL $msg" -ForegroundColor Red; $script:fail++ }
}

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("gissue-guard-test-" + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null

# 스텁 1: list-issues 대체 — GUARD_STUB_ROWS 가 가리키는 JSON 배열을 그대로 출력한다.
$listStub = Join-Path $tmp 'list-issues-stub.js'
@'
const fs = require('fs');
const rows = JSON.parse(fs.readFileSync(process.env.GUARD_STUB_ROWS, 'utf-8'));
process.stdout.write(JSON.stringify(rows));
'@ | Set-Content -LiteralPath $listStub -Encoding UTF8

# 스텁 2: 정본 조회 헬퍼 대체 — GUARD_STUB_MAP 이 가리키는 JSON 을 그대로 출력한다.
$mapStub = Join-Path $tmp 'get-csn-mapping-stub.js'
@'
const fs = require('fs');
process.stdout.write(fs.readFileSync(process.env.GUARD_STUB_MAP, 'utf-8'));
'@ | Set-Content -LiteralPath $mapStub -Encoding UTF8

function Write-Json($path, $obj) {
    [System.IO.File]::WriteAllText($path, ($obj | ConvertTo-Json -Depth 10), (New-Object System.Text.UTF8Encoding($false)))
}

Write-Host '== (A) 정본 판정 3값 =='
$v = Get-GissueCanonicalMappingStatus -Remote ([pscustomobject]@{ Found = $true; Enabled = $true; ProjectName = 'giipprj' })
Assert ($v.Status -eq 'MAPPED') '정본 등록+활성 → MAPPED'
$v = Get-GissueCanonicalMappingStatus -Remote ([pscustomobject]@{ Found = $true; Enabled = $false })
Assert ($v.Status -eq 'UNMAPPED') '정본 행 비활성 → UNMAPPED'
$v = Get-GissueCanonicalMappingStatus -Remote ([pscustomobject]@{ Found = $false; Reason = 'not_found' })
Assert ($v.Status -eq 'UNMAPPED') '정본에 없음(확인됨) → UNMAPPED'
$v = Get-GissueCanonicalMappingStatus -Remote ([pscustomobject]@{ Found = $false; Reason = 'scope_mismatch' })
Assert ($v.Status -eq 'UNKNOWN') '조회 불가(403) → UNKNOWN(침묵)'
$v = Get-GissueCanonicalMappingStatus -Remote ([pscustomobject]@{ Found = $false; Reason = 'error' })
Assert ($v.Status -eq 'UNKNOWN') '전송/파싱 실패 → UNKNOWN(침묵)'
$v = Get-GissueCanonicalMappingStatus -Remote ([pscustomobject]@{ Found = $false; Reason = 'invalid_row' })
Assert ($v.Status -eq 'UNKNOWN') '이상 행 → UNKNOWN(침묵)'

Write-Host '== (B) 응답 cSn 대조 게이트 =='
$logPath = Join-Path $tmp 'guard.log'
$rowsFile = Join-Path $tmp 'rows.json'
$env:GUARD_STUB_ROWS = $rowsFile
$env:GISSUE_CSNGUARD_OPS_CSN = ''

Write-Json $rowsFile @([pscustomobject]@{ isn = 4026; cSn = 47; status = 'READY' }, [pscustomobject]@{ isn = 4007; cSn = 47; status = 'PENDING' })
$kept = Get-GissueOpenIssuesAllCsn -CandidateCsns @('99999') -MappedCsns @() -ListIssuesScript $listStub `
    -GiipAccountsFile 'x' -ApiBase 'http://x' -LogFilePath $logPath
Assert (@($kept).Count -eq 0) '클램프된 응답(요청 99999 / 응답 cSn 47) → 0건 통과'
$logText = (Get-Content -LiteralPath $logPath -Raw -Encoding UTF8)
Assert (([regex]::Matches($logText, 'SKIP-CLAMP')).Count -eq 2) 'SKIP-CLAMP 로그 2건'

Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue
Write-Json $rowsFile @([pscustomobject]@{ isn = 4026; cSn = 99999; status = 'READY' })
$kept = Get-GissueOpenIssuesAllCsn -CandidateCsns @('99999') -MappedCsns @() -ListIssuesScript $listStub `
    -GiipAccountsFile 'x' -ApiBase 'http://x' -LogFilePath $logPath
Assert (@($kept).Count -eq 1) '응답 cSn 이 요청 csn 과 같으면 통과'
Assert (-not (Test-Path -LiteralPath $logPath)) '통과 시 SKIP 로그 없음(침묵)'

Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue
Write-Json $rowsFile @([pscustomobject]@{ isn = 4026; status = 'READY' })
$kept = Get-GissueOpenIssuesAllCsn -CandidateCsns @('99999') -MappedCsns @() -ListIssuesScript $listStub `
    -GiipAccountsFile 'x' -ApiBase 'http://x' -LogFilePath $logPath
Assert (@($kept).Count -eq 0) 'cSn 필드 없음 → 0건 통과'
$logText = (Get-Content -LiteralPath $logPath -Raw -Encoding UTF8)
Assert (([regex]::Matches($logText, 'SKIP-NOCSN')).Count -eq 1) 'SKIP-NOCSN 로그 1건'

Write-Host '== (C)(D) 게이트 본체 — 정본 판정과 게시 단위 =='
$mapFile = Join-Path $tmp 'csn-projects.json'
Write-Json $mapFile ([pscustomobject]@{ csn = [pscustomobject]@{ '99999' = [pscustomobject]@{ project = 'p'; workdir = 'C:/p'; enabled = $true } } })

# (C-1) 정본에 등록+활성 → 조회도 게시도 하지 않는다.
Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue
$mapJson = Join-Path $tmp 'map-mapped.json'
Write-Json $mapJson @{ found = $true; csn = 88888; projectName = 'giipprj'; workdir = 'C:/giipprj'; enabled = $true }
$env:GUARD_STUB_MAP = $mapJson
[void](Invoke-GissueUnmappedCsnGuard -MapFilePath $mapFile -CandidateCsns @('88888') `
    -ListIssuesScript $listStub -RegisterIssueScript 'none' -GiipAccountsFile 'x' -ApiBase 'http://x' `
    -LogFilePath $logPath -MappingHelperPath $mapStub -SkResolver { param($c) 'dummy-sk' })
$logText = (Get-Content -LiteralPath $logPath -Raw -Encoding UTF8)
Assert ($logText.Contains('SKIP-MAPPED-CANONICAL')) '정본 등록 csn → SKIP-MAPPED-CANONICAL 로그'
Assert (-not $logText.Contains('TEST-WOULD-POST')) '정본 등록 csn → 게시 없음'
Assert (-not $logText.Contains('SKIP-CLAMP')) '정본 등록 csn → 이슈 조회 자체를 하지 않음'

# (C-2) 정본 조회 불가(UNKNOWN) → 아무것도 쓰지 않는다(로컬로 되돌아가지 않는다).
Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue
$mapUnknown = Join-Path $tmp 'map-unknown.json'
Write-Json $mapUnknown @{ found = $false; reason = 'scope_mismatch'; detail = 'http_403' }
$env:GUARD_STUB_MAP = $mapUnknown
[void](Invoke-GissueUnmappedCsnGuard -MapFilePath $mapFile -CandidateCsns @('88888') `
    -ListIssuesScript $listStub -RegisterIssueScript 'none' -GiipAccountsFile 'x' -ApiBase 'http://x' `
    -LogFilePath $logPath -MappingHelperPath $mapStub -SkResolver { param($c) 'dummy-sk' })
$logText = (Get-Content -LiteralPath $logPath -Raw -Encoding UTF8)
Assert ($logText.Contains('SKIP-CANONICAL-UNKNOWN')) '정본 조회 불가 → SKIP-CANONICAL-UNKNOWN 로그'
Assert (-not $logText.Contains('TEST-WOULD-POST')) '정본 조회 불가 → 게시 없음(fail-closed)'

# (D-1) 정본에 없음(확인) + 미매핑 이슈 존재 → 게시 단위 csn 1건(게시 스위치 없으면 침묵 로그).
Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue
$mapNone = Join-Path $tmp 'map-none.json'
Write-Json $mapNone @{ found = $false; reason = 'not_found'; detail = '' }
$env:GUARD_STUB_MAP = $mapNone
Write-Json $rowsFile @([pscustomobject]@{ isn = 4026; cSn = 88888; status = 'READY' }, [pscustomobject]@{ isn = 4007; cSn = 88888; status = 'PENDING' })
[void](Invoke-GissueUnmappedCsnGuard -MapFilePath $mapFile -CandidateCsns @('88888') `
    -ListIssuesScript $listStub -RegisterIssueScript 'none' -GiipAccountsFile 'x' -ApiBase 'http://x' `
    -LogFilePath $logPath -MappingHelperPath $mapStub -SkResolver { param($c) 'dummy-sk' })
$logText = (Get-Content -LiteralPath $logPath -Raw -Encoding UTF8)
Assert ($logText.Contains('csn=88888, 미처리 이슈 isn=[4026,4007]')) '미매핑 csn 의 이슈 목록 로그'
Assert ($logText.Contains('SKIP-NOOPSCSN')) 'GISSUE_CSNGUARD_OPS_CSN 미지정 → 게시 없음(로그만)'
Assert (-not $logText.Contains('POSTED:')) 'POSTED 없음(실제 등록 없음)'

# (D-2) 같은 조건에서 게시 스위치(-SkipPosting) → 무엇을 올릴지만 로그에 남는다(게시 1건 = csn 1건).
#       (운영 이슈를 받을 csn 이 지정된 상태에서 — 지정 없으면 침묵이 우선이라(SKIP-NOOPSCSN) 게시는 안 한다)
Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue
$env:GISSUE_CSNGUARD_OPS_CSN = '70424'
[void](Invoke-GissueUnmappedCsnGuard -MapFilePath $mapFile -CandidateCsns @('88888') `
    -ListIssuesScript $listStub -RegisterIssueScript 'none' -GiipAccountsFile 'x' -ApiBase 'http://x' `
    -LogFilePath $logPath -MappingHelperPath $mapStub -SkResolver { param($c) 'dummy-sk' } -SkipPosting)
$logText = (Get-Content -LiteralPath $logPath -Raw -Encoding UTF8)
Assert ($logText.Contains('TEST-WOULD-POST')) '게시 스위치 → TEST-WOULD-POST 로그'
Assert (([regex]::Matches($logText, 'TEST-WOULD-POST')).Count -eq 1) '게시 단위는 csn 1건(중복 게시 없음)'
Assert ($logText.Contains('[OPS] csn 88888 담당 배포 없음')) '운영 이슈 제목 형식(수정 요구 3)'

Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
if ($fail -gt 0) { Write-Host "FAIL $fail" -ForegroundColor Red; exit 1 }
Write-Host 'PASS'
exit 0
