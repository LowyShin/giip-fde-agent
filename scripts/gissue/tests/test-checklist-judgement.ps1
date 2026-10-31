# test-checklist-judgement.ps1 - 의뢰 체크리스트 판정(giip #4334)의 판정 케이스 테스트
#
# 이 테스트가 고정하는 것(이슈 4334 완료조건 3):
#   (1) PR 없는 정당 완료 -> 유지(KEEP)        : 비코드 항목이 전부 충족이면 PR 이 없어도 되돌리지 않는다.
#   (2) 복수 항목 중 일부 미충족 -> 그 항목만 명시해 되돌림(REVERT)
#   (3) 증거 부족(판정불가만) -> 되돌리지 않고 보류(HOLD -> NEEDS_DECISION), 호출 실패/빈 응답도 전이 없음
#   (4) 코드 항목 -> PR 머지를 증거로 사용(머지 없으면 충족 주장을 보정)
#   + 코멘트 의무(모든 판정 본문에 체크리스트), 되돌림 횟수 집계, 반복 감지, 모드 해석(기본 Shadow).
# LLM/네트워크 없이 돈다 - Invoke-GissueJudge 를 스텁으로 교체한다.
#
# 실행: powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gissue/tests/test-checklist-judgement.ps1

$ErrorActionPreference = 'Stop'
$gissueDir = Split-Path -Parent $PSScriptRoot
. (Join-Path $gissueDir 'gissue-audit-lib.ps1')
. (Join-Path $gissueDir 'gissue-gate-tally-lib.ps1')

$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  ok   $msg" }
    else { Write-Host "  FAIL $msg" -ForegroundColor Red; $script:fail++ }
}

function New-Item4($n, $kind, $verdict, $text, $ev = '') {
    return [pscustomobject]@{ N = $n; Kind = $kind; Verdict = $verdict; Text = $text; Evidence = $ev }
}
$prMerged = @{ Known = $true; HasMerged = $true; HasAny = $true }
$prOpen = @{ Known = $true; HasMerged = $false; HasAny = $true }
$prNone = @{ Known = $true; HasMerged = $false; HasAny = $false }
$prUnknown = @{ Known = $false; HasMerged = $false; HasAny = $false }

Write-Host '== (1) PR 없는 정당 완료 -> KEEP =='
$items = @(
    (New-Item4 1 'other' 'MET' '문서 등록' '코멘트 1: 문서 경로 docs/x.md 등록 완료'),
    (New-Item4 2 'other' 'MET' '외부 설정 반영' '코멘트 2: 설정 화면 캡처 링크')
)
$d = Get-ChecklistDecision $items $prNone
Assert ($d.Decision -eq 'KEEP') 'PR 없음 + 비코드 항목 전부 충족 -> KEEP (PR 유무로 되돌리지 않는다)'
$body = Format-ChecklistComment 1 $d.Decision $d.Items $d.Reason
Assert ($body.Contains('[REVIEW-AUDIT:CHECKLIST-KEEP]')) 'KEEP 코멘트 마커'
Assert (-not $body.Contains('## 미충족 항목')) 'KEEP 코멘트에는 미충족 절이 없다'

Write-Host '== (2) 복수 항목 중 일부 미충족 -> 그 항목만 명시해 REVERT =='
$items = @(
    (New-Item4 1 'other' 'MET' '문서 등록' '코멘트 링크'),
    (New-Item4 2 'code' 'MET' '스크립트 수정' 'PR 머지'),
    (New-Item4 3 'other' 'UNMET' '운영 서버 설정 변경' '변경했다는 증적이 없다'),
    (New-Item4 4 'other' 'UNDETERMINED' '고객 통보' '외부 확인 필요')
)
$d = Get-ChecklistDecision $items $prMerged
Assert ($d.Decision -eq 'REVERT') '미충족 1건이라도 있으면 REVERT'
$body = Format-ChecklistComment 7 $d.Decision $d.Items $d.Reason 2 3
Assert ($body.Contains('[REVIEW-AUDIT:CHECKLIST-REVERT]')) 'REVERT 코멘트 마커'
Assert ($body.Contains('이번이 2번째 되돌림입니다')) '되돌림 회차 표기'
Assert ($body.Contains('- [x] (C1,')) '충족 항목은 [x] 로 표시'
Assert ($body.Contains('- [ ] (C3,')) '미충족 항목은 [ ] 로 표시'
$cs = @([pscustomobject]@{ regdate = '2026-10-31T01:00:00Z'; content = $body })
$unmet = @(Get-LatestUnmetChecklistItems $cs)
Assert ($unmet.Count -eq 1 -and $unmet[0].N -eq 3 -and $unmet[0].Text -eq '운영 서버 설정 변경') '후속 세션이 읽는 미충족 목록 = 미충족 항목 1건만(충족/판정불가 제외)'

Write-Host '== (3) 증거 부족 -> 되돌리지 않고 HOLD =='
$items = @(
    (New-Item4 1 'other' 'MET' '문서 등록' '링크'),
    (New-Item4 2 'other' 'UNDETERMINED' '외부 시스템 반영' '외부 시스템 상태 확인 필요')
)
$d = Get-ChecklistDecision $items $prNone
Assert ($d.Decision -eq 'HOLD') '판정불가만 있으면 HOLD(되돌림 아님)'
$body = Format-ChecklistComment 1 $d.Decision $d.Items $d.Reason
Assert ($body.Contains('[REVIEW-AUDIT:CHECKLIST-HOLD]') -and $body.Contains('## 필요한 증거')) 'HOLD 코멘트에 필요한 증거 절'
Assert ((Get-GateRevertTally @([pscustomobject]@{ regdate = 'x'; content = $body })).Total -eq 0) 'HOLD 코멘트는 되돌림 횟수에 안 센다'
$d0 = Get-ChecklistDecision @() $prNone
Assert ($d0.Decision -eq 'HOLD') '항목 0건(분해 실패) -> HOLD'

Write-Host '== (4) 코드 항목은 PR 머지를 증거로 사용 =='
$code = @((New-Item4 1 'code' 'MET' '버그 수정' '수정했다고 보고'))
Assert ((Get-ChecklistDecision $code $prMerged).Decision -eq 'KEEP') '코드 항목 + 머지된 PR -> 충족 유지'
$d = Get-ChecklistDecision $code $prOpen
Assert ($d.Decision -eq 'REVERT' -and $d.Items[0].Verdict -eq 'UNMET') '코드 항목 + 미머지 PR -> UNMET 로 보정'
$d = Get-ChecklistDecision $code $prNone
Assert ($d.Decision -eq 'HOLD' -and $d.Items[0].Verdict -eq 'UNDETERMINED') '코드 항목 + PR 없음 -> 판정불가(근거 없이 되돌리지 않음)'
$codeCommit = @((New-Item4 1 'code' 'MET' '버그 수정' 'https://example.com/org/repo/commit/0123456789abcdef'))
Assert ((Get-ChecklistDecision $codeCommit $prNone).Decision -eq 'KEEP') '코드 항목 + 커밋 링크 증거 -> 충족 인정'
Assert ((Get-ChecklistDecision $code $prUnknown).Decision -eq 'KEEP') 'PR 조회 불가(Known=false)면 보정하지 않는다'
$nonCode = @((New-Item4 1 'other' 'MET' '문서 등록' '링크'))
Assert ((Get-ChecklistDecision $nonCode $prOpen).Decision -eq 'KEEP') '비코드 항목은 미머지 PR 이 있어도 영향 없음'

Write-Host '== 응답 파싱 =='
$raw = @'
다음은 판정입니다.
ITEM|code|MET|스크립트 수정|PR 머지 | 링크 포함
- ITEM|other|UNMET|문서 등록|증적 없음
ITEM|other|MAYBE|이상한 판정|근거
ITEM|weird|MET|분류 이상|근거
ITEM|other|MET||빈 항목
ITEM|other|MET
'@
$p = @(ConvertFrom-ChecklistJudgeOutput $raw)
Assert ($p.Count -eq 4) '형식 맞는 줄만 항목으로 (머리말/빈 항목/필드 부족 제외) = 4건'
Assert ($p[0].Evidence -eq 'PR 머지 | 링크 포함') '근거 필드 안의 | 는 보존'
Assert ($p[1].Verdict -eq 'UNMET' -and $p[1].N -eq 2) '불릿 접두사 허용 + 번호 부여'
Assert ($p[2].Verdict -eq 'UNDETERMINED') '알 수 없는 판정값 -> 판정불가(보수적)'
$p4 = @(ConvertFrom-ChecklistJudgeOutput 'ITEM|weird|MET|분류 이상|근거')
Assert ($p4[0].Kind -eq 'other') '알 수 없는 kind -> other'
$p5 = @(ConvertFrom-ChecklistJudgeOutput "라벨|code|MET|항목 본문|근거 본문`n설명 | 문장 | 이다 | 아님 | 그냥")
Assert ($p5.Count -eq 1 -and $p5[0].Text -eq '항목 본문' -and $p5[0].Kind -eq 'code') 'ITEM 접두사 누락(<라벨>|kind|판정|항목|근거) 변형을 인정하고, 설명문은 오인하지 않는다'

Write-Host '== 코멘트 의무 / 집계 =='
foreach ($dec in @('KEEP', 'HOLD', 'REVERT')) {
    $b = Format-ChecklistComment 5 $dec @((New-Item4 1 'other' 'UNMET' 'x' 'y')) 'r'
    Assert ($b.Contains('## 의뢰 체크리스트 판정')) "$dec 코멘트는 항상 체크리스트 전문을 담는다"
}
$rev = Format-ChecklistComment 5 'REVERT' @((New-Item4 1 'other' 'UNMET' 'x' 'y')) 'r' 1 3
$tally = Get-GateRevertTally @([pscustomobject]@{ regdate = '2026-10-31T01:00:00Z'; content = $rev })
Assert ($tally.Total -eq 1 -and $tally.Counts['checklist'] -eq 1) 'CHECKLIST-REVERT 는 되돌림 횟수에 정확히 1회 집계(다른 게이트와 중복 없음)'
Assert (-not $rev.Contains('[PR-GATE-' + 'REVERT]') -and -not $rev.Contains('[SCOPE-GATE-' + 'REVERT]')) '다른 게이트 마커 원문을 넣지 않는다(카운팅 오염 방지)'

Write-Host '== 반복 감지 =='
$same = @((New-Item4 1 'other' 'UNMET' '운영  서버 설정 변경' 'a'), (New-Item4 2 'other' 'MET' '문서' 'b'))
$prevBody = Format-ChecklistComment 5 'REVERT' @((New-Item4 1 'other' 'UNMET' '운영 서버 설정 변경' 'a')) 'r' 1 3
$prevComments = @([pscustomobject]@{ regdate = '2026-10-31T01:00:00Z'; content = $prevBody })
Assert (Test-ChecklistUnmetRepeat $prevComments $same) '같은 미충족 집합(공백 차이 무시) -> 반복'
Assert (-not (Test-ChecklistUnmetRepeat $prevComments @((New-Item4 1 'other' 'UNMET' '다른 항목' 'a')))) '다른 미충족 집합 -> 반복 아님'
Assert (-not (Test-ChecklistUnmetRepeat @() $same)) '이전 되돌림 없음 -> 반복 아님'

Write-Host '== 모드 해석(기본 Shadow, Live 는 명시적으로만) =='
$saved = $env:GISSUE_CHECKLIST_MODE
try {
    $env:GISSUE_CHECKLIST_MODE = ''
    Assert ((Get-ChecklistMode) -eq 'Shadow') '미지정 -> Shadow (신규 로직 기본은 판정만, 전이 없음)'
    Assert ((Get-ChecklistMode 'live') -eq 'Live') "명시 'live' -> Live"
    Assert ((Get-ChecklistMode 'off') -eq 'Off') "명시 'off' -> Off"
    Assert ((Get-ChecklistMode 'whatever') -eq 'Shadow') '알 수 없는 값 -> Shadow (안전 쪽)'
    $env:GISSUE_CHECKLIST_MODE = 'Live'
    Assert ((Get-ChecklistMode) -eq 'Live') '환경변수 Live -> Live'
    Assert ((Get-ChecklistMode 'Off') -eq 'Off') '명시값이 환경변수보다 우선'
} finally { $env:GISSUE_CHECKLIST_MODE = $saved }

Write-Host '== Invoke-ChecklistAssessment (LLM 스텁) =='
function Invoke-GissueJudge($prompt, $model = 'x') { return $script:stubResult }
$script:stubResult = @{ ok = $false; text = 'boom'; exit = 1 }
$a = Invoke-ChecklistAssessment 1 'content' @() $prNone
Assert (-not $a.Ok -and $a.Decision -eq 'HOLD') '판정 호출 실패 -> Ok=false (호출부는 전이하지 않는다)'
$script:stubResult = @{ ok = $true; text = '설명만 있고 항목이 없음'; exit = 0 }
$a = Invoke-ChecklistAssessment 1 'content' @() $prNone
Assert (-not $a.Ok) '항목을 파싱하지 못한 응답 -> Ok=false (전이 없음)'
$script:stubResult = @{ ok = $true; text = "ITEM|other|MET|문서 등록|링크`nITEM|code|MET|코드 수정|PR"; exit = 0 }
$a = Invoke-ChecklistAssessment 1 'content' @() $prOpen
Assert ($a.Ok -and $a.Decision -eq 'REVERT') '코드 항목 충족 주장 + 미머지 PR -> 보정되어 REVERT'
$a = Invoke-ChecklistAssessment 1 'content' @() $prMerged
Assert ($a.Ok -and $a.Decision -eq 'KEEP') '코드 항목 + 머지된 PR -> KEEP'

if ($fail -gt 0) { Write-Host "`n$fail 건 실패" -ForegroundColor Red; exit 1 }
Write-Host "`n전체 통과"
exit 0
