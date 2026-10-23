# test-scope-gate-multi-pr.ps1 — scope-gate 의 "여러 PR 합산 판정" 회귀 테스트 (giip #3833)
#
# 왜 필요한가 (2026-10-18~19 실사고):
#   한 이슈를 여러 PR 로 구현하면(특히 giipdb/giipfaw/giipv3/giip-fde-agent 를 넘나드는 변경)
#   scope-gate 가 그 중 **primary PR 하나**만 판정에 실었다. 개별 PR 하나는 정의상 이슈 범위보다
#   좁으므로 **MISMATCH 가 구조적으로 보장**됐고, REVIEW → READY 되돌림이 3회 캡까지 반복됐다.
#   실측: isn 3833 은 PR 8개(giipdb #498/#499, giipfaw #216/#219/#220, giip-fde-agent #177/#178,
#   giipv3 #944 …)로 구현됐는데 되돌림 코멘트의 "평가한 PR" 은 **#939 하나**였다.
#   그 결과 사람 판단 대기(REVIEW)가 큐에서 사라지고 이미 머지된 이슈를 "처음부터 구현"으로 되돌렸다.
#
#   Get-IssuePrInfo 는 이미 `all`(레포 횡단 전체 PR)을 모아 두고 있었다 — 코멘트 증거로만 쓰고
#   판정에는 안 썼다. 수정은 그 `all` 을 판정에도 쓰는 것이다.
#
# 이 테스트가 고정하는 것(양방향 — 한쪽만 고정하면 게이트가 무력화되거나 오탐이 재발한다):
#   (A) 합산 판정   : PR 이 2개 이상이면 프롬프트에 **그 PR 들이 모두** 실리고,
#                     "개별 PR 이 좁은 것은 정상 / 합쳐서 판정하라" 지시가 포함된다.
#   (B) 하위호환    : PR 이 1개 이하이거나 목록이 없으면 **종전 단일 PR 프롬프트** 그대로여야 한다
#                     (게이트를 약화시키지 않는다 — 무관한 PR 하나로 완료 위조하는 것은 계속 막힌다).
#
# 실행: pwsh -File scripts/gissue/tests/test-scope-gate-multi-pr.ps1

$ErrorActionPreference = 'Stop'
$libPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'gissue-audit-lib.ps1'
if (-not (Test-Path $libPath)) { Write-Host "lib 없음: $libPath" -ForegroundColor Red; exit 1 }
. $libPath

$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  ok   $msg" }
    else { Write-Host "  FAIL $msg" -ForegroundColor Red; $script:fail++ }
}

# 판정 LLM 을 호출하지 않고 프롬프트만 가로채기 위해 Invoke-GissueJudge 를 덮어쓴다.
# (원본은 claude CLI 를 띄우므로 테스트에서 부를 수 없다.)
$script:CapturedPrompt = $null
function Invoke-GissueJudge($prompt, $model = 'ignored') {
    $script:CapturedPrompt = $prompt
    return @{ ok = $true; text = "MATCH`n테스트 스텁"; exit = 0 }
}

$issue = '[security] 파이프라인 구현 — 수집·게이트웨이·저장·화면까지'
$comments = '진행 코멘트들...'
$primary = @{ number = 939; slug = 'SHINSEMA/giipv3'; repo = 'C:\x\giipv3'; state = 'MERGED' }
$primaryDiff = @{ files = 'src/app/page.tsx'; diff = '--- a/src/app/page.tsx' }

Write-Host '== (A) PR 2개 이상 → 합산 판정 =='
$list = @(
    @{ info = @{ number = 939; slug = 'SHINSEMA/giipv3'; repo = 'r1'; state = 'MERGED' }; diff = @{ files = 'src/app/page.tsx'; diff = 'diff-v3' } },
    @{ info = @{ number = 498; slug = 'LowyShin/giipdb'; repo = 'r2'; state = 'MERGED' }; diff = @{ files = 'SP/pApiX.sql'; diff = 'diff-db' } },
    @{ info = @{ number = 219; slug = 'LowyShin/giipfaw'; repo = 'r3'; state = 'MERGED' }; diff = @{ files = 'giipJevGateway/run.ps1'; diff = 'diff-faw' } }
)
$script:CapturedPrompt = $null
$null = Invoke-ScopeMatchJudge 3833 $issue $comments $primary $primaryDiff $list
$p = "$script:CapturedPrompt"
Assert ($p -ne '') '프롬프트가 생성됐다'
Assert ($p -match '#939') 'PR #939 가 실렸다'
Assert ($p -match '#498') 'PR #498 이 실렸다(다른 레포)'
Assert ($p -match '#219') 'PR #219 가 실렸다(또 다른 레포)'
Assert ($p -match 'diff-db') '다른 레포 PR 의 diff 본문이 실렸다'
Assert ($p -match '개의 PR 로 구현') 'PR 개수를 판정기에 알렸다'
Assert ($p -match '합쳐서') '합산 판정 지시가 포함됐다'
Assert ($p -match '좁은 것이 정상') '개별 PR 이 좁은 것은 정상이라고 못박았다(오탐 차단)'

Write-Host '== (B) PR 1개 → 종전 단일 판정(하위호환) =='
$script:CapturedPrompt = $null
$null = Invoke-ScopeMatchJudge 1234 $issue $comments $primary $primaryDiff @(
    @{ info = @{ number = 939; slug = 'SHINSEMA/giipv3'; repo = 'r1'; state = 'MERGED' }; diff = $primaryDiff }
)
$p1 = "$script:CapturedPrompt"
Assert ($p1 -match '#939') '단일 PR 이 실렸다'
Assert ($p1 -notmatch '개의 PR 로 구현') '합산 문구가 없다(종전 프롬프트)'
Assert ($p1 -match '신고 범위보다 훨씬 좁은') '종전 질문 문구가 유지됐다(게이트 약화 없음)'

Write-Host '== (B-2) 목록 미전달 → 종전 단일 판정 =='
$script:CapturedPrompt = $null
$null = Invoke-ScopeMatchJudge 1234 $issue $comments $primary $primaryDiff
$p2 = "$script:CapturedPrompt"
Assert ($p2 -match '#939') '단일 PR 이 실렸다'
Assert ($p2 -notmatch '개의 PR 로 구현') '합산 문구가 없다'

Write-Host '== (C) 번호가 비정상인 항목은 합산에서 제외 =='
$script:CapturedPrompt = $null
$null = Invoke-ScopeMatchJudge 3833 $issue $comments $primary $primaryDiff @(
    @{ info = @{ number = ''; slug = 'x/y'; repo = 'r' }; diff = @{ files = 'f'; diff = 'd' } },
    @{ info = @{ number = $null; slug = 'x/y'; repo = 'r' }; diff = @{ files = 'f'; diff = 'd' } }
)
$p3 = "$script:CapturedPrompt"
Assert ($p3 -notmatch '개의 PR 로 구현') '유효 PR 이 1개 미만이면 합산 경로로 가지 않는다(giip #2504 원칙 유지)'

Write-Host ''
if ($fail -eq 0) { Write-Host 'ALL PASS' -ForegroundColor Green; exit 0 }
Write-Host "$fail FAILED" -ForegroundColor Red; exit 1
