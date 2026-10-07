# [giip 3617] page-feedback-analyze.ps1 단위 테스트 (네트워크, 실제 claude 호출, DB 기록 없음 - 외부 호출은 전부 모킹)
# 실행: pwsh -NoProfile -File scripts/gissue/tests/test-page-feedback-analyze.ps1
$ErrorActionPreference = 'Stop'
$ScriptPath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../page-feedback-analyze.ps1')).Path
. $ScriptPath

$fail = 0
function Check($name, [bool]$ok, $detail) {
    if ($ok) { Write-Output "[PASS] $name" } else { $script:fail++; Write-Output "[FAIL] $name - $detail" }
}
function Throws([scriptblock]$b) { try { & $b | Out-Null; return $false } catch { return $true } }

# 한자/가나는 이 파일에 직접 쓰지 않고 코드포인트로 만든다.
$HAN = [string][char]0x4E2D + [char]0x6587    # 한자 2자
$KANA = [string][char]0x3042 + [char]0x30A2   # 가나 2자

function New-Json([string]$sv = 'pass', [string]$sec = 'pass', [string]$all = 'pass', [string]$verdict = 'ACTIONABLE', [string]$summary = '요약입니다', $scope = @('범위1', '범위2'), $acc = @('기준1', '기준2'), [string]$ev = '근거') {
    $o = [ordered]@{
        checks = [ordered]@{
            service_value = @{ result = $sv; evidence = $ev }
            security      = @{ result = $sec; evidence = $ev }
            all_users     = @{ result = $all; evidence = $ev }
        }
        verdict = $verdict; summary = $summary; scope = $scope; acceptance = $acc
    }
    return ($o | ConvertTo-Json -Depth 6 -Compress)
}

# ---- 파싱과 재판정 ----
$d = ConvertFrom-PfaAiText (New-Json)
Check 'p1 세 항목 pass + 모델 ACTIONABLE = ACTIONABLE' ($d.Verdict -eq 'ACTIONABLE') $d.Verdict
foreach ($i in 0..2) {
    foreach ($bad in 'fail', 'uncertain') {
        $a = @('pass', 'pass', 'pass'); $a[$i] = $bad
        $d = ConvertFrom-PfaAiText (New-Json $a[0] $a[1] $a[2])
        Check "p2 항목$($i+1)=$bad 이고 모델이 ACTIONABLE 이어도 REPORT_ONLY 로 강등" ($d.Verdict -eq 'REPORT_ONLY' -and $d.ModelVerdict -eq 'ACTIONABLE') $d.Verdict
    }
}
$d = ConvertFrom-PfaAiText (New-Json -verdict 'REPORT_ONLY')
Check 'p3 세 항목 pass 여도 모델이 REPORT_ONLY 면 REPORT_ONLY' ($d.Verdict -eq 'REPORT_ONLY') $d.Verdict
$d = ConvertFrom-PfaAiText (New-Json -verdict 'NOT_ACTIONABLE' -sv 'fail')
Check 'p4 NOT_ACTIONABLE 은 REPORT_ONLY 로 대체' ($d.Verdict -eq 'REPORT_ONLY') $d.Verdict
$d = ConvertFrom-PfaAiText (New-Json -ev '')
Check 'p5 근거가 빈 pass 는 uncertain 이라 REPORT_ONLY' ($d.Verdict -eq 'REPORT_ONLY' -and $d.Checks.security.Result -eq 'uncertain') $d.Verdict
$d = ConvertFrom-PfaAiText (New-Json -sv 'PASS ' -sec 'Pass')
Check 'p6 pass 대소문자/공백 허용' ($d.Verdict -eq 'ACTIONABLE') $d.Verdict
$d = ConvertFrom-PfaAiText (New-Json -sv 'maybe')
Check 'p7 알 수 없는 result 는 uncertain -> REPORT_ONLY' ($d.Verdict -eq 'REPORT_ONLY' -and $d.Checks.service_value.Result -eq 'uncertain') $d.Verdict
$j = '{"checks":{"service_value":{"result":"pass","evidence":"e"},"security":{"result":"pass","evidence":"e"}},"verdict":"ACTIONABLE","summary":"s","scope":["a"],"acceptance":["b"]}'
$d = ConvertFrom-PfaAiText $j
Check 'p8 세 번째 항목 누락 = uncertain -> REPORT_ONLY' ($d.Verdict -eq 'REPORT_ONLY' -and $d.Checks.all_users.Result -eq 'uncertain') $d.Verdict
$d = ConvertFrom-PfaAiText (New-Json -scope @())
Check 'p9 ACTIONABLE 인데 범위 없음 -> REPORT_ONLY' ($d.Verdict -eq 'REPORT_ONLY') $d.Verdict
$d = ConvertFrom-PfaAiText ("설명 앞부분 `n" + (New-Json) + "`n끝")
Check 'p10 JSON 앞뒤 잡문이 있어도 파싱' ($d.Verdict -eq 'ACTIONABLE') $d.Verdict
Check 'p11 파손 JSON 은 예외(재시도 대상)' (Throws { ConvertFrom-PfaAiText '{"checks": {' })
Check 'p12 JSON 없음은 예외' (Throws { ConvertFrom-PfaAiText '그냥 문장' })
Check 'p13 checks 객체 없음은 예외' (Throws { ConvertFrom-PfaAiText '{"verdict":"ACTIONABLE","summary":"s"}' })
Check 'p14 알 수 없는 verdict 는 예외' (Throws { ConvertFrom-PfaAiText (New-Json -verdict 'MAYBE') })
Check 'p15 요약과 근거가 모두 없으면 예외' (Throws { ConvertFrom-PfaAiText (New-Json -sv 'fail' -sec 'fail' -all 'fail' -verdict 'REPORT_ONLY' -summary '' -ev '') })

# ---- 보안 재필터 ----
Check 's1 HIGH 제외' (-not (Test-PfaEligible @{ risk_level = 'HIGH' }))
Check 's2 SECURITY_SUSPECTED 제외' (-not (Test-PfaEligible @{ triage_category = 'SECURITY_SUSPECTED' }))
Check 's3 SECURE_REVIEW 제외' (-not (Test-PfaEligible @{ triage_category = 'SECURE_REVIEW' }))
Check 's4 일반 건 통과' (Test-PfaEligible @{ risk_level = 'LOW'; triage_category = 'GENERAL' })

# ---- 한자/가나 ----
Check 'c1 한자 감지' (Test-PfaForeign "가나다 $HAN")
Check 'c2 가나 감지' (Test-PfaForeign "라마 $KANA")
Check 'c3 순수 한글은 통과' (-not (Test-PfaForeign '순수 한글 English 123'))
Check 'c4 제거' ((Remove-PfaForeign "좋은 $HAN 기능") -eq '좋은 기능') (Remove-PfaForeign "좋은 $HAN 기능")

# ---- 모킹 준비 ----
$script:apiCalls = New-Object System.Collections.ArrayList
$script:claudeQueue = New-Object System.Collections.ArrayList
$script:claudeCount = 0
$script:comments = New-Object System.Collections.ArrayList
$script:setStatus = New-Object System.Collections.ArrayList
$script:issueStatus = 'NEEDS_DECISION'
$script:registerStatus = 200
function Invoke-PfaApi([string]$Sk, [string]$Name, [hashtable]$Json) {
    [void]$script:apiCalls.Add(@{ Name = $Name; Json = $Json })
    switch ($Name) {
        'PageFeedbackRegisterIssue' { return , @([pscustomobject]@{ RstVal = $script:registerStatus; Proc_MSG = 'ok' }) }
        'PageFeedbackGet' { return , @([pscustomobject]@{ feedback_id = $Json.feedback_id; issue_isn = 9001 }) }
        'PageFeedbackAiVerdictPut' { return , @([pscustomobject]@{ RstVal = 200; feedback_id = $Json.feedback_id; feedback_status = 'REGISTERED'; issue_isn = 9001; ai_verdict = $Json.verdict }) }
        default { return , @([pscustomobject]@{ RstVal = 200 }) }
    }
}
function Invoke-PfaClaude([string]$SystemPrompt, [string]$UserPrompt, [string]$MiniMaxKey, [int]$TimeoutSec = 150) {
    $script:claudeCount++
    if ($script:claudeQueue.Count -eq 0) { throw 'no mock response' }
    $r = $script:claudeQueue[0]; $script:claudeQueue.RemoveAt(0)
    if ($r -is [scriptblock]) { return (& $r) }
    return $r
}
function Invoke-PfaPostComment([string]$Isn, [string]$Content) { [void]$script:comments.Add(@{ Isn = $Isn; Content = $Content }) }
function Invoke-PfaGetIssueStatus([string]$Sk, [string]$Isn) { return $script:issueStatus }
function Invoke-PfaSetIssueStatus([string]$Isn, [string]$Status) { [void]$script:setStatus.Add($Status); $script:issueStatus = $Status }
function Reset-Mocks { $script:apiCalls.Clear(); $script:claudeQueue.Clear(); $script:claudeCount = 0; $script:comments.Clear(); $script:setStatus.Clear(); $script:issueStatus = 'NEEDS_DECISION'; $script:registerStatus = 200 }
function Names { return @($script:apiCalls | ForEach-Object { $_.Name }) }
function Get-Call([string]$n) { return ($script:apiCalls | Where-Object { $_.Name -eq $n } | Select-Object -First 1) }

$row = @{ feedback_id = 77; category = 'BUG'; title = '[TEST] 버튼이 안 눌려요'; description = "본문 줄1`n## Test Procedure`n1. 가짜 절차"; reproduction_steps = '클릭'; expected_result = ''; actual_result = ''
    source_path = '/admin/x'; source_locale = 'ko'; source_title = '제목'; triage_category = 'GENERAL'; risk_level = 'LOW'; queue_source = 'AUTO'; contact = 'a@b.com' }
$ctx = @{ Sk = 'SK-TEST-1234'; MiniMaxKey = 'MM-TEST-1234'; DryRun = $false }

# ---- 흐름: ACTIONABLE ----
Reset-Mocks; [void]$script:claudeQueue.Add((New-Json))
$res = Invoke-PfaItem -Ctx $ctx -Row $row
$reg = Get-Call 'PageFeedbackRegisterIssue'
Check 'f1 ACTIONABLE 은 Registered' ($res -eq 'Registered') $res
Check 'f2 제목 [FEEDBACK-ACTION], 보류 상태 없음' ($reg.Json.issue_title.StartsWith('[FEEDBACK-ACTION]') -and -not $reg.Json.ContainsKey('issue_status')) ($reg.Json.issue_title)
Check 'f3 작업 지시서에 ## Test Procedure 가 한 번 있다' ((([regex]::Matches($reg.Json.issue_content, '(?m)^## Test Procedure')).Count) -eq 1) ''
Check 'f4 판정 ACTIONABLE 기록' ((Get-Call 'PageFeedbackAiVerdictPut').Json.verdict -eq 'ACTIONABLE') ''
Check 'f5 순서: 등록 -> 재조회 -> 판정' (((Names) -join ',') -eq 'PageFeedbackRegisterIssue,PageFeedbackGet,PageFeedbackAiVerdictPut') ((Names) -join ',')
Check 'f6 연락처(메일)가 본문에 없다' (-not $reg.Json.issue_content.Contains('a@b.com')) ''
Check 'f7 코멘트 없음(ACTIONABLE)' ($script:comments.Count -eq 0) ''

# ---- 흐름: REPORT_ONLY ----
Reset-Mocks; [void]$script:claudeQueue.Add((New-Json -all 'uncertain'))
$res = Invoke-PfaItem -Ctx $ctx -Row $row
$reg = Get-Call 'PageFeedbackRegisterIssue'
Check 'r1 REPORT_ONLY 는 Reported' ($res -eq 'Reported') $res
Check 'r2 제목 [FEEDBACK-REPORT] + NEEDS_DECISION 으로 생성' ($reg.Json.issue_title.StartsWith('[FEEDBACK-REPORT]') -and $reg.Json.issue_status -eq 'NEEDS_DECISION') ''
Check 'r3 레포트 이슈 본문에 Test Procedure 헤딩이 없다(사용자 원문 안의 것은 인용 줄이라 헤딩 아님)' (([regex]::Matches($reg.Json.issue_content, '(?m)^## Test Procedure')).Count -eq 0) ''
Check 'r4 레포트 이슈 본문에 수행 범위/완료 기준 절이 없다' (-not ($reg.Json.issue_content -match '(?m)^## (수행 범위|완료 기준)')) ''
Check 'r5 판정 REPORT_ONLY 기록' ((Get-Call 'PageFeedbackAiVerdictPut').Json.verdict -eq 'REPORT_ONLY') ''
Check 'r6 레포트 코멘트 1건, 세 질문 포함, Test Procedure 없음' ($script:comments.Count -eq 1 -and $script:comments[0].Content -match '서비스 도움' -and $script:comments[0].Content -match '전체 유저' -and $script:comments[0].Content -match 'UNCERTAIN' -and $script:comments[0].Content -notmatch 'Test Procedure') ''
Check 'r7 이미 NEEDS_DECISION 이면 상태 전이 호출 없음' ($script:setStatus.Count -eq 0) ''

Reset-Mocks; $script:issueStatus = 'PENDING'; [void]$script:claudeQueue.Add((New-Json -sec 'fail'))
$res = Invoke-PfaItem -Ctx $ctx -Row $row
Check 'r8 SP 가 PENDING 으로 만들었으면 NEEDS_DECISION 으로 전이(이중 방어)' ($script:setStatus.Count -eq 1 -and $script:setStatus[0] -eq 'NEEDS_DECISION' -and $res -eq 'Reported') "$($script:setStatus -join ',') $res"

# ---- 흐름: 모델이 ACTIONABLE 이라 해도 강등 ----
Reset-Mocks; [void]$script:claudeQueue.Add((New-Json -sv 'uncertain' -verdict 'ACTIONABLE'))
$res = Invoke-PfaItem -Ctx $ctx -Row $row
$reg = Get-Call 'PageFeedbackRegisterIssue'
Check 'd1 모델 ACTIONABLE 이어도 항목 uncertain 이면 레포트 전용 이슈' ($res -eq 'Reported' -and $reg.Json.issue_title.StartsWith('[FEEDBACK-REPORT]')) $res

# ---- 흐름: 관리자 승인(MANUAL) ----
Reset-Mocks; [void]$script:claudeQueue.Add((New-Json -sec 'fail' -verdict 'REPORT_ONLY' -scope @() -acc @()))
$m = $row.Clone(); $m.queue_source = 'MANUAL'
$res = Invoke-PfaItem -Ctx $ctx -Row $m
$reg = Get-Call 'PageFeedbackRegisterIssue'
Check 'm1 MANUAL 은 판정과 무관하게 [FEEDBACK-ACTION] 작업 지시서' ($res -eq 'Registered' -and $reg.Json.issue_title.StartsWith('[FEEDBACK-ACTION]') -and $reg.Json.trigger_source -eq 'ADMIN') $res
Check 'm2 MANUAL 은 판정을 기록하지 않는다' ($null -eq (Get-Call 'PageFeedbackAiVerdictPut')) ''
Check 'm3 MANUAL 작업 지시서도 Test Procedure 포함' ($reg.Json.issue_content -match '(?m)^## Test Procedure') ''

# ---- 실패: 파싱 실패는 재시도 기록, 판정 기록 안 함 ----
Reset-Mocks; [void]$script:claudeQueue.Add('JSON 아님')
$res = Invoke-PfaItem -Ctx $ctx -Row $row
Check 'e1 파싱 실패는 Failed' ($res -eq 'Failed') $res
Check 'e2 재시도 기록(ResultPut)만 남고 등록/판정 기록 없음' (((Names) -join ',') -eq 'PageFeedbackIssueResultPut') ((Names) -join ',')
Reset-Mocks; [void]$script:claudeQueue.Add({ throw 'claude 종료 코드 1: 키 MM-TEST-1234 만료' })
Add-PfaSecret 'MM-TEST-1234'
$res = Invoke-PfaItem -Ctx $ctx -Row $row
$errText = (Get-Call 'PageFeedbackIssueResultPut').Json.error
Check 'e3 호출 실패도 재시도 기록, 비밀값은 가려진다' ($res -eq 'Failed' -and $errText -notmatch 'MM-TEST-1234' -and $errText -match '\*\*\*') $errText
Reset-Mocks; $script:registerStatus = 500; [void]$script:claudeQueue.Add((New-Json))
$res = Invoke-PfaItem -Ctx $ctx -Row $row
Check 'e4 등록 거부는 Failed + 재시도 기록, 판정 기록 없음' ($res -eq 'Failed' -and $null -ne (Get-Call 'PageFeedbackIssueResultPut') -and $null -eq (Get-Call 'PageFeedbackAiVerdictPut')) ((Names) -join ',')

# ---- 한자/가나 후처리 ----
Reset-Mocks; [void]$script:claudeQueue.Add((New-Json -summary "요약 $HAN 포함")); [void]$script:claudeQueue.Add((New-Json))
$d = Get-PfaDraft -Row $row -MiniMaxKey 'k'
Check 'h1 오염되면 재생성(2번 호출), 깨끗한 결과 사용' ($script:claudeCount -eq 2 -and $d.Summary -eq '요약입니다') "$($script:claudeCount) $($d.Summary)"
Reset-Mocks; $dirty = New-Json -summary ("요약입니다 요약입니다 요약입니다 요약입니다 요약입니다 요약입니다 $HAN"); [void]$script:claudeQueue.Add($dirty); [void]$script:claudeQueue.Add($dirty)
$d = Get-PfaDraft -Row $row -MiniMaxKey 'k'
Check 'h2 두 번 다 오염되면 문자 제거(소량)' ($script:claudeCount -eq 2 -and -not (Test-PfaForeign (Get-PfaDraftText $d))) ''
Reset-Mocks; $heavy = New-Json -summary ("$HAN$HAN$HAN$HAN$KANA$KANA$HAN$HAN 짧음"); [void]$script:claudeQueue.Add($heavy); [void]$script:claudeQueue.Add($heavy)
Check 'h3 오염이 심하면 예외(재시도 대상)' (Throws { Get-PfaDraft -Row $row -MiniMaxKey 'k' })
Reset-Mocks; $ev = New-Json -ev "$HAN" -summary ('충분히 긴 요약 문장입니다 ' * 12); [void]$script:claudeQueue.Add($ev); [void]$script:claudeQueue.Add($ev)
$d = Get-PfaDraft -Row $row -MiniMaxKey 'k'
Check 'h4 근거가 한자뿐이라 제거 후 비면 pass 가 아니게 되어 REPORT_ONLY' ($d.Verdict -eq 'REPORT_ONLY') $d.Verdict

# ---- 큐 단위(보안 재필터, 드라이런, 시간 상한) ----
function Get-QueueRows { return @() }
function Invoke-PfaApi([string]$Sk, [string]$Name, [hashtable]$Json) {
    [void]$script:apiCalls.Add(@{ Name = $Name; Json = $Json })
    if ($Name -eq 'PageFeedbackIssueQueueList') {
        return , @(
            [pscustomobject]@{ RstVal = 200; feedback_id = 1; queue_source = 'AUTO'; risk_level = 'HIGH'; triage_category = 'GENERAL'; title = 't'; description = 'd' },
            [pscustomobject]@{ RstVal = 200; feedback_id = 2; queue_source = 'AUTO'; risk_level = 'LOW'; triage_category = 'SECURITY_SUSPECTED'; title = 't'; description = 'd' },
            [pscustomobject]@{ RstVal = 200; feedback_id = 3; queue_source = 'AUTO'; risk_level = 'LOW'; triage_category = 'GENERAL'; title = 't'; description = 'd'; source_path = '/p'; source_locale = 'ko' })
    }
    return , @([pscustomobject]@{ RstVal = 200; feedback_id = $Json.feedback_id; issue_isn = 9001; feedback_status = 'REGISTERED' })
}
Reset-Mocks; [void]$script:claudeQueue.Add((New-Json))
$r = Invoke-PfaRun -Ctx @{ Sk = 'S'; MiniMaxKey = 'k'; DryRun = $true } -Batch 5 -MaxMinutes 15
Check 'q1 보안 건 2개는 건너뛰고 claude 는 1번만 호출' ($r.Skipped -eq 2 -and $script:claudeCount -eq 1 -and $r.DryRun -eq 1) "$($r.Skipped) $($script:claudeCount)"
Check 'q2 드라이런은 큐 조회 외 DB 호출 0(쓰기 0)' (((Names) -join ',') -eq 'PageFeedbackIssueQueueList') ((Names) -join ',')
Check 'q3 드라이런은 코멘트/상태 변경 0' ($script:comments.Count -eq 0 -and $script:setStatus.Count -eq 0) ''
Reset-Mocks; [void]$script:claudeQueue.Add('JSON 아님')
$r = Invoke-PfaRun -Ctx @{ Sk = 'S'; MiniMaxKey = 'k'; DryRun = $true } -Batch 5 -MaxMinutes 15
Check 'q4 드라이런에서 실패해도 재시도 기록(쓰기) 없음' ($r.Failed -eq 1 -and ((Names) -join ',') -eq 'PageFeedbackIssueQueueList') ((Names) -join ',')
Reset-Mocks
$r = Invoke-PfaRun -Ctx @{ Sk = 'S'; MiniMaxKey = 'k'; DryRun = $false } -Batch 5 -MaxMinutes 0
Check 'q5 시간 상한 0분이면 모든 건을 건너뜀(분석 호출 0)' ($script:claudeCount -eq 0 -and $r.Skipped -eq 3) "$($r.Skipped)"

# ---- 한 건 실패가 다음 건을 막지 않음 ----
function Invoke-PfaApi([string]$Sk, [string]$Name, [hashtable]$Json) {
    [void]$script:apiCalls.Add(@{ Name = $Name; Json = $Json })
    if ($Name -eq 'PageFeedbackIssueQueueList') {
        return , @(
            [pscustomobject]@{ RstVal = 200; feedback_id = 11; queue_source = 'AUTO'; risk_level = 'LOW'; triage_category = 'GENERAL'; title = 'a'; description = 'd' },
            [pscustomobject]@{ RstVal = 200; feedback_id = 12; queue_source = 'AUTO'; risk_level = 'LOW'; triage_category = 'GENERAL'; title = 'b'; description = 'd' })
    }
    if ($Name -eq 'PageFeedbackGet') { return , @([pscustomobject]@{ feedback_id = $Json.feedback_id; issue_isn = 9002 }) }
    if ($Name -eq 'PageFeedbackAiVerdictPut') { return , @([pscustomobject]@{ RstVal = 200; feedback_id = $Json.feedback_id; feedback_status = 'REGISTERED'; issue_isn = 9002 }) }
    return , @([pscustomobject]@{ RstVal = 200 })
}
Reset-Mocks; [void]$script:claudeQueue.Add('깨진 응답'); [void]$script:claudeQueue.Add((New-Json))
$r = Invoke-PfaRun -Ctx @{ Sk = 'S'; MiniMaxKey = 'k'; DryRun = $false } -Batch 5 -MaxMinutes 15
Check 'i1 첫 건 실패, 둘째 건은 등록' ($r.Failed -eq 1 -and $r.Registered -eq 1) "$($r.Failed) $($r.Registered)"

# ---- 락 ----
$lockPath = Join-Path ([System.IO.Path]::GetTempPath()) ("pfa-test-" + [guid]::NewGuid().ToString('N') + '/x.lock')
$l1 = Enter-PfaLock $lockPath
$l2 = Enter-PfaLock $lockPath
Check 'k1 첫 락은 성공, 중복 락은 null' (($null -ne $l1) -and ($null -eq $l2))
$l1.Dispose()
$l3 = Enter-PfaLock $lockPath
Check 'k2 해제 후 다시 잡을 수 있다' ($null -ne $l3)
$l3.Dispose(); Remove-Item -LiteralPath (Split-Path -Parent $lockPath) -Recurse -Force

# ---- 설정 게이트(기본 비활성) ----
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("pfa-cfg-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null
function Write-Cfg($name, $text) { $p = Join-Path $tmp $name; Set-Content -LiteralPath $p -Value $text -Encoding UTF8; return $p }
Check 'g1 파일 없음 = 비활성' (-not (Get-PfaSettings (Join-Path $tmp 'nope.json')).Enabled)
Check 'g2 키 없음 = 비활성' (-not (Get-PfaSettings (Write-Cfg 'a.json' '{"csn":{}}')).Enabled)
Check 'g3 enabled=false = 비활성' (-not (Get-PfaSettings (Write-Cfg 'b.json' '{"pageFeedbackAnalyze":{"enabled":false}}')).Enabled)
Check 'g4 enabled="true"(문자열) = 비활성' (-not (Get-PfaSettings (Write-Cfg 'c.json' '{"pageFeedbackAnalyze":{"enabled":"true"}}')).Enabled)
Check 'g5 깨진 JSON = 비활성' (-not (Get-PfaSettings (Write-Cfg 'd.json' '{ 깨짐')).Enabled)
$s = Get-PfaSettings (Write-Cfg 'e.json' '{"pageFeedbackAnalyze":{"enabled":true}}')
Check 'g6 enabled=true 만 켜면 dryRun 은 기본 true(안전)' ($s.Enabled -and $s.DryRun) ''
$s = Get-PfaSettings (Write-Cfg 'f.json' '{"pageFeedbackAnalyze":{"enabled":true,"dryRun":false,"batch":50,"maxMinutes":7}}')
Check 'g7 dryRun=false 명시 시 실제 기록, 배치 상한 20' ($s.Enabled -and -not $s.DryRun -and $s.Batch -eq 20 -and $s.MaxMinutes -eq 7) ''
$out = & pwsh -NoProfile -NonInteractive -File $ScriptPath -ConfigFile (Join-Path $tmp 'a.json') 2>&1
Check 'g8 비활성 실행은 "[SKIP] 비활성" 한 줄만 출력하고 종료 코드 0' (($LASTEXITCODE -eq 0) -and (@($out).Count -eq 1) -and ("$($out | Select-Object -First 1)" -eq '[SKIP] 비활성')) ("$LASTEXITCODE | $out")
Remove-Item -LiteralPath $tmp -Recurse -Force

# ---- 스케줄러 에이전트 등록 ----
$script:spCalls = New-Object System.Collections.ArrayList
function Invoke-SchedulerAgentSp([string]$ApiUrl, [string]$Sk, [string]$Name, [object[]]$Values = @()) { [void]$script:spCalls.Add(@{ Name = $Name; Values = $Values }); return @{ RstVal = 200 } }
Write-PfaSchedulerState -Action upsert -Sk 'S' -RunIdKey '' -Counts @{} -Status '' -Summary ''
Write-PfaSchedulerState -Action runStart -Sk 'S' -RunIdKey 'run1' -Counts @{ Picked = 3 } -Status '' -Summary ''
Write-PfaSchedulerState -Action runEnd -Sk 'S' -RunIdKey 'run1' -Counts @{ Processed = 2; Skipped = 1; Failed = 0 } -Status 'DONE' -Summary 'ACTIONABLE 1건, REPORT_ONLY 1건'
Check 'a1 Upsert/RunStart/RunEnd 순서로 호출' ((($script:spCalls | ForEach-Object { $_.Name }) -join ',') -eq 'SchedulerAgentUpsert,SchedulerAgentRunStart,SchedulerAgentRunEnd') (($script:spCalls | ForEach-Object { $_.Name }) -join ',')
Check 'a2 agentKey=feedback_analyzer_csn47, 스케줄 설명 cron :12/:32/:52' ($script:spCalls[0].Values[0] -eq 'feedback_analyzer_csn47' -and $script:spCalls[0].Values[5] -eq 'cron :12/:32/:52') ($script:spCalls[0].Values -join '|')
Check 'a3 RunEnd 에 처리 건수/요약/종료코드 0' ($script:spCalls[2].Values[3] -eq '2' -and $script:spCalls[2].Values[7] -match 'REPORT_ONLY' -and $script:spCalls[2].Values[6] -eq '0') ($script:spCalls[2].Values -join '|')
function Invoke-SchedulerAgentSp([string]$ApiUrl, [string]$Sk, [string]$Name, [object[]]$Values = @()) { throw 'boom' }
Check 'a4 등록 호출이 실패해도 예외가 새지 않는다' (-not (Throws { Write-PfaSchedulerState -Action runEnd -Sk 'S' -RunIdKey 'r' -Counts @{ Processed = 0; Skipped = 0; Failed = 0 } -Status 'DONE' -Summary '' }))

# ---- 소스 점검: 도구 차단, 권한 우회 금지 ----
$src = Get-Content -LiteralPath $ScriptPath -Raw -Encoding UTF8
$code = (($src -split "`n") | Where-Object { $_ -notmatch '^\s*#' }) -join "`n"
Check 'z1 코드에 --dangerously-skip-permissions 실행 인자가 없다' ($code -notmatch 'dangerously-skip-permissions')
Check 'z2 도구 전부 차단 옵션 --tools "" 사용' ($code -match "'--tools', ''")
Check 'z3 MCP/설정/스킬 로드 차단' ($code -match 'strict-mcp-config' -and $code -match "'--setting-sources', ''" -and $code -match 'disable-slash-commands')
Check 'z4 비밀값을 Write-Host 로 직접 찍지 않는다' ($code -notmatch 'Write-(Host|Output)[^\n]*\$(sk|key|MiniMaxKey)\b')
Check 'z5 스크립트 소스에 한자/가나가 없다' (-not (Test-PfaForeign $src))

if ($fail -gt 0) { Write-Output "FAILED: $fail"; exit 1 }
Write-Output 'ALL PASS'
