# test-temp-filename-collision.ps1 — 고정 임시 파일명 충돌로 인한 거짓 FAIL 재발 방지 회귀 테스트
#
# 왜 필요한가 (2026-11-16 실측):
#   scripts/gissue/tests/test-verify-runner-korean-encoding.ps1 이 stdout/stderr 리다이렉트
#   파일을 **고정 이름**으로 만들었다. → 이 호스트에서 **동시에 실행되는 다른 게이트/테스트
#   프로세스**가 같은 파일을 쓰거나 지우면, 상대 프로세스의 출력이 사라져
#   "한글보존=False / 출력=(빈값)" 로 **거짓 FAIL** 이 난다.
#   실측: 같은 테스트를 2개 동시 실행 → 1건 PASS(exit 0) / 1건 FAIL(exit 1).
#   이 호스트에서는 여러 CSN 정비 세션이 매시 동시에 돌아가는데, 레포가 달라도 임시 폴더는 하나다
#   → 충돌이 일상적으로 일어난다(거짓 FAIL 는 "validation 실패"로 오인되어 작업을 막는다).
#
# 고정하는 것:
#   A. 저장소 전체 .ps1 의 **코드 라인**에서 임시 경로 뒤에 **고정 파일명**(실행별 보간 없음)이
#      오는 사용처이 0건이어야 한다 — PID · GUID 같은 실행별 고유 이름만 허용한다.
#   B. 검사기 자체가 맞게 동작하는지(고정명은 잡고 · 보간·괄호식·주석은 놓치지 않는지)도 함께 고정한다.
#   C. **스캔 범위**가 저장소 전체인지도 고정한다(루트 식별 실패로 일부만 훑는 사고를 막는다).
#
# 실행:
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gissue/tests/test-temp-filename-collision.ps1
# 종료코드: 0 = 전건 PASS, 1 = 1건 이상 FAIL
#
# 이 테스트는 **읽기 전용**이다 — 어떤 파일도 고치지/지우지 않는다(임시 파일을 만들지 않는다).

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'

# 저장소 루트 — .git(파일/디렉터리 어느 쪽이든)을 만날 때까지 올라간다.
# (경로 단계 수로 계산하면 tests → gissue → scripts 처럼 중간에서 멈춰 범위가 줄어든다)
$RepoRoot = $PSScriptRoot
while ($RepoRoot -and -not (Test-Path -LiteralPath (Join-Path $RepoRoot '.git'))) {
    $RepoRoot = Split-Path $RepoRoot -Parent
}
if (-not $RepoRoot) { Write-Output '  FAIL  저장소 루트를 찾을 수 없습니다(.git 없음)'; exit 1 }

$script:Pass = 0
$script:Fail = 0
function Assert-True($cond, $name, $detail = '') {
    if ($cond) { $script:Pass++; Write-Output "  PASS  $name" }
    else { $script:Fail++; Write-Output "  FAIL  $name$(if ($detail) { " — $detail" })" }
}

# ──────────────────────────────────────────────────────────────────────────────
# 주석 제거기 — 코드 라인만 검사하기 위해 문자열 밖의 '#' 이후를 잘라낸다.
# (따옴표 안의 '#'은 문자열 일부이므로 보존해야 한다)
# ──────────────────────────────────────────────────────────────────────────────
function Remove-CodeComment([string]$Line) {
    if ($null -eq $Line) { return '' }
    $inSingle = $false
    $inDouble = $false
    for ($i = 0; $i -lt $Line.Length; $i++) {
        $c = $Line[$i]
        if ($c -eq "'" -and -not $inDouble) { $inSingle = -not $inSingle; continue }
        if ($c -eq '"' -and -not $inSingle) { $inDouble = -not $inDouble; continue }
        if ($c -eq '#' -and -not $inSingle -and -not $inDouble) {
            if ($i -eq 0 -or $Line[$i - 1] -match '\s') { return $Line.Substring(0, $i) }
        }
    }
    return $Line
}

# 임시 경로 접두부는 조각으로 조립한다 — 이 파일 자신의 본문이 스캔 대상이 되면 안 된다.
$TempVar = '$env' + ':TEMP'

# 코드 라인에서 "고정 임시 파일명"을 찾아낸다.
#   · 임시 경로 바로 뒤가 역슬래시+이름  → 인라인 리터럴
#   · 임시 경로 뒤가 따옴표 문자열      → Join-Path 형태
#   · 괄호식·변수 등                    → 동적(무시)
# 실행별 고유 이름(보간 포함)은 허용한다.
function Get-FixedTempNames([string]$Line) {
    $code = Remove-CodeComment $Line
    if ($code.Trim() -eq '') { return @() }
    $found = @()
    $idx = 0
    while ($true) {
        $idx = $code.IndexOf($TempVar, $idx, [System.StringComparison]::Ordinal)
        if ($idx -lt 0) { break }
        $after = $idx + $TempVar.Length
        $j = $after
        while ($j -lt $code.Length -and [char]::IsWhiteSpace($code[$j])) { $j++ }
        if ($j -ge $code.Length) { break }
        $c = $code[$j]
        if ($c -eq '\') {
            $j++
            $start = $j
            while ($j -lt $code.Length -and ($code[$j] -notmatch '[\s"''`()]')) { $j++ }
            $name = $code.Substring($start, $j - $start)
            $next = if ($j -lt $code.Length) { [string]$code[$j] } else { '' }
            if ($name -ne '' -and $name -notmatch '\$' -and $next -ne '$' -and $next -ne '+') {
                $found += ($TempVar + '\' + $name)
            }
        }
        elseif ($c -eq '"' -or $c -eq "'") {
            $quote = $c
            $j++
            $start = $j
            while ($j -lt $code.Length -and $code[$j] -ne $quote) { $j++ }
            $name = $code.Substring($start, $j - $start)
            $k = $j + 1
            while ($k -lt $code.Length -and [char]::IsWhiteSpace($code[$k])) { $k++ }
            $next = if ($k -lt $code.Length) { [string]$code[$k] } else { '' }
            if ($name -ne '' -and $name -notmatch '\$' -and $next -ne '+') {
                $found += ($TempVar + '\' + $name)
            }
        }
        $idx = $after
    }
    return $found
}

Write-Output ''
Write-Output 'A. 검사기 자체 검증 — 고정명은 잡고, 실행별 고유 이름·괄호식·주석은 놓치지 않는다'
Assert-True ((Get-FixedTempNames ('Start-Process -FilePath x -RedirectStandardOutput "' + $TempVar + '\fixed_out.txt"')).Count -eq 1) `
    'A-1 고정 임시 파일명은 검출된다' ''
Assert-True ((Get-FixedTempNames ('Remove-Item "' + $TempVar + '\fixed_out.txt" -ErrorAction SilentlyContinue')).Count -eq 1) `
    'A-2 삭제 대상 고정 파일명도 검출된다' ''
Assert-True ((Get-FixedTempNames ('$p = "' + $TempVar + '\gissue-x-$PID.txt"')).Count -eq 0) `
    'A-3 PID 보간은 검출되지 않는다(오탐 없음)' ''
Assert-True ((Get-FixedTempNames ('$p = Join-Path ' + $TempVar + ' ("gissue-x-" + [guid]::NewGuid().ToString("N"))')).Count -eq 0) `
    'A-4 괄호식(GUID 조합)은 검출되지 않는다(오탐 없음)' ''
Assert-True ((Get-FixedTempNames ('$p = Join-Path ' + $TempVar + ' "gissue-x-" + [guid]::NewGuid().ToString("N")')).Count -eq 0) `
    'A-5 문자열 연결(GUID 조합)은 검출되지 않는다(오탐 없음)' ''
Assert-True ((Get-FixedTempNames ('# 임시 경로 ' + $TempVar + '\fixed.txt 는 주석이라 무시')).Count -eq 0) `
    'A-6 주석 안의 고정명은 검출되지 않는다(오탐 없음)' ''
Assert-True ((Get-FixedTempNames ('Write-Output "값 ' + $TempVar + '\fixed.txt"')).Count -eq 1) `
    'A-7 문자열 안의 고정명은 검출된다(실사용처)' ''

Write-Output ''
Write-Output 'B. 저장소 전체 .ps1 스캔 — 고정 임시 파일명 0건'
$files = @(Get-ChildItem -LiteralPath $RepoRoot -Recurse -File -Filter '*.ps1' -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch '\\\.git\\' -and $_.FullName -notmatch '\\node_modules\\' })
# 상대 경로는 항상 '/' 로 정규화한다(경로 표기 차이로 스캔 범위 판단이 틀리지 않도록)
$relAll = @($files | ForEach-Object { ($_.FullName.Substring($RepoRoot.Length).TrimStart('\', '/')) -replace '\\', '/' })

Write-Output ("  저장소 루트: {0}" -f $RepoRoot)
Write-Output ("  검사 대상 .ps1: {0}건" -f $files.Count)

# C. 스캔 범위 고정 — 루트 식별이 어긋나면 일부 디렉터리가 통째로 빠진다.
foreach ($prefix in @('.agent/scripts/', 'mgmt/', 'slack-bot/', 'scripts/')) {
    $hit = @($relAll | Where-Object { $_.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase) }).Count
    Assert-True ($hit -gt 0) ("C-1 스캔 범위 포함: {0} ({1}건)" -f $prefix, $hit) ''
}

$offenders = @()
foreach ($f in $files) {
    $lines = @(Get-Content -LiteralPath $f.FullName -Encoding UTF8 -ErrorAction SilentlyContinue)
    for ($i = 0; $i -lt $lines.Count; $i++) {
        foreach ($name in (Get-FixedTempNames $lines[$i])) {
            $rel = ($f.FullName.Substring($RepoRoot.Length).TrimStart('\', '/')) -replace '\\', '/'
            $offenders += ("{0}:{1} {2}" -f $rel, ($i + 1), $name)
        }
    }
}
Write-Output ("  발견: {0}건" -f $offenders.Count)
Assert-True ($offenders.Count -eq 0) 'C-2 고정 임시 파일명 사용처 0건' ($offenders -join ' | ')

Write-Output ''
Write-Output "결과: PASS=$($script:Pass) FAIL=$($script:Fail)"
if ($script:Fail -gt 0) { exit 1 }
exit 0
