# test-humanconfirm-signal.ps1 — review-done-audit.ps1 의 사람-확인 신호 판정 회귀 테스트 (giip #2424)
#
# 왜 필요한가: giip #2424 1차 수정(2026-09-14)은 판정 분기를 전부 `continue` 로 처리한 탓에
#   Get-HumanConfirmSignal 이 어떤 입력에도 $null 을 반환하는 죽은 코드가 됐다. 오탐은 사라졌지만
#   진짜 사람 확인 요청까지 전부 놓치는, 탐지 없음과 동일한 상태였고 아무도 눈치채지 못했다.
#   그 유형의 회귀를 다시 놓치지 않도록 "오탐 안 남" 과 "정탐 남음" 을 함께 고정한다.
#
# 픽스처는 실제 giip 코멘트에서 발췌했다(네트워크/SK 불필요 — 언제든 그대로 실행 가능).
#   giip #2394 / #2123 / #2148 / #2423 : 오탐 실측 표본(세션 자신의 자기 검증 완료 보고)
#   giip #2340                          : 정탐 실측 표본(사람 코멘트의 "사용자 확인 필요")
#
# 실행:
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gissue/tests/test-humanconfirm-signal.ps1
# 종료코드: 0 = 전건 PASS, 1 = 1건 이상 FAIL

param([string]$ScriptPath)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'

if (-not $ScriptPath) { $ScriptPath = Join-Path $PSScriptRoot '..\review-done-audit.ps1' }
$ScriptPath = (Resolve-Path -LiteralPath $ScriptPath).Path
$lines = Get-Content -LiteralPath $ScriptPath -Encoding UTF8

# review-done-audit.ps1 은 -Workdir 필수 파라미터 + 최상위 실행부를 가진 스크립트라 통째로 dot-source
# 할 수 없다. 판정에 필요한 부분(Parse-Utc, $BotAuthors ~ Get-HumanConfirmSignal)만 잘라 평가한다.
function Get-FunctionBlock([string[]]$src, [string]$startRegex) {
    $start = -1
    for ($i = 0; $i -lt $src.Count; $i++) { if ($src[$i] -match $startRegex) { $start = $i; break } }
    if ($start -lt 0) { throw "블록 시작을 찾지 못함: $startRegex" }
    $out = New-Object System.Collections.Generic.List[string]
    for ($j = $start; $j -lt $src.Count; $j++) {
        $out.Add($src[$j])
        if ($src[$j] -match '^\}\s*$') { break }
    }
    return ($out -join "`n")
}

Invoke-Expression (Get-FunctionBlock $lines '^function Parse-Utc')

$bStart = -1; $bEnd = -1
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($bStart -lt 0 -and $lines[$i] -match '^\$BotAuthors\s*=') { $bStart = $i }
    if ($lines[$i] -match '^function Get-HumanConfirmSignal') { $bEnd = $i }
}
if ($bStart -lt 0 -or $bEnd -lt 0) { throw '판정 블록($BotAuthors ~ Get-HumanConfirmSignal)을 찾지 못함' }
for ($j = $bEnd; $j -lt $lines.Count; $j++) { if ($lines[$j] -match '^\}\s*$') { $bEnd = $j; break } }
Invoke-Expression (($lines[$bStart..$bEnd]) -join "`n")

function New-Comment($author, $role, $date, $content) {
    return [pscustomobject]@{ author = $author; loadedRole = $role; regdate = $date; content = $content }
}

$cases = @(
    @{
        Name = 'giip #2394 — 세션의 "직접 확인 완료 / 재조사 불필요" 자기 검증 보고'
        Expect = $null
        Comments = @(
            (New-Comment 'Lowy Shin' 'orchestrator' '2026-09-13T04:41:19Z' '[착수: 2026-09-13T04:41:19Z · dp01-console · orchestrator] 서브에이전트 위임 착수. 정확한 마커 문자열 확인 완료(pr-gate-sweep.ps1/gissue-audit-lib.ps1 직접 확인, 재조사 불필요).'),
            (New-Comment 'gissue-scheduler-watchdog' $null '2026-09-13T16:45:00Z' '[BUDGET] gissue 스케줄러 실행 시간 예산(105분) 소진으로 이 이슈는 이번 실행에서 처리하지 못했습니다.')
        )
    },
    @{
        Name = 'giip #2123 — loadedRole 없는 서브에이전트 완료 보고의 "직접 확인"'
        Expect = $null
        Comments = @(
            (New-Comment 'Lowy Shin' $null '2026-09-14T01:33:20Z' "## [gareport-2123] 재실측 + 생성측 수정 + 라이브 검증 완료`n`n**사유(Why)**: 게이트가 요구하는 근거를 생성 측이 갖추도록 수정하고 라이브로 리포트 생성을 직접 확인했다.")
        )
    },
    @{
        Name = 'giip #2148 — 완료 보고 안의 "사람 확인" 단독 등장(요청 아님)'
        Expect = $null
        Comments = @(
            (New-Comment 'Lowy Shin' $null '2026-09-14T01:17:41Z' "## [slackbot-restart-2148] ISN 2148 구현 완료`n`nPR 머지 확인 완료. 남은 것은 사람 확인 절차 정리뿐이며 이 이슈 범위 밖이다.")
        )
    },
    @{
        Name = 'giip #2423 — "[완료:" 세션 진행 헤더 코멘트'
        Expect = $null
        Comments = @(
            (New-Comment 'Lowy Shin' $null '2026-09-14T01:01:01Z' "[완료: 2026-09-14 01:00 UTC · gate-widget-2423 · role=frontend_specialist] 상태: IN_PROGRESS -> REVIEW`n`n요청 3건을 모두 구현·머지·배포하고 실제 API 재호출로 직접 확인했습니다.")
        )
    },
    @{
        Name = '봇 계정이 남긴 요청형 문구 — 사람 신호로 채택하지 않는다'
        Expect = $null
        Comments = @(
            (New-Comment 'gissue-review-audit' $null '2026-09-12T10:21:04Z' '[REVIEW-AUDIT:WARN] 무한 왕복을 막기 위해 자동 조치를 중단합니다 — 사람 확인 필요.')
        )
    },
    @{
        Name = '판정 규칙을 논의하며 문구를 따옴표로 인용한 코멘트 — 인용은 요청이 아니다'
        Expect = $null
        Comments = @(
            (New-Comment 'Lowy Shin' $null '2026-09-12T01:38:16Z' 'PR은 완료됐지만 "테스트 방법(사람 확인용)"류 안내가 코멘트에 있는 경우 NEEDS_DECISION 으로 전이하는 옵션을 추가한다.')
        )
    },
    @{
        Name = '완료/부정 어미가 뒤따르는 요청형 문구 — "사용자 확인 필요 없음"'
        Expect = $null
        Comments = @(
            (New-Comment 'Lowy Shin' $null '2026-09-14T02:00:00Z' '배포까지 전부 자동 검증으로 끝났으므로 사용자 확인 필요 없음.')
        )
    },
    # ── giip #2424 2차(2026-09-16): 봇 코멘트를 사람 신호로 오독하던 2단 연쇄 ─────────────────
    # 아래 5건은 NEEDS_DECISION 26건을 실제로 만들어낸 경로다. 픽스처는 giip 2424 의 실제 코멘트
    # (cSn=14876 author=gissue-scope-gate / cSn=15144 author=gissue-review-audit)에서 발췌했다.
    @{
        Name = 'giip #2424 실측 — gissue-scope-gate 의 [SCOPE-GATE-REVERT] 말미 안내문("사람 확인 필요로 전환됩니다")'
        Expect = $null
        Comments = @(
            (New-Comment 'gissue-scope-gate' $null '2026-09-14T08:04:04Z' "[SCOPE-GATE-REVERT] (재검증 시각: 2026-09-14 17:04:18)`n이번이 1번째 되돌림입니다(최대 3 회).`n사유: PR #()의 실제 변경 내용이 이 이슈에서 신고된 증상과 무관하거나 신고 범위보다 훨씬 좁은/다른 것을 고친 것으로 판정되었습니다.`n`n최대 3 회를 초과하면 더 이상 자동으로 되돌리지 않고 REVIEW 유지 + 사람 확인 필요로 전환됩니다.")
        )
    },
    @{
        Name = 'giip #2424 실측 — gissue-review-audit 의 NEEDS_DECISION 코멘트가 인용한 발췌 구역 안의 문구'
        Expect = $null
        Comments = @(
            (New-Comment 'gissue-review-audit' $null '2026-09-14T15:36:42Z' "[REVIEW-AUDIT:NEEDS_DECISION] (재검증 시각: 2026-09-15 00:36:57)`n감지된 코멘트 발췌(author=gissue-scope-gate, regdate=2026-09-14T08:04:04Z):`n> [SCOPE-GATE-REVERT] ...`n최대 3 회를 초과하면 REVIEW 유지 + 사람 확인 필요로 전환됩니다.")
        )
    },
    @{
        Name = '발췌 구역 안의 요청형 문구는 사람 계정 코멘트라도 인용이다 — 그 코멘트 자신의 요청이 아니다'
        Expect = $null
        Comments = @(
            (New-Comment 'Lowy Shin' $null '2026-09-16T01:00:00Z' "게이트 오탐을 조사한다.`n감지된 코멘트 발췌(author=gissue-scope-gate, regdate=2026-09-14T08:04:04Z):`n최대 3 회를 초과하면 REVIEW 유지 + 사람 확인 필요로 전환됩니다.")
        )
    },
    @{
        Name = '새 게이트 봇(gissue-comment-gate) — 목록에 없어도 gissue- 접두사로 봇 판정'
        Expect = $null
        Comments = @(
            (New-Comment 'gissue-comment-gate' $null '2026-09-15T02:00:00Z' '[COMMENT-GATE-REVERT] 착수/테스트결과 코멘트가 없어 되돌립니다. 반복되면 사람 확인 필요로 전환됩니다.')
        )
    },
    @{
        Name = '봇 마커로 시작하지만 계정명이 사람인 코멘트(봇 마스터 uSn 29 공유 경로)'
        Expect = $null
        Comments = @(
            (New-Comment 'Lowy Shin' $null '2026-09-15T03:00:00Z' "## [gissue-review-audit] ISN 2485 상태전이: REVIEW -> NEEDS_DECISION`n**사유(Why)**: 사람 확인 필요 문구가 감지되었습니다.")
        )
    },
    @{
        Name = 'giip #2340 — 사람 코멘트의 진짜 요청형 "사용자 확인 필요"(정탐 고정)'
        Expect = '사용자 확인 필요'
        Comments = @(
            (New-Comment 'Lowy Shin' $null '2026-09-11T05:01:02Z' 'PR 3건 모두 직접 머지하지 않았습니다(giipdb #307은 서브에이전트의 지시 위반으로 이미 머지된 상태 — 사용자 확인 필요). giipv3/giipfaw는 오너 최종 확인 후 머지 여부 결정 바랍니다.')
        )
    },
    @{
        Name = '사람 코멘트의 "사람이 직접 확인해 주십시오" — 요청형 정탐'
        Expect = '사람이 직접 확인'
        Comments = @(
            (New-Comment 'Lowy Shin' $null '2026-09-14T02:10:00Z' '자동 판정으로는 결론이 서지 않습니다. 사람이 직접 확인해 주십시오.')
        )
    },
    @{
        Name = '발췌 구역이 있어도 그 앞(작성자 본문)의 요청형 문구는 정탐으로 남는다 — 과잉 억제 방지'
        Expect = '사용자 확인 필요'
        Comments = @(
            (New-Comment 'Lowy Shin' $null '2026-09-16T02:00:00Z' "이건 제가 직접 봐야겠습니다. 사용자 확인 필요.`n감지된 코멘트 발췌(author=gissue-scope-gate, regdate=2026-09-14T08:04:04Z):`n> [SCOPE-GATE-REVERT] ...")
        )
    },
    @{
        Name = '사람 코멘트의 "오너 판단 필요" — 요청형 정탐'
        Expect = '오너 판단 필요'
        Comments = @(
            (New-Comment 'Lowy Shin' $null '2026-09-14T02:20:00Z' '두 설계안 중 어느 쪽으로 갈지는 오너 판단 필요.')
        )
    }
)

$fail = 0
foreach ($case in $cases) {
    $sig = Get-HumanConfirmSignal $case.Comments
    $got = if ($sig) { $sig.Phrase } else { $null }
    $ok = ($got -eq $case.Expect)
    if (-not $ok) { $fail++ }
    $verdict = if ($ok) { 'PASS' } else { 'FAIL' }
    $expectText = if ($null -eq $case.Expect) { '(신호 없음)' } else { $case.Expect }
    $gotText = if ($null -eq $got) { '(신호 없음)' } else { $got }
    Write-Output "[$verdict] 기대=$expectText 실제=$gotText — $($case.Name)"
}

Write-Output ''
if ($fail -eq 0) {
    Write-Output "결과: 전체 $($cases.Count)건 PASS"
} else {
    Write-Output "결과: $($cases.Count)건 중 $fail 건 FAIL"
    exit 1
}
