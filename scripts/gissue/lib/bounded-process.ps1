# bounded-process.ps1 — 외부 프로세스(gh/git) 호출에 유한한 타임아웃을 거는 순수 실행기
#
# ── 왜 필요한가 ───────────────────────────────────────────────────────────────────
# worktree 정리 단계(Invoke-GissueWorktreeCleanupForRepo)는 `gh pr list` 와 각종
# `git` 호출을 동기(`&`)로 실행한다. 동기 호출은 호출이 끝나야 다음 줄로 가므로,
# 호출 하나가 멈추면(2026-11-25 실측: 17:07 회차가 [WORKTREE-CLEANUP]에서
# 18:21:25 이후 31분간 침묵하다 예산 종료로 강제종료, 종료 기록·슬롯 기록 없음)
# 항목 경계에서만 검사하는 시간 한도(기본 180초)도, stall 마커도 발동하지 않는다.
# 이 파일은 외부 호출 1회를 Start-Process + WaitForExit(유한 대기)로 실행해,
# 한도를 넘기면 자식 프로세스를 죽이고 TimedOut=$true 로 돌려준다. 호출자는
# 타임아웃을 "실패"로 취급해 fail-closed 로 처리하고 다음 레포·항목으로 진행한다.
# 유한 대기가 true 를 돌려줘도 리다이렉트 출력 펌프가 파일을 다 쓰기 전일 수
# 있으므로(.NET 문서: WaitForExit(타임아웃) 반환 시 비동기 출력 처리가 끝나지
# 않았을 수 있음 — Unix 의 파이프+펌프 구현에서 실측됨), 파일을 읽기 전에
# 인자 없는 WaitForExit()로 펌프가 끝날 때까지 한 번 더 기다린다. 이 호출을
# 빼먹으면 git 호출이 ExitCode=0 인데 stdout 이 비어 읽혀 "origin remote 없음"·
# 빈 worktree 목록 같은 가짜 실패가 간헐적으로 난다(2026-11-25 실측: 6회 중 3회).
#
# ── 계약 ─────────────────────────────────────────────────────────────────────────
#   - 반환: @{ Started; TimedOut; ExitCode; StdOut; StdErr }
#     - Started=$false: 실행 파일 자체를 못 띄움(미설치 등). TimedOut=$false, ExitCode=-1.
#     - TimedOut=$true: 한도 내 종료하지 않아 강제종료함. ExitCode=-1.
#     - 정상 종료: ExitCode=자식 종료 코드, TimedOut=$false.
#   - StdOut/StdErr 는 UTF-8 로 읽는다(gh 는 UTF-8 JSON, git 분기명은 호출처가
#     같은 디코딩으로 일관되게 비교한다).
#   - 인자는 공백·따옴표를 포함해도 자식에게 1개 인자로 전달되게 따옴표 처리한다
#     (PS 5.1 의 Start-Process -ArgumentList 는 배열을 공백으로 이어붙일 뿐
#     따옴표를 자동 추가하지 않는다).
#   - -StandardInputFile 을 주면 그 파일을 자식의 stdin 으로 넘긴다(선택 — 기본 $null 이면
#     종전 동작 그대로 = stdin 리다이렉트 없음). 판정 LLM 호출(claude CLI)이 프롬프트를
#     stdin 으로 먹여야 유한 대기와 stdout/stderr 분리를 동시에 성립한다.
#   - 이 파일은 함수 정의만 한다 — dot-source 시점에 부작용이 없어야 한다.
#   - PowerShell 5.1 호환(잡·스레드 미사용 — Start-Process + WaitForExit 만 쓴다).
#
# ── 한도 기본값 ──────────────────────────────────────────────────────────────────
#   - gh 호출: 60초 (실측 건강 상태 6초, 한도 소진 실패는 즉시 반환되므로 60초면 충분)
#   - git 호출: 30초 (로컬 연산은 통상 2초 이내)
#   - claude 호출: 300초 (실측 정상 판정 11~29초, 실측 무응답 9분+ — 유한해야 한다)
#   - env GISSUE_GH_CALL_TIMEOUT_SEC / GISSUE_GIT_CALL_TIMEOUT_SEC / GISSUE_CLAUDE_CALL_TIMEOUT_SEC
#     (양의 정수, 초)로 재정의.

# 외부 프로세스 1회를 유한한 시간 안에 실행한다.
function Invoke-GissueBoundedProcess {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [int]$TimeoutSec = 60,
        [string]$WorkingDirectory = $null,
        # 선택: 자식의 stdin 으로 넘길 파일. $null(기본) 이면 종전 동작 그대로다.
        #   파일은 호출자가 UTF-8 BOM 없이 써야 한다(BOM 이면 프롬프트 앞이 깨진다).
        [string]$StandardInputFile = $null
    )
    if ($TimeoutSec -le 0) { $TimeoutSec = 60 }
    $outFile = $null
    $errFile = $null
    $proc = $null
    try {
        # 인자 문자열 조립 — 공백·따옴표 포함 인자는 큰따옴표로 감싼다.
        $quoted = @()
        foreach ($a in @($ArgumentList)) {
            $s = "$a"
            if ($s -match '[\s"]') { $quoted += ('"' + ($s -replace '"', '\"') + '"') }
            else { $quoted += $s }
        }
        $argString = ($quoted -join ' ')
        $stamp = "$PID-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
        $tmpDir = [System.IO.Path]::GetTempPath()
        $outFile = Join-Path $tmpDir "gissue-bounded-$stamp.out"
        $errFile = Join-Path $tmpDir "gissue-bounded-$stamp.err"
        $startArgs = @{
            FilePath               = $FilePath
            ArgumentList           = $argString
            RedirectStandardOutput = $outFile
            RedirectStandardError  = $errFile
            NoNewWindow            = $true
            PassThru               = $true
            ErrorAction            = 'Stop'
        }
        if ($WorkingDirectory) { $startArgs['WorkingDirectory'] = $WorkingDirectory }
        # stdin 리다이렉트 — 프롬프트를 파일로 먹이는 호출(claude CLI 판정)에 쓴다.
        if ($StandardInputFile) {
            if (-not (Test-Path -LiteralPath $StandardInputFile)) { throw "stdin 파일 없음: $StandardInputFile" }
            $startArgs['RedirectStandardInput'] = $StandardInputFile
        }
        $proc = Start-Process @startArgs
        # 핸들을 먼저 캐시한다 — 이것이 없으면 **종료 코드가 항상 0 으로 읽힌다**
        # (.NET Framework 의 Process 는 핸들을 캐시하지 않은 채로 종료되면
        #  ExitCode 를 0(=성공) 으로 돌려준다 — 2026-11-26 실측: PS 5.1 에서
        #  `merge-base --is-ancestor`(조상 아님 → 종료코드 1)이 0 으로 돌아와
        #  "HEAD 가 origin/main 의 조상" 판정을 내렸다 → 워크트리 삭제 가드가
        #  **fail-open** 으로 뒤집혀 "미반영 커밋이 있는 워크트리"를 삭제했다).
        #  핸들을 만지면 프로세스 객체가 그 핸들을 붙들어 종료 코드가 정상 전달된다.
        $null = $proc.Handle
        $exited = $proc.WaitForExit($TimeoutSec * 1000)
        if (-not $exited) {
            try { $proc.Kill() } catch {}
            try { $null = $proc.WaitForExit(5000) } catch {}
            return [pscustomobject]@{
                Started  = $true
                TimedOut = $true
                ExitCode = -1
                StdOut   = ''
                StdErr   = ''
            }
        }
        # 유한 대기가 true 를 돌려줘도 출력 펌프가 파일을 다 쓰지 못했을 수 있다.
        # 인자 없는 WaitForExit()는 비동기 출력 처리가 끝날 때까지 기다린다
        # (.NET 문서 권장 패턴). 프로세스는 이미 종료했으므로 펌프 비우기만 기다린다.
        try { $null = $proc.WaitForExit() } catch {}
        $stdOut = ''
        $stdErr = ''
        if (Test-Path -LiteralPath $outFile) { $stdOut = [System.IO.File]::ReadAllText($outFile, [System.Text.Encoding]::UTF8) }
        if (Test-Path -LiteralPath $errFile) { $stdErr = [System.IO.File]::ReadAllText($errFile, [System.Text.Encoding]::UTF8) }
        return [pscustomobject]@{
            Started  = $true
            TimedOut = $false
            ExitCode = [int]$proc.ExitCode
            StdOut   = $stdOut
            StdErr   = $stdErr
        }
    } catch {
        return [pscustomobject]@{
            Started  = $false
            TimedOut = $false
            ExitCode = -1
            StdOut   = ''
            StdErr   = "$($_.Exception.Message)"
        }
    } finally {
        if ($proc) { try { $proc.Dispose() } catch {} }
        foreach ($f in @($outFile, $errFile)) {
            if ($f -and (Test-Path -LiteralPath $f)) { try { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue } catch {} }
        }
    }
}

# 외부 호출 한도 해석 — 명시 env > 기본값. 양의 정수가 아니면 기본값을 쓴다.
# Kind 'Gh': env GISSUE_GH_CALL_TIMEOUT_SEC, 기본 60초.
# Kind 'Git': env GISSUE_GIT_CALL_TIMEOUT_SEC, 기본 30초.
# Kind 'Claude': env GISSUE_CLAUDE_CALL_TIMEOUT_SEC, 기본 300초. (판정 LLM 호출.
#   실측 정상 판정 11~29초, 실측 무응답 9분+. 300초면 여유가 있으면서 유한하다.)
function Resolve-GissueBoundedCallTimeoutSec {
    param([ValidateSet('Gh', 'Git', 'Claude')][string]$Kind)
    if ($Kind -eq 'Gh') { $envName = 'GISSUE_GH_CALL_TIMEOUT_SEC'; $default = 60 }
    elseif ($Kind -eq 'Git') { $envName = 'GISSUE_GIT_CALL_TIMEOUT_SEC'; $default = 30 }
    else { $envName = 'GISSUE_CLAUDE_CALL_TIMEOUT_SEC'; $default = 300 }
    $raw = [System.Environment]::GetEnvironmentVariable($envName)
    $n = 0
    if ($null -ne $raw -and [int]::TryParse("$raw".Trim(), [ref]$n) -and $n -gt 0) { return $n }
    return $default
}
