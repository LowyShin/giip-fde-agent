# test-manage-gissue-scheduler.ps1 — manage-gissue-scheduler.ps1 의 -AuxTaskNames 기본 배열 회귀 테스트 (giip #5053)
#
# 왜 필요한가(실사고): 정본 상태 조회 도구(-Action Status)의 보조 태스크 목록(-AuxTaskNames 기본 배열)이
#   등록기 목록과 어긋난 채 방치돼, 매시 :37 에 정상 등록·실행 중이던 무소식 감지 태스크
#   GIIP_GissueLiveness_Hourly 가 "## Auxiliary Hourly Schedulers" 절에 아예 출력되지 않았다. 같은
#   드리프트(기본 배열에서 항목이 빠지는 것)가 되돌아오면 조용히 재발하므로 순수 단위 테스트로 고정한다.
#
# 고정하는 것:
#   (A) 실제 파일의 param() 블록 $AuxTaskNames 기본 배열에 GIIP_GissueLiveness_Hourly 가 들어 있다(기대 PASS).
#   (B) 그 항목을 지운 임시 사본에서는 검사기가 "없음"을 보고한다(기대 FAIL). (B)가 없으면 "항상 PASS 하는
#       검사기"와 구분되지 않는다(rule 42).
#
# 이 테스트는 Get-ScheduledTask 를 호출하지 않는 순수 파일(AST) 검사다 — 실제 스케줄러를 건드리지 않는다.
#
# 실행: powershell -NoProfile -ExecutionPolicy Bypass -File scripts\gissue\tests\test-manage-gissue-scheduler.ps1

$ErrorActionPreference = 'Stop'

$target = Join-Path (Split-Path -Parent $PSScriptRoot) 'manage-gissue-scheduler.ps1'
if (-not (Test-Path $target)) { Write-Host "대상 없음: $target" -ForegroundColor Red; exit 1 }

$wanted = 'GIIP_GissueLiveness_Hourly'

# PowerShell AST 파서로 param() 블록의 $AuxTaskNames 기본값 배열에서 문자열 리터럴을 뽑아낸다.
# 정규식 grep 이 아니라 실제 파서를 쓰는 이유: 주석 안의 같은 문자열이나 다른 배열에 섞여도 오탐하지 않게.
function Get-AuxTaskNamesDefault([string]$path) {
    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
    if ($errors -and $errors.Count -gt 0) {
        throw "구문 오류로 파싱 실패: $path ($($errors.Count)건)"
    }
    $paramAst = $ast.Find(
        {
            param($n)
            $n -is [System.Management.Automation.Language.ParameterAst] -and
            $n.Name.VariablePath.UserPath -eq 'AuxTaskNames'
        }, $true)
    if (-not $paramAst) { throw "param() 블록에 \$AuxTaskNames 파라미터가 없음: $path" }
    if (-not $paramAst.DefaultValue) { throw "\$AuxTaskNames 에 기본값 배열이 없음: $path" }
    $strs = $paramAst.DefaultValue.FindAll(
        { param($n) $n -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true)
    return @($strs | ForEach-Object { $_.Value })
}

$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  ok   $msg" }
    else { Write-Host "  FAIL $msg" -ForegroundColor Red; $script:fail++ }
}

# (A) 실제 파일 — 기대 PASS: 항목이 들어 있어야 한다.
Write-Host "(A) 실제 파일의 -AuxTaskNames 기본 배열"
$names = Get-AuxTaskNamesDefault $target
Write-Host ("     추출된 기본 배열: " + ($names -join ', '))
Assert ($names -contains $wanted) "기본 배열에 $wanted 포함 (기대 PASS)"

# (B) 해당 항목을 지운 임시 사본 — 기대 FAIL: 검사기가 "없음"을 보고해야 한다(검사기가 진짜 감지하는지 확인).
Write-Host "(B) 해당 항목을 지운 임시 사본"
$raw = Get-Content -LiteralPath $target -Raw
# 앞 콤마까지 함께 제거해 배열에 끝 콤마가 남아 파싱이 깨지지 않게 한다.
$mutated = [regex]::Replace($raw, ",\s*'$([regex]::Escape($wanted))'", '')
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("manage-gissue-scheduler.mutated.{0}.ps1" -f ([guid]::NewGuid().ToString('N')))
try {
    # UTF-8 with BOM 로 저장(원본 한국어 리터럴 보존 + ParseFile 안정).
    $enc = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllText($tmp, $mutated, $enc)
    $mutNames = Get-AuxTaskNamesDefault $tmp
    Write-Host ("     사본 기본 배열: " + ($mutNames -join ', '))
    Assert (-not ($mutNames -contains $wanted)) "항목을 지운 사본에서는 $wanted 미검출 (기대 FAIL 확인)"
}
finally {
    if (Test-Path $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
}

if ($fail -gt 0) { Write-Host "FAILED: $fail" -ForegroundColor Red; exit 1 }
Write-Host 'ALL PASS'
