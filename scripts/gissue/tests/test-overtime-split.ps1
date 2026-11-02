# test-overtime-split.ps1 — 2시간 초과 실행 처리 규칙(giip 4429)의 회귀 테스트
#
# 고정하는 것(이슈 완료조건):
#   (1) 임계 미만이면 무동작
#   (2) 임계 초과 시 순서 보장: 원인 코멘트 -> 서브 이슈 -> 종료/락 정리 -> 원본 코멘트 -> DONE
#   (3) 분할 불가면 DONE 하지 않는다(서브 이슈 없음, READY 복귀)
#   (4) 같은 원본의 미해결 서브 이슈가 있으면 새로 만들지 않는다(rule 69-4)
#   (5) 락 정리 범위: 이 러너가 만든 것만, 다른 CSN/다른 인스턴스(생존 PID)의 락은 건드리지 않는다
#   (6) [SPLIT-CLOSE] 마커가 review-done-audit 감사에서 면제된다(무한루프 방지)
#   (7) Shadow 모드에서는 쓰기 포트 호출이 0건이다
# 실제 이슈·락·프로세스·네트워크를 건드리지 않는다 — 시간, 잡 출력, 포트를 전부 가짜로 주입한다.
#
# 실행: powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gissue/tests/test-overtime-split.ps1

$ErrorActionPreference = 'Stop'
$gissueDir = Split-Path -Parent $PSScriptRoot
. (Join-Path $gissueDir 'lib/overtime-split.ps1')
. (Join-Path $gissueDir 'gissue-audit-lib.ps1')

$script:fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  ok   $msg" }
    else { Write-Host "  FAIL $msg" -ForegroundColor Red; $script:fail++ }
}

# 환경변수 오염 방지
$saved = @{}
foreach ($k in 'GISSUE_OVERTIME_SPLIT_MODE', 'GISSUE_OVERTIME_RUN_DEADLINE_MIN', 'GISSUE_OVERTIME_ISSUE_MIN', 'GISSUE_TASK_LIMIT_MIN') {
    $saved[$k] = [Environment]::GetEnvironmentVariable($k)
    [Environment]::SetEnvironmentVariable($k, $null)
}

Write-Host '[A] 설정/모드 해석'
$s = Get-GissueOvertimeSettings
Assert ($s.Mode -eq 'Shadow') '기본 모드는 Shadow'
Assert ($s.RunDeadlineMin -eq 105 -and $s.IssueMin -eq 105 -and $s.TaskLimitMin -eq 120) '기본값 105/105/120'
Assert ((Get-GissueOvertimeMode 'live') -eq 'Live') 'live -> Live'
Assert ((Get-GissueOvertimeMode ' Live ') -eq 'Live') '공백 포함 Live -> Live'
Assert ((Get-GissueOvertimeMode 'off') -eq 'Off') 'off -> Off'
Assert ((Get-GissueOvertimeMode 'bogus') -eq 'Shadow') '알 수 없는 값은 Shadow(안전 쪽)'
$env:GISSUE_OVERTIME_SPLIT_MODE = 'Live'
Assert ((Get-GissueOvertimeSettings).Mode -eq 'Live') '환경변수 Live 반영'
Assert ((Get-GissueOvertimeSettings 'Shadow').Mode -eq 'Shadow') '명시값이 환경변수보다 우선'
[Environment]::SetEnvironmentVariable('GISSUE_OVERTIME_SPLIT_MODE', $null)
$c = Get-GissueOvertimeSettings $null 200 $null 120
Assert ($c.RunDeadlineMin -eq 110 -and $c.Clamped) '마감시각은 (제한-10분) 이하로 보정'
$bad = Get-GissueOvertimeSettings $null 'abc' '-5' $null
Assert ($bad.RunDeadlineMin -eq 105 -and $bad.IssueMin -eq 105) '숫자가 아니거나 음수면 기본값'

Write-Host '[B] 과시간 판정(순수) — 임계 미만 무동작'
$p0 = [datetime]::Parse('2026-01-01T00:00:00Z', [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind)
$set = Get-GissueOvertimeSettings
$t1 = Test-GissueOvertime $p0.AddMinutes(104) $p0 $null $set
Assert (-not $t1.Over) '프로세스 104분 = 임계 미만'
$t2 = Test-GissueOvertime $p0.AddMinutes(105) $p0 $null $set
Assert ($t2.Over -and $t2.Reason -eq 'run') '프로세스 105분 = 초과(run)'
$t3 = Test-GissueOvertime $p0.AddMinutes(60) $p0 $p0.AddMinutes(-50) $set
Assert ($t3.Over -and $t3.Reason -eq 'issue') '이슈 시작 후 110분이면 프로세스 60분이어도 초과(issue)'
$t4 = Test-GissueOvertime $p0.AddMinutes(60) $p0 $p0.AddMinutes(10) $set
Assert (-not $t4.Over) '이슈 50분 + 프로세스 60분 = 임계 미만'

Write-Host '[C] 처리 중 이슈 식별'
$lines = @('[REPO-MAINT] x', '[ISSUE-T0] isn=100 status=READY utc=2026-01-01T00:10:00.0000000Z', '[ISSUE] isn=100 status=READY elapsed=5분 cap=40분 처리 시작')
$f = Get-GissueInFlightIssue $lines
Assert ($f -and $f.Isn -eq 100 -and $f.Status -eq 'READY') 'T0 만 있으면 처리 중'
Assert ($f.StartUtc.ToUniversalTime().Minute -eq 10) '시작 시각 파싱'
$f2 = Get-GissueInFlightIssue ($lines + '[ISSUE-END] isn=100')
Assert ($null -eq $f2) 'END 가 있으면 처리 중 아님'
$f3 = Get-GissueInFlightIssue ($lines + '[ISSUE-END] isn=100' + '[ISSUE-T0] isn=101 status=PENDING utc=2026-01-01T01:00:00.0000000Z')
Assert ($f3 -and $f3.Isn -eq 101) '다음 이슈의 T0 가 있으면 그 이슈'
Assert ($null -eq (Get-GissueInFlightIssue @())) '출력 없음 -> 처리 중 이슈 없음'

# ── 가짜 포트 ────────────────────────────────────────────────────────────
function New-FakePorts($opts) {
    # 스크립트블록은 클로저가 아니므로 상태는 $script: 변수에 둔다(포트가 라이브러리 안에서 호출될 때도 이 스크립트 스코프를 본다).
    $script:FakeCalls = New-Object System.Collections.ArrayList
    $script:FakeOpts = @{ CauseOk = $true; CloseOk = $true; RegisterFail = @(); ExistingRows = @(); Locks = @(); StatusOk = $true; ThrowOnWrite = $false }
    foreach ($k in $opts.Keys) { $script:FakeOpts[$k] = $opts[$k] }
    $script:FakeState = @{ regN = 0; nextIsn = 9000 }
    $script:lastChildTitles = @()
    $ports = @{
        Log = { param($m) [void]$script:FakeCalls.Add("log:$m") }
        FindOpenChildren = { param($isn) [void]$script:FakeCalls.Add('read:find-children'); if ($script:FakeOpts.FindFail) { throw 'find failed' }; return $script:FakeOpts.ExistingRows }
        ListLocks = { [void]$script:FakeCalls.Add('read:list-locks'); return $script:FakeOpts.Locks }
        PostComment = {
            param($isn, $body)
            if ($script:FakeOpts.ThrowOnWrite) { throw 'WRITE-IN-SHADOW' }
            $kind = if ($body -match '^\[OVERTIME-REPORT\]') { 'cause' } elseif ($body -match '^\[SPLIT-CLOSE\]') { 'close' } elseif ($body -match '^\[OVERTIME-NOSPLIT\]') { 'nosplit' } else { 'other' }
            [void]$script:FakeCalls.Add("write:comment:$kind")
            if ($kind -eq 'cause') { return $script:FakeOpts.CauseOk }
            if ($kind -eq 'close') { return $script:FakeOpts.CloseOk }
            return $true
        }
        RegisterChild = {
            param($title, $content)
            if ($script:FakeOpts.ThrowOnWrite) { throw 'WRITE-IN-SHADOW' }
            $script:FakeState.regN++
            if (@($script:FakeOpts.RegisterFail) -contains $script:FakeState.regN) { [void]$script:FakeCalls.Add('write:register-child:FAIL'); return $null }
            $script:FakeState.nextIsn++
            [void]$script:FakeCalls.Add("write:register-child:$($script:FakeState.nextIsn)")
            $script:lastChildTitles += @($title)
            return $script:FakeState.nextIsn
        }
        StopJob = { if ($script:FakeOpts.ThrowOnWrite) { throw 'WRITE-IN-SHADOW' }; [void]$script:FakeCalls.Add('write:stop-job') }
        RemoveLocks = { param($t) if ($script:FakeOpts.ThrowOnWrite) { throw 'WRITE-IN-SHADOW' }; [void]$script:FakeCalls.Add("write:remove-locks:$(@($t).Count)") }
        SetStatus = { param($isn, $st, $why) if ($script:FakeOpts.ThrowOnWrite) { throw 'WRITE-IN-SHADOW' }; [void]$script:FakeCalls.Add("write:set-status:$st"); return $script:FakeOpts.StatusOk }
    }
    [pscustomobject]@{ Ports = $ports; Calls = $script:FakeCalls }
}
function Get-Writes($calls) { @($calls | Where-Object { $_ -like 'write:*' }) }

$issueContent = @"
## 배경
테스트 이슈

## 완료조건
- [x] 이미 끝난 항목
- [ ] 첫 번째 잔여 항목
- [ ] 두 번째 잔여 항목
- [ ] 세 번째 잔여 항목

``````verify
echo original-verify
``````
"@
$jobOut = @('[REPO-MAINT] 저장소 정비 세션 시작', '[ENGINE] MiniMax 우선 시도 (model=X)', '[ENGINE] MiniMax 1차 시도 실패(exit=-1) → 재시도 1회',
    '[ISSUE-T0] isn=500 status=READY utc=2026-01-01T00:20:00.0000000Z', '[ISSUE] isn=500 status=READY elapsed=5분 cap=40분 처리 시작')
$liveSet = Get-GissueOvertimeSettings 'Live'
$isAliveFake = { param($pid2) return ($pid2 -eq 4242) }   # 4242 만 생존
function New-Base($outLines, $minutes, $locks = @()) {
    @{
        NowUtc = $p0.AddMinutes($minutes); ProcessStartUtc = $p0; OutputLines = $outLines; Settings = $liveSet; Csn = '111'
        RunnerPid = 1000; JobPids = @(2000); IsAlive = $isAliveFake; IssueUrlBase = 'https://example.invalid/giip-issues/'
        LoadIssue = { param($isn) [pscustomobject]@{ Title = '테스트 이슈 제목'; Status = 'READY'; Content = $issueContent; Comments = @() } }
    }
}

Write-Host '[D] (1) 임계 미만 무동작 — 진입점 Invoke-GissueOvertimeGuard'
$fp = New-FakePorts @{}
$g = Invoke-GissueOvertimeGuard (New-Base $jobOut 60) 'Live' $fp.Ports
Assert (-not $g.Over -and $g.Reason -eq 'under-threshold') '임계 미만 -> Over=false'
Assert ($fp.Calls.Count -eq 0) '임계 미만 -> 포트 호출 0건(읽기 포함)'

Write-Host '[E] (2) Live: 임계 초과 시 순서 보장'
$script:lastChildTitles = @()
$locks = @(
    [pscustomobject]@{ Kind = 'csn-lock'; Path = 'L111'; Csn = '111'; Pid = 1000 }
)
$fp = New-FakePorts @{ Locks = $locks }
$g = Invoke-GissueOvertimeGuard (New-Base $jobOut 106 $locks) 'Live' $fp.Ports
$r = $g.Result
Assert ($g.Over -and $r.Mode -eq 'Live') '임계 초과 -> 처리됨(Live)'
$w = Get-Writes $fp.Calls
$expected = @('write:comment:cause', 'write:register-child:9001', 'write:register-child:9002', 'write:register-child:9003', 'write:stop-job', 'write:remove-locks:1', 'write:comment:close', 'write:set-status:DONE')
Assert (($w -join '|') -eq ($expected -join '|')) "쓰기 순서 = 원인 코멘트 -> 서브 이슈 -> 종료 -> 락 정리 -> 원본 코멘트 -> DONE (실제: $($w -join ' > '))"
Assert ($r.FinalStatus -eq 'DONE') '최종 DONE'
Assert (@($r.ChildIsns).Count -eq 3) '서브 이슈 3건(잔여 항목 3건, 최대 5)'
Assert (($script:lastChildTitles -join ';') -match '원본 giip 500 분해 1/3' -and ($script:lastChildTitles -join ';') -match '분해 3/3') '제목 관례: (원본 giip <isn> 분해 i/N)'
Assert (@($r.Errors).Count -eq 0) '오류 없음'

Write-Host '[F] 원인 보고 내용 — 모르면 미상'
$cause = Get-GissueOvertimeCause $jobOut 500 $p0.AddMinutes(20) $p0.AddMinutes(106) $g.Check
Assert ($cause.Known -and $cause.Summary -match '재시도') '단계 줄이 있으면 마지막 단계(재시도 구간)를 보고'
Assert ($cause.Summary -match '미상') '한계(엔진 안 동작은 미상)를 명시'
$causeEmpty = Get-GissueOvertimeCause @() $null $null $p0.AddMinutes(106) $g.Check
Assert ((-not $causeEmpty.Known) -and $causeEmpty.Summary -match '미상') '잡 출력이 없으면 미상'

Write-Host '[G] (3) 분할 불가 시 DONE 하지 않는다'
$noItems = @{ Content = "## 완료조건`n- [x] 전부 끝남`n"; }
$base = New-Base $jobOut 106
$base.LoadIssue = { param($isn) [pscustomobject]@{ Title = 'T'; Status = 'READY'; Content = "## 완료조건`n- [x] 전부 끝남`n"; Comments = @() } }
$fp = New-FakePorts @{}
$g = Invoke-GissueOvertimeGuard $base 'Live' $fp.Ports
$w = Get-Writes $fp.Calls
Assert (-not ($w -contains 'write:set-status:DONE')) '분할 불가 -> DONE 안 함'
Assert (-not ($w | Where-Object { $_ -like 'write:register-child*' })) '분할 불가 -> 서브 이슈 등록 0건'
Assert (($w -contains 'write:set-status:READY') -and ($w -contains 'write:comment:nosplit')) '분할 불가 -> 사유 코멘트 + READY 복귀(TIMEBOX 관례)'
Assert (($w -contains 'write:stop-job') -and ($w -contains 'write:remove-locks:0')) '분할 불가여도 종료·정리는 수행'
Assert ($g.Result.FinalStatus -eq 'READY' -and -not $g.Result.Splittable) '결과: READY / 분할 불가'

Write-Host '[H] (3b) 원인 코멘트 실패 / 일부 등록 실패 / 종결 코멘트 실패 -> DONE 안 함'
$fp = New-FakePorts @{ CauseOk = $false }
$g = Invoke-GissueOvertimeGuard (New-Base $jobOut 106) 'Live' $fp.Ports
$w = Get-Writes $fp.Calls
Assert ((-not ($w | Where-Object { $_ -like 'write:register-child*' })) -and -not ($w -contains 'write:set-status:DONE')) '원인 보고 실패 -> 분할·DONE 보류'
Assert ($w -contains 'write:stop-job') '원인 보고 실패여도 종료는 수행(외부 강제 종료가 곧 온다)'
$script:lastChildTitles = @()
$fp = New-FakePorts @{ RegisterFail = @(2) }
$g = Invoke-GissueOvertimeGuard (New-Base $jobOut 106) 'Live' $fp.Ports
$w = Get-Writes $fp.Calls
Assert (-not ($w -contains 'write:set-status:DONE') -and ($w -contains 'write:set-status:READY')) '서브 이슈 일부 등록 실패 -> DONE 안 함, READY'
$fp = New-FakePorts @{ CloseOk = $false }
$g = Invoke-GissueOvertimeGuard (New-Base $jobOut 106) 'Live' $fp.Ports
$w = Get-Writes $fp.Calls
Assert (-not ($w -contains 'write:set-status:DONE')) '[SPLIT-CLOSE] 코멘트 실패 -> DONE 안 함'

Write-Host '[I] (4) 중복 서브 이슈 가드 (rule 69-4)'
$rowsOpen = @([pscustomobject]@{ Isn = 777; Status = 'READY'; Title = '[후속] 무언가 (원본 giip #500)' })
$fp = New-FakePorts @{ ExistingRows = $rowsOpen }
$g = Invoke-GissueOvertimeGuard (New-Base $jobOut 106) 'Live' $fp.Ports
$w = Get-Writes $fp.Calls
Assert (-not ($w | Where-Object { $_ -like 'write:register-child*' })) '미해결 후속이 있으면 새로 등록하지 않는다'
Assert (($w -contains 'write:set-status:DONE') -and ($g.Result.ChildIsns -contains 777)) '기존 이슈를 서브 이슈로 쓰고 DONE'
$rowsDone = @([pscustomobject]@{ Isn = 778; Status = 'DONE'; Title = '(원본 giip 500 분해 1/2)' }, [pscustomobject]@{ Isn = 779; Status = 'CANCELLED'; Title = '(원본 giip 500 분해 2/2)' },
    [pscustomobject]@{ Isn = 780; Status = 'READY'; Title = '(원본 giip 5001 분해 1/2)' })
$fp = New-FakePorts @{ ExistingRows = $rowsDone }
$g = Invoke-GissueOvertimeGuard (New-Base $jobOut 106) 'Live' $fp.Ports
Assert (@(Get-Writes $fp.Calls | Where-Object { $_ -like 'write:register-child*' }).Count -eq 3) '종결된 후속/다른 원본(5001)은 중복으로 보지 않는다'

$fp = New-FakePorts @{ FindFail = $true }
$g = Invoke-GissueOvertimeGuard (New-Base $jobOut 106) 'Live' $fp.Ports
Assert (-not (Get-Writes $fp.Calls | Where-Object { $_ -like 'write:register-child*' }) -and -not ((Get-Writes $fp.Calls) -contains 'write:set-status:DONE')) '기존 서브 이슈 조회 실패 -> 중복 등록 위험이라 등록·DONE 보류(fail-closed)'
Assert ((Get-Writes $fp.Calls) -contains 'write:set-status:READY') '조회 실패 -> READY 복귀'

Write-Host '[J] (5) 락 정리 범위'
$isAlive = { param($x) return ($x -eq 4242) }
$recs = @(
    [pscustomobject]@{ Kind = 'csn-lock'; Path = 'own.lock'; Csn = '111'; Pid = 1000 },
    [pscustomobject]@{ Kind = 'csn-lock'; Path = 'otherinst.lock'; Csn = '111'; Pid = 3333 },
    [pscustomobject]@{ Kind = 'csn-lock'; Path = 'othercsn.lock'; Csn = '222'; Pid = 1000 },
    [pscustomobject]@{ Kind = 'repo-lock'; Path = 'repo-own'; Holder = 'gissue-csn111:2000' },
    [pscustomobject]@{ Kind = 'repo-lock'; Path = 'repo-dead'; Holder = 'gissue-csn111:5555' },
    [pscustomobject]@{ Kind = 'repo-lock'; Path = 'repo-alive-other'; Holder = 'gissue-csn111:4242' },
    [pscustomobject]@{ Kind = 'repo-lock'; Path = 'repo-othercsn-dead'; Holder = 'gissue-csn222:5555' },
    [pscustomobject]@{ Kind = 'repo-lock'; Path = 'repo-human'; Holder = 'push_with_auth:5555' }
)
$sel = Get-GissueOvertimeLockTargets $recs '111' 1000 @(2000) $isAlive
$names = @($sel.Targets | ForEach-Object { $_.Path })
Assert (($names -contains 'own.lock') -and ($names -contains 'repo-own') -and ($names -contains 'repo-dead')) '이 러너의 CSN 락 / 이 잡 소유 repo 락 / 죽은 PID repo 락은 정리'
Assert (-not ($names -contains 'otherinst.lock')) '다른 인스턴스(PID 다름)의 CSN 락은 유지'
Assert (-not ($names -contains 'othercsn.lock') -and -not ($names -contains 'repo-othercsn-dead')) '다른 CSN 의 락은 유지'
Assert (-not ($names -contains 'repo-alive-other')) '생존 PID 의 repo 락은 유지'
Assert (-not ($names -contains 'repo-human')) 'gissue 잡이 아닌 holder 는 유지'
Assert ($names.Count -eq 3) "정리 대상은 정확히 3건 (실제: $($names -join ','))"

Write-Host '[K] (6) [SPLIT-CLOSE] 마커 — 감사 면제'
$closeBody = Format-GissueSplitCloseComment 500 @(9001, 9002) 'https://example.invalid/giip-issues/' $liveSet
$cm = @([pscustomobject]@{ content = $closeBody; issuetype = 'note'; regdate = '2026-01-01T02:00:00Z' })
Assert (Test-HasSplitCloseMarker $cm) 'Format 이 만든 종결 코멘트는 유효 마커로 인식'
Assert ($closeBody -match '분할 이전') '코멘트에 "분할 이전" 명시'
Assert (($closeBody -split "`r?`n")[0] -match '^\[SPLIT-CLOSE\]') '첫 줄이 [SPLIT-CLOSE]'
Assert (-not (Test-HasSplitCloseMarker @([pscustomobject]@{ content = "[SPLIT-CLOSE]`n분할 이전 종결" }))) '서브 이슈 번호가 없으면 무효'
Assert (-not (Test-HasSplitCloseMarker @([pscustomobject]@{ content = "[SPLIT-CLOSE]`ngiip 9001 서브 이슈" }))) '"분할 이전" 문구가 없으면 무효'
Assert (-not (Test-HasSplitCloseMarker @([pscustomobject]@{ content = "본문 중간에 [SPLIT-CLOSE]`n분할 이전 giip 9001" }))) '첫 줄이 마커가 아니면 무효'
Assert (-not (Test-HasSplitCloseMarker @([pscustomobject]@{ content = "그냥 코멘트 giip 9001" }))) '마커 없는 일반 코멘트는 무효'
$auditSrc = Get-Content -LiteralPath (Join-Path $gissueDir 'review-done-audit.ps1') -Raw -Encoding UTF8
$iExempt = $auditSrc.IndexOf('Test-HasSplitCloseMarker $comments')
$iClassify = $auditSrc.IndexOf('Get-IssueClassification $allText $latestCommentText')
$iPrEval = $auditSrc.IndexOf('Test-IssueHasMergedPr $isn $repos')
Assert ($iExempt -gt 0) 'review-done-audit.ps1 이 Test-HasSplitCloseMarker 를 호출'
Assert (($iExempt -lt $iClassify) -and ($iExempt -lt $iPrEval)) '면제 판정이 분류/PR 대조/체크리스트 판정보다 앞에 있다(DONE 되돌림 불가)'

Write-Host '[L] (7) Shadow: 쓰기 0건'
$shadowSet = Get-GissueOvertimeSettings 'Shadow'
$baseS = New-Base $jobOut 106
$baseS.Settings = $shadowSet
$fp = New-FakePorts @{ ThrowOnWrite = $true; Locks = $locks }
$g = Invoke-GissueOvertimeGuard $baseS 'Shadow' $fp.Ports
Assert ($g.Over -and $g.Result.Mode -eq 'Shadow') 'Shadow 에서도 과시간은 판정'
Assert ((Get-Writes $fp.Calls).Count -eq 0 -and $g.Result.WriteCalls -eq 0) 'Shadow -> 쓰기 포트 호출 0건'
Assert (@($g.Result.Errors).Count -eq 0) 'Shadow -> 오류 없음(쓰기 포트가 던지는 함정에 걸리지 않음)'
$logs = @($fp.Calls | Where-Object { $_ -like 'log:*' })
Assert (@($logs | Where-Object { $_ -match '\[OVERTIME-SHADOW\]' }).Count -gt 0 -and @($logs | Where-Object { $_ -match 'would:' }).Count -gt 0) '[OVERTIME-SHADOW] would: 로그를 남긴다'
Assert ($g.Result.FinalStatus -eq 'DONE(would)') 'Shadow 예정 결과 DONE(would)'
$gOff = Invoke-GissueOvertimeGuard (New-Base $jobOut 106) 'Off' (New-FakePorts @{}).Ports
Assert (-not $gOff.Over) 'Off -> 무동작'

Write-Host '[M] 처리 중 이슈가 없을 때(저장소 정비 단계) — 이슈 쓰기 0건, 종료는 러너 TIMEOUT 경로에 위임'
$noIssueOut = @('[REPO-MAINT] 저장소 정비 세션 시작', '[ENGINE] MiniMax 우선 시도 (model=X)')
$fp = New-FakePorts @{}
$g = Invoke-GissueOvertimeGuard (New-Base $noIssueOut 106) 'Live' $fp.Ports
Assert ($g.Over -and (Get-Writes $fp.Calls).Count -eq 0) '이슈 없음 -> 코멘트/등록/상태전이 0건'
Assert ($g.Result.NeedsRunnerTimeout) 'Live 에서는 러너의 기존 TIMEOUT 경로로 종료하도록 표시'

Write-Host '[N] 분할 계획 — 항목 수/상한/verify'
$items7 = 1..7 | ForEach-Object { [pscustomobject]@{ Text = "항목 $_"; Source = 'body' } }
$plan = New-GissueOvertimeSplitPlan 500 '제목' $items7 @() 'u' 'c' 5
Assert ($plan.Splittable -and $plan.Children.Count -eq 4) '항목 7건을 최대 5건 상한 안에서 묶어 분할(2건씩 4개)'
Assert ($plan.Children[0].Content -match 'exit 1' -and $plan.Children[0].Content -match '```verify') 'verify 블록이 없는 원본이면 의도적으로 실패하는 verify 블록(교체 안내) 포함'
$plan2 = New-GissueOvertimeSplitPlan 500 '제목' $items7[0..1] @('echo ok') 'u' 'c' 5
Assert ($plan2.Children[0].Content -match 'echo ok') '원본 verify 블록이 있으면 승계'
Assert ($plan2.Children.Count -eq 2 -and $plan2.Children[1].Title -match '분해 2/2') '항목 2건 -> 2개, 제목 i/N 보정'
$remain = Get-GissueRemainingChecklistItems $issueContent @()
Assert (@($remain).Count -eq 3 -and $remain[0].Text -eq '첫 번째 잔여 항목') '본문 완료조건에서 미체크 항목만 추출(체크된 항목/verify 펜스 제외)'
$vb = Get-GissueVerifyBlocks $issueContent
Assert (@($vb).Count -eq 1 -and @($vb)[0] -match 'original-verify') 'verify 블록 추출'

Write-Host '[O] 러너 배선 (소스 검사)'
$runnerSrc = Get-Content -LiteralPath (Join-Path $gissueDir 'run-gissue-claude.ps1') -Raw -Encoding UTF8
Assert ($runnerSrc -match '\[string\]\$OvertimeSplitMode\s*=\s*''''') '러너 파라미터 -OvertimeSplitMode 기본값 빈 문자열(= 환경변수 -> Shadow)'
Assert ($runnerSrc -match 'Get-GissueOvertimeSettings \$OvertimeSplitMode') '설정은 Get-GissueOvertimeSettings 로 해석(기본 Shadow)'
Assert ($runnerSrc -match 'ISSUE-T0\] isn=') '잡이 [ISSUE-T0] 표식을 출력'
Assert ($runnerSrc -match 'ISSUE-END\] isn=') '잡이 [ISSUE-END] 표식을 출력'
$iHook = $runnerSrc.IndexOf('Invoke-GissueOvertimeCheck $r }')
$iTimeout = $runnerSrc.IndexOf('(Get-Date) -gt $r.Deadline')
Assert (($iHook -gt 0) -and ($iHook -lt $iTimeout)) 'Phase 2 에서 과시간 검사가 기존 TIMEOUT 판정보다 먼저 실행'
Assert ($runnerSrc -match 'RunnerStartedAtUtc = \(Get-Process -Id \$PID\)\.StartTime') '기준 시각 = 프로세스 시작 시각'
Assert ($runnerSrc -match 'if \(\$mode -ne ''Live''\) \{ return \$false \}') 'Shadow/Off 는 어떤 경우에도 잡을 정리하지 않고 반환'
$libSrc = Get-Content -LiteralPath (Join-Path $gissueDir 'lib/overtime-split.ps1') -Raw -Encoding UTF8
Assert ($libSrc -match "else \{ 'Shadow' \}") '기본 모드 Shadow(라이브러리)'
Assert ($libSrc -notmatch '(?<![\d.])\d{5}(?![\d.])') '라이브러리에 5자리 이상 숫자(CSN 번호 등) 하드코딩 없음(공개 범용 레포)'
foreach ($k in $saved.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k]) }
if ($script:fail -gt 0) { Write-Host "`n실패 $($script:fail)건" -ForegroundColor Red; exit 1 }
Write-Host "`n전체 통과"
exit 0
