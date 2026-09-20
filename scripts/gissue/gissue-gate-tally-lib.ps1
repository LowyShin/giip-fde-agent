# gissue-gate-tally-lib.ps1 — 게이트 되돌림 "전체 합산" 집계기 (giip #2415 요구사항 #2)
#
# 배경: giip #2085 로 각 게이트(PR-gate/scope-gate/comment-gate)에 "이슈당 3회 캡"이 생겼지만,
#   캡이 게이트별로 따로라 전체 왕복 횟수는 아무도 세지 않았다(giip #2415 원문: #2110 이 7일간
#   57 코멘트 왕복). giip #2415 1차 구현(PR #728)에서 pr-gate-sweep.ps1 안에 합산 로직이 들어갔으나
#   (a) `review-done-audit.ps1` 이 남기는 되돌림(`[REVIEW-AUDIT:REVERT]`)이 합산에서 빠졌고
#   (b) 합산할 때마다 게이트 수만큼 코멘트 API 를 다시 조회했으며
#   (c) 에스컬레이션 코멘트에 "누적 N회"만 적히고 회차별 시각/게이트/사유가 없었다.
#   이 파일은 그 셋을 한 곳에서 해결한다 — 호출부가 이미 1회 조회해 둔 코멘트 배열만 넘기면
#   추가 API 호출 없이 게이트별 횟수 + 전체 합계 + 회차 이력을 한 번에 돌려준다.
#
# 주의(카운팅 오염 방지): 이 파일이 만들어 내는 어떤 문자열에도 되돌림 마커 원문
#   (`[PR-GATE-REVERT]` 등)을 그대로 넣지 않는다. 집계는 "작성자 + 마커 포함" 조합으로 세기 때문에,
#   에스컬레이션 코멘트 본문에 마커 원문이 들어가면 그 코멘트 자신이 다음 회차 카운트를 부풀린다.
#   그래서 이력 요약은 항상 게이트 Key/Label(예: `scope-gate`)로만 표기한다.

# 되돌림 출처 정의. Marker/Author 조합은 각 스크립트의 상수와 반드시 일치해야 한다:
#   - pr-gate-sweep.ps1  : $RevertMarker/$RevertAuthor, $ScopeRevertMarker/$ScopeRevertAuthor,
#                          $CommentRevertMarker/$CommentRevertAuthor
#   - review-done-audit.ps1 : '[REVIEW-AUDIT:REVERT]' + $AuditAuthor('gissue-review-audit')
# 마커 원문을 여기서 직접 문자열 리터럴로 쓰지 않기 위해 조립해서 만든다(위 "카운팅 오염 방지" 주석 참고).
function Get-GateRevertSourceDefs {
    return @(
        @{ Key = 'PR-gate';      Marker = ('[PR-GATE-' + 'REVERT]');      Author = 'gissue-pr-gate';      Label = 'PR-gate(대응 PR 없음)' },
        @{ Key = 'scope-gate';   Marker = ('[SCOPE-GATE-' + 'REVERT]');   Author = 'gissue-scope-gate';   Label = 'scope-gate(scope-match MISMATCH)' },
        @{ Key = 'comment-gate'; Marker = ('[COMMENT-GATE-' + 'REVERT]'); Author = 'gissue-comment-gate'; Label = 'comment-gate(진행 코멘트 프로토콜 미충족)' },
        @{ Key = 'review-audit'; Marker = ('[REVIEW-AUDIT:' + 'REVERT]'); Author = 'gissue-review-audit'; Label = 'review-done-audit(완료위조 감사 되돌림)' }
    )
}

# 되돌림 코멘트 1건에서 "사유 1줄"을 뽑는다. 게이트마다 본문 구조가 다르므로
# Get-GateRevertHistorySummary(gissue-audit-lib.ps1)와 동일한 규칙을 쓴다:
#   1번째 줄(마커+시각)과 "이번이 N번째 되돌림입니다" 줄은 건너뛰고, 그 다음 비어있지 않은 첫 줄.
function Get-GateRevertReasonLine($content) {
    $bodyLines = @("$content" -split '\r?\n' | Where-Object { $_.Trim() -ne '' })
    if ($bodyLines.Count -le 1) { return '(사유 추출 실패 — 원문 코멘트 확인 필요)' }
    $skip = 1
    if ($bodyLines.Count -gt 1 -and $bodyLines[1] -match '번째 되돌림입니다') { $skip = 2 }
    $picked = @($bodyLines | Select-Object -Skip $skip -First 1)
    $line = ("$($picked -join ' ')").Trim()
    if (-not $line) { return '(사유 추출 실패 — 원문 코멘트 확인 필요)' }
    if ($line.Length -gt 160) { $line = $line.Substring(0, 160) + '…' }
    return $line
}

# 이미 조회해 둔 코멘트 배열($comments)로부터 게이트 되돌림을 전부 집계한다(추가 API 호출 없음).
# 반환: PSCustomObject
#   .Total        [int]    모든 게이트 되돌림 합계(review-done-audit 되돌림 포함)
#   .Counts       [hashtable] Key(게이트) → 횟수
#   .Rounds       [array]  회차 목록(시간 오름차순). 각 원소: @{ When; Gate; Label; Reason }
#   .CountsText   [string] "PR-gate=1, scope-gate=2, ..." 한 줄 요약(0인 게이트 제외, 전부 0이면 '없음')
#   .HistoryText  [string] "  1회차 [시각] scope-gate: 사유" 여러 줄. 없으면 안내 문구 1줄.
function Get-GateRevertTally($comments) {
    $defs = Get-GateRevertSourceDefs
    $counts = @{}
    foreach ($d in $defs) { $counts[$d.Key] = 0 }
    $rounds = @()

    foreach ($c in @($comments)) {
        $content = "$($c.content)"
        if (-not $content) { continue }
        foreach ($d in $defs) {
            # [giip #2645 이식] author 는 판정에 쓰지 않는다 — 이 레포는 giipfaw API 로만 코멘트를
            # 쓰고 API 경로에서는 author 를 서버가 정하므로, AND 조건으로 두면 집계가 항상 0 이 되어
            # 전체 합산 에스컬레이션이 영영 발동하지 않는다. 마커는 게이트마다 고유하고 위
            # "카운팅 오염 방지" 규약이 마커 원문 재출현을 막으므로 마커 단독으로 변별된다.
            if ($content.Contains($d.Marker)) {
                $counts[$d.Key] = $counts[$d.Key] + 1
                $rounds += @{
                    When   = "$($c.regdate)"
                    Gate   = $d.Key
                    Label  = $d.Label
                    Reason = (Get-GateRevertReasonLine $content)
                }
                break   # 한 코멘트가 두 게이트로 중복 집계되지 않게 한다.
            }
        }
    }

    $rounds = @($rounds | Sort-Object { $_.When })

    $total = 0
    foreach ($d in $defs) { $total += $counts[$d.Key] }

    $countParts = @()
    foreach ($d in $defs) {
        if ($counts[$d.Key] -gt 0) { $countParts += ("{0}={1}회" -f $d.Key, $counts[$d.Key]) }
    }
    $countsText = if ($countParts.Count -gt 0) { $countParts -join ', ' } else { '없음' }

    if ($rounds.Count -eq 0) {
        $historyText = '  (되돌림 이력 없음)'
    } else {
        $lines = @()
        $i = 0
        foreach ($r in $rounds) {
            $i++
            $lines += ("  {0}회차 [{1}] {2} — {3}" -f $i, $r.When, $r.Label, $r.Reason)
        }
        $historyText = ($lines -join "`n")
    }

    return [pscustomobject]@{
        Total       = $total
        Counts      = $counts
        Rounds      = $rounds
        CountsText  = $countsText
        HistoryText = $historyText
    }
}
