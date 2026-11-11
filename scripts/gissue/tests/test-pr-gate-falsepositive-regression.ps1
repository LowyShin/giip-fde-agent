# test-pr-gate-falsepositive-regression.ps1 - 알려진 오판 2건 재현 회귀 테스트 (giip #4840/#4839)
#
# 왜 필요한가: "대응 PR 없음" REVIEW→READY 되돌림이 27건 이상 누적됐다. 그중 알려진 두 건이
#   **다른 종류**의 오탐이라 "PR 탐색 범위"만 넓혀서는 잡히지 않는다:
#     (giip #4840) **판정 대상이 아닌 PR** 을 근거로 한 오탐 — 이 isn 을 브랜치/제목으로 선언한 PR 과
#                  "본문에서만 이 isn 을 인용한" PR 이 함께 있을 때, 인용만 한 PR 이 대표(판정 대상)로
#                  잡히면 무관한 diff 로 scope 판정이 MISMATCH → 잘못된 되돌림이 된다.
#     (giip #4839) **진행 코멘트 형식**을 이유로 2회 되돌림 — 사소한 형식 사유로 되돌려진 경우.
#                  → 되돌림은 "의뢰 항목 이행 여부(체크리스트)"가 UNFULFILLED 일 때만 일어나야 한다.
#
# 이 테스트가 고정하는 것:
#   (1) 대표 PR 은 "이 isn 을 선언한 PR" 이다(인용만 한 PR 이 아니다).
#   (2) 구룰(PR-gate/scope-gate/comment-gate)이 되돌림을 제안해도, 체크리스트 판정이 KEEP/HOLD/실패면
#       **되돌리지 않는다**. UNFULFILLED(미충족 항목 있음)일 때만 체크리스트 코멘트와 함께 되돌린다.
#   (3) 되돌림은 **체크리스트 코멘트를 남긴 뒤** 상태를 바꾼다(코멘트 없는 전이 금지).
#   (4) Gated 모드에서 구룰의 3개 되돌림 지점 전부가 게이트를 통과한다.
#
# LLM/네트워크 없이 돈다 - gh 조회와 Node 정본 경로를 스텁으로 교체한다.
#
# 실행: powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gissue/tests/test-pr-gate-falsepositive-regression.ps1

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$gissueDir = Split-Path -Parent $PSScriptRoot
. (Join-Path $gissueDir 'gissue-audit-lib.ps1')
. (Join-Path $gissueDir 'gissue-gate-tally-lib.ps1')

$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  ok   $msg" }
    else { Write-Host "  FAIL $msg" -ForegroundColor Red; $script:fail++ }
}

# gh 조회 스텁 — 전부 빈 결과(레포 스캔으로는 아무것도 못 찾는 상황).
function Invoke-GhPrQuery($repoSpec, $ghArgs) { return @() }

# Node 정본 경로 스텁 — "이 isn 을 선언한 PR(#901)" 과 "본문에서만 인용한 PR(#950)" 을 돌려준다.
# 대표(primary)는 #901 이어야 한다 — Node 정본이 그렇게 고른다(lib/pr-lookup-cli.mjs 의 rank 규칙).
$script:nodeResult = @{
    ok = $true; isn = 4840
    primary = @{ number = 901; url = 'https://github.com/OtherOrg/giipv3/pull/901'; title = 'fix(giip): 4840 수정'; state = 'MERGED'; headRefName = 'bot/task-giip-4840'; repo = 'slug:OtherOrg/giipv3'; slug = 'OtherOrg/giipv3'; how = 'org-branch' }
    all = @(
        @{ number = 901; url = 'https://github.com/OtherOrg/giipv3/pull/901'; title = 'fix(giip): 4840 수정'; state = 'MERGED'; headRefName = 'bot/task-giip-4840'; repo = 'slug:OtherOrg/giipv3'; slug = 'OtherOrg/giipv3'; how = 'org-branch' }
        @{ number = 950; url = 'https://github.com/OtherOrg/giipv3/pull/950'; title = 'fix: 문서 정정'; state = 'MERGED'; headRefName = 'docs/cleanup'; repo = 'slug:OtherOrg/giipv3'; slug = 'OtherOrg/giipv3'; how = 'org-pr' }
    )
    sources = @('org-branch', 'org-pr')
    errors = @()
}
function Get-IssuePrAttributionViaNode($isn, $repos, $Orgs = @()) { return $script:nodeResult }

$ISN = 4840
$REPOS = @('slug:OtherOrg/giipv3')

Write-Host '== (giip #4840) 판정 대상이 아닌 PR 을 근거로 삼지 않는다 =='
$script:PrAttributionCache = @{}
$attr = Get-IssuePrAttribution $ISN $REPOS @()
Assert (@($attr.Candidates).Count -eq 2) '두 PR 후보가 모두 수집된다(숨기지 않는다)'
Assert ($attr.HasPr) 'PR 이 존재한다고 판정된다(되돌림 근거가 사라진다)'
Assert ($attr.Primary -and [int]$attr.Primary.number -eq 901) '대표(판정 대상) PR 은 이 isn 을 선언한 #901 이다'
Assert ($attr.Primary -and [int]$attr.Primary.number -ne 950) '본문 인용만 한 #950 은 판정 대상이 아니다'
$script:PrAttributionCache = @{}
Assert (Test-IssueHasPr $ISN $REPOS @()) '1차 판정도 "PR 있음" 으로落到한다(대응 PR 없음 되돌림이 발생하지 않는다)'

Write-Host '== (giip #4839) 진행 코멘트 형식 사유로 되돌리지 않는다 =='
function New-Item6($n, $kind, $verdict, $text, $ev = '') {
    return [pscustomobject]@{ N = $n; Kind = $kind; Verdict = $verdict; Text = $text; Evidence = $ev }
}
$tally0 = @{ Total = 0; Counts = @{}; CountsText = '없음' }
# 코멘트 프로토콜/진행 형식은 "충족" 으로 판정된 상태 — 즉 구룰이 제안할 만한 사유가 없다.
$itemsMet = @(
    (New-Item6 1 'code' 'MET' '스크립트 수정' 'PR #901 머지 (https://github.com/OtherOrg/giipv3/pull/901)'),
    (New-Item6 2 'other' 'MET' '진행 코멘트 등록' '착수/테스트/검증방법 코멘트 모두 존재')
)
$d = Get-GatedRevertDecision $ISN (@{ Ok = $true; Decision = 'KEEP'; Items = $itemsMet; Reason = '전 항목 충족 2건' }) $tally0 3 @()
Assert ($d.Action -eq 'keep') '구룰이 되돌림을 제안해도 체크리스트 KEEP 이면 되돌리지 않는다'
Assert (-not $d.Comment) 'KEEP 일 때는 코멘트도 남기지 않는다(틱마다 쌓이지 않게)'
Assert (-not $d.Status) 'KEEP 일 때는 상태 전이가 없다'

# 판정 불가(근거 부족)여도 되돌리면 안 된다 — 오탐 비용이 더 크다(rule 49).
$itemsUndet = @((New-Item6 1 'other' 'UNDETERMINED' '외부 시스템 반영' '확인 필요'))
$d = Get-GatedRevertDecision $ISN (@{ Ok = $true; Decision = 'HOLD'; Items = $itemsUndet; Reason = '판정불가 1건' }) $tally0 3 @()
Assert ($d.Action -eq 'hold') '근거 부족(HOLD) 이면 보류 — 되돌리지 않는다'

Write-Host '== UNFULFILLED 일 때만 체크리스트 코멘트와 함께 되돌린다 =='
$itemsUnmet = @(
    (New-Item6 1 'code' 'MET' '스크립트 수정' 'PR #901 머지'),
    (New-Item6 2 'other' 'UNMET' '운영 서버 설정 반영', '코멘트에 반영 증거가 없다')
)
$d = Get-GatedRevertDecision $ISN (@{ Ok = $true; Decision = 'REVERT'; Items = $itemsUnmet; Reason = '미충족 1건 / 전체 2건' }) $tally0 3 @()
Assert ($d.Action -eq 'revert' -and $d.Status -eq 'READY') '미충족(UNFULFILLED) 일 때만 READY 로 되돌린다'
Assert ($d.Comment -match '## 의뢰 체크리스트 판정') '되돌림 전에 체크리스트 전문을 남긴다'
Assert ($d.Comment -match '운영 서버 설정 반영') '미충족 항목이 다음 세션 작업 범위로 명시된다'

Write-Host '== 되돌림은 코멘트 → 상태 전이 순서(코멘트 없는 전이 금지) =='
$sweepSrc = Get-Content -LiteralPath (Join-Path $gissueDir 'pr-gate-sweep.ps1') -Raw -Encoding UTF8
$fnIdx = $sweepSrc.IndexOf('function Invoke-ChecklistTransition')
$body = $sweepSrc.Substring($fnIdx, [Math]::Min(3000, $sweepSrc.Length - $fnIdx))
$commentIdx = $body.IndexOf("--comment-file")
$statusIdx = $body.IndexOf("--status")
Assert ($commentIdx -gt 0 -and $statusIdx -gt 0 -and $commentIdx -lt $statusIdx) '코멘트 등록이 상태 전이보다 먼저다'

Write-Host '== Gated 모드: 구룰의 되돌림 지점 3곳이 모두 게이트를 통과한다 =='
$gatedCalls = ([regex]::Matches($sweepSrc, 'Invoke-GatedRevertGate \$isn')).Count
Assert ($gatedCalls -eq 3) "PR-gate/scope-gate/comment-gate 3곳이 모두 체크리스트 게이트를 거친다 (실제 $gatedCalls)"
Assert ($sweepSrc -match "\[string\]\`$PrGateMode = ''") 'PrGateMode 스위치가 있다'
Assert ($sweepSrc -match 'Get-PrGateMode \$PrGateMode') 'PrGateMode 이 해석된다'
$rdaSrc = Get-Content -LiteralPath (Join-Path $gissueDir 'review-done-audit.ps1') -Raw -Encoding UTF8
Assert ($rdaSrc -match 'Get-PrGateMode \$PrGateMode') 'review-done-audit 도 같은 스위치를 쓴다'
Assert ($rdaSrc -match '\$gatedRevert') 'review-done-audit 도 되돌림을 체크리스트 판정으로 게이트한다'

Write-Host '== Shadow 비교 가능성: 구룰/신룰 결론이 같은 스키마로 기록된다 =='
Assert ($sweepSrc -match 'Invoke-ChecklistShadowJudge \$isn ''REVERT'' \$src') 'Gated 경로도 shadow 로그에 구룰(REVERT)·신룰 결론을 함께 남긴다'
Assert ($rdaSrc -match 'Write-ChecklistShadowRecord \$iss\.isn ''REVERT'' \$assess') 'review-done-audit 도 같은 스키마로 기록한다'

if ($fail -gt 0) { Write-Host "`n$fail 건 실패" -ForegroundColor Red; exit 1 }
Write-Host "`n전체 통과"
exit 0
