# test-git-repo-paths.ps1 — 저장소 후보 수집이 커밋 0건 잔여 디렉터리를 제외하는지 회귀 테스트 (giip #5102)
#
# 왜 필요한가:
#   저장소 후보 수집이 `.git` 존재만으로 후보를 받으면, `git init` 만 된 커밋 0건 잔여 스캐폴드가
#   저장소로 오인돼 두 가지 증상이 난다:
#     1) busy-wait/auto-unblock 이 `git rev-parse --abbrev-ref HEAD` 에서 unborn HEAD 를 만나
#        예외로 죽는다.
#     2) PR 게이트 스윕·REVIEW/DONE 감사·PR 귀속 스윕은 EAP=Stop 이라 origin probe 의 네이티브
#        stderr 가 throw 되어 **저장소 수집 단계에서** 스윕 전체가 전멸한다(관측: "No such remote
#        'origin'"). 의도된 "origin 없는 디렉터리 제외" 로직이 한 번도 실행되지 않는다.
#
# 고정하는 것:
#   A. Get-GissueGitRepoPaths (모든 사본) — 커밋 0건 디렉터리 제외 / 커밋 있는 저장소 포함 /
#      자기 저장소(레포 루트)는 항상 포함 / 제외 시 로그가 실제로 남는지 / 반환값이 로그로 오염되지 않는지.
#   B. Get-NestedRepoPaths (gissue-audit-lib) — EAP=Stop 에서 커밋 0건·origin 없는 디렉터리에
#      예외를 던지지 않고 그 디렉터리를 제외하며 정상 반환.
#   C. neg 컨트롤 — rev-parse HEAD 판정이 실제 변별력을 가지는지 스스로 확인(빈 통과 배제).
#   D. Get-GissueBusyRepo (러너 메인 스코프 + 잡 스코프 사본 전부) — busy 판정의
#      `git rev-parse --abbrev-ref HEAD` probe 가 EAP=Stop 에서 예외를 던지지 않는다 /
#      비-base 브랜치 저장소를 여전히 busy 로 판정한다 / 모든 사본이 EAP 비파괴 패턴을 갖는다 /
#      neg 컨트롤로 비파괴화 전 형태는 실제로 throw 함을 확인(빈 통과 배제).
#
# 구현 방식 — AST 로 **실제 배포본 함수 본문을 그대로 추출**해 호출한다:
#   이 레포의 러너는 4000줄 단일 파일이라 dot-source 하면 러너 본문이 실행된다. 그래서
#   PowerShell AST(Parser::ParseFile)로 함수 정의만 뽑아 그 본문을 그대로 평가한다.
#   → 테스트는 "복사본"이 아니라 **배포되는 소스의 텍스트**를 검증한다(사본 drift 불가).
#   → 사본이 여러 개여도 전부 자동 수집되어, 하나라도 수정이 빠지면 그 사본에서 FAIL 한다.
#
# 실행:
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gissue/tests/test-git-repo-paths.ps1
# 종료코드: 0 = 전건 PASS, 1 = 1건 이상 FAIL
#
# 이 테스트는 임시 디렉터리(시스템 임시 폴더)에만 레포를 만들고 끝나면 정리한다 —
# 살아있는 체크아웃이나 워크트리 경로를 절대 건드리지 않는다.

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$gissueDir = Split-Path -Parent $PSScriptRoot
$runnerFile       = Join-Path $gissueDir 'run-gissue-claude.ps1'
$restartCheckFile = Join-Path $gissueDir 'run-slackbot-restart-check.ps1'
$auditLibFile     = Join-Path $gissueDir 'gissue-audit-lib.ps1'

$script:Pass = 0
$script:Fail = 0
function Assert-True($cond, $name, $detail = '') {
    if ($cond) { $script:Pass++; Write-Output "  PASS  $name" }
    else { $script:Fail++; Write-Output "  FAIL  $name$(if ($detail) { " — $detail" })" }
}

# 로그 수집 버퍼 — 두 경로(러너의 -Log 콜백 / 재시작 점검 스크립트의 Write-RestartLog)를 한곳에 모은다.
$script:LogMessages = @()

# run-slackbot-restart-check.ps1 사본이 호출하는 로깅 함수의 테스트 스텁.
# 실제 함수와 동일하게 Write-Output 도 하므로, 호출부에서 출력을 폐기하지 않으면
# Get-GissueGitRepoPaths 의 반환값(경로 목록)이 로그 문자열로 오염된다 — 그 실패 모드까지 함께 잡는다.
function Write-RestartLog($msg) {
    $script:LogMessages += $msg
    Write-Output "[slackbot-restart] $msg"
}

# 파일에서 함수 정의 본문을 전부 추출한다(중첩 정의 포함).
function Get-FunctionSourceTexts {
    param([string]$Path, [string]$Name)
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors -and @($parseErrors).Count -gt 0) {
        throw "AST 파싱 실패 ($Path): $(@($parseErrors)[0].Message)"
    }
    $defs = @($ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $Name
        }, $true))
    return @($defs | ForEach-Object { $_.Extent.Text })
}

# git 사용자 설정이 없는 환경에서도 커밋이 되도록 로컬 설정을 강제한다(CI 러너에는 전역 identity 가 없다).
function Invoke-Git { param([string]$RepoPath, [string[]]$GitArgs)
    $full = @('-C', $RepoPath) + $GitArgs
    & git @full 2>&1 | Out-Null
}
function New-EmptyRepo($path) {
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    Invoke-Git $path @('init', '-q')
}
function New-CommittedRepo($path) {
    New-EmptyRepo $path
    Invoke-Git $path @('config', 'user.email', 'test@example.com')
    Invoke-Git $path @('config', 'user.name', 'test')
    Set-Content -LiteralPath (Join-Path $path 'readme.txt') -Value 'hello' -Encoding UTF8
    Invoke-Git $path @('add', 'readme.txt')
    Invoke-Git $path @('commit', '-q', '-m', 'init')
}

# 크로스플랫폼 임시 경로 — $env:TEMP 는 Windows 전용이라 이 레포의 배포 대상(Linux/docker) 에서는 없다.
$tmpRoot = [System.IO.Path]::GetTempPath()
$tmp = Join-Path $tmpRoot ("gissue-git-repo-paths-test-" + $PID)
$emptySelf = Join-Path $tmpRoot ("gissue-git-repo-paths-emptyself-" + $PID)

if (Test-Path $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force }

try {
    # workdir(자기 저장소=레포 루트) 자체를 커밋 있는 저장소로 만든다.
    New-CommittedRepo $tmp
    # 직계 자식: 커밋 0건(빈 저장소) + 커밋 있는 저장소
    $emptyChild     = Join-Path $tmp 'empty-child'
    $committedChild = Join-Path $tmp 'committed-child'
    New-EmptyRepo $emptyChild
    New-CommittedRepo $committedChild

    # ── A. Get-GissueGitRepoPaths — 모든 사본에 대해 동일하게 검증한다 ──────────────
    $sources = @()
    $runnerDefs = @(Get-FunctionSourceTexts -Path $runnerFile -Name 'Get-GissueGitRepoPaths')
    for ($i = 0; $i -lt $runnerDefs.Count; $i++) {
        $sources += [pscustomobject]@{ Label = "run-gissue-claude.ps1#$($i + 1)"; Text = $runnerDefs[$i] }
    }
    $restartDefs = @(Get-FunctionSourceTexts -Path $restartCheckFile -Name 'Get-GissueGitRepoPaths')
    for ($i = 0; $i -lt $restartDefs.Count; $i++) {
        $sources += [pscustomobject]@{ Label = "run-slackbot-restart-check.ps1#$($i + 1)"; Text = $restartDefs[$i] }
    }

    Assert-True ($sources.Count -ge 1) "Get-GissueGitRepoPaths 정의를 최소 1개 찾았다" "찾은 개수=$($sources.Count)"
    Assert-True ($runnerDefs.Count -ge 2) "러너에 사본이 2개 이상 있다(메인 스코프 + 잡 스코프)" "개수=$($runnerDefs.Count)"
    Assert-True ($restartDefs.Count -ge 1) "재시작 점검 스크립트에 자체 사본이 있다" "개수=$($restartDefs.Count)"

    foreach ($src in $sources) {
        Write-Output "A. Get-GissueGitRepoPaths — $($src.Label)"

        # 실제 배포본 함수 본문을 그대로 평가한다(사본이 아니라 소스를 검증).
        Invoke-Expression $src.Text
        $cmd = Get-Command Get-GissueGitRepoPaths
        $hasLogParam = $cmd.Parameters.ContainsKey('Log')

        $script:LogMessages = @()
        $logCollector = { param($m) $script:LogMessages += $m }

        $paths = @()
        if ($hasLogParam) { $paths = @(Get-GissueGitRepoPaths $tmp -Log $logCollector) }
        else { $paths = @(Get-GissueGitRepoPaths $tmp) }

        # A-1 커밋 0건 디렉터리 → 후보에서 제외
        Assert-True ($paths -notcontains $emptyChild) 'A-1 커밋 0건(빈 저장소) 디렉터리 → 후보 제외' "paths=$($paths -join '; ')"
        # A-2 커밋 있는 저장소 → 후보 포함
        Assert-True ($paths -contains $committedChild) 'A-2 커밋 있는 저장소 → 후보 포함' "paths=$($paths -join '; ')"
        # A-3 자기 저장소(레포 루트) → 항상 포함(이 판정이 빠지면 러너 전체가 무력화된다)
        Assert-True ($paths -contains $tmp) 'A-3 자기 저장소(레포 루트) → 항상 포함' "paths=$($paths -join '; ')"

        # A-4 반환값에 경로가 아닌 값(로그 문자열 등)이 섞이지 않는다 — 로깅이 반환값을 오염시키면
        #      호출부가 그 문자열을 저장소 경로로 취급해 git 조회를 시도한다.
        $notDir = @($paths | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Container) })
        Assert-True ($notDir.Count -eq 0) 'A-4 반환값에 경로가 아닌 값이 섞이지 않는다(로그 오염 방지)' "섞인 값=$($notDir -join '; ')"

        # A-5 제외 사실이 로그로 남는다(조용히 제외되면 diagnosability 가 사라진다)
        $skipLogs = @($script:LogMessages | Where-Object { $_ -like '*EMPTY-REPO-SKIP*' })
        Assert-True ($skipLogs.Count -ge 1) 'A-5 커밋 0건 제외 시 로그가 남는다(EMPTY-REPO-SKIP)' "로그=$($script:LogMessages -join ' / ')"

        # A-6 자기 저장소가 커밋 0건이어도 유지되는가(루프 바깥 선추가라 HEAD 판정 대상이 아님)
        if (Test-Path $emptySelf) { Remove-Item -LiteralPath $emptySelf -Recurse -Force }
        New-EmptyRepo $emptySelf
        if ($hasLogParam) { $selfPaths = @(Get-GissueGitRepoPaths $emptySelf -Log $logCollector) }
        else { $selfPaths = @(Get-GissueGitRepoPaths $emptySelf) }
        Assert-True ($selfPaths -contains $emptySelf) 'A-6 커밋 0건 자기 저장소도 후보 유지(루프 바깥 선추가)' "paths=$($selfPaths -join '; ')"
        Remove-Item -LiteralPath $emptySelf -Recurse -Force
    }

    # ── B. Get-NestedRepoPaths (gissue-audit-lib) — EAP=Stop 에서 비파괴 probe ─────────
    Write-Output 'B. Get-NestedRepoPaths (gissue-audit-lib) — EAP=Stop 에서 비파괴 probe'
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    . $auditLibFile
    $ErrorActionPreference = $prevEap

    # 스윕 3종과 동일 환경(EAP=Stop)을 세워, 수정 전이라면 origin probe 가 throw 하던 조건을 재현한다.
    $threw = $false
    $nested = @()
    $savedEap = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Stop'
        $nested = @(Get-NestedRepoPaths $tmp)
    } catch {
        $threw = $true
    } finally {
        $ErrorActionPreference = $savedEap
    }
    # B-1 예외를 던지지 않는다(수정 전이면 여기서 throw → FAIL)
    Assert-True (-not $threw) 'B-1 커밋 0건·origin 없는 디렉터리에서 예외를 던지지 않음(EAP=Stop)' ''
    # B-2 origin 없는 빈 저장소는 제외된다
    Assert-True ($nested -notcontains $emptyChild) 'B-2 origin 없는 빈 저장소 → 수집 목록에서 제외' "nested=$($nested -join '; ')"

    # ── C. neg 컨트롤 — rev-parse HEAD 판정의 변별력 확인(빈 통과 배제) ───────────────
    Write-Output 'C. neg 컨트롤 — rev-parse HEAD 판정의 변별력 확인(빈 통과 배제)'
    # 빈 저장소에서 rev-parse HEAD 는 실패(비0), 커밋 있는 저장소에서는 성공(0)이어야 한다.
    # 둘이 같은 결과면 A-1/A-2 의 통과는 무의미(vacuous)하다 — 즉 커밋 0건 저장소를 만들지 않았다면
    # A-1 은 변별력 없이 통과했을 것이므로, 이 컨트롤이 실패하면 전체 PASS 를 신뢰할 수 없다.
    $c1 = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $null = git -C $emptyChild rev-parse --verify HEAD 2>&1;     $emptyRc     = $LASTEXITCODE
    $null = git -C $committedChild rev-parse --verify HEAD 2>&1; $committedRc = $LASTEXITCODE
    $ErrorActionPreference = $c1
    Assert-True ($emptyRc -ne 0)     'C-1 빈 저장소: rev-parse HEAD 실패(비0)'   "rc=$emptyRc"
    Assert-True ($committedRc -eq 0) 'C-2 커밋 저장소: rev-parse HEAD 성공(0)'    "rc=$committedRc"
    Assert-True ($emptyRc -ne $committedRc) 'C-3 두 결과가 달라야 변별력 성립(neg 컨트롤)' "empty=$emptyRc committed=$committedRc"

    # ── D. Get-GissueBusyRepo — EAP=Stop 비파괴 probe (giip 5180) ─────────────────────
    # 결함: busy-wait/auto-unblock 이 "이 저장소가 지금 다른 세션이 쓰는 중인가" 를 판정할 때
    #   `git rev-parse --abbrev-ref HEAD` 를 `2>$null` 로만 감싼다. Windows PowerShell 5.1 +
    #   EAP=Stop 환경에서는 네이티브 stderr 가 `2>$null` 이어도 NativeCommandError 로 throw 되므로
    #   **저장소 후보 수집이 아니라 그 다음 단계에서 러너/잡 전체가 죽는다.**
    #   같은 계열의 결함(커밋 0건 판정 · origin probe)은 이미 EAP 비파괴화돼 있으므로,
    #   busy-repo 판정 사본(러너 메인 스코프 + 잡 스코프)이 같은 형태로 고쳐졌는지를 여기서 고정한다.
    Write-Output 'D. Get-GissueBusyRepo — EAP=Stop 비파괴 probe'

    $busyDefs = @(Get-FunctionSourceTexts -Path $runnerFile -Name 'Get-GissueBusyRepo')
    Assert-True ($busyDefs.Count -ge 2) 'D-0 러너에 Get-GissueBusyRepo 사본이 2개 이상 있다(메인 스코프 + 잡 스코프)' "개수=$($busyDefs.Count)"

    # busy 판정이 의존하는 두 헬퍼도 **배포본 소스에서 그대로** 추출해 평가한다 —
    # 복사본을 만들어 테스트하면 사본 drift 가 그대로 통과한다.
    $repoPathsDefs = @(Get-FunctionSourceTexts -Path $runnerFile -Name 'Get-GissueGitRepoPaths')
    $baseBranchDefs = @(Get-FunctionSourceTexts -Path $runnerFile -Name 'Get-RepoBaseBranch')
    Assert-True ($repoPathsDefs.Count -ge 1) 'D-0 저장소 후보 수집 함수 소스를 찾았다' "개수=$($repoPathsDefs.Count)"
    Assert-True ($baseBranchDefs.Count -ge 1) 'D-0 base 브랜치 판정 함수 소스를 찾았다' "개수=$($baseBranchDefs.Count)"
    # A 그룹이 마지막에 평가한 것은 재시작 점검 스크립트 사본(($workdir) 만 받는 1인자형)이라,
    # 러너 사본(-Log 있는 2인자형)을 다시 평가해 호출 계약이 맞는 상태로 맞춘다.
    Invoke-Expression $repoPathsDefs[0]
    Invoke-Expression $baseBranchDefs[0]

    # EAP 비파괴 probe 패턴 판정 — try/finally + 'Continue' + $LASTEXITCODE 판정, 그리고
    # `2>$null` 만으로 감싼 형태가 남아 있지 않을 것.
    function Test-EapSafeRevParseProbe {
        param([string]$Text)
        if (-not $Text) { return $false }
        $hasTry      = [bool]($Text -match '(?m)\btry\s*\{')
        $hasFinally  = [bool]($Text -match '(?m)\bfinally\s*\{')
        $hasContinue = [bool]($Text -match '\$ErrorActionPreference\s*=\s*''Continue''')
        $hasExitCode = [bool]($Text -match '\$LASTEXITCODE\s*-eq\s*0')
        # `2>$null` 은 PS 5.1 + EAP=Stop 에서 stderr 를 삼키지 못한다 — 남아 있으면 비파괴화 전 상태.
        $hasBareRedir = [bool]($Text -match 'rev-parse[^\r\n]*2>\$null')
        return ($hasTry -and $hasFinally -and $hasContinue -and $hasExitCode -and -not $hasBareRedir)
    }

    # D-1 입력 — 두 가지 "probe 가 stderr 를 남기는 저장소" 상태.
    #   (a) 커밋 0건(unborn HEAD) 저장소 — `git init` 만 된 잔여 스캐폴드.
    #   (b) .git 파일이 깨진 디렉터리(gitdir 링크가 존재하지 않는 clone 잔여).
    # 둘 다 `git rev-parse --abbrev-ref HEAD` 가 stderr 와 함께 실패한다(rc != 0).
    if (Test-Path $emptySelf) { Remove-Item -LiteralPath $emptySelf -Recurse -Force }
    New-EmptyRepo $emptySelf
    $brokenSelf = Join-Path $tmpRoot ("gissue-git-repo-paths-broken-" + $PID)
    if (Test-Path $brokenSelf) { Remove-Item -LiteralPath $brokenSelf -Recurse -Force }
    New-Item -ItemType Directory -Path $brokenSelf -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $brokenSelf '.git') -Value 'gitdir: /nonexistent-git-dir-for-probe' -Encoding ASCII

    # 양의 대조 — 커밋이 있고 base 가 아닌 브랜치에 있는 저장소는 busy 로 판정되어야 한다.
    # (비파괴화 때문에 "안 죽는 대신 아무것도 못 판정" 으로 퇴화하지 않았는지 확인.)
    $busyRepo = Join-Path $tmp 'busy-branch-repo'
    if (Test-Path $busyRepo) { Remove-Item -LiteralPath $busyRepo -Recurse -Force }
    New-CommittedRepo $busyRepo
    Invoke-Git $busyRepo @('checkout', '-q', '-b', 'feature/branch')

    for ($i = 0; $i -lt $busyDefs.Count; $i++) {
        $label = "run-gissue-claude.ps1#$($i + 1)"
        Write-Output "D. Get-GissueBusyRepo — $label"

        # 실제 배포본 함수 본문을 그대로 평가한다(사본이 아니라 소스를 검증).
        Invoke-Expression $busyDefs[$i]
        $cmd = Get-Command Get-GissueBusyRepo
        $hasLogParam = $cmd.Parameters.ContainsKey('Log')

        foreach ($probe in @(
            [pscustomobject]@{ Name = '커밋 0건(unborn HEAD) 저장소'; Dir = $emptySelf },
            [pscustomobject]@{ Name = '.git 깨진 디렉터리';          Dir = $brokenSelf }
        )) {
            $threw = $false
            $result = @()
            $savedEap = $ErrorActionPreference
            try {
                $ErrorActionPreference = 'Stop'
                if ($hasLogParam) { $result = @(Get-GissueBusyRepo $probe.Dir -Log $logCollector) }
                else { $result = @(Get-GissueBusyRepo $probe.Dir) }
            } catch {
                $threw = $true
            } finally {
                $ErrorActionPreference = $savedEap
            }
            # D-1 예외를 던지지 않는다(수정 전이면 여기서 throw → FAIL)
            Assert-True (-not $threw) "D-1 $label EAP=Stop 에서 예외를 던지지 않는다 — $($probe.Name)" "threw=$threw"
            # D-1b 반환 계약 — 객체(Repo/Branch/Base) 또는 null. 다른 값이 섞이면 안 된다.
            $objs = @($result | Where-Object { $null -ne $_ })
            $shapeOk = $true
            foreach ($o in $objs) {
                if ($null -eq $o.Repo -or $null -eq $o.Branch -or $null -eq $o.Base) { $shapeOk = $false }
            }
            Assert-True ($shapeOk) "D-1b $label 반환 계약이 지켜진다(Repo/Branch/Base 객체 또는 null) — $($probe.Name)" "objects=$($objs.Count)"
        }

        # D-1c 양의 대조 — 비-base 브랜치 저장소는 여전히 busy 로 판정된다.
        $busyThrew = $false
        $busyResult = $null
        $savedEap2 = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Stop'
            if ($hasLogParam) { $busyResult = @(Get-GissueBusyRepo $busyRepo -Log $logCollector) }
            else { $busyResult = @(Get-GissueBusyRepo $busyRepo) }
        } catch {
            $busyThrew = $true
        } finally {
            $ErrorActionPreference = $savedEap2
        }
        $busyObj = @($busyResult | Where-Object { $null -ne $_ }) | Select-Object -First 1
        Assert-True ((-not $busyThrew) -and $null -ne $busyObj -and $busyObj.Repo -eq $busyRepo -and $busyObj.Branch -eq 'feature/branch') `
            "D-1c $label 비-base 브랜치 저장소를 busy 로 판정한다(비파괴화가 판정까지 무력화하지 않음)" `
            "threw=$busyThrew result=$(($busyResult | ForEach-Object { "$_" }) -join '; ')"

        # D-2 모든 사본이 EAP 비파괴 패턴을 갖고 있다(패턴 누락 = 사본 하나만 수정된 drift).
        # 라벨 문자열은 큰따옴표가 아니라 작은따옴표로 만든다 — $LASTEXITCODE/$null 이
        # 값으로 전개되면 판정 문구가 아니라 실제 값이 출력된다.
        $d2Label = 'D-2 ' + $label + ' EAP 비파괴 패턴(try/finally + ''Continue'' + $LASTEXITCODE 판정, 2>$null 없음)을 갖고 있다'
        Assert-True (Test-EapSafeRevParseProbe $busyDefs[$i]) $d2Label "사본#$($i + 1)"
    }

    # ── D-3 neg 컨트롤 — 비파괴화되지 않은 형태로는 위 판정이 FAIL 한다(빈 통과 배제) ────
    Write-Output 'D. neg 컨트롤 — 비파괴화되지 않은 형태(원본)는 실제로 throw 하고 패턴 판정도 FAIL 한다'
    $unfixedText = @'
function Get-GissueBusyRepoUnfixedProbe($workdir, $restBranch = '', [scriptblock]$Log) {
    foreach ($repo in (Get-GissueGitRepoPaths $workdir $Log)) {
        $branch = (git -C $repo rev-parse --abbrev-ref HEAD 2>$null)
        if (-not $branch) { continue }
        if ($restBranch -and $branch -eq $restBranch) { continue }
        $base = Get-RepoBaseBranch $repo
        if ($branch -ne $base) { return [pscustomobject]@{ Repo = $repo; Branch = $branch; Base = $base } }
    }
    return $null
}
'@
    # D-3a 패턴 판정기가 "항상 참" 이 아니다 — 비파괴화 전 형태는 FAIL 로 판정된다.
    Assert-True (-not (Test-EapSafeRevParseProbe $unfixedText)) 'D-3a neg 컨트롤: 비파괴화되지 않은 형태는 EAP 비파괴 패턴 판정을 FAIL 한다(빈 통과 배제)' ''
    # D-3b 동작 판정에도 변별력이 있다 — 비파괴화 전 형태는 EAP=Stop 에서 실제로 throw 한다.
    Invoke-Expression $unfixedText
    $ctrlThrew = $false
    $savedEap3 = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Stop'
        $null = Get-GissueBusyRepoUnfixedProbe $emptySelf -Log $logCollector
    } catch {
        $ctrlThrew = $true
    } finally {
        $ErrorActionPreference = $savedEap3
    }
    Assert-True ($ctrlThrew) 'D-3b neg 컨트롤: 비파괴화되지 않은 형태는 EAP=Stop 에서 실제로 throw 한다(D-1 판정이 변별력을 가짐)' "threw=$ctrlThrew"
}
finally {
    if (Test-Path $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
    if (Test-Path $emptySelf) { Remove-Item -LiteralPath $emptySelf -Recurse -Force -ErrorAction SilentlyContinue }
    if (Test-Path $brokenSelf) { Remove-Item -LiteralPath $brokenSelf -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Output ''
Write-Output "결과: PASS=$script:Pass FAIL=$script:Fail"
if ($script:Fail -gt 0) { exit 1 } else { exit 0 }
