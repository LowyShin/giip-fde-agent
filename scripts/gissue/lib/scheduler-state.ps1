# scheduler-state.ps1 — gissue 스케줄러 상태(에이전트 등록, 실행 시작/heartbeat/종료)를 GIIP 에 기록하는 공용 호출(giip #3563).
#
# 근본 원인(2026-10-05 실측): 예전 Record-SchedulerState 는 giipApiSk2 에 폼 키 `sk`/`proc` 로 보냈다. 디스패처는 SK 를
#   `token`, 실행할 SP 를 `text` 로만 읽으므로 `sk`/`proc` 는 무시되고 `help` 가 실행됐다. 응답도 검사하지 않아 WARN 한 줄 없이
#   조용히 실패했고, 그래서 tSchedulerAgent 에 gissue_csn<CSN> 행이 없었고 admin/catquest/schedulers 의 History 가 비어 있었다.
# 올바른 형식(giipAgentLinux lib/scheduler_agent_run.sh 와 같다):
#   token = SK,  text = "<이름> <값...>" (서버가 pApi<이름>bySk 로 조립, 값은 SP 파라미터 선언 순서의 위치 인자),  jsondata = 빈 값
#   - 값은 작은따옴표 리터럴. 값 안의 작은따옴표는 제거(토큰 경계라 이스케이프가 아니라 제거), CR/LF 는 공백. NULL 은 따옴표 없는 NULL.
#   - ⚠️ NULL 도 디스패처가 **문자열**로 넘긴다. VARCHAR 파라미터는 괜찮지만 INT 파라미터(예: @exitCode)에 NULL 을 주면 `nvarchar to int` 변환 오류가 난다(실측).
#     INT 자리에는 숫자 문자열('0')을 채우고, $null 은 문자열 파라미터에만 쓴다.
#   - jsondata 가 비어 있지 않으면 디스패처가 마지막 파라미터로 하나 더 붙인다(giip #2477).
# 반환: 응답 첫 행({RstVal, Proc_MSG}). RstVal 이 200 이 아니거나 통신 실패면 예외 — 호출부가 로그에 남긴다.

function ConvertTo-DispatcherSqlLiteral([string]$Value) {
    $v = ($Value -replace "'", '') -replace '[\r\n]+', ' '
    return "'$v'"
}

function Invoke-SchedulerAgentSp {
    param(
        [Parameter(Mandatory)][string]$ApiUrl,
        [Parameter(Mandatory)][string]$Sk,
        [Parameter(Mandatory)][string]$Name,     # 예: SchedulerAgentRunStart (pApi...BySK 의 접두/접미 제외)
        [object[]]$Values = @()                  # $null 은 SQL NULL
    )
    $parts = foreach ($v in $Values) { if ($null -eq $v) { 'NULL' } else { ConvertTo-DispatcherSqlLiteral ([string]$v) } }
    $text = (@($Name) + @($parts)) -join ' '
    $form = New-Object System.Collections.Specialized.NameValueCollection
    $form.Add('token', $Sk)
    $form.Add('text', $text)
    $form.Add('jsondata', '')
    $wc = New-Object System.Net.WebClient
    $wc.Encoding = [System.Text.Encoding]::UTF8
    $raw = [System.Text.Encoding]::UTF8.GetString($wc.UploadValues($ApiUrl, 'POST', $form))
    $json = $raw | ConvertFrom-Json
    $row = if ($json.data) { @($json.data)[0] } else { $null }
    if ($null -eq $row -or [int]$row.RstVal -ne 200) {
        $msg = if ($row) { "$($row.RstVal) $($row.Proc_MSG)" } elseif ($json.error) { "$($json.error)" } else { 'no data' }
        throw "$Name 실패: $msg"
    }
    return $row
}

# Complete-Run 의 최종 상태 문구를 SP(@status VARCHAR(20))가 쓰는 값으로 바꾼다.
function ConvertTo-SchedulerRunStatus([string]$Status) {
    if ($Status -eq 'DONE') { return 'SUCCEEDED' }
    if ($Status -like 'TIMEOUT*') { return 'TIMED_OUT' }
    return 'FAILED'
}
