# test-manage-gissue-scheduler-logdir.ps1 — manage-gissue-scheduler.ps1 의 경로 지정 지원 회귀 테스트 (giip #5054)
#
# 왜 필요한가(실사고): 정본 상태 조회 도구(-Action Status)의 CSN 타깃·락·로그 조회가
#   **그 스크립트가 있는 저장소의 경로만** 본다(하드코딩). 스케줄러가 실제로 도는 배포본이 다른
#   디렉터리면 "락 0건 / 대상 CSN 0건" 이 운영 reality 와 반대인 거짓출력이 되고, "락이 죽은
#   프로세스의 것인지" 도 상태 조회만으로 판정할 수 없다. 경로 지정(-LogDir / -ConfigPath) 지원이
#   조용히 되돌아가면 그대로 재발하므로 고정한다.
#
# 고정하는 것:
#   (A) 구조 — param() 블록에 $LogDir / $ConfigPath 가 있고 폴백(if (-not ...))이 있으며,
#       하드코딩된 $MapFile 참조가 남아 있지 않다. (기대 PASS)
#   (B) 동작 — 기본 호출이면 '## CSN Targets' / '## Locks' / '로그 디렉터리' / 'CSN 맵' 이 보인다. (기대 PASS)
#   (C) 동작 — -LogDir 로 지정한 임시 디렉터리의 락 파일이 PID·상태와 함께 보인다. (기대 PASS)
#   (D) 동작 — -ConfigPath 로 지정한 CSN 맵의 대상이 '## CSN Targets' 절에 보인다. (기대 PASS)
#   (E) 음성 — $LogDir 파라미터가 지워진 사본에서는 (A) 검사기가 "없음"을 보고한다. (기대 FAIL 확인)
#       (E)가 없으면 "항상 PASS 하는 검사기"와 구분되지 않는다(rule 42).
#
# 실제 스케줄러·락·프로세스는 건드리지 않는다 — 읽기 전용 조회 + $env:TEMP 아래 임시 트리만 쓴다.
# 이 PC 에 pwsh 가 없으므로 실행은 Windows PowerShell 5.1 기준이다(rule 62).
#
# 실행: powershell -NoProfile -ExecutionPolicy Bypass -File scripts\gissue\tests\test-manage-gissue-scheduler-logdir.ps1

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }

$target = Join-Path (Split-Path -Parent $PSScriptRoot) 'manage-gissue-scheduler.ps1'
if (-not (Test-Path $target)) { Write-Host "대상 없음: $target" -ForegroundColor Red; exit 1 }

$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  ok   $msg" }
    else { Write-Host "  FAIL $msg" -ForegroundColor Red; $script:fail++ }
}

# ── 구조 검사기 ────────────────────────────────────────────────────────────────
# 검사기를 함수로 분리한 이유: (E) 에서 "사본에는 없다" 를 실제로 보고시켜
# "항상 PASS 하는 검사기"가 아님을 증명해야 한다(rule 42).
function Test-SchedulerPaths([string]$path) {
    $raw = Get-Content -LiteralPath $path -Raw
    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
    if ($errors -and $errors.Count -gt 0) { throw "구문 오류로 파싱 실패: $path ($($errors.Count)건)" }

    $paramNames = @($ast.FindAll(
        { param($n) $n -is [System.Management.Automation.Language.ParameterAst] },
        $true) | ForEach-Object { $_.Name.VariablePath.UserPath })

    return [pscustomobject]@{
        HasLogDirParam          = ($paramNames -contains 'LogDir')
        HasConfigPathParam      = ($paramNames -contains 'ConfigPath')
        HasLogDirFallback       = ($raw -match 'if\s*\(\s*-not\s+\$LogDir\s*\)')
        HasConfigPathFallback   = ($raw -match 'if\s*\(\s*-not\s+\$ConfigPath\s*\)')
        HasMapFileRef           = ($raw -match '\$MapFile')
        CsnMapUsesConfigPath    = ($raw -match '(?s)function\s+Get-CsnMap.*?\$ConfigPath')
    }
}

# ── (A) 구조 ──────────────────────────────────────────────────────────────────
Write-Host '(A) 실제 파일의 경로 지정 구조'
$r = Test-SchedulerPaths $target
Assert $r.HasLogDirParam          'param() 블록에 $LogDir 파라미터가 있다'
Assert $r.HasConfigPathParam      'param() 블록에 $ConfigPath 파라미터가 있다'
Assert $r.HasLogDirFallback       'if (-not $LogDir) 폴백이 있다'
Assert $r.HasConfigPathFallback   'if (-not $ConfigPath) 폴백이 있다'
Assert (-not $r.HasMapFileRef)     '하드코딩 $MapFile 참조가 남아 있지 않다'
Assert $r.CsnMapUsesConfigPath    'Get-CsnMap 이 $ConfigPath 를 쓴다'

# ── (B) 기본 호출 ─────────────────────────────────────────────────────────────
Write-Host '(B) 기본 호출 — 기존 절과 경로 표시가 유지된다'
$out = (& $target -Action Status | Out-String)
Assert ($out -match '## CSN Targets') '기본 호출에 CSN Targets 절이 있다'
Assert ($out -match '## Locks')       '기본 호출에 Locks 절이 있다'
Assert ($out -match '로그 디렉터리')   '기본 호출에 로그 디렉터리 표시가 있다'
Assert ($out -match 'CSN 맵')          '기본 호출에 CSN 맵 표시가 있다'

# ── (C) -LogDir 지정 ──────────────────────────────────────────────────────────
Write-Host '(C) -LogDir 지정 — 지정 경로의 락이 PID·상태와 함께 보인다'
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("giip5054-test-{0}" -f [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
try {
    # PID 로 Int32.MaxValue 를 쓴다 — 이 값의 프로세스는 존재할 수 없으므로 항상 "죽은 PID" 다.
    $lockName = 'gissue_csn999999.lock'
    Set-Content -LiteralPath (Join-Path $tmp $lockName) -Value '2147483647' -Encoding ASCII
    $out2 = (& $target -Action Status -LogDir $tmp | Out-String)
    Assert ($out2 -match [regex]::Escape($lockName))  '-LogDir 로 지정한 락 파일이 보인다'
    Assert ($out2 -match 'STALE_DEAD_PID')            '죽은 PID 락이 STALE_DEAD_PID 로 표시된다'
    Assert ($out2 -match [regex]::Escape($tmp))       '지정한 로그 디렉터리 경로가 출력에 표시된다'
}
finally {
    if (Test-Path $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}

# ── (D) -ConfigPath 지정 ──────────────────────────────────────────────────────
Write-Host '(D) -ConfigPath 지정 — 지정한 CSN 맵의 대상이 보인다'
$tmpCfgDir = Join-Path ([System.IO.Path]::GetTempPath()) ("giip5054-cfg-{0}" -f [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmpCfgDir -Force | Out-Null
try {
    $cfg = Join-Path $tmpCfgDir 'csn-projects.json'
    $json = '{ "csn": { "999999": { "project": "gissue5054-fixture", "enabled": true, "workdir": "." } } }'
    [System.IO.File]::WriteAllText($cfg, $json, (New-Object System.Text.UTF8Encoding $false))
    $out3 = (& $target -Action Status -ConfigPath $cfg | Out-String)
    Assert ($out3 -match 'gissue5054-fixture') '-ConfigPath 로 지정한 CSN 맵의 대상이 CSN Targets 절에 보인다'
    Assert (-not ($out3 -match 'No CSN targets found')) '지정 CSN 맵이 있을 때 "No CSN targets found" 가 아니다'
}
finally {
    if (Test-Path $tmpCfgDir) { Remove-Item -LiteralPath $tmpCfgDir -Recurse -Force -ErrorAction SilentlyContinue }
}

# ── (E) 음성 — 파라미터를 지운 사본에서는 검사기가 "없음"을 보고해야 한다 ────────
Write-Host '(E) $LogDir 파라미터가 지워진 사본'
$rawSrc = Get-Content -LiteralPath $target -Raw
$mutated = $rawSrc.Replace("[string]`$LogDir = '',", '')
$tmp2 = Join-Path ([System.IO.Path]::GetTempPath()) ("giip5054-mut-{0}.ps1" -f [guid]::NewGuid().ToString('N'))
try {
    # UTF-8 with BOM 로 저장(원본 한국어 리터럴 보존 + ParseFile 안정).
    [System.IO.File]::WriteAllText($tmp2, $mutated, (New-Object System.Text.UTF8Encoding $true))
    $r2 = Test-SchedulerPaths $tmp2
    Assert (-not $r2.HasLogDirParam) '사본에서는 $LogDir 파라미터가 검출되지 않는다 (기대 FAIL 확인)'
}
finally {
    if (Test-Path $tmp2) { Remove-Item -LiteralPath $tmp2 -Force -ErrorAction SilentlyContinue }
}

if ($fail -gt 0) { Write-Host "FAILED: $fail" -ForegroundColor Red; exit 1 }
Write-Host 'ALL PASS'
