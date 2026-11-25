# stall-marker.ps1 — gissue stall 마커(시간 한도 도달 기록) 순수 로직 + 파일 IO
#
# ── 왜 필요한가 ───────────────────────────────────────────────────────────────────
# 사후 스윕(WorktreeCleanup 등)이 시간 한도에 걸리면 그 단계는 멈추고 러너는 다음 단계로
# 진행한다. 그런데 그 실행 자체가 나중에 강제종료되면(스케줄러 ExecutionTimeLimit·0x41306),
# Complete-Run 이 돌지 않아 [RUN-END-SUMMARY]·SchedulerAgentRunEnd 가 남지 않는다 —
# stall 사실이 어디에도 기록되지 않은 채 사라진다.
#
# 그래서 시간 한도에 걸린 단계는 멈추는 즉시 **stall 마커**(로그 디렉터리의 JSON 파일)를
# 남긴다. 마커는 프로세스가 죽어도 디스크에 살아남으므로, **다음 :07 실행 시작 시**
# 러너가 마커를 읽어 CSN 로그에 [STALL-PREV] 로 남기고, 그 실행의 Complete-Run 이
# [RUN-END-SUMMARY] 에 실어 tSchedulerAgentRun.summary 로 올린다.
# 마커 삭제는 종료 기록 시도 **뒤에만** 한다 — 기록 전에 지우면 강제종료 시 stall 사실
# 자체가 사라진다. 종료 기록을 못 남긴 실행(SK 없음 등)은 마커를 남겨 다음 실행에 다시
# 표면화되게 한다.
#
# ── 이 파일이 하는 일 ─────────────────────────────────────────────────────────────
#   - `Get-GissueStallMarkerPath`   : 마커 파일 경로(로그 디렉터리, CSN·단계별 1개)
#   - `Write-GissueStallMarker`     : 마커 쓰기(실패해도 던지지 않음 — fail-open)
#   - `Read-GissueStallMarkers`     : 남은 마커 전부 읽기(깨진 JSON 은 건너뜀)
#   - `Format-GissueStallMarkerNote`: 마커 1건 → 한 줄 요약(실행 기록용)
#   - `Get-GissuePrevStallNotes`    : 이전 실행 마커 → 요약 배열(다음 실행 기록용)
#   - `Clear-GissueStallMarkers`    : 마커 삭제(종료 기록 뒤 소비용, 실패해도 던지지 않음)
#
# 이 파일은 파일 IO 외에 DB/네트워크에 직접 아무것도 쓰지 않는다. 마커를 실행 기록으로
# 올리는 것은 러너(Complete-Run → SchedulerAgentRunEnd, 기존 #6214 경로)가 한다 —
# 새 API 를 만들지 않는다. PowerShell 5.1 호환.
# 소비처: run-gissue-claude.ps1(단계 래퍼의 마커 쓰기 + 실행 시작 시 표면화 +
#         Complete-Run 의 기록·소비) + tests/test-worktree-cleanup-timebox.ps1.

# ── 마커 파일 경로 ───────────────────────────────────────────────────────────────
# 이름 규칙은 CSN별 로그(`gissue_csn<csn>.log`)와 같은 계열이다. 단계(Phase)는 파일명에
# 그대로 들어가므로 경로 주입을 막기 위해 영숫자·`-`·`_` 외 문자는 `_` 로 치환한다.
function Get-GissueStallMarkerPath {
    param(
        [Parameter(Mandatory = $true)][string]$LogDir,
        [Parameter(Mandatory = $true)][string]$Csn,
        [Parameter(Mandatory = $true)][string]$Phase
    )
    $safePhase = ([string]$Phase -replace '[^A-Za-z0-9_-]', '_')
    if (-not $safePhase) { $safePhase = 'Unknown' }
    return (Join-Path $LogDir "gissue_csn${Csn}-stall-${safePhase}.json")
}

# ── 마커 쓰기 ────────────────────────────────────────────────────────────────────
# 시간 한도에 걸린 단계가 멈추는 즉시 부른다. 쓰기 실패(디렉터리 없음·권한 등)는
# WARN 성격의 $null 반환으로만 알리고 **절대 던지지 않는다** — 마커 쓰기가 정리 단계나
# 러너를 막아서는 안 된다(fail-open). 성공 시 쓴 파일 경로를 돌려준다.
function Write-GissueStallMarker {
    param(
        [Parameter(Mandatory = $true)][string]$LogDir,
        [Parameter(Mandatory = $true)][string]$Csn,
        [Parameter(Mandatory = $true)][string]$Phase,
        [int]$ElapsedSec = 0,
        [int]$Processed = 0,
        [int]$Remaining = 0,
        [int]$BudgetSec = 0,
        [string]$RunId = '',
        [string]$Detail = ''
    )
    try {
        if (-not (Test-Path -LiteralPath $LogDir)) { return $null }
        $path = Get-GissueStallMarkerPath -LogDir $LogDir -Csn $Csn -Phase $Phase
        $marker = [pscustomobject]@{
            SchemaVersion = 1
            Csn           = "$Csn"
            Phase         = "$Phase"
            CreatedUtc    = ([datetime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ'))
            RunId         = "$RunId"
            ElapsedSec    = [int]$ElapsedSec
            BudgetSec     = [int]$BudgetSec
            Processed     = [int]$Processed
            Remaining     = [int]$Remaining
            Detail        = "$Detail"
        }
        ($marker | ConvertTo-Json -Depth 3) | Set-Content -LiteralPath $path -Encoding UTF8 -ErrorAction Stop
        return $path
    } catch {
        return $null
    }
}

# ── 남은 마커 전부 읽기 ──────────────────────────────────────────────────────────
# 깨진 JSON(쓰기 도중 강제종료로 반만 남은 파일 등)은 건너뛰고 나머지만 돌려준다 —
# 마커 하나가 깨졌다고 이전 실행의 stall 전부를 못 보게 해서는 안 된다.
# 반환: 마커 객체 배열(없으면 빈 배열). 호출자는 @(...) 로 받아 .Count 를 본다
# (PS 5.1: 1건짜리 반환값은 언롤돼 PSCustomObject 가 되고 .Count 가 없다).
function Read-GissueStallMarkers {
    param(
        [Parameter(Mandatory = $true)][string]$LogDir,
        [Parameter(Mandatory = $true)][string]$Csn
    )
    $out = @()
    try {
        if (-not (Test-Path -LiteralPath $LogDir)) { return @() }
        $files = @(Get-ChildItem -LiteralPath $LogDir -Filter "gissue_csn${Csn}-stall-*.json" -File -ErrorAction SilentlyContinue |
            Sort-Object Name)
        foreach ($f in $files) {
            try {
                $raw = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 -ErrorAction Stop
                $m = ($raw | ConvertFrom-Json -ErrorAction Stop)
                if ($null -eq $m -or -not $m.Phase) { continue }
                # Phase 는 파일명에서 온 값이 아니라 본문 값을 쓴다(본문이 정본).
                $out += [pscustomobject]@{
                    Csn        = "$($m.Csn)"
                    Phase      = "$($m.Phase)"
                    CreatedUtc = "$($m.CreatedUtc)"
                    RunId      = "$($m.RunId)"
                    ElapsedSec = [int]$m.ElapsedSec
                    BudgetSec  = [int]$m.BudgetSec
                    Processed  = [int]$m.Processed
                    Remaining  = [int]$m.Remaining
                    Detail     = "$($m.Detail)"
                    Path       = $f.FullName
                }
            } catch {
                continue
            }
        }
    } catch {
        return @($out)
    }
    return @($out)
}

# ── 마커 1건 → 한 줄 요약 ────────────────────────────────────────────────────────
# 실행 기록([RUN-END-SUMMARY])에 실리는 문장이라 짧게 끊는다. Detail 은 단계가 남긴
# 부가 설명(예: 어느 레포·어느 단위)이라 60자로 자른다.
function Format-GissueStallMarkerNote {
    param($Marker)
    if ($null -eq $Marker) { return '' }
    $note = "[STALL-이전실행] $($Marker.Phase): 시간 한도 도달 — 처리 $($Marker.Processed)건, 남음 $($Marker.Remaining)건, 경과 $($Marker.ElapsedSec)초(예산 $($Marker.BudgetSec)초)"
    if ("$($Marker.RunId)") { $note += ", 실행 $($Marker.RunId)" }
    $detail = "$($Marker.Detail)"
    if ($detail) {
        if ($detail.Length -gt 60) { $detail = $detail.Substring(0, 59) + '…' }
        $note += " — $detail"
    }
    return $note
}

# ── 이전 실행 마커 → 요약 배열 ───────────────────────────────────────────────────
# 다음 실행 시작 시 부른다. 마커를 **지우지 않는다** — 삭제는 Complete-Run 이 종료
# 기록에 실은 뒤에만 한다(기록 전 삭제는 강제종료 시 stall 사실 소실).
# 오래된 것부터 순서대로 돌려준다(여러 단계가 같은 실행에서 멈췄을 때 순서가 유지되게).
function Get-GissuePrevStallNotes {
    param(
        [Parameter(Mandatory = $true)][string]$LogDir,
        [Parameter(Mandatory = $true)][string]$Csn
    )
    $markers = @(Read-GissueStallMarkers -LogDir $LogDir -Csn $Csn |
        Sort-Object { "$($_.CreatedUtc)" }, { "$($_.Phase)" })
    $notes = @()
    foreach ($m in $markers) {
        $n = Format-GissueStallMarkerNote -Marker $m
        if ($n) { $notes += $n }
    }
    return @($notes)
}

# ── 마커 삭제(소비) ─────────────────────────────────────────────────────────────
# Complete-Run 이 종료 기록에 stall 요약을 실은 뒤에만 부른다. 삭제 실패는 0건 반환으로만
# 알리고 던지지 않는다 — 남은 마커는 다음 실행에 다시 표면화될 뿐이다(무해).
function Clear-GissueStallMarkers {
    param(
        [Parameter(Mandatory = $true)][string]$LogDir,
        [Parameter(Mandatory = $true)][string]$Csn
    )
    $removed = 0
    try {
        if (-not (Test-Path -LiteralPath $LogDir)) { return 0 }
        $files = @(Get-ChildItem -LiteralPath $LogDir -Filter "gissue_csn${Csn}-stall-*.json" -File -ErrorAction SilentlyContinue)
        foreach ($f in $files) {
            try {
                Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop
                $removed++
            } catch {
                continue
            }
        }
    } catch {
        return $removed
    }
    return $removed
}
