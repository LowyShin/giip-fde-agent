# verify-nested-repo.ps1 — nested git 레포 체크아웃 무결성 가드 (giip #1365)
#
# 배경(giip #1365): 2026-08-22~23 사이 giipprj\giipdb 체크아웃이(어떤 프로세스가 그랬는지는
#   불명 — 근본원인 조사는 이 스크립트 범위 밖) 조용히 손상됐다. 실제로 있어야 할 원격
#   `LowyShin/giipdb.git`(main) 대신 엉뚱한 원격 `LowyShin/giip.git`(gh-pages)의 **bare
#   clone**이 그 경로를 차지하고 있었다 — 작업트리가 없는 bare 레포라 mgmt\*.ps1 스크립트가
#   전부 존재하지 않았고, 매시 :07 run-gissue-claude.ps1(giipdb\mgmt 의존, CSN 무관 공통
#   인프라)이 이 상태로 최대 하루 가까이 돌면서도 아무도 눈치채지 못했다.
#
# 이 스크립트는 그 사고를 감지만 한다 — 자동 재clone/자동 복구는 명시적으로 범위 밖이다.
#   이유: 애초에 "누군가/무언가 잘못된 레포를 자동으로 clone했다"는 것 자체가 이번 사고의
#   원인이었고, 그 프로세스가 아직 특정되지 않았다. 여기서 또 다른 자동 clone 로직을 추가하면
#   같은 실패 모드를 반복할 위험이 있다 — 그래서 detect-and-log만 하고, 실제 복구는 사람이
#   판단한다.
#
# 체크 항목(전부 순서대로 누적 검사 — 첫 실패에서 멈추지 않고 해당되는 모든 사유를 모아 보고):
#   1. $Path 존재(디렉터리) 여부
#   2. 유효한 git 레포인지(.git 존재 + `git rev-parse --git-dir` 성공)
#   3. bare 레포가 아닌지(`git rev-parse --is-bare-repository` = false) — giip #1365 실제
#      사고가 정확히 이 패턴(bare clone)이라 이 체크 하나만으로도 그때 잡혔을 것이다.
#   4. origin 리모트가 $ExpectedRemoteSuffix 로 끝나는지(ssh/https, .git 유무 무관하게 비교)
#   5. $RequiredFiles 각각 존재 — 없으면 하드 FAIL
#   6. $RequiredPsDir 안에 *.ps1 파일이 1개 이상 있는지 — 없으면 하드 FAIL
#   7. $OptionalFiles 각각 존재 — 없어도 FAIL 아님, WARN만(gitignore 대상 등 정상적으로
#      없을 수 있는 파일용, 예: dbconfig.json)
#
# 재사용 설계: giipprj\giipdb 전용이 아니다 — -Path/-ExpectedRemoteSuffix/-RequiredFiles 등을
#   바꿔 넘기면 giipprj\giipv3, giipprj\giipAgentWin 같은 다른 nested repo에도 그대로 쓸 수
#   있다(현재는 giipdb 하나만 run-gissue-claude.ps1 Phase -2 에 배선돼 있다).
#
# 출력 규약(run-gissue-claude.ps1 이 파싱): stdout 마지막 줄이 항상
#   `RESULT: PASS` 또는 `RESULT: FAIL: <사유1>; <사유2>; ...` 이고, exit code 는 PASS=0, FAIL=1.
#   [WARN] 로 시작하는 줄은 그 앞에 0개 이상 출력될 수 있다(정보성, exit code 에 영향 없음).
#
# 사용 예:
#   powershell -File verify-nested-repo.ps1 -Path 'C:\...\giipprj\giipdb' `
#     -ExpectedRemoteSuffix 'LowyShin/giipdb.git' -RequiredFiles @('mgmt') -RequiredPsDir 'mgmt' `
#     -OptionalFiles @('mgmt\dbconfig.json')

param(
    [Parameter(Mandatory=$true)][string]$Path,                 # 검증할 체크아웃 경로
    [Parameter(Mandatory=$true)][string]$ExpectedRemoteSuffix, # 예: "LowyShin/giipdb.git" 또는 "SHINSEMA/giipv3.git"
    [string[]]$RequiredFiles = @(),   # $Path 기준 상대경로(파일/폴더) — 없으면 하드 FAIL
    [string[]]$OptionalFiles = @(),   # 상대경로 — 없어도 FAIL 아님(gitignore 대상 등), WARN만
    [string]$RequiredPsDir = $null,   # 상대 디렉터리 경로 — 존재 + *.ps1 1개 이상 필수, 아니면 하드 FAIL
    # giipdb dbconfig.json databaseName/login 검증 스위치 (giip #1365).
    # 이 스위치가 켜지면 mgmt\dbconfig.json 을 직접 읽어 databaseName=giipdb,
    # login=giipadmin(관리용 로컬 접속 계정)을 검증한다. 웹서버가 쓰는 프로덕션 계정
    # (lwmspdbo)과는 다른 계정이며, 이 파일은 로컬 관리 스크립트(execSQLFile.ps1 등)용이므로
    # giipadmin이 맞다. 파일 없으면 하드 FAIL.
    [switch]$ValidateDbConfig = $false
)

$failReasons = @()
$warnLines = @()

function Add-Fail([string]$reason) {
    $script:failReasons += $reason
}

function Add-Warn([string]$entry) {
    $line = "[WARN] 선택 파일 없음(정상일 수 있음, gitignore 대상): $entry"
    $script:warnLines += $line
}

# 1) 경로 존재 여부 — 없으면 이후 검사는 의미가 없으므로 여기서 그대로 종료.
if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
    Add-Fail "경로가 존재하지 않음: $Path"
    foreach ($w in $warnLines) { Write-Output $w }
    Write-Output ("RESULT: FAIL: " + ($failReasons -join '; '))
    exit 1
}

# 2) 유효한 git 레포인지(.git 존재 + rev-parse 성공).
$gitDirOk = $false
try {
    $null = git -C $Path rev-parse --git-dir 2>&1
    if ($LASTEXITCODE -eq 0) { $gitDirOk = $true }
} catch { $gitDirOk = $false }
if (-not $gitDirOk) {
    Add-Fail "유효한 git 레포가 아님(.git 없음/손상): $Path"
}

# 3) bare 레포 여부 — giip #1365 실제 사고 패턴(작업트리 없는 bare clone)을 직접 겨냥.
if ($gitDirOk) {
    $isBare = $null
    try {
        $isBare = (git -C $Path rev-parse --is-bare-repository 2>&1)
        if ($LASTEXITCODE -ne 0) { $isBare = $null }
    } catch { $isBare = $null }
    if ($null -eq $isBare) {
        Add-Fail "bare 레포임(작업트리 없음) — giip #1365 인시던트와 동일 패턴"
    } else {
        $isBareStr = ("$isBare").Trim()
        if ($isBareStr -ne 'false') {
            Add-Fail "bare 레포임(작업트리 없음) — giip #1365 인시던트와 동일 패턴"
        }
    }
}

# 4) origin 리모트가 예상 접미사로 끝나는지(ssh/https, .git 유무 무관하게 정규화 후 비교).
if ($gitDirOk) {
    $originUrl = $null
    try {
        $originUrl = (git -C $Path remote get-url origin 2>&1)
        if ($LASTEXITCODE -ne 0) { $originUrl = $null }
    } catch { $originUrl = $null }
    if (-not $originUrl) {
        try {
            $originUrl = (git -C $Path config --get remote.origin.url 2>&1)
            if ($LASTEXITCODE -ne 0) { $originUrl = $null }
        } catch { $originUrl = $null }
    }
    $originUrlStr = if ($originUrl) { ("$originUrl").Trim() } else { '' }
    if (-not $originUrlStr) {
        Add-Fail "origin remote 미설정"
    } else {
        $normActual = $originUrlStr.ToLower()
        if ($normActual.EndsWith('.git')) { $normActual = $normActual.Substring(0, $normActual.Length - 4) }
        $normExpected = $ExpectedRemoteSuffix.ToLower()
        if ($normExpected.EndsWith('.git')) { $normExpected = $normExpected.Substring(0, $normExpected.Length - 4) }
        if (-not $normActual.EndsWith($normExpected)) {
            Add-Fail "origin remote '$originUrlStr' 이 예상 접미사 '$ExpectedRemoteSuffix' 와 불일치 — 잘못된 레포 clone 의심(giip #1365 패턴)"
        }
    }
}

# 5) 필수 파일/폴더 — 하나라도 없으면 전부 모아서 하드 FAIL.
$missingRequired = @()
foreach ($entry in $RequiredFiles) {
    $full = Join-Path $Path $entry
    if (-not (Test-Path -LiteralPath $full)) { $missingRequired += $entry }
}
if ($missingRequired.Count -gt 0) {
    Add-Fail ("필수 파일/폴더 없음: " + ($missingRequired -join ', '))
}

# 6) 필수 ps1 디렉터리 — 존재 + *.ps1 1개 이상.
if ($RequiredPsDir) {
    $psDirFull = Join-Path $Path $RequiredPsDir
    $psOk = $false
    if (Test-Path -LiteralPath $psDirFull -PathType Container) {
        $ps1Count = @(Get-ChildItem -Path $psDirFull -Filter *.ps1 -File -ErrorAction SilentlyContinue).Count
        if ($ps1Count -ge 1) { $psOk = $true }
    }
    if (-not $psOk) {
        Add-Fail "$RequiredPsDir 안에 *.ps1 파일이 없음(디렉터리 없음 또는 비어있음)"
    }
}

# 7) 선택 파일 — 없어도 FAIL 아님, WARN만.
foreach ($entry in $OptionalFiles) {
    $full = Join-Path $Path $entry
    if (-not (Test-Path -LiteralPath $full)) { Add-Warn $entry }
}

# 8) giipdb 전용: dbconfig.json databaseName/login 검증 (giip #1365).
#    이 검사는 verify-nested-repo.ps1 가 이미 giipprj/giipdb 의 mgmt/dbconfig.json 위치를
#    알고 있으므로 별도 JSON 파라미터 없이 여기서 직접 읽는다.
if ($ValidateDbConfig) {
    $dbconfigPath = Join-Path $Path 'mgmt\dbconfig.json'
    if (-not (Test-Path -LiteralPath $dbconfigPath)) {
        Add-Fail "dbconfig.json 없음: $dbconfigPath — 이 파일은 체크아웃에 반드시 포함되어야 합니다(giip #1365 패턴)"
    } else {
        try {
            $dbconfigContent = Get-Content -LiteralPath $dbconfigPath -Raw -Encoding UTF8
            $dbconfigJson = $dbconfigContent | ConvertFrom-Json
            if ($null -eq $dbconfigJson.databaseName) {
                Add-Fail "dbconfig.json에 databaseName 필드 없음"
            } elseif ("$($dbconfigJson.databaseName)" -ne 'giipdb') {
                Add-Fail "dbconfig.json databaseName = '$($dbconfigJson.databaseName)' (기대값: 'giipdb') — 잘못된 DB 설정(giip #1365 패턴)"
            }
            if ($null -eq $dbconfigJson.login) {
                Add-Fail "dbconfig.json에 login 필드 없음"
            } elseif ("$($dbconfigJson.login)" -ne 'giipadmin') {
                Add-Fail "dbconfig.json login = '$($dbconfigJson.login)' (기대값: 'giipadmin') — 잘못된 DB 설정(giip #1365 패턴)"
            }
        } catch {
            Add-Fail "dbconfig.json 파싱 실패: $_"
        }
    }
}

foreach ($w in $warnLines) { Write-Output $w }
if ($failReasons.Count -gt 0) {
    Write-Output ("RESULT: FAIL: " + ($failReasons -join '; '))
    exit 1
} else {
    Write-Output "RESULT: PASS"
    exit 0
}
