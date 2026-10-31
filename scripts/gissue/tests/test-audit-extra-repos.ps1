# test-audit-extra-repos.ps1 - audit-extra-repos.json 재발 방지 테스트 (giip #4159/#3828 계열, #4336)
#
# 배경: PR-gate/review-done-audit 는 "workdir 자신 + 1단계 nested 레포 + lowyworkenv" 만 훑는다
#   (Get-NestedRepoPaths). 실제 소스가 별도 형제 체크아웃(예: /work/lordoflords)인 CSN 은 이 범위
#   밖이라, 대응 PR 이 머지돼 있어도 "PR 없음"으로 판정돼 REVIEW/DONE 이 READY 로 반복 되돌려졌다
#   (isn=4159 실측: PR #154/#155/#156/#157 전부 머지됐는데도 4회 되돌림 → NEEDS_DECISION).
#   해법은 audit-extra-repos.json 에 그 레포 slug 를 추가해 `gh pr list --repo <slug>` 직접 조회로
#   보완하는 것(giip #2504 최초 도입, #4290/#4336/giip-4159계열 로 slug 추가).
#
# 이 테스트가 고정하는 것: 과거에 이 패턴으로 추가된 slug 가 향후 편집(예: 다른 CSN 추가 중 실수로
# 삭제/오타)으로 다시 빠지면 즉시 실패해야 한다 — "조용히 빈 목록이 되는" 실패 모드(코드 자체는
# try/catch 로 게이트를 막지 않게 설계돼 있어 에러 없이 그냥 탐지 범위가 줄어든다, giip #2504 주석
# 참고)라 테스트 없이는 회귀를 아무도 못 본다.
#
# LLM/네트워크 없이 돈다 - audit-extra-repos.json 파싱과 Get-ExtraAuditRepoSlugs 만 검증한다.
#
# 실행: pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/gissue/tests/test-audit-extra-repos.ps1

$ErrorActionPreference = 'Stop'
$gissueDir = Split-Path -Parent $PSScriptRoot
. (Join-Path $gissueDir 'gissue-audit-lib.ps1')

$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  ok   $msg" }
    else { Write-Host "  FAIL $msg" -ForegroundColor Red; $script:fail++ }
}

$cfgPath = Join-Path $gissueDir 'audit-extra-repos.json'

Write-Host '== audit-extra-repos.json 스키마 =='
Assert (Test-Path -LiteralPath $cfgPath) '파일이 존재한다'
$raw = Get-Content -LiteralPath $cfgPath -Raw -Encoding UTF8
$json = $null
try { $json = $raw | ConvertFrom-Json } catch {}
Assert ($null -ne $json) '유효한 JSON 이다'
Assert ($null -ne $json.slugs -and @($json.slugs).Count -gt 0) 'slugs 배열이 비어있지 않다'
foreach ($s in @($json.slugs)) {
    Assert ("$s" -match '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') "slug '$s' 형식이 OWNER/REPO 이다"
}
$lower = @($json.slugs | ForEach-Object { "$_".ToLower() })
Assert (($lower | Select-Object -Unique).Count -eq $lower.Count) 'slugs 에 중복이 없다(대소문자 무시)'

Write-Host '== Get-ExtraAuditRepoSlugs() 결과 =='
$slugs = @(Get-ExtraAuditRepoSlugs)
Assert ($slugs.Count -gt 0) '빈 목록이 아니다(파일이 있는데 파싱이 깨지면 조용히 0건이 되는 회귀를 여기서 잡는다)'

# 회귀 고정 — 과거 "#4159/#3828 계열(별도 체크아웃 미탐지)" 패턴으로 추가된 slug 들이
# 향후 편집으로 다시 빠지면 이 테스트가 즉시 실패한다.
$required = @(
    'LowyShin/giipAgentLinux',   # giip #2504 최초 사례
    'LowyShin/giipAgentWin',     # giip #2504 최초 사례
    'LowyShin/caci-aqchat',      # giip #4290/#4336 (CSN 70423)
    'LowyShin/lordoflords'       # giip #4159/#3828 계열 (CSN 70371, isn=4159 PR #154~#157 미탐지 실측)
)
foreach ($r in $required) {
    $hit = @($slugs | Where-Object { $_.ToLower() -eq $r.ToLower() })
    Assert ($hit.Count -eq 1) "필수 slug '$r' 가 정확히 1회 등록돼 있다"
}

if ($fail -gt 0) { Write-Host "`n$fail 건 실패" -ForegroundColor Red; exit 1 }
Write-Host "`n전체 통과"
exit 0
