# timebox-followup.ps1 — 시간 캡 초과 후속(캐리어오버) 이슈의 "중복 등록 방지" 판정 (giip #2667 / rule 69-4)
#
# 왜 필요한가 (실측, 2026-11-28):
#   시간 캡(40분) 초과로 강제 정리되면 러너는 그 원본의 잔여 작업을 담은 "후속(캐리어오버)" 이슈를 새로
#   등록한다. 그런데 **같은 원본에 대한 미해결 후속이 이미 있는데도 또 등록**하는 경로가 있었다.
#   실측: isn=5141 에 대해 후속이 5208(2026-11-13) · 6606(2026-11-27) · 6679(2026-11-28) **3건**이다.
#   → 같은 잔여 작업의 캐리어오버가 증식된다. 선례: giip #2523 의 후속이 2532/2661 로 2건 중복(giip #2523).
#
#   중복 판정의 키는 제목 안의 "(원본 giip #N)" 표식이다.
#   · 제목이 큰따옴표 앞에서 잘리면 표식이 사라진다(giip #6620 → PR #584 로 `--title-file` 경유로 수리 완료).
#   · 표식이 살아있는데도 **"이미 미해결 후속이 있는지"를 조회하는 코드가 없었다** → 항상 신규 등록.
#
# 이 파일이 하는 일 — "같은 원본의 미해결 후속이 이미 있는가"를 **순수 함수**로 판정한다.
#   · 조회(I/O)는 호출부(러너)가 하고 판정만 여기 둔다 → 단위 테스트가 가능하다(러너와 같은 코드를 닷소싱).
#   · 종료 상태(DONE/CLOSED)는 "미해결"이 아니므로 제외한다.
#
# 알려진 한계(명시):
#   · **표식이 잘린 제목(과거 잔재)은 키가 없으므로 찾지 못한다.** 제목 절단 자체가 고쳐진 뒤(PR #584)
#     새로 등록되는 후속부터 성립하는 성질이며, 과거 잔재(#5141 의 5208/6606/6679 등)는 사람이 정리한다.
#   · 본문(원본 이슈 URL)을 키로 쓰는 방식은 목록 조회 API 가 본문을 주지 않으므로 쓰지 않는다.
#
# 사용처: scripts/gissue/run-gissue-claude.ps1 (타임박스 후속 등록 경로) · 회귀 테스트
#         scripts/gissue/tests/test-timebox-followup-dedup.ps1

# 후속 제목에 들어가는 원본 마커. 닫는 괄호까지 포함하므로 "#5141)" 가 "#51410)" 에 잘못 걸리지 않는다.
function Get-GissueTimeboxFollowupMarker {
    param($OriginIsn)
    return "(원본 giip #$OriginIsn)"
}

# 순수: 제목에 원본 마커가 있고 상태가 종료(DONE/CLOSED)가 아닌 첫 행을 돌려준다. 없으면 $null.
# $Rows 의 각 행은 .Isn/.Title/.Status 를 가진 객체면 된다
# (list-issues.js --json 출력의 {isn,title,status} 도 PowerShell 의 대소문자 무시 속성 접근으로 그대로 읽힌다).
function Find-GissueOpenTimeboxFollowup {
    param($Rows, $OriginIsn, $ClosedStatuses = @('DONE', 'CLOSED'))
    $marker = Get-GissueTimeboxFollowupMarker $OriginIsn
    $closed = @(@($ClosedStatuses) | ForEach-Object { "$_".Trim().ToUpperInvariant() })
    foreach ($r in @($Rows)) {
        if ($null -eq $r) { continue }
        if ("$($r.Title)".IndexOf($marker, [System.StringComparison]::Ordinal) -lt 0) { continue }
        $status = "$($r.Status)".Trim().ToUpperInvariant()
        if ($closed -contains $status) { continue }
        return $r
    }
    return $null
}
