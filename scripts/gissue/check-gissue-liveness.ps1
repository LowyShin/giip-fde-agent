# check-gissue-liveness.ps1 — gissue 처리 "무소식" 점검 (giip 4411)
#
# 무엇을: CSN 별 처리 로그(gissue_csn<N>.log)의 최신 갱신 시각과 .lock 상태를 읽어, 이슈 처리 본체
#   (run-gissue-claude.ps1)가 최근에 실제로 돌았는지 판정한다. Task Scheduler 결과코드(LastTaskResult)는
#   보지 않는다 — 태스크가 엉뚱한 스크립트를 가리켜도 0 으로 끝나기 때문이다(실사고: 처리 본체가 6일 넘게
#   안 돌았는데 결과코드는 계속 0).
# 읽기 전용: 로그·락·설정을 쓰지 않는다. 파일을 쓰는 것은 -Notify 일 때의 쿨다운 상태 파일 하나뿐이다.
# 결과 저장·소비: 표준출력(요약 또는 -Json) + 종료코드. 종료코드는 이 점검을 매시 돌리는 독립 태스크의
#   LastTaskResult 로 남는다(register-gissue-liveness-task.ps1). -Notify 이면 [OPS] 이슈(giip 이슈 DB)과
#   logs/gissue_liveness_state.json(에피소드 상태)에 기록된다.
#
# 판정:
#   · CSN 별: OK(최근 -MaxSilentHours 이내 로그 갱신) / RUNNING(살아있는 락 = 처리 중, 오탐 방지) /
#             SILENT(로그가 기준보다 오래됨; 죽은 PID 락·-StaleLockHours 이상 묵은 락이면 사유에 표시) /
#             NO_LOG(로그 파일 없음)
#   · 전체: OK / PARTIAL_SILENT(일부 CSN 만 무소식) / ALL_SILENT(전부 무소식 = 스케줄러 자체 정지 의심) /
#           NO_TARGETS(점검 대상 없음 — 판정 불가, 정상으로 치지 않는다)
# 종료코드: 0 = 정상 / 1 = 무소식 또는 판정 불가
#
# 알림(-Notify, 기본 꺼짐 = 출력만): -OpsCsn(또는 환경변수 GISSUE_LIVENESS_OPS_CSN)로 지정한 CSN 에
#   "[OPS] gissue 처리 무소식 감지" 이슈를 1건 등록한다. 그 CSN 은 이 배포가 쓰기 권한을 가진 작업 CSN
#   이어야 한다(남의 CSN 에 쓰지 않는다).
#
#   ★ 무소식 = "에피소드 1건" 으로 관리한다(2026-11-11 중복 등록 #4870/#4874 사고 뒤에 바뀜):
#     · 이미 열린 같은 제목 이슈가 있으면 **새로 만들지 않고** 그 이슈에 상태 서명 코멘트를 누적한다
#       (침묵 중인 CSN 목록 · 침묵 시작 시각 · 경과). 조용히 생략하면 "침묵이 얼마나 이어졌는지"가
#       아무 데도 남지 않는다.
#     · 처리 흔적이 복귀(회복)하면 열린 [OPS] 이슈에 회복 코멘트를 달고 DONE 으로 닫는다. 닫는 경로가
#       없으면 PENDING·코멘트 0건 이슈가 계속 쌓인다.
#     · 열린 같은 제목 이슈 조회(list)가 실패하면 **등록하지 않는다**(중복 등록 방지 우선).
#     · 에피소드의 정체는 상태 파일(에피소드 기록)이 안다 — 에피소드 이슈가 외부에 의해 닫혀 열려 있지
#       않아도 침묵이 계속되는 동안에는 새 이슈를 만들지 않는다(만들면 중복 등록이 된다).
#       에피소드 기록은 회복 시점에 정리된다.
#   선례: run-gissue-claude.ps1 의 미매핑 CSN 가드 — GISSUE_CSNGUARD_OPS_CSN
#
#   ★ 중복 등록이 뚫렸던 근본 원인(읽기 CSN 과 쓰기 CSN 의 비대칭):
#     등록(register-issue.js)과 중복 조회가 서로 다른 주체·CSN 스코프를 쓰고 있었다. 등록은 default
#     계정으로 csn=<OpsCsn> 을 요청하지만 서버(giipdb pApiGiipIssuePutbyAK)는 "멤버가 아니면 홈 CSN 으로
#     클램프"한다. 조회는 list-issues.js --csn <OpsCsn> 으로 "i.cSn = <OpsCsn> 인 줄만" 본다. ⇒ 이슈는 홈
#     CSN 에 생겼는데 조회는 OpsCsn 을 쳐서 "같은 제목 없음" 으로 판단 → 매 시간 중복 등록(6h 쿨다운이
#     6시간 동안만 이를 가렸다). 이제 등록·조회·코멘트·종료를 **같은 주체(default 계정)** 로 수행하고,
#     조회 후보 CSN 을 {OpsCsn, default 계정의 csn} 으로 넓힌다. → scripts/gissue/lib/liveness-ops-issue.js
#     (조회에만 SK 폴백: 그 CSN 의 계정이 없으면 등록 주체 SK 로 조회 — 서버 클램프 때문에 홈 CSN 행은
#      항상 보이고, 멤버면 그 CSN 행도 보인다. 쓰기(코멘트·종료)에는 폴백이 없다 — 타 CSN 쓰기 금지.)
#
# 사용:
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\gissue\check-gissue-liveness.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\gissue\check-gissue-liveness.ps1 -Json
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\gissue\check-gissue-liveness.ps1 -Notify -OpsCsn <csn>

param(
    # 처리 로그가 이 시간(시) 넘게 갱신되지 않으면 무소식. 스케줄 주기 1h + 긴 실행(상한 105분)을 감안한 기본 3h.
    [double]$MaxSilentHours = 3,
    # 락이 이 시간(시) 이상 묵으면 멈춘 실행으로 본다(살아있는 PID 여도 진행 중으로 치지 않는다).
    [double]$StaleLockHours = 2,
    [string]$LogDir = '',
    [string]$ConfigPath = '',
    [switch]$Json,
    # 실알림 스위치. 없으면 "알릴 내용"만 출력한다.
    [switch]$Notify,
    [string]$OpsCsn = '',
    [double]$CooldownHours = 6,
    # [OPS] 에피소드 이슈 도구 경로(기본: scripts/gissue/lib/liveness-ops-issue.js).
    # 테스트가 스텁을 주입하기 위한 파라미터다(운영에서는 지정하지 않는다).
    [string]$OpsHelper = ''
)
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }

$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $LogDir)     { $LogDir = Join-Path $ScriptDir 'logs' }
if (-not $ConfigPath) { $ConfigPath = Join-Path $ScriptDir 'csn-projects.json' }
. (Join-Path (Join-Path $ScriptDir 'lib') 'gissue-liveness-lib.ps1')

# -Json 일 때 표준출력은 JSON 한 덩어리여야 하므로 부가 안내는 표준오류로 보낸다.
function Say($m) { if ($Json) { [Console]::Error.WriteLine($m) } else { Write-Output $m } }

$result = Get-GissueLiveness -LogDir $LogDir -ConfigPath $ConfigPath -MaxSilentHours $MaxSilentHours -StaleLockHours $StaleLockHours

if ($Json) {
    $result | ConvertTo-Json -Depth 5
} else {
    Write-Output "[gissue-liveness] $($result.Overall) — $($result.Summary)"
    foreach ($r in $result.Csns) {
        $line = "  CSN $($r.Csn): $($r.Status)"
        if ($r.LastLog) { $line += " (마지막 로그 $($r.LastLog), $($r.SilentHours)h 전)" }
        if ($r.Reason)  { $line += " — $($r.Reason)" }
        Write-Output $line
    }
}

# ── [OPS] 에피소드 이슈 도구 호출 ───────────────────────────────────────────
# node 호출 규칙(레포 공통, rule 63): stderr 리다이렉트를 하지 않는다(2>&1 은 $ErrorActionPreference='Stop' 과
# 만나면 NativeCommandError 로 죽는다). 이 함수 안에서만 Continue 로 내려가고 $LASTEXITCODE + JSON 으로
# 성패를 직접 확인한다. 도구는 성공/실패 모두 stdout 에 JSON 한 줄을 낸다(실패면 ok=false).
function Invoke-OpsHelper {
    param([Parameter(Mandatory = $true)][string]$Verb, [string[]]$HelperArgs = @())
    $ErrorActionPreference = 'Continue'
    $global:LASTEXITCODE = 0
    $out = & node $script:OpsHelperPath $Verb @HelperArgs
    $code = $LASTEXITCODE
    $json = (@($out) -join "`n")
    $data = $null
    if ($json.Trim()) { try { $data = $json | ConvertFrom-Json } catch { $data = $null } }
    if ($null -eq $data) {
        return [pscustomobject]@{ Ok = $false; Code = $code; Data = $null; Error = "도구 출력 파싱 실패(exit=$code): $($json.Trim())" }
    }
    if ($data.PSObject.Properties.Name -contains 'ok' -and -not $data.ok) {
        return [pscustomobject]@{ Ok = $false; Code = $code; Data = $data; Error = "$($data.error)" }
    }
    return [pscustomobject]@{ Ok = $true; Code = $code; Data = $data; Error = '' }
}

# 본문을 UTF-8(BOM) 임시 파일로 넘긴다 — 코멘트/등록 본문의 인용부호·개행 이스케이프 사고를 피한다.
function Write-TempBody {
    param([string]$Body)
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("gissue_liveness_{0}.txt" -f [guid]::NewGuid().ToString('N'))
    [System.IO.File]::WriteAllText($tmp, $Body, (New-Object System.Text.UTF8Encoding $true))
    return $tmp
}

$ops = if ($OpsCsn) { $OpsCsn } else { "$($env:GISSUE_LIVENESS_OPS_CSN)".Trim() }
$title = '[OPS] gissue 처리 무소식 감지'
$script:OpsHelperPath = if ($OpsHelper) { $OpsHelper } else { Join-Path (Join-Path $ScriptDir 'lib') 'liveness-ops-issue.js' }
$stateFile = Join-Path $LogDir 'gissue_liveness_state.json'
$state = $null
if (Test-Path -LiteralPath $stateFile) { try { $state = Get-Content -LiteralPath $stateFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $state = $null } }
$now = Get-Date

function Save-LivenessState($obj) {
    $obj | ConvertTo-Json -Depth 6 | Out-File -FilePath $stateFile -Encoding UTF8
}

# 제목은 **파일로** 넘긴다 — 한글 제목을 커맨드라인 인자로 주면 Windows PowerShell 5.1 콘솔 코드페이지로
# 깨져 "같은 제목" 비교가 성립하지 않는다(중복 등록으로 이어진다).
$titleFile = $null
if ($Notify -and $ops -and $ops -match '^\d+$') { $titleFile = Write-TempBody $title }

if (-not $result.Healthy) {
    # ── 무소식: 에피소드 1건을 유지한다 ────────────────────────────────────
    if (-not $ops -or $ops -notmatch '^\d+$') {
        Say "[gissue-liveness] 알림 대상 CSN 없음(-OpsCsn / GISSUE_LIVENESS_OPS_CSN 미지정) — 출력만"
    } elseif (-not $Notify) {
        $due = Test-LivenessNotifyDue -Result $result -State $state -CooldownHours $CooldownHours
        Say "[gissue-liveness] DRYRUN: -Notify 없음 — 알림 안 함(쿨다운 판정: Due=$($due.Due), $($due.Why)); 대상 CSN=$ops 제목=$title"
    } else {
        $due = Test-LivenessNotifyDue -Result $result -State $state -CooldownHours $CooldownHours
        # 현재 진행 중인 에피소드 기록(있으면 그 이슈가 에피소드의 정체다 — 새 이슈를 만들지 않는다).
        $episode = Get-LivenessEpisode -State $state
        # 1) 열린 같은 제목 이슈 조회 — 실패하면 등록하지 않는다(중복 등록 방지 우선).
        $lookup = Invoke-OpsHelper -Verb 'find' -HelperArgs @('--title-file', $titleFile, '--ops-csn', $ops)
        if (-not $lookup.Ok) {
            Say "[gissue-liveness] LIST-FAIL: 열린 [OPS] 이슈 조회 실패 — 등록하지 않음(중복 등록 방지 우선). 사유: $($lookup.Error)"
        } else {
            # @($null) 은 원소 1개를 갖는 배열이므로 isn 이 있는 행만 남긴다.
            $open = @($lookup.Data.issues | Where-Object { $_ -and $_.isn })
            if ($open.Count -gt 0) {
                # 2) 이미 열린 이슈가 있다 → 새 이슈를 만들지 않고 진행 보고를 누적한다.
                $dueCmt = Test-LivenessEpisodeCommentDue -Result $result -State $state -Issues $open -CooldownHours $CooldownHours -Now $now
                if (-not $dueCmt.Due) {
                    Say "[gissue-liveness] 진행 보고 생략: $($dueCmt.Why) (열린 이슈 isn=$($open[0].isn))"
                } else {
                    $body = New-LivenessStatusComment -Result $result -State $state -Now $now
                    $tmp = Write-TempBody $body
                    $posted = 0
                    try {
                        foreach ($iss in $open) {
                            $r = Invoke-OpsHelper -Verb 'comment' -HelperArgs @('--isn', "$($iss.isn)", '--csn', "$($iss.cSn)", '--file', $tmp)
                            if ($r.Ok) { $posted++; Say "[gissue-liveness] 진행 보고 코멘트 등록: isn=$($iss.isn) (cSn=$($iss.cSn))" }
                            else { Say "[gissue-liveness] [경고] 진행 보고 코멘트 실패: isn=$($iss.isn) — $($r.Error)" }
                        }
                    } finally {
                        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
                    }
                    if ($posted -gt 0) {
                        $ep = Get-LivenessEpisodeState -State $state -Issues $open -Result $result -Now $now
                        $newState = [ordered]@{
                            lastNotifiedAt = $now.ToString('yyyy-MM-ddTHH:mm:ss')
                            signature      = (Get-LivenessSignature -Result $result)
                            episode        = $ep
                        }
                        Save-LivenessState $newState
                        Say "[gissue-liveness] 진행 보고 완료(isn=$($open[0].isn)): $($dueCmt.Why)"
                    }
                }
            } elseif ($episode -and $episode.isn) {
                # 에피소드 이슈가 열려 있지 않다 = 외부(처리 스케줄러 등)가 이미 닫았다.
                # 여기서 새 이슈를 만들면 "한 침묵에 여러 이슈" 가 된다 — 2026-11-11 중복 등록(#4870/#4874)의
                # 재발 경로다. 등록하지 않고 에피소드 기록을 유지한다(회복 시점에 정리된다).
                Say "[gissue-liveness] 에피소드 이슈 #$($episode.isn) 가 열려 있지 않음(외부 종료) — 중복 등록 방지를 위해 새 이슈를 만들지 않음(침묵 계속)"
            } elseif (-not $due.Due) {
                Say "[gissue-liveness] 알림 생략: $($due.Why)"
            } else {
                # 3) 열린 이슈가 없다 → 에피소드의 첫 이슈를 등록한다.
                $body = @(
                    "gissue 처리 로그가 기준(${MaxSilentHours}h) 넘게 갱신되지 않았습니다. (auto-detected: check-gissue-liveness.ps1, giip 4411)",
                    '',
                    $result.Summary,
                    ''
                ) + @($result.Csns | Where-Object { $_.Status -in @('SILENT', 'NO_LOG') } | ForEach-Object { "- CSN $($_.Csn): $($_.Status) — $($_.Reason)" }) + @(
                    '',
                    '먼저 확인: 스케줄 태스크가 run-gissue-claude.ps1 를 가리키는지(`manage-gissue-scheduler.ps1 -Action Status`), 락 파일이 죽은 프로세스의 것은 아닌지.'
                )
                $tmp = Write-TempBody ($body -join "`n")
                try {
                    $reg = Invoke-OpsHelper -Verb 'register' -HelperArgs @('--title-file', $titleFile, '--content-file', $tmp, '--csn', $ops)
                } finally {
                    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
                }
                if (-not $reg.Ok) {
                    Say "[gissue-liveness] POST-FAIL: 알림 실패: $($reg.Error)"
                } else {
                    $isn = $reg.Data.isn
                    Say "[gissue-liveness] POSTED: 운영 이슈 등록(isn=$isn). 출력: $($reg.Data.stdout)"
                    # 서버가 "멤버가 아니면 홈 CSN 으로 클램프"할 수 있다 → 실제로 놓인 CSN 을 기록한다.
                    $epCsn = if ($reg.Data.cSn) { $reg.Data.cSn } else { $ops }
                    $ep = Get-LivenessEpisodeState -State $state -Issues @([pscustomobject]@{ isn = $isn; cSn = $epCsn }) -Result $result -Now $now
                    $newState = [ordered]@{
                        lastNotifiedAt = $now.ToString('yyyy-MM-ddTHH:mm:ss')
                        signature      = (Get-LivenessSignature -Result $result)
                        episode        = $ep
                    }
                    Save-LivenessState $newState
                }
            }
        }
    }
} else {
    # ── 회복: 처리 흔적이 복귀했다 → 열린 [OPS] 이슈에 회복 보고를 남기고 DONE 으로 닫는다 ──
    if ($Notify -and $ops -and $ops -match '^\d+$') {
        $lookup = Invoke-OpsHelper -Verb 'find' -HelperArgs @('--title-file', $titleFile, '--ops-csn', $ops)
        if (-not $lookup.Ok) {
            Say "[gissue-liveness] LIST-FAIL: 회복 확인용 조회 실패 — 닫지 않음(다음 실행에서 다시 시도). 사유: $($lookup.Error)"
        } else {
            # @($null) 은 원소 1개를 갖는 배열이므로 isn 이 있는 행만 남긴다.
            $open = @($lookup.Data.issues | Where-Object { $_ -and $_.isn })
            $closed = 0
            $closedList = @()
            # 이미 우리가 종료한 이슈는 다시 건드리지 않는다 — 사후감사 게이트가 DONE 을 되살리는 경로에서
            # "코멘트 + 종료" 를 매시간 반복하지 않게 하기 위한 안전장치다.
            $prevClosed = @()
            if ($state -and ($state.PSObject.Properties.Name -contains 'closedIsns') -and $state.closedIsns) {
                $prevClosed = @($state.closedIsns)
            }
            foreach ($iss in $open) {
                if ($prevClosed -contains [int]$iss.isn) {
                    Say "[gissue-liveness] 이슈 #$($iss.isn) 는 이미 이 경로가 종료한 이슈 — 다시 건드리지 않음"
                    continue
                }
                $body = New-LivenessRecoveryComment -Result $result -State $state -Now $now -Issue $iss
                $tmp = Write-TempBody $body
                try {
                    $cm = Invoke-OpsHelper -Verb 'comment' -HelperArgs @('--isn', "$($iss.isn)", '--csn', "$($iss.cSn)", '--file', $tmp)
                } finally {
                    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
                }
                if (-not $cm.Ok) {
                    Say "[gissue-liveness] [경고] 회복 코멘트 실패(isn=$($iss.isn)) — 닫지 않음: $($cm.Error)"
                    continue
                }
                $cl = Invoke-OpsHelper -Verb 'close' -HelperArgs @('--isn', "$($iss.isn)", '--csn', "$($iss.cSn)", '--status', 'DONE')
                if ($cl.Ok) {
                    $closed++
                    $closedList += [int]$iss.isn
                    Say "[gissue-liveness] RECOVERED: 회복 감지 — 이슈 #$($iss.isn) 에 회복 코멘트 후 DONE 으로 닫음"
                } else {
                    Say "[gissue-liveness] [경고] 종료 실패(isn=$($iss.isn)): $($cl.Error)"
                }
            }
            # 에피소드 정리는 "이슈를 닫았는지"와 무관하게 한다 — 이슈가 외부에서 이미 닫혔어도
            # 침묵이 끝났으므로 기록은 정리해야 다음 침묵에서 새 에피소드를 시작할 수 있다.
            $episode = Get-LivenessEpisode -State $state
            if ($closed -gt 0 -or $episode) {
                $keep = @(@($prevClosed) + @($closedList) | Select-Object -Unique | Select-Object -Last 10)
                $newState = [ordered]@{
                    lastNotifiedAt = $now.ToString('yyyy-MM-ddTHH:mm:ss')
                    signature      = (Get-LivenessSignature -Result $result)
                    recoveredAt    = $now.ToString('yyyy-MM-ddTHH:mm:ss')
                    closedIsns     = $keep
                }
                Save-LivenessState $newState
            }
        }
    }
}

if ($titleFile) { Remove-Item -LiteralPath $titleFile -Force -ErrorAction SilentlyContinue }
if ($result.Healthy) { exit 0 } else { exit 1 }
