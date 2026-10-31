# test-pr-link-evidence.ps1 - PR 이 nested repo 스캔 범위 밖에만 있을 때의 오탐 되돌림 재현/수정 검증 (giip #4335)
#
# 배경(실사고): 이슈 #4335 의 대응 PR(#991)이 SHINSEMA/giipv3 — csn-projects.json workdir(/work/dibo)의
#   nested repo도 아니고 audit-extra-repos.json 에도 없는 제품 레포 — 에만 있어서, Test-IssueHasPr(repos)가
#   레포 스캔만으로는 "PR 없음"으로 판정해 REVIEW→READY 되돌림이 4회 반복됐다(실제로는 이슈 본문·코멘트에
#   PR 링크가 명시돼 있었다). 이 테스트는 그 재현 + 수정(이슈 본문/코멘트의 PR 링크를 보조 증거로 인정)을
#   함께 고정한다.
#
# LLM/네트워크 없이 돈다 - gh 를 직접 부르는 Invoke-GhPrQuery 를 스텁으로 교체한다
#   (list 계열=레포 스캔 → 항상 빈 결과로 "스캔 범위 밖" 상황을 재현, view 계열=링크 검증 → 고정 응답).
#
# 실행: pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/gissue/tests/test-pr-link-evidence.ps1

$ErrorActionPreference = 'Stop'
$gissueDir = Split-Path -Parent $PSScriptRoot
. (Join-Path $gissueDir 'gissue-audit-lib.ps1')

$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  ok   $msg" }
    else { Write-Host "  FAIL $msg" -ForegroundColor Red; $script:fail++ }
}

# ── gh 스텁: list(레포 스캔)는 항상 빈 결과, view(번호 지정 조회)는 아래 고정 응답만 안다. ──
# #989 = 실제 isn4335 와 무관한, 먼저 머지돼 버린 "참고용" PR(제목/브랜치/본문에 4335 참조 없음).
# #991 = 이 isn 의 실제 대응 PR(제목에 "giip 4335", 브랜치에 "isn4335" — isn 참조 있음).
$script:stub991Merged = $null  # view 로 돌려줄 #991 의 mergedAt(테스트마다 바꿔 끼운다)
function Invoke-GhPrQuery($repoSpec, $ghArgs) {
    $spec = "$repoSpec"
    if (@($ghArgs) -contains 'list') { return @() }   # 레포 스캔: #4335 당시처럼 아무것도 못 찾는다
    if (@($ghArgs) -contains 'view') {
        if ($spec -eq 'slug:SHINSEMA/giipv3' -and (@($ghArgs) -contains '991')) {
            return @([pscustomobject]@{ number = 991; state = 'OPEN'; url = 'https://github.com/SHINSEMA/giipv3/pull/991'; title = 'fix(vercel): 라우트 복구 (giip 4335)'; headRefName = 'fix/isn4335-restore-vercel-config-routes'; body = ''; mergedAt = $script:stub991Merged })
        }
        if ($spec -eq 'slug:SHINSEMA/giipv3' -and (@($ghArgs) -contains '989')) {
            return @([pscustomobject]@{ number = 989; state = 'MERGED'; url = 'https://github.com/SHINSEMA/giipv3/pull/989'; title = 'fix(vercel): 토큰 안내 정정(팀별 /tokens 없음)'; headRefName = 'fix/vercel-token-guide-links-20261029'; body = '이 isn 과 무관한 별개 수정'; mergedAt = '2026-10-29T09:04:48Z' })
        }
        return @()   # 다른 슬러그/번호는 존재하지 않는 PR(오타 등) — 조용히 제외돼야 한다
    }
    return @()
}

$repos = @()  # /work/dibo nested repo 스캔 + audit-extra-repos.json 모두 giipv3 를 모른다고 가정
$issueBody = "## 작업 CSN`n70442. 관련 PR(문구 정정, 이 isn 과 무관): https://github.com/SHINSEMA/giipv3/pull/989`n"
$prCommentText = "PR: https://github.com/SHINSEMA/giipv3/pull/991 (base=main)"

Write-Host '== Get-PrLinksFromText =='
$links = @(Get-PrLinksFromText @($issueBody, $prCommentText))
Assert ($links.Count -eq 2) '본문·코멘트에 각각 있는 PR 링크 2건을 모두 추출(#989, #991)'
Assert (@($links | Where-Object { $_.Number -eq 991 -and $_.Slug -eq 'SHINSEMA/giipv3' }).Count -eq 1) '#991 슬러그/번호 정확히 파싱'
$dup = @(Get-PrLinksFromText @($prCommentText, $prCommentText))
Assert ($dup.Count -eq 1) '같은 링크 중복 텍스트는 1건으로 dedup'
$bad = @(Get-PrLinksFromText @('github.com/org/repo/pull/0', 'github.com/org/repo/pull/abc'))
Assert ($bad.Count -eq 0) '0 이하/비숫자 PR 번호는 거부(Test-ValidPrNumber 재사용)'

Write-Host '== #4335 재현: 레포 스캔만으로는 "PR 없음" (수정 전 동작, LinkTexts 생략) =='
$script:stub991Merged = $null
Assert (-not (Test-IssueHasPr 4335 $repos)) '인자 3개 중 LinkTexts 생략 -> 기존 동작과 동일(스캔 범위 밖 PR 은 못 찾음)'
Assert (-not (Test-IssueHasPr 4335 $repos @())) '빈 배열을 명시해도 동일 — 기존 호출부 회귀 없음'

Write-Host '== 수정 확인: 이슈 본문/코멘트의 PR 링크를 보조 증거로 인정 (giip #4335) =='
Assert (Test-IssueHasPr 4335 $repos @($issueBody, $prCommentText)) 'LinkTexts 전달 시 외부 레포(SHINSEMA/giipv3) PR #991 을 증거로 인정'
Assert (-not (Test-IssueHasMergedPr 4335 $repos @($issueBody, $prCommentText))) '#991(진짜 대응 PR)이 아직 OPEN -> 머지 판정은 false 유지'

$info = Get-IssuePrInfo 4335 $repos @($issueBody, $prCommentText)
Assert ($info -and [int]$info.number -eq 991) 'Get-IssuePrInfo 가 isn 참조 있는 #991 을 돌려준다(#989 아님)'
Assert ($info.slug -eq 'SHINSEMA/giipv3') 'Get-IssuePrInfo 가 슬러그를 돌려준다(gh --repo 호출에 필요)'
Assert ($info.how -eq 'text-link') 'how=text-link 로 어떤 경로(레포스캔 아님)로 찾았는지 구분 가능'

$ev = Get-ChecklistPrEvidence 4335 $repos @($issueBody, $prCommentText)
Assert ($ev.Known -and $ev.HasAny -and -not $ev.HasMerged) 'Get-ChecklistPrEvidence(체크리스트 경로)도 링크 증거로 대응 PR 존재를 인식 — Pr.HasAny=true 로 Get-ChecklistDecision 의 code-항목 보정이 UNDETERMINED 로 떨어지지 않는다'

Write-Host '== 회귀 재현(수정 전이면 실패했을 케이스): 무관한 PR 이 먼저 머지돼 있어도 오인하지 않는다 =='
# #989 은 mergedAt 이 항상 채워진 채로 응답하는 스텁이다(위 Invoke-GhPrQuery 참고) — isn 필터가
# 없다면 "#989 이 머지됐으니 isn4335 도 머지됨"으로 오판해 조기 DONE 위험이 있었다(실측 버그, 수정 커밋에서 고침).
Assert (-not (Test-IssueHasMergedPr 4335 $repos @($issueBody, $prCommentText))) '무관 PR(#989, 상시 머지됨 스텁)이 함께 링크돼 있어도 실제 대응 PR(#991)이 미머지면 머지 판정은 여전히 false'

Write-Host '== 머지되면(실제 대응 PR 자신이) 머지 판정도 true =='
$script:stub991Merged = '2026-10-31T06:00:00Z'
Assert (Test-IssueHasMergedPr 4335 $repos @($issueBody, $prCommentText)) '#991 이 머지되면(mergedAt 존재) 링크 경로로도 머지 판정 true'
$ev2 = Get-ChecklistPrEvidence 4335 $repos @($issueBody, $prCommentText)
Assert ($ev2.HasMerged) 'Get-ChecklistPrEvidence 도 머지 상태 반영'

Write-Host '== 무관한 레포/오타는 증거로 인정하지 않는다 =='
$script:stub991Merged = $null
$wrongText = "참고: https://github.com/someone/unrelated/pull/42"
Assert (-not (Test-IssueHasPr 4335 $repos @($wrongText))) '스텁이 모르는 슬러그/번호는 gh 조회가 빈 결과 -> 증거로 인정하지 않는다(과대 인정 방지)'
Assert (-not (Test-IssueHasPr 9999 $repos @($issueBody, $prCommentText))) '다른 isn(9999) 로 조회하면 #989/#991 모두 그 isn 참조가 없어 증거로 인정하지 않는다(isn 특이성 확인)'

if ($fail -gt 0) { Write-Host "`n$fail 건 실패" -ForegroundColor Red; exit 1 }
Write-Host "`n전체 통과"
exit 0
