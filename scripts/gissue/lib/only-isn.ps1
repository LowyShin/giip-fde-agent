# lib/only-isn.ps1 — 이슈 번호 지정 실행(-OnlyIsn)의 판정 정본 (giip 5544)
#
# 배경: 5분 간격 감지기가 "지금 이 이슈를 처리하라"고 번호를 지정해 러너를 깨우는 구조
#   (front-fde 프로젝트 요청)에서는, 큐 우선순위와 READY 경과(기본 60분) 조건을 우회해야
#   지정의 의미가 있다. 그러나 안전 게이트까지 우회하면 지정 1건이 NEEDS_DECISION(사람
#   결정 대기)나 처리 중인 이슈를 건드리게 되므로, 우회 범위와 게이트 유지를 이 파일의
#   순수 판정 함수 하나로 고정한다(규칙 48 — 판정은 한 곳에만).
#
# 판정 계약 (Get-GissueOnlyIsnVerdict):
#   RUN  — 큐에 이미 있으면 그 행 그대로(큐가 [OPS] 제외·라벨 정규화를 끝낸 상태),
#          READY 인데 경과 부족으로 큐에 없을 때만 행을 만들어 RUN(경과 조건 우회 지점).
#   SKIP — CSN_MISMATCH(giip #1053 가드) / AUTO_OPS / NEEDS_DECISION /
#          IN_PROGRESS_ACTIVE(다른 실행이 처리 중 — 신선한 IN_PROGRESS 는 큐에 없다) /
#          REVIEW_NO_NEW_SIGNAL(REVIEW/TESTED 가 dedup·최대 경과로 큐에서 빠진 경우) /
#          STATUS_NOT_PROCESSABLE(DONE 등) / NOT_FOUND.
#   REVIEW/TESTED 의 재검증 쿨다운·회차 상한은 큐가 아니라 잡 루프의 기존 게이트가
#   그대로 적용한다 — 이 판정은 그 앞단(큐 구성)까지만 책임진다.
#
# ⚠ 커플링: $script:GissueAutoOpsTitlePrefix 는 list-issues.js 의
#   AUTO_OPS_TITLE_PREFIX 및 check-gissue-liveness.ps1 의 $title 과 반드시 동일해야
#   한다(자동 감지 이슈 판정). 회귀 테스트(test-only-isn.ps1)가 list-issues.js 와의
#   일치를 고정한다.

$script:GissueAutoOpsTitlePrefix = '[OPS] gissue 처리 무소식 감지'

# 자동 감지(무소식) 이슈 제목인가 — list-issues.js isAutoDetectionOpsTitle 과 동일 규칙
# (제목 정확 일치 또는 그 접두사로 시작).
function Test-GissueAutoOpsTitle {
    param([AllowNull()][AllowEmptyString()][string]$Title)
    $t = "$Title".Trim()
    if (-not $t) { return $false }
    return ($t -eq $script:GissueAutoOpsTitlePrefix -or $t.StartsWith($script:GissueAutoOpsTitlePrefix))
}

# 지정 이슈 1건의 조회 — list-issues.js --status 직접 조회(큐가 아닌 전 상태 조회라
# NEEDS_DECISION·DONE 도 보인다). 반환: @{ Row = <행 또는 $null>; Error = <문자열 또는 ''> }
# Row = @{ Isn; Title; Status; Csn } (Csn 은 응답이 실제로 돌려준 소속 — giip #4116).
function Get-GissueIssueByIsn {
    param(
        [Parameter(Mandatory)][string]$ListIssuesScript,
        [Parameter(Mandatory)][string]$Csn,
        [Parameter(Mandatory)][string]$AccountsFile,
        [Parameter(Mandatory)][string]$ApiBase,
        [Parameter(Mandatory)][int]$Isn
    )
    try {
        $raw = & node $ListIssuesScript --csn $Csn --status 'PENDING,READY,IN_PROGRESS,REVIEW,TESTED,NEEDS_DECISION,DONE' --accounts-file $AccountsFile --api-base $ApiBase --json 2>&1
        if ($LASTEXITCODE -ne 0) {
            return @{ Row = $null; Error = "list-issues exit=$LASTEXITCODE`: $(($raw | Out-String).Trim())" }
        }
        $parsed = ($raw | Out-String) | ConvertFrom-Json
        foreach ($r in @($parsed)) {
            if ($null -ne $r -and "$($r.isn)" -eq "$Isn") {
                return @{ Row = @{ Isn = "$($r.isn)"; Title = "$($r.title)"; Status = "$($r.status)"; Csn = "$($r.cSn)" }; Error = '' }
            }
        }
        return @{ Row = $null; Error = '' }
    } catch {
        return @{ Row = $null; Error = $_.Exception.Message }
    }
}

# 지정 실행 판정(순수 함수 — API·파일 접근 없음).
#   Found       : 대상 CSN 스코프 조회에서 이슈가 보였는가
#   Status      : 이슈의 현재 상태(Found 일 때)
#   RowCsn      : 응답이 돌려준 실제 소속 CSN(비면 판정 생략 — 서버가 안 준 경우)
#   TargetCsn   : 이 실행의 대상 CSN
#   Title       : 이슈 제목([OPS] 판정용)
#   InQueue     : 일반 큐(--queue)에 이 이슈가 포함됐는가
#   QueueStatus : 큐에서의 라벨(InQueue 일 때 — STALE_IN_PROGRESS 등 정규화된 값)
# 반환: @{ Action = 'RUN'|'SKIP'; Reason = <SKIP 사유 코드 또는 ''>; QueueStatus = <RUN 시 사용할 큐 상태 라벨> }
function Get-GissueOnlyIsnVerdict {
    param(
        [Parameter(Mandatory)][bool]$Found,
        [AllowEmptyString()][string]$Status = '',
        [AllowEmptyString()][string]$RowCsn = '',
        [Parameter(Mandatory)][string]$TargetCsn,
        [AllowEmptyString()][string]$Title = '',
        [Parameter(Mandatory)][bool]$InQueue,
        [AllowEmptyString()][string]$QueueStatus = ''
    )
    if (-not $Found) {
        return @{ Action = 'SKIP'; Reason = 'NOT_FOUND'; QueueStatus = '' }
    }
    # giip #1053 CSN 가드 — 응답이 다른 CSN 소속이라고 하면 절대 실행하지 않는다.
    if ($RowCsn -and $RowCsn -ne $TargetCsn) {
        return @{ Action = 'SKIP'; Reason = 'CSN_MISMATCH'; QueueStatus = '' }
    }
    if (Test-GissueAutoOpsTitle $Title) {
        return @{ Action = 'SKIP'; Reason = 'AUTO_OPS'; QueueStatus = '' }
    }
    if ($Status -eq 'NEEDS_DECISION') {
        return @{ Action = 'SKIP'; Reason = 'NEEDS_DECISION'; QueueStatus = '' }
    }
    $processable = @('PENDING', 'READY', 'IN_PROGRESS', 'REVIEW', 'TESTED')
    if ($processable -notcontains $Status) {
        return @{ Action = 'SKIP'; Reason = 'STATUS_NOT_PROCESSABLE'; QueueStatus = '' }
    }
    if ($InQueue) {
        # 큐가 이미 [OPS] 제외·경과·라벨 정규화를 적용한 행 — 그대로 쓴다.
        return @{ Action = 'RUN'; Reason = ''; QueueStatus = $QueueStatus }
    }
    switch ($Status) {
        'READY' {
            # 경과(기본 60분) 부족으로 큐에 없을 뿐 — 지정 실행이 우회하는 바로 그 조건.
            return @{ Action = 'RUN'; Reason = ''; QueueStatus = 'READY' }
        }
        'IN_PROGRESS' {
            # 신선한(60분 미만) IN_PROGRESS 는 큐에 없다 = 다른 실행이 처리 중이다.
            return @{ Action = 'SKIP'; Reason = 'IN_PROGRESS_ACTIVE'; QueueStatus = '' }
        }
        'REVIEW' { return @{ Action = 'SKIP'; Reason = 'REVIEW_NO_NEW_SIGNAL'; QueueStatus = '' } }
        'TESTED' { return @{ Action = 'SKIP'; Reason = 'REVIEW_NO_NEW_SIGNAL'; QueueStatus = '' } }
        default  { return @{ Action = 'SKIP'; Reason = 'NOT_IN_QUEUE'; QueueStatus = '' } }
    }
}

# SKIP 사유 코드 → 이슈에 남길 운영 코멘트 문구(사람이 읽는 한 줄 + 판정 근거).
function Get-GissueOnlyIsnSkipNote {
    param(
        [Parameter(Mandatory)][string]$Reason,
        [Parameter(Mandatory)][int]$Isn,
        [AllowEmptyString()][string]$Status = ''
    )
    $detail = switch ($Reason) {
        'CSN_MISMATCH'          { '지정된 이슈가 이 CSN 소속이 아닙니다(CSN 가드, giip #1053).' }
        'AUTO_OPS'              { '자동 감지([OPS] 무소식) 이슈는 작업 대상이 아닙니다.' }
        'NEEDS_DECISION'        { 'NEEDS_DECISION 상태라 지정 실행 대상이 아닙니다(사람의 결정이 먼저 필요합니다).' }
        'IN_PROGRESS_ACTIVE'    { '다른 실행이 이미 IN_PROGRESS로 처리 중이라 중복 실행하지 않습니다.' }
        'REVIEW_NO_NEW_SIGNAL' { 'REVIEW/TESTED 재검증 큐에서 제외된 상태입니다(신규 신호 없음 또는 최대 경과 초과).' }
        'STATUS_NOT_PROCESSABLE' { "현재 상태($Status)는 처리 대상 상태가 아닙니다." }
        default                 { "지정 실행 대상 판정을 통과하지 못했습니다(사유: $Reason)." }
    }
    return "[ONLYISN-SKIP] isn=$Isn 번호 지정 실행을 건너뜁니다 — $detail"
}
