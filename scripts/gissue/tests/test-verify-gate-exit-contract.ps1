# test-verify-gate-exit-contract.ps1 — VERIFY-GATE 종료 규약/호출 규약 회귀 테스트 (giip #2586)
#
# 왜 필요한가 (실측 사고, 2026-09-16):
#   `/gissue-review-check` 전체 CSN 진단에서 review-done-audit.ps1 의 VERIFY-GATE(giip #2418, rule 57)가
#   **모든 경로에서 fail-open** 하고 있었다. PASS→DONE 예정 10건 전부가 아래 로그 한 줄만 남기고
#   완료조건을 단 한 번도 실행하지 않은 채 통과했다.
#       [VERIFY-GATE] 예외로 건너뜀(기존 판정 유지): node:internal/errors:985
#   원인은 셋이었고, 이 테스트는 그 셋을 각각 고정한다.
#     A. verify-runner.mjs 가 `process.exit()` 즉시 호출 → undici 핸들 정리 중 libuv assertion 으로
#        abort → 종료코드가 의도한 0/1/2/3 이 아니라 127 (Windows/Node v24.13.0).
#     B. review-done-audit.ps1 의 러너 호출이 `& node ... 2>&1`(네이티브 stderr 리다이렉트) +
#        `$ErrorActionPreference='Stop'` → NativeCommandError 가 종료성 오류가 되어 $LASTEXITCODE
#        분기에 도달조차 못하고 catch 로 떨어짐 (rule 63).
#     C. dry-run 에서도 `--comment` 가 무조건 붙어, A 를 고치는 순간 진단 실행이 실제 이슈에
#        [VERIFY-RUN] 코멘트를 쓰기 시작하는 상태였음(dry-run 계약 위반).
#
# 실행:
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gissue/tests/test-verify-gate-exit-contract.ps1
#   powershell ... -File ... -SkipLive     # 네트워크/SK 없는 환경에서 A-3(라이브 러너 실행)을 건너뛴다
# 종료코드: 0 = 전건 PASS, 1 = 1건 이상 FAIL
#
# 이 테스트는 giip API 에 **쓰기**를 하지 않는다. A-3 만 읽기 조회 1회를 하고(러너가 --comment 없이
# 호출되므로 코멘트가 생기지 않는다), 나머지는 전부 오프라인(정적 + node 셰임)이다.
# 임시 파일은 `$env:TEMP\gissue-verifygate-test-<pid>` 안에서만 만들고 지운다.

[CmdletBinding()]
param(
    [switch]$SkipLive,
    [int]$LiveIsn = 2338,      # verify 블록이 없는 실제 이슈 — 러너가 exit 2 를 내야 한다
    [int]$LiveCsn = 33
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'   # ← 사고 당시와 동일 조건. C-4 가 이 전제 위에서만 의미가 있다.

$GissueDir = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$Runner = Join-Path $GissueDir 'verify-runner.mjs'
$Audit = Join-Path $GissueDir 'review-done-audit.ps1'

$script:Pass = 0
$script:Fail = 0
function Assert-True($cond, $name, $detail = '') {
    if ($cond) { $script:Pass++; Write-Output "  PASS  $name" }
    else { $script:Fail++; Write-Output "  FAIL  $name$(if ($detail) { " — $detail" })" }
}

$root = Join-Path $env:TEMP ("gissue-verifygate-test-$PID")
if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force -Confirm:$false }
New-Item -ItemType Directory -Path $root -Force | Out-Null

# ──────────────────────────────────────────────────────────────────────────────
Write-Output 'A. verify-runner.mjs 종료 규약 — 의도한 종료코드 + assertion 없음'
# ──────────────────────────────────────────────────────────────────────────────

Assert-True (Test-Path -LiteralPath $Runner) 'A-0 러너 파일 존재' $Runner

# A-1 정적: 실행 코드에 `process.exit(` 가 없어야 한다(주석/문서 인용은 제외).
#     이게 남아 있으면 fetch 핸들 정리 중 abort 가 재발하고 종료코드가 127 로 뭉개진다.
$runnerLines = Get-Content -LiteralPath $Runner -Encoding UTF8
$exitCalls = @($runnerLines | Where-Object {
        $t = $_.Trim()
        ($t -match 'process\.exit\s*\(') -and -not ($t.StartsWith('*') -or $t.StartsWith('//') -or $t.StartsWith('/*'))
    })
Assert-True ($exitCalls.Count -eq 0) 'A-1 실행 코드에 process.exit( 호출이 없음(process.exitCode 만 사용)' ($exitCalls -join ' | ')
Assert-True (($runnerLines -join "`n") -match 'process\.exitCode\s*=') 'A-1b 종료코드를 process.exitCode 로 전달' ''

# 러너를 실제로 띄워 종료코드와 stderr 를 본다. stdout/stderr 는 파일로 받는다
# (Start-Process 리다이렉트 — PowerShell 의 네이티브 stderr 리다이렉트 함정 회피, rule 63).
function Invoke-RunnerProcess([string[]]$RunnerArgs) {
    $o = Join-Path $root ("out_{0}.txt" -f [guid]::NewGuid().ToString('N'))
    $e = Join-Path $root ("err_{0}.txt" -f [guid]::NewGuid().ToString('N'))
    $p = Start-Process -FilePath 'node' -ArgumentList (@($Runner) + $RunnerArgs) `
        -NoNewWindow -Wait -PassThru -RedirectStandardOutput $o -RedirectStandardError $e `
        -WorkingDirectory $GissueDir
    $so = ''
    $se = ''
    if (Test-Path -LiteralPath $o) { $so = [string](Get-Content -LiteralPath $o -Raw -Encoding UTF8) }
    if (Test-Path -LiteralPath $e) { $se = [string](Get-Content -LiteralPath $e -Raw -Encoding UTF8) }
    return [pscustomobject]@{ Exit = $p.ExitCode; Stdout = $so; Stderr = $se }
}

# A-2 오프라인 경로(인자 없음 = usage) → 종료코드 3, assertion 없음.
$a2 = Invoke-RunnerProcess @()
Assert-True ($a2.Exit -eq 3) 'A-2 인자 없이 호출 → 종료코드 3(usage)' "실제=$($a2.Exit)"
Assert-True ($a2.Stderr -notmatch 'Assertion failed') 'A-2b stderr 에 libuv assertion 없음' $a2.Stderr

# A-3 라이브 경로(fetch 이후 종료) → verify 블록이 없는 이슈에서 종료코드 2, assertion 없음.
#     원인 A 는 "fetch 이후"에만 터지므로 이 케이스가 진짜 재현 테스트다.
if ($SkipLive) {
    Write-Output "  NOTE  A-3 라이브 러너 실행 생략(-SkipLive)"
} else {
    $a3 = Invoke-RunnerProcess @("$LiveIsn", "$LiveCsn")
    Assert-True ($a3.Stderr -notmatch 'Assertion failed') 'A-3 fetch 이후 종료에도 libuv assertion 없음' $a3.Stderr
    if ($a3.Exit -eq 3 -and $a3.Stdout + $a3.Stderr -match '조회 실패') {
        Write-Output "  NOTE  A-3b 이슈 조회 실패(네트워크/SK 미가용)로 종료코드 검증 생략 — assertion 검사는 통과했다."
    } else {
        Assert-True ($a3.Exit -eq 2) "A-3b verify 블록 없는 이슈(isn=$LiveIsn) → 종료코드 2" "실제=$($a3.Exit) / $($a3.Stdout)"
    }
}

# ──────────────────────────────────────────────────────────────────────────────
Write-Output ''
Write-Output 'B. review-done-audit.ps1 — rule 63 정본 형태 (정적)'
# ──────────────────────────────────────────────────────────────────────────────

Assert-True (Test-Path -LiteralPath $Audit) 'B-0 감사 스크립트 존재' $Audit
$auditText = Get-Content -LiteralPath $Audit -Raw -Encoding UTF8

# B-1 사고 당시의 호출 형태가 남아있지 않아야 한다(giip #2586 완료조건의 grep 과 동일 정규식).
Assert-True ($auditText -notmatch 'node \$verifyRunner .*2>&1') 'B-1 러너 호출에 네이티브 stderr 리다이렉트 없음' ''

# B-2 AST 로 Invoke-VerifyRunner 함수를 뽑아, 그 안에 stderr 리다이렉트가 없고
#     $LASTEXITCODE 로 분기(반환)하는지 확인한다.
$tokens = $null; $perrs = $null
$auditAst = [System.Management.Automation.Language.Parser]::ParseFile($Audit, [ref]$tokens, [ref]$perrs)
Assert-True (@($perrs).Count -eq 0) 'B-2a 감사 스크립트가 파싱 오류 없이 읽힘' (@($perrs | ForEach-Object { $_.ToString() }) -join ' | ')
$fnAst = $auditAst.Find({
        param($n)
        $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Invoke-VerifyRunner'
    }, $true)
Assert-True ($null -ne $fnAst) 'B-2b Invoke-VerifyRunner 함수가 정의돼 있음(러너 호출 단일 통로)' ''
$fnText = if ($fnAst) { $fnAst.Extent.Text } else { '' }
Assert-True ($fnText -notmatch '2>&1' -and $fnText -notmatch '2>\$null') 'B-2c 함수 본문에 stderr 리다이렉트 없음' ''
Assert-True ($fnText -match '\$ErrorActionPreference\s*=\s*''Continue''') 'B-2d 함수 스코프에서만 Continue 로 내림(rule 63 규칙 2)' ''
Assert-True ($fnText -match '\$LASTEXITCODE') 'B-2e $LASTEXITCODE 로 종료코드를 직접 읽음' ''

# B-3 게이트 분기를 try/catch 로 삼키지 않는다(rule 63 규칙 3). 사고 당시의 로그 문구가 사라져야 한다.
Assert-True ($auditText -notmatch 'VERIFY-GATE\] 예외로 건너뜀') 'B-3 게이트의 예외-삼킴(fail-open) 경로 제거됨' ''

# B-4 호출부가 -Live 여부를 그대로 --comment 여부로 넘긴다(원인 C).
Assert-True ($auditText -match 'Invoke-VerifyRunner .*-WithComment:\$IsLive') 'B-4 호출부가 -WithComment:$IsLive 로 전달' ''
Assert-True ($auditText -match '\$verifyCsn\s*=') 'B-4b 진단 모드 csn=0 보완 로직 존재' ''

# ──────────────────────────────────────────────────────────────────────────────
Write-Output ''
Write-Output 'C. Invoke-VerifyRunner 동작 — node 셰임으로 실제 호출 (dry-run/--comment/rule 63)'
# ──────────────────────────────────────────────────────────────────────────────
# 감사 스크립트 본문에서 함수 정의만 떼어내 이 세션에 정의한다. 스크립트 전체를 dot-source 하면
# 스윕이 실제로 돌기 때문에 쓸 수 없다(-Workdir 필수 + 라이브 API 호출).
if ($fnAst) {
    # 함수 정의문을 임시 .ps1 로 떨궈 dot-source 한다. Invoke-Expression 으로 정의하면 함수 안의
    # $PSScriptRoot 가 빈 문자열이 되어 Join-Path 가 죽는다(실측) — 파일 경유라야 그 값이 채워진다.
    # 한글 주석이 들어가므로 반드시 UTF-8 **BOM** 으로 쓴다(PS 5.1 은 BOM 없으면 ANSI 로 오독).
    $fnFile = Join-Path $root 'Invoke-VerifyRunner.ps1'
    [System.IO.File]::WriteAllText($fnFile, $fnText, (New-Object System.Text.UTF8Encoding $true))
    . $fnFile

    # PATH 앞에 셰임을 끼워 `& node` 가 이걸 타게 한다. 셰임은 (1) 받은 인자를 stdout 에 그대로 찍고
    # (2) stderr 에도 한 줄 쓴다 — (2)가 rule 63 회귀(NativeCommandError 종료성 오류)를 재현하는 장치다.
    $binDir = Join-Path $root 'bin'
    New-Item -ItemType Directory -Path $binDir -Force | Out-Null
    $shim = @(
        '@echo off',
        'echo ARGV %*',
        'echo shim-stderr-line 1>&2',
        'exit /b %GISSUE_SHIM_EXIT%'
    ) -join "`r`n"
    Set-Content -LiteralPath (Join-Path $binDir 'node.cmd') -Value $shim -Encoding ASCII

    $origPath = $env:PATH
    $env:PATH = "$binDir;$origPath"
    $env:GISSUE_SHIM_EXIT = '2'
    try {
        # C-1 dry-run(= -WithComment 미지정) → --comment 가 붙으면 안 된다. 이게 붙으면 진단/드라이런이
        #     실제 이슈에 [VERIFY-RUN] 코멘트를 쓴다(원인 C).
        $c1 = Invoke-VerifyRunner -Isn 2338 -Csn 33
        Assert-True ($c1.Output -notmatch '--comment') 'C-1 dry-run 호출에 --comment 가 붙지 않음' $c1.Output
        Assert-True ($c1.Output -match '\b33\b') 'C-1b csn 인자가 전달됨' $c1.Output

        # C-2 -Live 경로(= -WithComment) → --comment 가 붙어야 한다(게이트가 판정근거를 이슈에 남긴다).
        $c2 = Invoke-VerifyRunner -Isn 2338 -Csn 33 -WithComment
        Assert-True ($c2.Output -match '--comment') 'C-2 -WithComment 지정 시 --comment 가 붙음' $c2.Output

        # C-3 csn 0 은 아예 넘기지 않는다(러너가 csn=0 으로 SK 를 찾지 않도록).
        $c3 = Invoke-VerifyRunner -Isn 2338 -Csn 0
        Assert-True ($c3.Output -notmatch '(?m)\s0(\s|$)') 'C-3 csn=0 은 인자로 넘기지 않음' $c3.Output

        # C-4 ★핵심 회귀 가드★ — 셰임이 stderr 에 쓰고 exit 2 로 끝나도 예외 없이 Exit=2 를 돌려줘야 한다.
        #     사고 당시 형태(`2>&1` + Stop)였다면 여기서 NativeCommandError 로 죽는다.
        $threw = $false
        $c4 = $null
        try { $c4 = Invoke-VerifyRunner -Isn 2338 -Csn 33 } catch { $threw = $true }
        Assert-True (-not $threw) 'C-4 자식이 stderr 를 써도 종료성 오류로 죽지 않음(rule 63)' ''
        Assert-True ($null -ne $c4 -and $c4.Exit -eq 2) 'C-4b 자식 종료코드 2 가 그대로 전달됨' "실제=$(if ($c4) { $c4.Exit } else { '(예외)' })"

        # C-5 node 를 찾을 수 없을 때 0(=PASS)으로 오독되면 안 된다($LASTEXITCODE 선초기화 127).
        $emptyBin = Join-Path $root 'nobin'
        New-Item -ItemType Directory -Path $emptyBin -Force | Out-Null
        $env:PATH = $emptyBin
        $c5Exit = $null
        try { $c5Exit = (Invoke-VerifyRunner -Isn 2338 -Csn 33).Exit } catch { $c5Exit = 'throw' }
        Assert-True ($c5Exit -ne 0) 'C-5 node 실행 불가 시 0(PASS)으로 오독되지 않음' "실제=$c5Exit"
    } finally {
        $env:PATH = $origPath
        Remove-Item Env:\GISSUE_SHIM_EXIT -ErrorAction SilentlyContinue
    }
} else {
    Write-Output '  NOTE  Invoke-VerifyRunner 를 찾지 못해 C 섹션 생략(위 B-2b 가 이미 FAIL).'
}

# ── 정리: 이 테스트가 만든 임시 디렉터리만 제거한다 ──
try {
    Remove-Item -LiteralPath $root -Recurse -Force -Confirm:$false
} catch {
    Write-Output "  NOTE: 임시 디렉터리 정리 실패(무해) — $($_.Exception.Message) / 경로: $root"
}

Write-Output ''
Write-Output "결과: PASS=$($script:Pass) FAIL=$($script:Fail)"
if ($script:Fail -gt 0) { exit 1 }
exit 0
