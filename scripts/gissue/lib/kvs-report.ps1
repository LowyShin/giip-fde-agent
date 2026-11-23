# =============================================================================
# kvs-report.ps1 — 스케줄러 시작/알람/실행 리포트를 GIIP tKVS 에 기록하는 공용 모듈
# (giip #5345, 사용자 지시 2026-11-15)
# =============================================================================
#
# ── 왜 필요한가 ──
# 기존 tKVS 기록은 종료 시점의 scheduler_run_history 1건뿐이었다(giip #2384 — 건수+hostname).
#   - 시작 기록이 없어 "시작은 했는데 AI limit 으로 죽은 실행"과 "아예 시작 안 한 실행"을
#     GIIP 쪽에서 구분할 수 없었다.
#   - IP 가 없어 같은 CSN 을 두 머신에서 돌릴 때 어느 머신의 실행인지 특정할 수 없었다.
#   - limit 같은 치명적 에러가 나도 tKVS 알람이 없어, 사람이 로컬 로그를 열기 전까지 몰랐다.
#
# ── 설계 원칙 (가이드 정본: docs/60-operations/hourly-issue-scheduler.md §17) ──
#   1) **이 경로는 AI 를 거치지 않는다.** 시작/알람/리포트는 전부 스케줄러 본체(순수 코드)가
#      직접 전송한다. limit 으로 AI 가 죽는 바로 그 순간에도 전송이 가능해야 하기 때문이다.
#      시작 기록은 어떤 엔진 호출보다 먼저 남긴다.
#   2) **fail-open.** 전송 실패는 WARN 로그만 남기고 $false 를 돌려준다. 이 모듈의 실패가
#      스케줄러 본 실행을 멈추면 안 된다(기존 Send-GissueRunHistory 와 같은 규약).
#   3) **판정은 한 곳에서만**(rule 48). limit 서명 정규식과 알람 종류 판정은 이 파일이 정본이다.
#      엔진 시도 쪽의 자체 판정(폴백 결정용)과는 목적이 다르다 — 여기는 "GIIP 에 알릴 것인가"의 판정이다.
#   4) **전송 와이어 형식은 기존과 동일.** giipApiSk4 + token, text='KVSPut kType kKey kFactor',
#      jsondata 는 무BOM 임시파일 + curl --data-urlencode (giip #2316, #2384 에서 검증된 형식).
#      kType='lssn', kKey=<LSSN> 으로 기존 scheduler_run_history 와 같은 키 공간을 쓴다.
#
# ── kFactor 목록 ──
#   scheduler_run_start   실행 시작 1건 (event=start, runId, hostname, ips, csns, agentCommit, pid)
#   scheduler_alarm       비정상 1건 (event=alarm, kind=LIMIT|TIMEOUT|ZOMBIE|OVERTIME|RUN_FAIL, csn, status, detail)
#   scheduler_run_report  CSN별 종료 1건 (event=report, csn, status, processed, skipped, failed, runId)
#   scheduler_token_usage 토큰 사용량 1건 (event=token_usage, csn, runId, hostname, ips, engines[모델별 calls/freshIn/cacheCreate/cacheRead/out])
#   scheduler_run_history 기존 종료 집계 (giip #2384 — Send-GissueRunHistory 가 이 모듈 경유로 전송)
#
# ── 구현 주의 ──
#   값을 돌려주는 함수 안의 로그는 Write-Host 로 쓴다. Write-Output 은 함수 반환 스트림에 섞여
#   $ok 가 배열이 되고, 실패($false)가 truthy 로 판정되는 실결함이 된다(CI test-kvs-report 가 검출).
#
# ── 테스트 ──
#   전송은 $script:GissueKvsTransport 포트(스크립트블록: param($JsonData, $Sk) -> bool)로 교체할 수 있다.
#   테스트는 포트를 가짜로 바꿔 네트워크 없이 페이로드를 검증한다 (tests/test-kvs-report.ps1).
# =============================================================================

$script:GissueKvsTransport = $null

# limit/인증 사망 서명 — "AI 가 더는 일할 수 없는 상태"의 텍스트 신호. 엔진 출력·상태 문구 공용.
$script:GissueLimitSignature = '\b429\b|rate limit|quota|usage limit|insufficient balance|insufficient.{0,10}credit|too many requests|사용량 한도|token.{0,30}revoked|limit reached|token plan'

function Test-GissueLimitSignature([string]$Text) {
    if (-not $Text) { return $false }
    return ($Text -match $script:GissueLimitSignature)
}

# 알람 종류 판정(순수 함수). 알릴 필요가 없으면 $null.
function Get-GissueAlarmKind([string]$Status, [string]$Text) {
    if (Test-GissueLimitSignature $Text) { return 'LIMIT' }
    if ($Status -like 'TIMEOUT*') { return 'TIMEOUT' }
    if ($Status -like 'ZOMBIE*') { return 'ZOMBIE' }
    if ($Status -like 'OVERTIME*') { return 'OVERTIME' }
    if ($Status -and $Status -ne 'DONE') { return 'RUN_FAIL' }
    return $null
}

# 실행 머신 식별. 같은 CSN 을 두 머신에서 돌리는 경우의 구분 근거라 hostname 과 IP 를 함께 남긴다.
function Get-GissueHostIdentity {
    $hostname = $env:COMPUTERNAME
    if (-not $hostname) { try { $hostname = [System.Environment]::MachineName } catch { $hostname = 'unknown' } }
    $ips = @()
    try {
        if (Get-Command Get-NetIPAddress -ErrorAction SilentlyContinue) {
            $ips = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
                Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } |
                ForEach-Object { $_.IPAddress })
        }
    } catch { $ips = @() }
    if ($ips.Count -eq 0) {
        try {
            $ips = @([System.Net.Dns]::GetHostAddresses([System.Net.Dns]::GetHostName()) |
                Where-Object { $_.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork } |
                ForEach-Object { $_.IPAddressToString } |
                Where-Object { $_ -notlike '127.*' -and $_ -notlike '169.254.*' })
        } catch { $ips = @() }
    }
    return @{ hostname = "$hostname"; ips = @($ips | Select-Object -Unique | Sort-Object) }
}

# tKVS 전송 본체. 성공 $true / 실패·스킵 $false. 절대 throw 하지 않는다.
function Send-GissueKvsPut {
    param(
        [string]$Lssn,
        [Parameter(Mandatory)][string]$Factor,
        [Parameter(Mandatory)]$Value,
        [string]$Sk
    )
    if (-not $Lssn -or -not $Sk) {
        Write-Host "[WARN][KVS] SKIP factor=$Factor (lssn/sk 없음)"
        return $false
    }
    try {
        $jsondataObj = @{ kType = 'lssn'; kKey = $Lssn; kFactor = $Factor; kValue = $Value }
        $jsondata = $jsondataObj | ConvertTo-Json -Depth 12 -Compress
        if ($script:GissueKvsTransport) {
            return [bool](& $script:GissueKvsTransport $jsondata $Sk)
        }
        $tmpFile = [System.IO.Path]::GetTempFileName()
        try {
            $utf8NoBom = New-Object System.Text.UTF8Encoding $false
            [System.IO.File]::WriteAllText($tmpFile, $jsondata, $utf8NoBom)
            $apiUrl = ($ApiSk2Url -replace 'giipApiSk2$', 'giipApiSk4')
            $curlExe = if ($script:GissueCurlExe) { $script:GissueCurlExe } else { 'curl.exe' }
            $curlArgs = @(
                '-s', '-X', 'POST', $apiUrl,
                '-H', 'Content-Type: application/x-www-form-urlencoded',
                '--data-urlencode', 'text=KVSPut kType kKey kFactor',
                '--data-urlencode', "token=$Sk",
                '--data-urlencode', "jsondata@$tmpFile",
                '--max-time', '20'
            )
            $respRaw = (& $curlExe @curlArgs) -join "`n"
            $rstVal = $null
            try {
                $resp = $respRaw | ConvertFrom-Json
                $rstVal = $resp.data[0].RstVal
            } catch {
                $m = [regex]::Match($respRaw, '"RstVal"\s*:\s*(\d+)')
                if ($m.Success) { $rstVal = [int]$m.Groups[1].Value }
            }
            if ($rstVal -ne 200) {
                Write-Host "[WARN][KVS] KVSPut 실패(factor=$Factor): $respRaw"
                return $false
            }
            return $true
        } finally {
            Remove-Item -Path $tmpFile -Force -ErrorAction SilentlyContinue
        }
    } catch {
        Write-Host "[WARN][KVS] 전송 실패(factor=$Factor, 스케줄러 본연 동작에는 영향 없음): $($_.Exception.Message)"
        return $false
    }
}

# 실행 시작 기록 — 어떤 엔진(AI) 호출보다 먼저 호출할 것.
# [giip #6214] -CodeSync: 러너 기동 초입의 자동 반영(자기 갱신) 결과(전후 HEAD·사유).
#   이 실행이 **죽더라도** 남아야 하는 사실이므로 종료 기록(RunEnd)뿐 아니라 시작 기록에도 싣는다.
#   비어 있으면 키 자체를 넣지 않는다(기존 기록 형태를 깨지 않기 위해).
function Send-GissueSchedulerStartRecord {
    param(
        [Parameter(Mandatory)][string]$Lssn,
        [Parameter(Mandatory)][string]$Sk,
        [Parameter(Mandatory)][string]$RunId,
        [Parameter(Mandatory)]$CsnList,
        [string]$Commit = '',
        [string]$CodeSync = ''
    )
    $hostId = Get-GissueHostIdentity
    $value = [ordered]@{
        event       = 'start'
        runId       = $RunId
        at          = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        hostname    = $hostId.hostname
        ips         = @($hostId.ips)
        csns        = @($CsnList)
        agentCommit = $Commit
        pid         = $PID
    }
    if ($CodeSync) { $value['codeSync'] = $CodeSync }
    $ok = Send-GissueKvsPut -Lssn $Lssn -Factor 'scheduler_run_start' -Value $value -Sk $Sk
    Write-Host "[KVS-START] $(if ($ok) { 'OK' } else { 'FAIL' }) runId=$RunId host=$($hostId.hostname) ips=$(@($hostId.ips) -join ',')"
    return $ok
}

# 비정상 알람 기록 — limit 은 AI 가 죽은 상황이므로 본체가 직접 보낸다.
function Send-GissueSchedulerAlarmRecord {
    param(
        [Parameter(Mandatory)][string]$Lssn,
        [Parameter(Mandatory)][string]$Sk,
        [Parameter(Mandatory)][string]$Kind,
        [string]$Csn = '',
        [string]$RunId = '',
        [string]$Status = '',
        [string]$Detail = ''
    )
    $hostId = Get-GissueHostIdentity
    $detailTrim = if ($Detail -and $Detail.Length -gt 500) { $Detail.Substring(0, 500) } else { $Detail }
    $value = [ordered]@{
        event    = 'alarm'
        kind     = $Kind
        csn      = $Csn
        runId    = $RunId
        at       = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        hostname = $hostId.hostname
        ips      = @($hostId.ips)
        status   = $Status
        detail   = $detailTrim
    }
    $ok = Send-GissueKvsPut -Lssn $Lssn -Factor 'scheduler_alarm' -Value $value -Sk $Sk
    Write-Host "[KVS-ALARM] $(if ($ok) { 'OK' } else { 'FAIL' }) kind=$Kind csn=$Csn status=$Status"
    return $ok
}

# CSN별 종료 리포트.
function Send-GissueSchedulerRunReport {
    param(
        [Parameter(Mandatory)][string]$Lssn,
        [Parameter(Mandatory)][string]$Sk,
        [Parameter(Mandatory)][string]$Csn,
        [Parameter(Mandatory)][string]$Status,
        [int]$Processed = 0,
        [int]$Skipped = 0,
        [int]$Failed = 0,
        [string]$RunId = ''
    )
    $hostId = Get-GissueHostIdentity
    $value = [ordered]@{
        event     = 'report'
        csn       = $Csn
        runId     = $RunId
        at        = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        hostname  = $hostId.hostname
        ips       = @($hostId.ips)
        status    = $Status
        processed = $Processed
        skipped   = $Skipped
        failed    = $Failed
    }
    $ok = Send-GissueKvsPut -Lssn $Lssn -Factor 'scheduler_run_report' -Value $value -Sk $Sk
    Write-Host "[KVS-REPORT] $(if ($ok) { 'OK' } else { 'FAIL' }) csn=$Csn status=$Status processed=$Processed failed=$Failed"
    return $ok
}

# CSN별 토큰 사용량 기록 — 설계 정본: docs/60-operations/token-usage-metering.md §3 (giip #5398).
# 토큰은 4분류(freshIn/cacheCreate/cacheRead/out) 원형으로 남긴다. 과금 가중·단가는 여기서 적용하지
# 않고 플랫폼 집계 단계의 요율표가 적용한다(원형 저장 원칙). 합산은 lib/token-usage.ps1 이 담당하고
# 이 함수는 전송만 한다. 기록 실패가 본 실행을 멈추지 않는다(fail-open, 기존 규약과 동일).
function Send-GissueTokenUsageRecord {
    param(
        [Parameter(Mandatory)][string]$Lssn,
        [Parameter(Mandatory)][string]$Sk,
        [Parameter(Mandatory)][string]$Csn,
        [Parameter(Mandatory)]$Engines,
        [string]$RunId = ''
    )
    $hostId = Get-GissueHostIdentity
    $value = [ordered]@{
        event    = 'token_usage'
        csn      = $Csn
        runId    = $RunId
        at       = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        hostname = $hostId.hostname
        ips      = @($hostId.ips)
        engines  = @($Engines)
    }
    $ok = Send-GissueKvsPut -Lssn $Lssn -Factor 'scheduler_token_usage' -Value $value -Sk $Sk
    $totalCalls = 0
    foreach ($e in @($Engines)) { try { $totalCalls += [int]$e['calls'] } catch { } }
    Write-Host "[KVS-TOKEN-USAGE] $(if ($ok) { 'OK' } else { 'FAIL' }) csn=$Csn engines=$(@($Engines).Count) calls=$totalCalls"
    return $ok
}
