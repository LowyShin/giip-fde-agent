# test-report-completion-gate.ps1 — 보고형 완료 게이트(giip #3801) 순수 로직 회귀 테스트
#
# 왜 필요한가: [NO-PR-REASON] 보고/조사형 이슈를 "마커만 보고 통과"시키던 종전 동작을,
#   의뢰(이슈 본문)↔결과(코멘트 보고)를 대조해 FULFILLED→DONE / UNFULFILLED→되돌림 하도록 바꿨다.
#   LLM 판정 자체는 모델이 필요해 단위테스트가 불가하지만, 그 판정을 "자동 DONE / 되돌림 / 안전폴백"
#   세 갈래로 라우팅하는 두 순수 함수는 결정적이고, 여기가 틀리면 완성된 보고를 되돌리거나(시간낭비)
#   미완성을 닫아버린다(완료위조). 그래서 그 두 지점을 고정한다:
#     1) Get-JudgeVerdict 가 FULFILLED/UNFULFILLED 를 첫 줄만 보고 정확히 뽑는가(모호 → $null → 안전폴백)
#     2) Get-GateRevertTally 가 새 [NO-PR-REASON-REVERT] 되돌림을 집계에 포함해 3회 캡이 발동하는가
#
# 네트워크/SK/claude 불필요 — 순수 함수에 합성 입력을 직접 먹인다.
#
# 실행:
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gissue/tests/test-report-completion-gate.ps1
# 종료코드: 0 = 전건 PASS, 1 = 1건 이상 FAIL

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\gissue-audit-lib.ps1')
. (Join-Path $PSScriptRoot '..\gissue-gate-tally-lib.ps1')

$fail = 0
function Assert-Eq($name, $expected, $actual) {
    if ("$expected" -eq "$actual") {
        Write-Output "PASS  $name"
    } else {
        Write-Output "FAIL  $name — expected='$expected' actual='$actual'"
        $script:fail++
    }
}

# ── 1) Get-JudgeVerdict 라우팅 (FULFILLED/UNFULFILLED) ──
Assert-Eq 'A. 첫 줄 FULFILLED → FULFILLED' 'FULFILLED' (Get-JudgeVerdict "FULFILLED`n근거: 근본원인과 사용자 결정이 코멘트에 기록됨." 'FULFILLED' 'UNFULFILLED')
Assert-Eq 'B. 첫 줄 UNFULFILLED → UNFULFILLED' 'UNFULFILLED' (Get-JudgeVerdict "UNFULFILLED`n근거: 조사가 아직 끝나지 않음." 'FULFILLED' 'UNFULFILLED')
# 근거 서술에 반대 키워드가 인용돼도 첫 줄만 본다(giip #2119 회귀 방지).
Assert-Eq 'C. FULFILLED + 근거에 UNFULFILLED 인용 → FULFILLED' 'FULFILLED' (Get-JudgeVerdict "FULFILLED`n이전 게이트가 UNFULFILLED 로 오판했으나 실제로는 충족됨." 'FULFILLED' 'UNFULFILLED')
# 첫 줄에 둘 다 있거나 둘 다 없으면 모호 → $null → 호출부는 안전폴백(REVIEW 유지).
Assert-Eq 'D. 첫 줄에 둘 다 → 모호($null)' '' (Get-JudgeVerdict "FULFILLED or UNFULFILLED?`n모르겠다" 'FULFILLED' 'UNFULFILLED')
Assert-Eq 'E. 첫 줄에 판정 없음 → 모호($null)' '' (Get-JudgeVerdict "음 글쎄요`nFULFILLED" 'FULFILLED' 'UNFULFILLED')
Assert-Eq 'F. 빈 응답 → 모호($null)' '' (Get-JudgeVerdict '' 'FULFILLED' 'UNFULFILLED')

# ── 2) Get-GateRevertTally 가 [NO-PR-REASON-REVERT] 를 집계해 3회 캡이 발동하는가 ──
$reportMarker = '[NO-PR-REASON-' + 'REVERT]'   # 카운팅 오염 방지(리터럴 분할)
$comments = @(
    @{ content = "$reportMarker (재검증 시각: 2026-10-15 01:00:00)`n이번이 1번째 되돌림입니다(최대 3 회).`n미충족: 근본원인 미제시."; regdate = '2026-10-15T01:00:00Z' },
    @{ content = "$reportMarker (재검증 시각: 2026-10-15 02:00:00)`n이번이 2번째 되돌림입니다(최대 3 회).`n미충족: 여전히 분석 누락."; regdate = '2026-10-15T02:00:00Z' }
)
$tally = Get-GateRevertTally $comments
Assert-Eq 'G. report-gate 되돌림 2건 집계됨' '2' $tally.Counts['report-gate']
Assert-Eq 'H. 전체 합산 Total=2' '2' $tally.Total
# 3번째 되돌림 예정분(+1) 포함하면 캡(3) 도달 → 되돌림 대신 에스컬레이션 분기로 가야 한다.
$wouldEscalate = (($tally.Total + 1) -ge 3)
Assert-Eq 'I. 누적 2 + 이번 1 = 3 >= 캡 → 에스컬레이션' 'True' $wouldEscalate

# 되돌림 이력이 아직 1건뿐이면(이번이 2회차) 캡 미도달 → 되돌림 진행.
$tally1 = Get-GateRevertTally @($comments[0])
$wouldRevert = (($tally1.Total + 1) -lt 3)
Assert-Eq 'J. 누적 1 + 이번 1 = 2 < 캡 → 되돌림 진행' 'True' $wouldRevert

if ($fail -gt 0) { Write-Output "`n$fail 건 FAIL"; exit 1 }
Write-Output "`n전건 PASS"
exit 0
