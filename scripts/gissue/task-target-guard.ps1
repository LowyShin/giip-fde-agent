# task-target-guard.ps1 — Windows 작업 스케줄러 등록 대상 .ps1 사전검증 공용 게이트
#
# 배경 (giip #2431, 2026-09-14):
#   `GIIP_AuditReviewPrs_Hourly` / `GIIP_StalePending_Hourly` 두 태스크가 **존재하지 않는 .ps1** 을
#   가리킨 채 Ready 로 등록돼 있었다. 등록 스크립트(`register-*-task.ps1`)에 `Test-Path` 가 있긴 했지만,
#   러너가 미추적 로컬 파일로 존재하던 시점에 등록이 통과한 뒤 파일만 사라지면 아무도 눈치채지 못한다.
#   선행 giip #2429 에서는 대상이 "있긴 하나 파싱 불가"라서 `powershell -File` 이 종료코드 0 을
#   돌려주며 조용히 죽는 사고가 확인됐고, 본문 문제의식으로 "등록 스크립트를 worktree 안에서 실행하면
#   `$ScriptDir` 가 임시 worktree 경로를 잡아 태스크에 박힌다"는 구조적 위험도 함께 지적됐다.
#
# 그래서 `Register-ScheduledTask` **직전에** 아래 3가지를 전부 통과해야만 등록되게 한다:
#   (1) 대상 .ps1 의 Test-Path       — 없는 파일을 태스크로 등록 금지
#   (2) 파싱 검사                     — check-ps1-parse.ps1 재사용 (giip #2429 산출물, 여기서 새로 만들지 않음)
#   (3) 임시 worktree 경로 거부       — D:\temp\worktrees\ (및 .claude\worktrees\) 하위면 등록 금지
#
# 이 파일은 각 등록 스크립트에 복붙하지 말고 dot-source 한다(이 환경 방침: 파일은 최대한 분리):
#   . (Join-Path $PSScriptRoot 'task-target-guard.ps1')
#   Assert-ScheduledTaskTarget -Target $Target -TaskName $TaskName
#
# 실패 시 이 함수는 사유를 출력하고 **호출 스크립트를 종료코드 1 로 즉시 종료**시킨다(등록 안 됨).

# 이 PC 의 콘솔 기본 출력 인코딩은 cp932(shift_jis) 라서 게이트 메시지의 한글이 '?' 로 뭉개지고,
# 아래에서 `& $engine ... check-ps1-parse.ps1` 의 UTF-8 출력을 캡처할 때도 깨진다(실측, giip #2436:
# "[TASK-GUARD][2/3][FAIL] ?? ?? ??" — 등록을 막은 이유를 사람이 읽을 수 없었다).
# check-ps1-parse.ps1 과 동일하게 UTF-8 로 고정한다. dot-source 시점에 한 번만 적용된다.
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }

# dot-source 되는 시점의 이 파일 위치. 함수 안에서 check-ps1-parse.ps1 을 찾는 데 쓴다.
$TaskTargetGuardDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }

# 임시 worktree 로 간주해 거부할 경로 패턴(대소문자 무시, 정규화된 전체 경로 기준).
$TaskTargetForbiddenPathPatterns = @(
    '\\temp\\worktrees\\',       # D:\temp\worktrees\... (이 PC 의 worktree 기본 위치)
    '\\\.claude\\worktrees\\'    # <repo>\.claude\worktrees\... (claude 내장 worktree)
)

function Test-TaskTargetPathForbidden {
    <#
        정규화된 대상 경로가 임시 worktree 하위인지 판정한다.
        반환: 일치한 패턴 문자열(거부) 또는 $null(통과).
    #>
    param([Parameter(Mandatory = $true)][string]$FullPath)

    $normalized = $FullPath -replace '/', '\'
    foreach ($pattern in $TaskTargetForbiddenPathPatterns) {
        if ($normalized -match "(?i)$pattern") { return $pattern }
    }
    return $null
}

function Assert-ScheduledTaskTarget {
    <#
        Register-ScheduledTask 직전에 호출한다. 3가지 게이트를 전부 검사하고,
        하나라도 실패하면 사유 전체를 출력한 뒤 exit 1 로 호출 스크립트를 끝낸다.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Target,
        [Parameter(Mandatory = $true)][string]$TaskName
    )

    $problems = @()

    # 대상 경로를 절대경로로 정규화(상대경로로 넘어와도 게이트가 흔들리지 않게).
    $fullTarget = $Target
    try { $fullTarget = [System.IO.Path]::GetFullPath($Target) } catch { }

    Write-Output "[TASK-GUARD] $TaskName -> $fullTarget"

    # --- 게이트 1: 대상 파일 존재 ---------------------------------------------------------------
    $exists = Test-Path -LiteralPath $fullTarget -PathType Leaf
    if ($exists) {
        Write-Output "[TASK-GUARD][1/3][OK]   대상 파일 존재"
    } else {
        Write-Output "[TASK-GUARD][1/3][FAIL] 대상 .ps1 이 존재하지 않음 — 등록 거부"
        $problems += "대상 .ps1 없음: $fullTarget"
    }

    # --- 게이트 2: 파싱 검사 (check-ps1-parse.ps1 재사용, giip #2429) --------------------------
    if (-not $exists) {
        Write-Output "[TASK-GUARD][2/3][SKIP] 파일이 없어 파싱 검사 생략"
    } else {
        $parser = Join-Path $TaskTargetGuardDir 'check-ps1-parse.ps1'
        if (-not (Test-Path -LiteralPath $parser -PathType Leaf)) {
            Write-Output "[TASK-GUARD][2/3][FAIL] 파싱 검사기를 찾을 수 없음: $parser"
            $problems += "파싱 검사기 없음: $parser"
        } else {
            # Windows PowerShell 로 고정 호출(검사기 자체가 5.1 파서 기준으로 검증됨).
            $engine = (Get-Command powershell -ErrorAction SilentlyContinue).Source
            if (-not $engine) { $engine = (Get-Command pwsh).Source }
            # `-Path` 명시 호출을 유지한다. giip #2431 시점에는 위치 인자가 아예 바인딩되지 않아
            # ("사용법" 출력 + exit 2) `-Path` 가 유일하게 동작하는 형태였고, giip #2436 에서 위치 인자
            # 바인딩이 고쳐진 뒤에도 `-Path` 는 여전히 올바른(그리고 의도가 명확한) 호출 형태다.
            # 참고: 대상 부재는 위 게이트 1 에서 이미 걸러지지만, 검사기 자체도 giip #2436 부터
            #       "지정한 파일 없음" 을 exit 1 로 차단한다(예전에는 [SKIP] 후 exit 0 통과였다).
            $parseOut = & $engine -NoProfile -ExecutionPolicy Bypass -File $parser -Path $fullTarget
            $parseRc = $LASTEXITCODE
            foreach ($line in $parseOut) { Write-Output "    $line" }
            if ($parseRc -eq 0) {
                Write-Output "[TASK-GUARD][2/3][OK]   파싱 통과"
            } else {
                Write-Output "[TASK-GUARD][2/3][FAIL] 파싱 검사 실패(exit $parseRc) — 등록 거부"
                $problems += "파싱 검사 실패(exit $parseRc): $fullTarget"
            }
        }
    }

    # --- 게이트 3: 임시 worktree 경로 거부 ------------------------------------------------------
    $hit = Test-TaskTargetPathForbidden -FullPath $fullTarget
    if ($hit) {
        Write-Output "[TASK-GUARD][3/3][FAIL] 임시 worktree 경로(패턴 '$hit') 하위 — 등록 거부"
        Write-Output "    등록 스크립트를 worktree 안에서 실행했을 가능성이 높습니다."
        Write-Output "    임시 worktree 가 아닌 **정상 체크아웃**(이 레포를 clone 한 경로)에서 다시 실행하세요."
        $problems += "임시 worktree 경로: $fullTarget"
    } else {
        Write-Output "[TASK-GUARD][3/3][OK]   임시 worktree 경로 아님"
    }

    if ($problems.Count -gt 0) {
        Write-Output ""
        Write-Output "[TASK-GUARD][BLOCKED] $TaskName 등록을 중단합니다($($problems.Count)건):"
        foreach ($p in $problems) { Write-Output "  - $p" }
        exit 1
    }

    Write-Output "[TASK-GUARD][PASS] 3개 게이트 전부 통과 — 등록 진행"
}
