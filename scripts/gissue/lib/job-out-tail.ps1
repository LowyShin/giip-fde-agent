# job-out-tail.ps1 — gissue Phase 2 잡 출력 증분 보존(giip 4431 항목 3) 순수 로직
#
# 배경(giip 4431 항목 3): 잡 출력(Receive-Job)을 `gissue_csn<N>.out.log` 로 옮기는 호출이 Complete-Run
#   한 곳에만 있었다. 즉 **정상 종료 경로에서만** out.log 가 채워진다. 외부 작업 스케줄러 제한(PT2H)으로
#   러너 프로세스 자체가 강제 종료되면 Complete-Run 에 도달하지 못해, 그 CSN 잡이 남긴 내부 단계가
#   사후에 전혀 남지 않았다(17:12/19:12 회차 "잡 출력이 로그에 남지 않음" 실측과 정합).
#   해법: Phase 2 대기 루프가 running 잡마다 주기적으로 `Receive-Job -Keep`(버퍼 보존) 으로 읽어
#   out.log 에 **증분 append** 한다. `-Keep` 은 매번 처음부터 전체 버퍼를 돌려주므로, "이미 기록한 줄
#   수"(OutLogWritten)를 기준으로 **아직 안 쓴 꼬리만** 골라야 이중 기록을 막을 수 있다 — 그 꼬리 선별이
#   이 파일의 순수 로직이다.
#
# 처리 내용 / 저장 위치 / 소비처
#   - 이 파일은 파일/DB/네트워크에 직접 아무것도 쓰지 않는다. 버퍼 읽기·파일 append 는 호출부가 한다.
#   - 소비처: run-gissue-claude.ps1 Phase 2 대기 루프의 Write-GissueJobOutIncremental(증분 flush) +
#             Complete-Run 의 최종 flush, tests/test-job-out-incremental.ps1(가짜 버퍼로 검증).
#
# 이 파일은 자기완결적이다(러너의 다른 함수를 부르지 않는다). PowerShell 5.1 호환.

# Receive-Job -Keep 이 반환한 전체 버퍼($AllLines)에서, 아직 out.log 에 기록하지 않은 꼬리만 골라낸다.
#   $AllLines     : 현재까지 잡이 남긴 전체 출력 줄(배열). -Keep 이라 매번 처음부터 전체를 반환한다.
#   $WrittenCount : 지금까지 out.log 에 기록한 줄 수(호출부가 run 객체에 보관하는 누적 카운터).
# 반환: NewLines = 이번에 새로 append 할 줄(없으면 빈 배열), WrittenCount = 갱신된 총 기록 줄 수.
# 규칙:
#   - 전체 줄 수가 이미 기록한 수 이하이면(새 줄 없음, 또는 방어적으로 카운터가 버퍼보다 큰 비정상) 빈
#     NewLines 를 돌려주고 WrittenCount 를 현재 전체 줄 수로 재동기화한다(버퍼가 줄어든 예외 상황 보정).
#   - 그 외에는 [WrittenCount .. 끝] 구간만 NewLines 로 돌려주고 WrittenCount 를 전체 줄 수로 올린다.
function Split-GissueJobOutTail {
    param(
        [string[]]$AllLines,
        [int]$WrittenCount
    )
    $all = @($AllLines)
    $total = $all.Count
    if ($WrittenCount -lt 0) { $WrittenCount = 0 }
    if ($WrittenCount -ge $total) {
        return [pscustomobject]@{ NewLines = @(); WrittenCount = $total }
    }
    $new = @($all[$WrittenCount..($total - 1)])
    return [pscustomobject]@{ NewLines = $new; WrittenCount = $total }
}
