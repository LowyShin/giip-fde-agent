# =============================================================================
# token-usage.ps1 — 엔진 세션 기록(JSONL)의 토큰 사용량을 호스트 로컬에서 합산하는 모듈
# (giip #5398, 설계 정본: docs/60-operations/token-usage-metering.md §3)
# =============================================================================
#
# ── 왜 필요한가 ──
# 엔진(claude CLI — MiniMax 도 같은 바이너리를 ANTHROPIC_BASE_URL 만 바꿔 쓴다)의 호출별
# usage 는 각 호스트의 세션 기록(JSONL)에만 남는다. 플랫폼에서는 사용량이 보이지 않아
# CSN별 귀속·집계·과금이 불가능했다. 이 모듈이 실행 시간 범위 안의 기록을 모델별로 합산하고,
# 전송은 lib/kvs-report.ps1 의 Send-GissueTokenUsageRecord 가 맡는다.
#
# ── 설계 원칙 ──
#   1) **원본 기록은 호스트 밖으로 내보내지 않는다.** 합산 결과(모델별 4분류 합계)만 전송한다.
#   2) **토큰은 4분류 원형으로 합산한다** (freshIn/cacheCreate/cacheRead/out). 과금 가중은
#      여기서 적용하지 않는다 — 플랫폼 집계 단계의 요율표 몫이다(원형 저장 원칙).
#   3) **fail-open.** 어떤 오류도 throw 하지 않고, 합산할 수 있었던 만큼만 돌려준다.
#      이 모듈의 실패가 스케줄러 본 실행을 멈추면 안 된다.
#   4) **중복 계수 방지.** 같은 message id 가 여러 파일에 다시 나타나면(세션 재개 사본)
#      한 번만 센다. 파일 선별은 갱신 시각으로 거칠게 거르고, 최종 판정은 레코드의
#      timestamp(UTC)로 한다.
#
# ── 구현 주의 ──
#   값을 돌려주는 함수 안의 로그는 Write-Host 로 쓴다. Write-Output 은 반환 스트림에 섞인다
#   (kvs-report.ps1 과 같은 규약).
# =============================================================================

# Claude Code 세션 기록 폴더 인코딩 — 작업 폴더 절대경로의 영숫자 외 문자를 전부 '-' 로 바꾼 이름.
function Get-GissueEncodedProjectDirName([string]$Path) {
    return ($Path -replace '[^A-Za-z0-9]', '-')
}

# UTC 기준 시각을 DateTime.Kind 에 안전하게 정규화한다.
#   - Kind=Utc        : 그대로 사용.
#   - Kind=Local      : 같은 instant 를 UTC 로 변환(.ToUniversalTime)한다.
#   - Kind=Unspecified: 'SinceUtc' 계약에 따라 UTC 로 간주한다(SpecifyKind).
#
# 왜 필요한가: 호출부가 ISO8601 'Z' 문자열이나 네이티브 DateTime 리터럴을 그대로
# 넘기면 PowerShell 의 [datetime] 캐스트는 Kind=Local(UTC+9 등) 값으로 변환한다.
# DateTime 비교 연산자는 Kind 를 무시하고 원시 tick 만 비교하므로 정규화 없이 두면
# 시간창이 UTC 오프셋만큼 밀려 **최근 구간이 0건으로 조용히 사라진다**(오류 아님).
# 측정 모듈에서 조용한 0건은 '측정값 0' 으로 오독되므로 여기서 반드시 정규화한다.
function ConvertTo-GissueUtcDateTime([datetime]$Value) {
    if ($Value.Kind -eq [System.DateTimeKind]::Local) { return $Value.ToUniversalTime() }
    if ($Value.Kind -eq [System.DateTimeKind]::Unspecified) { return [datetime]::SpecifyKind($Value, [System.DateTimeKind]::Utc) }
    return $Value
}

# 실행 시간 범위 안의 엔진 사용량을 모델별로 합산한다.
#   Roots    : 엔진 설정 폴더 후보들(예: $env:CLAUDE_CONFIG_DIR, ~/.claude). projects 하위를 본다.
#   Workdir  : CSN 잡의 작업 폴더(절대경로). 세션 기록 폴더명과 대조한다.
#   SinceUtc : 이 시각(UTC) 이후의 레코드만 합산한다. ISO8601 문자열('...Z')·네이티브
#             DateTime 리터럴·UTC/Local 어느 Kind 로 넘겨도 같은 instant 로 해석된다
#             (ConvertTo-GissueUtcDateTime 이 정규화한다 — 정규화 없이는 시간창이
#             UTC 오프셋만큼 밀려 최근 구간이 0건으로 조용히 사라진다).
# 반환: @([ordered]@{ model; calls; freshIn; cacheCreate; cacheRead; out }) — 없으면 빈 배열.
function Get-GissueTranscriptTokenUsage {
    param(
        [Parameter(Mandatory)][string[]]$Roots,
        [Parameter(Mandatory)][string]$Workdir,
        [Parameter(Mandatory)][datetime]$SinceUtc
    )
    # SinceUtc 는 UTC 기준이어야 한다. Kind 가 다르면 비교가 원시 tick 으로 이뤄져
    # 시간창이 UTC 오프셋만큼 밀린다(최근 구간이 0건으로 조용히 사라짐) -> 정규화.
    $sinceUtc = ConvertTo-GissueUtcDateTime $SinceUtc
    $byModel = @{}
    $seen = @{}
    $encoded = Get-GissueEncodedProjectDirName $Workdir
    $styles = [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal
    foreach ($root in $Roots) {
        if (-not $root) { continue }
        $projDir = Join-Path (Join-Path $root 'projects') $encoded
        if (-not (Test-Path -LiteralPath $projDir)) { continue }
        $files = @(Get-ChildItem -LiteralPath $projDir -Filter '*.jsonl' -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTimeUtc -ge $sinceUtc })
        foreach ($file in $files) {
            try {
                foreach ($line in [System.IO.File]::ReadLines($file.FullName)) {
                    if ($line -notmatch '"usage"') { continue }
                    $rec = $null
                    try { $rec = $line | ConvertFrom-Json } catch { continue }
                    if ($rec.type -ne 'assistant') { continue }
                    $msg = $rec.message
                    if (-not $msg -or -not $msg.usage) { continue }
                    $tsUtc = $null
                    try { $tsUtc = [datetime]::Parse("$($rec.timestamp)", [System.Globalization.CultureInfo]::InvariantCulture, $styles) } catch { continue }
                    if ($tsUtc -lt $sinceUtc) { continue }
                    $mid = "$($msg.id)"
                    if ($mid) {
                        if ($seen.ContainsKey($mid)) { continue }
                        $seen[$mid] = $true
                    }
                    $model = "$($msg.model)"
                    if (-not $model) { $model = 'unknown' }
                    if (-not $byModel.ContainsKey($model)) {
                        $byModel[$model] = [ordered]@{ model = $model; calls = 0; freshIn = [long]0; cacheCreate = [long]0; cacheRead = [long]0; out = [long]0 }
                    }
                    $row = $byModel[$model]
                    $row.calls       = [int]$row.calls + 1
                    $row.freshIn     = [long]$row.freshIn + [long]($msg.usage.input_tokens)
                    $row.cacheCreate = [long]$row.cacheCreate + [long]($msg.usage.cache_creation_input_tokens)
                    $row.cacheRead   = [long]$row.cacheRead + [long]($msg.usage.cache_read_input_tokens)
                    $row.out         = [long]$row.out + [long]($msg.usage.output_tokens)
                }
            } catch {
                Write-Host "[TOKEN-USAGE][WARN] 세션 기록 합산 일부 실패(계속): $($file.FullName) — $($_.Exception.Message)"
                continue
            }
        }
    }
    return @($byModel.Values)
}
