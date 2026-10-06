# scheduler-state.ps1 순수 함수 단위 테스트(네트워크 없음). 실행: pwsh -File scripts/gissue/tests/test-scheduler-state.ps1
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../lib/scheduler-state.ps1')
function Assert-Eq($a, $b, $m) { if ($a -ne $b) { throw "FAIL $m : expected [$b] got [$a]" } }

Assert-Eq (ConvertTo-DispatcherSqlLiteral "abc") "'abc'" '기본 인용'
Assert-Eq (ConvertTo-DispatcherSqlLiteral "it's") "'its'" '작은따옴표는 제거(토큰 경계)'
Assert-Eq (ConvertTo-DispatcherSqlLiteral "a`r`nb") "'a b'" 'CR/LF 는 공백'
Assert-Eq (ConvertTo-SchedulerRunStatus 'DONE') 'SUCCEEDED' 'DONE'
Assert-Eq (ConvertTo-SchedulerRunStatus 'TIMEOUT (105분) — 중단') 'TIMED_OUT' 'TIMEOUT'
Assert-Eq (ConvertTo-SchedulerRunStatus 'ZOMBIE') 'FAILED' '그 외'

# text 조립(WebClient 를 가로채 폼 값을 검사)
$script:sent = $null
function New-Object { param($TypeName, $ArgumentList)
    if ($TypeName -eq 'System.Net.WebClient') {
        $o = [pscustomobject]@{ Encoding = $null }
        $o | Add-Member ScriptMethod UploadValues { param($u, $m, $f) $script:sent = $f; [System.Text.Encoding]::UTF8.GetBytes('{"data":[{"RstVal":200,"Proc_MSG":"200|ok"}]}') }
        return $o
    }
    Microsoft.PowerShell.Utility\New-Object @PSBoundParameters
}
$row = Invoke-SchedulerAgentSp -ApiUrl 'http://x' -Sk 'SK123' -Name 'SchedulerAgentRunEnd' -Values @('run_1', 'gissue_csn47', 'SUCCEEDED', 3, 0, 0, $null, "끝 'x'")
Assert-Eq $script:sent['token'] 'SK123' 'SK 는 token 키'
Assert-Eq $script:sent['text'] "SchedulerAgentRunEnd 'run_1' 'gissue_csn47' 'SUCCEEDED' '3' '0' '0' NULL '끝 x'" 'text 조립(NULL 은 따옴표 없음)'
Assert-Eq $script:sent['jsondata'] '' 'jsondata 는 비움'
Assert-Eq $script:sent['sk'] $null 'sk 키는 쓰지 않음'
Assert-Eq $script:sent['proc'] $null 'proc 키는 쓰지 않음'
Assert-Eq ([int]$row.RstVal) 200 '성공 응답'
Write-Host 'PASS test-scheduler-state'
