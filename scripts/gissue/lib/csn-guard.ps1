# csn-guard.ps1 — 미매핑 CSN 가드의 "응답 cSn 대조" 판정 (giip 4116 / 4139)
#
# 용도: run-gissue-claude.ps1 의 Get-GissueOpenIssuesAllCsn 이 list-issues.js --json 응답 행을 받았을 때,
#   그 행을 "요청한 csn 의 이슈"로 믿어도 되는지 판정한다.
# 처리: 봇 유저가 멤버가 아닌 csn 을 조회하면 서버 게이트가 요청을 홈 csn 으로 조용히 클램프해 다른 csn 의
#   이슈를 돌려준다. 그 행을 요청 csn 의 것으로 믿으면 거짓 양성 코멘트가 달린다(2026-10-22 사고).
#   응답 행의 cSn 이 요청 csn 과 같을 때만 통과시킨다.
#     cSn 필드 없음/비어 있음 -> SKIP-NOCSN (버림)
#     cSn != 요청 csn         -> SKIP-CLAMP  (버림)
#   기본값은 침묵이다: 거짓 코멘트 1건의 비용이 누락 1건의 비용보다 크다.
# 결과 저장: 반환값(통과 행 배열) 뿐이다. 버린 사유는 호출부가 넘긴 -Log 스크립트블록으로 한 줄씩 보낸다
#   (운영에서는 logs/gissue_csnguard.log, run-gissue-claude.ps1 의 UnmappedCsnGuardLog).
# 소비처: run-gissue-claude.ps1 Get-GissueOpenIssuesAllCsn -> Invoke-GissueUnmappedCsnGuard.
# 테스트: scripts/gissue/tests/test-csn-guard-clamp.ps1

function Select-GissueRowsMatchingCsn {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][AllowNull()]$Rows,
        [Parameter(Mandatory = $true)][string]$RequestedCsn,
        [scriptblock]$Log
    )
    $kept = @()
    foreach ($r in @($Rows)) {
        if (-not $r -or $null -eq $r.isn) { continue }
        $respCsn = $null
        if ($r.PSObject.Properties.Name -contains 'cSn' -and $null -ne $r.cSn -and "$($r.cSn)" -ne '') {
            $respCsn = "$($r.cSn)"
        }
        if ($null -eq $respCsn) {
            if ($Log) { & $Log "[UNMAPPED-CSN-WARN] SKIP-NOCSN: isn=$($r.isn) 응답에 cSn 필드 없음 (요청 csn=$RequestedCsn) — 행 버림" }
            continue
        }
        if ($respCsn -ne $RequestedCsn) {
            if ($Log) { & $Log "[UNMAPPED-CSN-WARN] SKIP-CLAMP: isn=$($r.isn) 응답 cSn=$respCsn != 요청 csn=$RequestedCsn (서버 클램프) — 행 버림" }
            continue
        }
        $kept += $r
    }
    return ,$kept
}
