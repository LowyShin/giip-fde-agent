# test-ai-name.ps1 — 로컬 AI 이름(aiName) 구조의 소스 단언 회귀 테스트
# 실행: pwsh -NoProfile -File scripts/gissue/tests/test-ai-name.ps1
# 네트워크·실제 스케줄러를 건드리지 않는다 — 하드코딩 제거와 배선을 소스로 고정한다.
$ErrorActionPreference = 'Stop'
$script:Pass = 0; $script:Fail = 0
function Assert-True([bool]$Cond, [string]$Name) {
    if ($Cond) { $script:Pass++; Write-Host "  PASS: $Name" }
    else { $script:Fail++; Write-Host "  FAIL: $Name" }
}

$gissueRoot = Split-Path $PSScriptRoot -Parent

Write-Host '== PS 스크립트에 하드코딩된 actor 할당이 없다 =='
$offenders = @()
foreach ($f in (Get-ChildItem -LiteralPath $gissueRoot -Filter '*.ps1' -File)) {
    # 주석 줄(옛 코드를 인용하는 설명)은 제외하고 실제 할당만 본다.
    $codeOnly = ((Get-Content -Encoding UTF8 $f.FullName) | Where-Object { $_ -notmatch '^\s*#' }) -join "`n"
    if ($codeOnly -match '\$env:GIIP_ACTOR\s*=\s*''ai\.') { $offenders += $f.Name }
}
Assert-True ($offenders.Count -eq 0) "하드코딩 할당 잔존: $($offenders -join ', ')"

Write-Host '== 러너가 aiName 을 해석해 env 로 확정하고 [ACTOR] 로그를 남긴다 =='
$runner = Get-Content -Raw -Encoding UTF8 (Join-Path $gissueRoot 'run-gissue-claude.ps1')
Assert-True ($runner -match 'MapRoot\.aiName') '러너가 MapRoot.aiName 을 읽는다'
Assert-True ($runner -match '\[ACTOR\]') '러너가 [ACTOR] 로그를 남긴다'
Assert-True ($runner -match 'resolve-actor\.js') '러너가 해석 정본(resolve-actor.js)을 경유한다'
Assert-True ($runner -match 'reviewRecheckBotAuthors \+= \$env:GIIP_ACTOR') '재검증 쿨다운의 자기 author 목록에 확정 주체를 더한다'

Write-Host '== 독립 스크립트들이 같은 해석을 탄다 =='
foreach ($name in @('review-done-audit.ps1', 'pr-gate-sweep.ps1', 'pr-attribution-sweep.ps1', 'review-merged-presweep.ps1', 'page-feedback-analyze.ps1')) {
    $text = Get-Content -Raw -Encoding UTF8 (Join-Path $gissueRoot $name)
    Assert-True ($text -match 'resolve-actor\.js') "$name 이 resolve-actor.js 를 경유한다"
}

Write-Host '== 표시 이름(hostname 폴백) 전송 배선 =='
$commentApi = Get-Content -Raw -Encoding UTF8 (Join-Path $gissueRoot 'lib/comment-api.js')
Assert-True ($commentApi -match 'body\.author = author') 'comment-api 가 author 필드를 body 에 싣는다'
$postComment = Get-Content -Raw -Encoding UTF8 (Join-Path $gissueRoot 'lib/post-comment.js')
Assert-True ($postComment -match 'resolveAuthorDisplayName') 'post-comment 가 표시 이름을 해석해 전송한다'
$resolver2 = Get-Content -Raw -Encoding UTF8 (Join-Path $gissueRoot 'lib/resolve-actor.js')
Assert-True ($resolver2 -match 'pickAuthorDisplayName') '표시 이름 판정 pickAuthorDisplayName 이 해석기에 있다'
Assert-True ($runner -match 'hostname') '러너의 [ACTOR] 미설정 로그가 hostname 전송을 알린다'

Write-Host '== 예시 파일·해석기 커플링 =='
$example = Get-Content -Raw -Encoding UTF8 (Join-Path $gissueRoot 'csn-projects.json.example')
Assert-True ($example -match '"aiName"') 'csn-projects.json.example 에 aiName 키가 있다'
$resolver = Get-Content -Raw -Encoding UTF8 (Join-Path $gissueRoot 'lib/resolve-actor.js')
Assert-True ($resolver -match 'pickActorKey') '해석기에 순수 판정 pickActorKey 가 있다'
Assert-True ($resolver -match 'csn-projects\.json#aiName') '출처 표기에 config:csn-projects.json#aiName 이 있다'

Write-Host ''
Write-Host "결과: PASS=$script:Pass FAIL=$script:Fail"
if ($script:Fail -gt 0) { exit 1 }
