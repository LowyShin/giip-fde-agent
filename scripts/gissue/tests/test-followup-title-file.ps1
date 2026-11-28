# test-followup-title-file.ps1 — 후속(캐리오버) 이슈 제목이 큰따옴표에서 잘리는 결함 회귀 테스트 (giip 6620)
#
# 왜 필요한가 (실측 재현, 2026-11-28):
#   Windows PowerShell 5.1 이 네이티브 명령(node)에 인자를 넘길 때, 값 안에 큰따옴표(")가 있으면
#   명령줄 재구성 단계에서 따옴표가 인자 구분자로 취급되어 **값이 두 토큰으로 쪼개진다.**
#   register-issue.js 는 `--title` 의 **바로 다음 토큰 하나만** 제목으로 읽으므로 등록 제목이
#   첫 조각으로 잘리고 '(원본 giip #NNNN)' 표식이 통째로 사라진다.
#   실측: isn=6606 의 저장 제목이 정확히 '[후속] slack-bot 이 소켓은' 으로 잘려 있었고,
#   isn=6620 은 그 잘린 제목에 접두가 다시 붙은 2차 손상이다.
#   → 해결: 제목은 UTF-8 **파일**로 넘긴다(`--title-file`). 인자 경계를 아예 건너지 않는다.
#
# 이 테스트가 잡는 것:
#   A. 환경 재현 — PowerShell → node 경계에서 실제로 쪼개지는지, 그리고 그 결과 표식이 사라지는지
#      (기대 FAIL 1건: `--title` 경로는 표식을 잃는다)
#   B. 수정 경로 — `--title-file` 경로는 제목이 원본과 **한 글자도 다르게** 등록된다
#      (기대 PASS 1건: 표식 포함 원본 그대로)
#   C. 회귀 가드 — 두 호출부(타임박스 후속 등록 / review-done-audit 후속 등록)가 네이티브
#      `--title $var` 직접 전달을 쓰지 않고 `--title-file` 을 쓴다
#
# 실행: powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gissue/tests/test-followup-title-file.ps1
# 종료코드: 0 = 전건 PASS, 1 = 1건 이상 FAIL
#
# 실 환경 등록(issueCreate)은 하지 않는다 — resolve-title.mjs 는 register-issue.js 의 순수
# 함수만 호출하고 main() 은 실행되지 않는다.

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\..')).Path
$RegisterJs = Join-Path $RepoRoot 'scripts\gissue\register-issue.js'
$RunnerPs1 = Join-Path $RepoRoot 'scripts\gissue\run-gissue-claude.ps1'
$AuditPs1 = Join-Path $RepoRoot 'scripts\gissue\review-done-audit.ps1'
$DumpFixture = Join-Path $PSScriptRoot 'fixtures\dump-argv.mjs'
$ResolveFixture = Join-Path $PSScriptRoot 'fixtures\resolve-title.mjs'

$script:Pass = 0
$script:Fail = 0
function Assert-True($cond, $name, $detail = '') {
    if ($cond) { $script:Pass++; Write-Output "  PASS  $name" }
    else { $script:Fail++; Write-Output "  FAIL  $name$(if ($detail) { " — $detail" })" }
}
function Assert-Equal($expected, $actual, $name) {
    if ($expected -ceq $actual) { $script:Pass++; Write-Output "  PASS  $name" }
    else { $script:Fail++; Write-Output "  FAIL  $name — expected='$expected' actual='$actual'" }
}

$TmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ("gissue-followup-title-test-{0}" -f [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $TmpDir -Force | Out-Null
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

try {
    # isn=5141 의 실제 제목(큰따옴표 포함) + 타임박스 캐리오버 접미사 — 6606 제목을 만든 입력 그 자체.
    $origTitle = '[후속] slack-bot 이 "소켓은 연결됐는데 이벤트가 한 건도 안 오는" 상태를 감지·자가복구하지 못함 (2026-11-13 재시작 직후 !help 무응답) - 40분 캡 초과 잔여 작업 (원본 giip #5141)'
    $marker = '(원본 giip #5141)'

    # ────────────────────────────────────────────────────────────────────────────
    # A. 환경 재현 — `--title` 네이티브 직접 전달은 표식을 잃는다(기대 FAIL 케이스)
    # ────────────────────────────────────────────────────────────────────────────
    Write-Output 'A. PowerShell → node 인자 경계 재현 (--title 직접 전달)'

    $argvOut = Join-Path $TmpDir 'argv.json'
    & node $DumpFixture $argvOut --title $origTitle
    if ($LASTEXITCODE -ne 0) { throw "dump-argv.mjs 실행 실패 (exit=$LASTEXITCODE)" }
    $spec = [System.IO.File]::ReadAllText($argvOut, [System.Text.Encoding]::UTF8) | ConvertFrom-Json

    Assert-True ($spec.args.Count -gt 2) 'A-1 큰따옴표 포함 값이 인자 경계에서 쪼개진다(토큰 3개 이상)' "tokens=$($spec.args.Count)"

    $specFileA = Join-Path $TmpDir 'spec-a.json'
    [System.IO.File]::WriteAllText($specFileA, (ConvertTo-Json @{ args = @($spec.args) } -Depth 5), $Utf8NoBom)
    $outA = Join-Path $TmpDir 'title-a.txt'
    & node $ResolveFixture $specFileA $outA
    if ($LASTEXITCODE -ne 0) { throw "resolve-title.mjs 실행 실패 (exit=$LASTEXITCODE)" }
    $resolvedA = [System.IO.File]::ReadAllText($outA, [System.Text.Encoding]::UTF8)

    Assert-True (-not $resolvedA.Contains($marker)) 'A-2 결함 실증: --title 경로에서는 표식이 사라진다' "resolved='$resolvedA'"
    Assert-Equal '[후속] slack-bot 이 소켓은' $resolvedA 'A-3 실측 재현: isn=6606 저장 제목과 정확히 일치한다'
    Assert-True ($resolvedA -cne $origTitle) 'A-4 결함 실증: 원본 제목과 다르다'

    # ────────────────────────────────────────────────────────────────────────────
    # B. 수정 경로 — `--title-file` 은 제목이 원본과 한 글자도 다르지 않다 (기대 PASS 케이스)
    # ────────────────────────────────────────────────────────────────────────────
    Write-Output 'B. 수정 경로 (--title-file)'

    $titleFile = Join-Path $TmpDir 'title.txt'
    [System.IO.File]::WriteAllText($titleFile, $origTitle, $Utf8NoBom)

    $specFileB = Join-Path $TmpDir 'spec-b.json'
    [System.IO.File]::WriteAllText($specFileB, (ConvertTo-Json @{ args = @('--title-file', $titleFile) } -Depth 5), $Utf8NoBom)
    $outB = Join-Path $TmpDir 'title-b.txt'
    & node $ResolveFixture $specFileB $outB
    if ($LASTEXITCODE -ne 0) { throw "resolve-title.mjs 실행 실패 (exit=$LASTEXITCODE)" }
    $resolvedB = [System.IO.File]::ReadAllText($outB, [System.Text.Encoding]::UTF8)

    Assert-Equal $origTitle $resolvedB 'B-1 --title-file 제목이 원본과 정확히 일치한다'
    Assert-True $resolvedB.Contains($marker) 'B-2 표식(원본 giip #NNNN)이 보존된다'
    Assert-True ($resolvedB.Length -eq $origTitle.Length) 'B-3 길이가 원본과 같다(추가 절단 없음)'

    # BOM 으로 저장된 제목 파일도 첫 줄 파싱이 깨지지 않아야 한다(파이썬/다른 도구 대비 안전).
    $titleFileBom = Join-Path $TmpDir 'title-bom.txt'
    [System.IO.File]::WriteAllText($titleFileBom, $origTitle, (New-Object System.Text.UTF8Encoding($true)))
    $specFileB2 = Join-Path $TmpDir 'spec-b2.json'
    [System.IO.File]::WriteAllText($specFileB2, (ConvertTo-Json @{ args = @('--title-file', $titleFileBom) } -Depth 5), $Utf8NoBom)
    $outB2 = Join-Path $TmpDir 'title-b2.txt'
    & node $ResolveFixture $specFileB2 $outB2
    if ($LASTEXITCODE -ne 0) { throw "resolve-title.mjs 실행 실패 (exit=$LASTEXITCODE)" }
    $resolvedB2 = [System.IO.File]::ReadAllText($outB2, [System.Text.Encoding]::UTF8)
    Assert-Equal $origTitle $resolvedB2 'B-4 BOM 있는 제목 파일도 제목이 원본과 일치한다'

    # ────────────────────────────────────────────────────────────────────────────
    # C. 회귀 가드 — 호출부가 파일 경유(파일 경유)를 쓰고 네이티브 직접 전달을 쓰지 않는다
    # ────────────────────────────────────────────────────────────────────────────
    Write-Output 'C. 호출부 소스 가드'

    $runnerSrc = [System.IO.File]::ReadAllText($RunnerPs1, [System.Text.Encoding]::UTF8)
    $auditSrc = [System.IO.File]::ReadAllText($AuditPs1, [System.Text.Encoding]::UTF8)

    Assert-True ($runnerSrc.Contains('--title-file $timeboxTitleTmp')) 'C-1 타임박스 후속 등록이 --title-file 을 쓴다'
    Assert-True (-not $runnerSrc.Contains('--title $timeboxFollowupTitle')) 'C-2 타임박스 후속 등록이 네이티브 --title 직접 전달을 쓰지 않는다'
    Assert-True ($auditSrc.Contains('--title-file $tmpTitle')) 'C-3 review-done-audit 후속 등록이 --title-file 을 쓴다'
    Assert-True (-not $auditSrc.Contains('--title $title ')) 'C-4 review-done-audit 후속 등록이 네이티브 --title 직접 전달을 쓰지 않는다'

    $regSrc = [System.IO.File]::ReadAllText($RegisterJs, [System.Text.Encoding]::UTF8)
    Assert-True ($regSrc.Contains("k === '--title-file'")) 'C-5 register-issue.js 가 --title-file 인자를 인식한다'
} finally {
    Remove-Item -LiteralPath $TmpDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output ''
Write-Output ("결과: PASS {0}건 / FAIL {1}건" -f $script:Pass, $script:Fail)
if ($script:Fail -gt 0) { exit 1 }
exit 0
