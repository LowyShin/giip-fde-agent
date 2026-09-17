# test-verify-runner-korean-encoding.ps1 — PowerShell verify 블록 한글 출력 보존 회귀 테스트 (giip #2589)
#
# 왜 필요한가 (실측, 2026-09-16):
#   verify-runner.mjs 의 runBlock() 이 spawnSync('powershell', [...], { encoding: 'utf8' }) 으로
#   자식 stdout 을 UTF-8 이라고 가정해 디코드했지만, Windows PowerShell 5.1 은 리다이렉트된 stdout 에
#   콘솔 코드페이지(cp949 계열)로 쓴다. cp949 바이트를 UTF-8 로 디코드하면 한글은 전부 '?' 로 깨진다.
#
#   실측 결과(2026-09-16):
#     - encoding='utf8' 만: qCount=7 (한글 7글자가 전부 ?로 대체)
#     - [Console]::OutputEncoding=[Text.Encoding]::UTF8; prefix 추가: qCount=0 (정상 보존)
#     - bash: UTF-8 정상
#
# 실행:
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gissue/tests/test-verify-runner-korean-encoding.ps1
# 종료코드: 0 = 전건 PASS, 1 = 1건 이상 FAIL

[CmdletBinding()]
param()

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'

$GissueDir = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$Runner = Join-Path $GissueDir 'verify-runner.mjs'

$script:Pass = 0
$script:Fail = 0
function Assert-True($cond, $name, $detail = '') {
    if ($cond) { $script:Pass++; Write-Output "  PASS  $name" }
    else { $script:Fail++; Write-Output "  FAIL  $name$(if ($detail) { " — $detail" })" }
}

# ──────────────────────────────────────────────────────────────────────────────
Write-Output 'A. 정적 검증 — runBlock 코드에 UTF-8 인코딩 처리가 존재해야 함'
# ──────────────────────────────────────────────────────────────────────────────

Assert-True (Test-Path -LiteralPath $Runner) 'A-0 verify-runner.mjs 파일 존재'

$runnerText = Get-Content -LiteralPath $Runner -Raw -Encoding UTF8

# A-1: PowerShell 분기에 OutputEncoding UTF-8 prefix 가 있어야 한다
Assert-True ($runnerText -match '\[Console\]::OutputEncoding\s*=\s*\[System\.Text\.Encoding\]::UTF8') `
    'A-1 runBlock에 PowerShell용 UTF-8 인코딩 prefix 존재' ''

# A-2: bash 분기에는 prefix가 없어야 한다 (bash는 UTF-8이 기본이므로)
#    bash 분기 문자열을 추출해서 pwshPrefix가 bash에 삽입되지 않았는지 확인
$pwsPrefix = '[Console]::OutputEncoding=[System.Text.Encoding]::UTF8; '
# bash spawnSync 호출 부분을 찾아서 거기에 OutputEncoding prefix가 없는지 확인
$bashSpawnMatch = $runnerText -match 'spawnSync\(''bash'',.*?\{[^}]*encoding:''utf8''[^}]*\}'
if ($bashSpawnMatch) {
    # bashspawn 코드에서 cmd 변수 대입 부분을 추출
    $bashSection = $runnerText -replace '(?s).*?spawnSync\(''bash''(.*?)(?=\n\s*(?:spawnSync|function|\z)).*', '$1'
    Assert-True (-not $bashSection.Contains($pwsPrefix.Replace(';', ''))) `
        'A-2 bash 분기에 OutputEncoding prefix 가 없음(필요 없음)' ''
}

# ──────────────────────────────────────────────────────────────────────────────
Write-Output ''
Write-Output 'B. 동적 검증 — 실제 spawnSync로 한글 출력 보존 확인'
# ──────────────────────────────────────────────────────────────────────────────

# [giip #2645 이식] 두 케이스 모두 스크립트를 **파일**로 넘긴다. 커맨드라인 인자로 한글을 넘기면
# 이 호스트에서 두 가지가 동시에 망가진다(실측):
#   (1) PowerShell 5.1 은 네이티브 프로세스 인자를 시스템 ANSI 코드페이지(cp932)로 인코딩한다 —
#       bash.exe 는 그걸 UTF-8 로 읽어 한글 인자가 통째로 사라졌고, `echo ""` 가 되어 빈 출력만
#       나왔다.
#   (2) Start-Process -ArgumentList 는 인자 안의 큰따옴표를 보존하지 못한다 — powershell 케이스는
#       `Write-Output "한글 테스트: ..."` 가 따옴표를 잃고 인자 3개로 쪼개져 세 줄로 출력됐다.
# 원본 테스트는 "물음표 개수 0"만 보았기 때문에 (1)의 **빈 출력**도 (2)의 **쪼개진 출력**도 전부
# PASS 로 통과시켰다(가짜 녹색). 실제 verify-runner.mjs 는 node spawnSync 로 실행하므로 둘 중
# 어느 함정도 타지 않는다 — 즉 검증 대상이 아닌 것을 검증하고 있었다.
# 파일 경유는 인자가 순수 ASCII 경로 하나뿐이라 두 함정을 모두 지나간다.
$testCases = @(
    @{
        Label     = 'B-1 PowerShell + UTF8 prefix'
        Cmd       = 'powershell'
        PreArgs   = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File')
        ScriptExt = '.ps1'
        ScriptBom = $true      # PowerShell 5.1 은 BOM 없는 .ps1 을 ANSI 로 읽는다(giip #2590/#2591)
        Script    = '[Console]::OutputEncoding=[System.Text.Encoding]::UTF8' + "`r`n" + 'Write-Output "한글 테스트: 분류=Modification"'
        ExpectQ   = 0
    },
    @{
        Label     = 'B-2 bash (UTF-8 기본)'
        Cmd       = 'bash'
        PreArgs   = @()
        ScriptExt = '.sh'
        ScriptBom = $false     # bash 는 BOM 을 명령의 일부로 읽는다 — 절대 붙이지 않는다.
        Script    = 'echo "한글 테스트: 분류=Modification"'
        ExpectQ   = 0
    }
)

# [giip #2645 이식] `Start-Process -FilePath 'bash'` 는 PATH 탐색 규칙이 `&`/Get-Command 와 달라
# Git Bash 가 설치돼 있어도 "The system cannot find the file specified" 로 죽는다(이 PC 실측:
# Get-Command bash 는 C:\Program Files\Git\usr\bin\bash.exe 를 찾는데 Start-Process 는 못 찾았다.
# 원본 lowyworkenv 에서도 동일하게 실패하던 선행 결함이다 — 이식하면서 함께 고친다).
# 실행파일은 Get-Command 로 **절대경로**를 먼저 해석하고, 그래도 없으면 그 케이스만 SKIP 한다
# (bash 가 없는 배포 대상에서 테스트 전체가 실패하지 않게 — 이 레포는 다른 PC 이식이 요건이다).
function Resolve-ExePath([string]$name) {
    $cmd = Get-Command $name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd -and $cmd.Source) { return $cmd.Source }
    # Windows 기본 Git 설치는 PATH 에 `<Git>\cmd` 만 올린다 — `bash.exe` 가 있는 `<Git>\bin` 은
    # 올라가지 않아 Get-Command 로도 안 잡힌다(이 PC 실측: PATH 에 Git\cmd 만 존재).
    # 절대경로를 박지 않고 git.exe 위치에서 형제 디렉터리를 유도한다(어느 PC 든 동일하게 동작).
    if ($name -eq 'bash') {
        $git = Get-Command git -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($git -and $git.Source) {
            $gitRoot = Split-Path (Split-Path $git.Source -Parent) -Parent   # <Git>\cmd\git.exe -> <Git>
            foreach ($rel in @('bin\bash.exe', 'usr\bin\bash.exe')) {
                $p = Join-Path $gitRoot $rel
                if (Test-Path -LiteralPath $p) { return $p }
            }
        }
    }
    return $null
}

foreach ($tc in $testCases) {
    # PowerShell 의 [Console]::OutputEncoding 설정은 이 프로세스 에서만 유효 —
    # node spawnSync 로 새 프로세스를 띄우므로 위 Cmd 문자열에 직접 prefix를 넣어야 한다.
    # (B-1은 이미 위에 그렇게 했다 — 별도 설정 불필요)

    $exe = Resolve-ExePath $tc.Cmd
    if (-not $exe) {
        Write-Output "  SKIP  $($tc.Label): '$($tc.Cmd)' 를 이 호스트에서 찾을 수 없습니다(미설치)."
        continue
    }

    $scriptFile = Join-Path $env:TEMP ("gissue_korean_test_{0}{1}" -f [guid]::NewGuid().ToString('N'), $tc.ScriptExt)
    $body = $tc.Script
    if (-not $tc.ScriptBom) {
        # bash 스크립트는 LF 로 — CR 이 남으면 `$'\r': command not found` 가 난다.
        $body = ($body -replace "`r`n", "`n")
    }
    [System.IO.File]::WriteAllText($scriptFile, $body + "`n", (New-Object System.Text.UTF8Encoding $tc.ScriptBom))
    $procArgs = @($tc.PreArgs) + @($scriptFile)

    $r = Start-Process -FilePath $exe -ArgumentList $procArgs `
        -NoNewWindow -Wait -PassThru -RedirectStandardOutput "$env:TEMP\gissue_korean_test_out.txt" `
        -RedirectStandardError "$env:TEMP\gissue_korean_test_err.txt"

    $stdout = ''
    if (Test-Path "$env:TEMP\gissue_korean_test_out.txt") {
        $stdout = Get-Content "$env:TEMP\gissue_korean_test_out.txt" -Raw -Encoding UTF8
    }

    $qCount = ([regex]::Matches($stdout, '\?') | Measure-Object).Count
    # [giip #2645 이식] "물음표 0개"만 보면 **빈 출력이 항상 통과**한다(실측: bash 케이스가 인자
    # 인코딩 때문에 빈 줄만 내고도 PASS 했다). 기대 문자열이 실제로 살아 돌아왔는지도 같이 본다.
    $hasKorean = ("$stdout" -match '한글 테스트: 분류=Modification')
    $passed = ($qCount -eq $tc.ExpectQ) -and $hasKorean

    Assert-True $passed "$($tc.Label): qCount=$qCount (기대값=$($tc.ExpectQ)), 한글보존=$hasKorean, 출력=$(($stdout -replace '[\r\n]+', ' ') | Select-Object -First 60)" ''

    Remove-Item "$env:TEMP\gissue_korean_test_out.txt" -ErrorAction SilentlyContinue
    Remove-Item "$env:TEMP\gissue_korean_test_err.txt" -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $scriptFile -Force -ErrorAction SilentlyContinue
}

# ──────────────────────────────────────────────────────────────────────────────
Write-Output ''
Write-Output "결과: PASS=$($script:Pass) FAIL=$($script:Fail)"
if ($script:Fail -gt 0) { exit 1 }
exit 0
