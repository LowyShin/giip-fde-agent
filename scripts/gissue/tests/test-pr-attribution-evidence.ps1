# test-pr-attribution-evidence.ps1 - 증거 기반 PR 귀속 + 체크리스트 되돌림 게이트 회귀 테스트
#                                  (giip #4840/#4839)
#
# 이 테스트가 고정하는 것:
#   (1) 귀속: 조직 전 레포(노드 정본 경로)·이슈 코멘트 PR 링크证据가 1차 판정에 반영된다.
#       - 레포 스캔 범위 밖의 PR 이 있어도 "PR 있음" 으로 판정된다(되돌림 오탐 방지).
#       - 머지 여부도 같은 증거로 판정된다.
#   (2) 증거 텍스트: Get-ChecklistPrEvidence 가 찾은 PR 을 근거로 싣는다.
#   (3) 되돌림 게이트: 순수 함수 Get-GatedRevertDecision —
#       판정 실패 → 전이 없음 / KEEP → 되돌리지 않음 / HOLD → 보류 /
#       REVERT(미충족=UNFULFILLED) → 체크리스트 코멘트와 함께 READY.
#       되돌림 코멘트에 **다른 게이트의 마커 원문이 없음**(되돌림 횟수 집계 오염 방지).
#   (4) 모드 해석: Gated(기본) | Shadow | Legacy.
#
# LLM/네트워크 없이 돈다 - Invoke-GhPrQuery 와 Get-IssuePrAttributionViaNode 을 스텁으로 교체한다.
#
# 실행: powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gissue/tests/test-pr-attribution-evidence.ps1

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

# ── 스텁 1: gh 조회 ───────────────────────────────────────────────────────────
# list(레포 스캔)=항상 빈 결과 → "레포 스캔 범위 밖" 상황을 재현한다.
# view(번호 지정)=지정한 PR 만 존재.
$script:stubLinks = @{}
function Invoke-GhPrQuery($repoSpec, $ghArgs) {
    $spec = "$repoSpec"
    if (@($ghArgs) -contains 'list') { return @() }
    if (@($ghArgs) -contains 'view') {
        $num = $null
        foreach ($a in @($ghArgs)) { if ("$a" -match '^\d+$') { $num = $a; break } }
        $key = "$spec#$num"
        if ($script:stubLinks.ContainsKey($key)) { return @($script:stubLinks[$key]) }
        return @()
    }
    return @()
}

# ── 스텁 2: Node 정본 경로(조직 전 탐색) ─────────────────────────────────────
# 레포 스캔으로는 절대 못 찾는 "다른 레포의 PR" 을 돌려주는 스텁.
$script:nodeResult = $null
function Get-IssuePrAttributionViaNode($isn, $repos, $Orgs = @()) {
    if ($script:nodeResult) { return $script:nodeResult }
    return @{ ok = $true; isn = [int]$isn; primary = $null; all = @(); sources = @(); errors = @() }
}

function Reset-AttributionCache { $script:PrAttributionCache = @{} }

$ISN = 4840

# 노드 경로가 "조직 전 레포에서 찾은 PR 2건" 을 돌려주도록 준비한다.
$script:nodeResult = @{
    ok = $true; isn = $ISN
    primary = @{ number = 901; url = 'https://github.com/OtherOrg/giipv3/pull/901'; title = 'fix(giip): 4840 수정'; state = 'MERGED'; headRefName = 'bot/task-giip-4840'; repo = 'slug:OtherOrg/giipv3'; slug = 'OtherOrg/giipv3'; how = 'org-branch' }
    all = @(
        @{ number = 901; url = 'https://github.com/OtherOrg/giipv3/pull/901'; title = 'fix(giip): 4840 수정'; state = 'MERGED'; headRefName = 'bot/task-giip-4840'; repo = 'slug:OtherOrg/giipv3'; slug = 'OtherOrg/giipv3'; how = 'org-branch' }
        @{ number = 902; url = 'https://github.com/OtherOrg/giipv3/pull/902'; title = 'fix: 4840 후속'; state = 'OPEN'; headRefName = 'fix/giip-4840-followup'; repo = 'slug:OtherOrg/giipv3'; slug = 'OtherOrg/giipv3'; how = 'org-pr' }
    )
    sources = @('org-branch', 'org-pr')
    errors = @()
}

Write-Host '== (1) 조직 목록 유도 =='
Assert (@(Get-AttributionOrgs @()).Count -eq 0) '레포 목록이 비면 조직도 비어 있다(네트워크 0 — 테스트 안전)'
$orgs = @(Get-AttributionOrgs @('slug:LowyShin/giipAgentLinux', 'slug:SHINSEMA/giipv3'))
Assert ($orgs.Count -eq 2 -and ($orgs -contains 'LowyShin') -and ($orgs -contains 'SHINSEMA')) 'slug:OWNER/REPO 에서 조직을 유도한다'
$savedOrgs = $env:GISSUE_GH_ORGS
try {
    $env:GISSUE_GH_ORGS = 'Acme, Beta'
    $o2 = @(Get-AttributionOrgs @())
    Assert ($o2.Count -eq 2 -and ($o2 -contains 'Acme') -and ($o2 -contains 'Beta')) '환경변수 GISSUE_GH_ORGS 로 조직을 지정할 수 있다'
} finally { $env:GISSUE_GH_ORGS = $savedOrgs }

Write-Host '== (2) 증거 기반 귀속 =='
Reset-AttributionCache
$attr = Get-IssuePrAttribution $ISN @() @()
Assert ($attr.HasPr) '노드(조직 전) 경로에서 찾은 PR 이 있으면 HasPr=true'
Assert ($attr.HasMerged) '머지된 PR 을 구분해 인식한다(HasMerged=true)'
Assert (@($attr.Candidates).Count -eq 2) '후보 2건이 모인다'
Assert (($attr.Sources -contains 'org-pr') -and ($attr.Sources -contains 'org-branch')) '탐색 경로가 기록된다'
Assert ($attr.Text -match 'PR #901') '증거 텍스트에 찾은 PR 이 실린다'
Assert ($attr.Text -match '탐색 경로') '증거 텍스트에 탐색 경로가 실린다'

# 이슈 본문/코멘트의 PR 링크(제품 레포) 경로가 합쳐지는지
$script:stubLinks['slug:SHINSEMA/giipv3#991'] = [pscustomobject]@{
    number = 991; state = 'MERGED'; url = 'https://github.com/SHINSEMA/giipv3/pull/991'
    title = 'fix: 링크로만 참조된 PR'; headRefName = 'fix/isn4840-x'; body = ''; mergedAt = '2026-11-01T00:00:00Z'
}
Reset-AttributionCache
$attr2 = Get-IssuePrAttribution $ISN @() @('https://github.com/SHINSEMA/giipv3/pull/991')
Assert (@($attr2.Candidates).Count -eq 3) '이슈 코멘트의 PR 링크 경로가 후보에 합쳐진다(3건)'
Assert (@($attr2.Candidates | Where-Object { $_.how -eq 'text-link' }).Count -eq 1) '링크 경로 후보는 how=text-link 로 구분된다'

Write-Host '== (3) 1차 판정에 증거 경로가 반영된다 =='
Reset-AttributionCache
Assert (Test-IssueHasPr $ISN @() @()) '레포 스캔 범위 밖(다른 레포)의 PR 이 있어도 "PR 있음" 판정'
Reset-AttributionCache
Assert (Test-IssueHasMergedPr $ISN @() @()) '같은 근거로 "머지된 PR 있음" 판정'
Reset-AttributionCache
$ev = Get-ChecklistPrEvidence $ISN @('slug:OtherOrg/giipv3') @()
Assert ($ev.Known -and $ev.HasAny -and $ev.HasMerged) '체크리스트 PR 증거가 증거 경로 결과를 반영한다'
Assert ($ev.Text -match 'PR #901') '체크리스트 PR 증거 텍스트에 찾은 PR 이 실린다'

Write-Host '== (4) 되돌림 게이트(체크리스트 판정이 UNFULFILLED 일 때만) =='
function New-Item5($n, $kind, $verdict, $text, $ev = '') {
    return [pscustomobject]@{ N = $n; Kind = $kind; Verdict = $verdict; Text = $text; Evidence = $ev }
}
$tally0 = @{ Total = 0; Counts = @{}; CountsText = '없음' }

$a = @{ Ok = $false; Decision = 'HOLD'; Items = @(); Reason = '판정 호출 실패' }
$d = Get-GatedRevertDecision $ISN $a $tally0 3 @()
Assert ($d.Action -eq 'skip' -and -not $d.Comment -and -not $d.Status) '판정 실패 → 전이 없음(근거 없이 되돌리지 않는다)'

$itemsMet = @((New-Item5 1 'other' 'MET' '문서 등록' '링크'))
$d = Get-GatedRevertDecision $ISN (@{ Ok = $true; Decision = 'KEEP'; Items = $itemsMet; Reason = '전 항목 충족 1건' }) $tally0 3 @()
Assert ($d.Action -eq 'keep' -and -not $d.Comment -and -not $d.Status) 'KEEP(전 항목 충족) → 되돌리지 않고 상태 유지'

$itemsUndet = @((New-Item5 1 'other' 'UNDETERMINED' '외부 시스템 반영' '확인 필요'))
$d = Get-GatedRevertDecision $ISN (@{ Ok = $true; Decision = 'HOLD'; Items = $itemsUndet; Reason = '판정불가 1건' }) $tally0 3 @()
Assert ($d.Action -eq 'hold') 'HOLD(근거 부족) → 보류'
Assert ($d.Comment -match '\[REVIEW-AUDIT:CHECKLIST-HOLD\]' -and $d.Comment -match '## 필요한 증거') 'HOLD 코멘트에 마커와 필요한 증거 절이 있다'

$itemsUnmet = @(
    (New-Item5 1 'other' 'MET' '문서 등록' '링크'),
    (New-Item5 2 'code' 'UNMET' '스크립트 수정' '수정 내역 없음')
)
$d = Get-GatedRevertDecision $ISN (@{ Ok = $true; Decision = 'REVERT'; Items = $itemsUnmet; Reason = '미충족 1건' }) $tally0 3 @()
Assert ($d.Action -eq 'revert' -and $d.Status -eq 'READY') 'REVERT(미충족=UNFULFILLED) → READY 되돌림'
Assert ($d.Comment -match '\[REVIEW-AUDIT:CHECKLIST-REVERT\]') '되돌림 전에 체크리스트 마커가 붙은 코멘트를 남긴다'
Assert ($d.Comment -match '## 의뢰 체크리스트 판정') '체크리스트 전문이 코멘트에 담긴다'
Assert ($d.Comment -match '## 미충족 항목') '미충족 항목이 다음 세션 작업 범위로 명시된다'
Assert ($d.Comment -match '이번이 1번째 되돌림입니다') '되돌림 회차가 표기된다'
Assert (-not ($d.Comment -match '\[PR-GATE-REVERT\]|\[SCOPE-GATE-REVERT\]|\[COMMENT-GATE-REVERT\]')) '구룰 게이트 마커 원문을 넣지 않는다(되돌림 횟수 집계 오염 방지)'

Write-Host '== (5) 되돌림 캡 / 동일 미충족 반복 =='
$tallyCap = @{ Total = 3; Counts = @{ 'PR-gate' = 3 }; CountsText = 'PR-gate=3회' }
$d = Get-GatedRevertDecision $ISN (@{ Ok = $true; Decision = 'REVERT'; Items = $itemsUnmet; Reason = '미충족 1건' }) $tallyCap 3 @()
Assert ($d.Action -eq 'escalate' -and $d.Status -eq 'NEEDS_DECISION') '전 게이트 합산 캡 도달 → 자동 되돌림 중단 + NEEDS_DECISION'
$prev = @([pscustomobject]@{ regdate = '2026-11-01T00:00:00Z'; content = (Format-ChecklistComment $ISN 'REVERT' @((New-Item5 2 'code' 'UNMET' '스크립트 수정' 'x')) 'r' 1 3) })
$d = Get-GatedRevertDecision $ISN (@{ Ok = $true; Decision = 'REVERT'; Items = $itemsUnmet; Reason = '미충족 1건' }) $tally0 3 $prev
Assert ($d.Action -eq 'escalate') '직전 체크리스트 되돌림과 같은 미충족 집합 → 반복으로 판단해 자동 되돌림 중단'

Write-Host '== (6) 모드 해석(기본 Gated) =='
$saved = $env:GISSUE_PR_GATE_MODE
try {
    $env:GISSUE_PR_GATE_MODE = ''
    Assert ((Get-PrGateMode) -eq 'Gated') '미지정 → Gated (근본 수정 경로가 기본)'
    Assert ((Get-PrGateMode 'legacy') -eq 'Legacy') "명시 'legacy' → Legacy (종전 동작)"
    Assert ((Get-PrGateMode 'SHADOW') -eq 'Shadow') "명시 'shadow' → Shadow (구룰 결정 + 신룰 기록)"
    Assert ((Get-PrGateMode 'whatever') -eq 'Gated') '알 수 없는 값 → Gated (오타가 오탐 경로를 되살리지 않게)'
    $env:GISSUE_PR_GATE_MODE = 'Legacy'
    Assert ((Get-PrGateMode) -eq 'Legacy') '환경변수 Legacy → Legacy'
    Assert ((Get-PrGateMode 'Gated') -eq 'Gated') '명시값이 환경변수보다 우선'
} finally { $env:GISSUE_PR_GATE_MODE = $saved }

if ($fail -gt 0) { Write-Host "`n$fail 건 실패" -ForegroundColor Red; exit 1 }
Write-Host "`n전체 통과"
exit 0
