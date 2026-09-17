# check-ps1-parse.ps1 — .ps1 파일 구문(파싱) + 인코딩(BOM) 검사기
#
# 배경 (giip #2429, 2026-09-14): `scripts/gissue/run-list-stale-review.ps1` 이 문자열 문법이 깨진 채
#   커밋 19f43ad1 로 main 에 들어갔고(`""$ts] ... ${if (...) { ... }"`), Windows Task Scheduler
#   `GIIP_StaleReview_Hourly` 가 그 파일을 가리킨 채 Ready 로 등록됐다. 결과적으로 REVIEW 장기방치
#   탐지는 등록만 되고 한 번도 돌지 못했다. `powershell -File` 은 파싱 에러가 나도 종료코드 0 을
#   돌려주는 경우가 있어(실측: 작업 스케줄러 LastTaskResult=0) **아무도 실패를 눈치채지 못했다.**
#   2026-08-27 gissue 스케줄러 전면마비도 같은 계열(미완성 코드 커밋)이라 1회성 오타가 아니라
#   재발 패턴으로 다룬다. 그래서 커밋 전에 파서로 먼저 막는다.
#
# 중요 — 인코딩 (이 검사기가 ParseFile 을 쓰지 않는 이유):
#   Windows PowerShell 5.1 의 `[Parser]::ParseFile()` 은 BOM 없는 파일을 **시스템 ANSI 코드페이지**로
#   읽는다. 이 PC 의 ACP 는 shift_jis(cp932) 라서, BOM 없는 UTF-8 파일에 한글/일본어 주석이 있으면
#   2바이트 시퀀스가 인용부호·괄호를 삼켜 **실제로는 멀쩡한 파일이 파싱 에러로 오탐**된다.
#   (실측: docs/50-technical/find-lsvrdetail-sender.ps1 → ParseFile 은 2건 에러, UTF-8 로 읽으면 0건)
#   따라서 여기서는 BOM 을 직접 보고 인코딩을 정한 뒤 `ParseInput()` 에 텍스트를 넘긴다.
#
# 그래서 판정 항목이 **두 개**다 (giip #2591, 2026-09-16):
#   [판정 1] BOM 게이트 — "BOM 없음 + 비ASCII 바이트 존재" 인 .ps1 을 차단한다.
#   [판정 2] 구문 게이트 — 위 UTF-8 강제 읽기 + `ParseInput()` (giip #2429 부터의 기존 검사, 그대로 유지).
#
#   판정 1 이 왜 따로 필요한가: 위의 "항상 UTF-8 로 읽는다" 는 결정은 오탐 방지 목적 안에서는 옳았지만,
#   그 순간 **검사기와 실행 엔진의 디코딩이 어긋난다.** `powershell -File` 은 여전히 BOM 없는 파일을
#   cp932 로 읽으므로, 검사기만 통과하고 실행은 죽는 파일이 생긴다. `ParseFile()` 이 보던 것은
#   오탐이 아니라 **실행 엔진이 실제로 겪을 현실**이기도 했던 것이다.
#   실측 (giip #2590 작업 중 발견, 2026-09-16):
#     - BOM 없는 UTF-8 .ps1 6개 → 이 검사기는 "6개 전부 통과"
#     - 같은 파일을 `powershell -File` 로 실행 → 파서 에러 7건
#       (`Unexpected token 'az' in expression or statement` 등), exit 1, 한 줄도 실행되지 않음
#     - 내용을 한 글자도 바꾸지 않고 BOM 3바이트(EF BB BF)만 추가 → 둘 다 정상
#   판정 2 를 되돌리지 않고 판정 1 을 **덧붙인** 이유가 이것이다. 판정 1 은 파서를 돌리지 않고
#   선두 바이트만 보므로 판정 2 의 오탐 문제를 다시 끌어오지 않는다.
#
#   판정 1 의 적용 범위:
#     - 비ASCII 바이트가 0개인 .ps1 은 cp932 로 읽으나 UTF-8 로 읽으나 결과가 같으므로 제외한다.
#       (레포에 ASCII 전용 .ps1 이 다수 있고, 그것까지 막으면 본질과 무관한 잡음이 된다.)
#     - UTF-16 LE/BE BOM(FF FE / FE FF)이 붙은 파일도 PowerShell 이 올바로 디코딩하므로 통과시킨다.
#       다만 이 레포의 권장 인코딩은 **UTF-8 with BOM** 이다.
#
# 사용법 (아래 5가지 전부 실측 검증됨 — giip #2436):
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gissue/check-ps1-parse.ps1 <파일1> [파일2 ...]
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gissue/check-ps1-parse.ps1 -Path <파일1> [파일2 ...]
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gissue/check-ps1-parse.ps1 -Staged
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gissue/check-ps1-parse.ps1 -All
#   위 어느 형태에나 `-RepoRoot <경로>` 를 덧붙일 수 있다(이름 지정 전용 — 위치 인자로는 바인딩되지 않는다).
#   파이프라인 입력(`'a.ps1' | check-ps1-parse.ps1`)은 **지원하지 않는다**(ValueFromPipeline 없음).
#
# 종료코드: 0 = 전부 통과 / 1 = 파싱 에러 또는 BOM 누락인 파일 존재, 혹은 지정한 파일을 못 찾음
#           2 = 사용법 오류

param(
    # 검사할 .ps1 경로들 (생략 시 -Staged 또는 -All 중 하나 필요).
    #
    # 위치 0 **하나만** 여기에 바인딩되고, 2번째 이후 인자는 아래 $RemainingPath 가 받는다.
    # 실행 직후 둘을 합쳐 $targetPaths 를 만든다 — 아래 NOTE 참조.
    [Parameter(Position = 0)]
    [string[]]$Path = @(),

    # git 스테이징된 .ps1 만 검사 (pre-commit 게이트용)
    [switch]$Staged,

    # 레포 전체 .ps1 검사 (.git / node_modules / .claude/worktrees / nested repo 제외)
    [switch]$All,

    # 리포지토리 루트 (미지정 시 현재 위치에서 git 으로 탐색) — 이름 지정 전용
    [string]$RepoRoot = '',

    # -All 스캔에서 제외할 디렉터리 정규식 (이름 지정 전용). 미지정 시 `\(.git|node_modules)\`.
    # nested repo 를 두는 배포에서 그 폴더명을 추가하는 용도. $Path 가 Position 0 을 점유하므로
    # 이 파라미터는 위치 인자로 바인딩되지 않는다(아래 $RemainingPath 주석의 바인딩 함정 참고).
    [string]$ExcludeDirPattern = '',

    # 2번째 이후의 이름 없는 인자 전부를 흡수한다. **호출측이 직접 지정하지 말 것** (-Path 를 쓴다).
    #
    # NOTE — 파라미터 바인딩 함정 3종 (전부 실측, giip #2436). 이 구조를 임의로 단순화하면
    #        게이트가 조용히 무동작이 된다:
    #   (a) [string[]]$Path 만 두고 위치 인자를 여러 개 넘기면 2번째부터
    #       "A positional parameter cannot be found that accepts argument '<2번째 파일>'" 로 죽는다.
    #       [string[]] 여도 위치 바인딩은 1개만 받기 때문이다.
    #   (b) 그래서 giip #2429 는 $Path 에 ValueFromRemainingArguments 만 달았는데, 그러면
    #       **Position 을 명시한 파라미터가 하나도 없어** 고급(advanced) 스크립트의 암묵 위치 배정이
    #       일어나고, VFRA 파라미터는 그 배정에서 빠져 $RepoRoot 가 위치 0 을 가져가 버린다. 증상:
    #         - 파일 1개만 넘기면 $Path 가 비어 "사용법" + exit 2 (검사 0건인데 호출측은 그냥 지나감)
    #         - 파일 N개를 넘기면 첫 파일이 $RepoRoot 로 빨려들어가 N-1 개만 검사되고,
    #           RepoRoot 가 파일경로로 바뀌어 나머지도 "파일 없음" 으로 스킵됨
    #   (c) $Path 하나에 Position=0 + VFRA 를 같이 달면 위치 인자 형태는 고쳐지지만,
    #       `-Path a b c` 처럼 이름 지정으로 여러 개를 넘기는 형태는 여전히 (a) 로 죽는다.
    #   → 위치 0 전용 $Path + 나머지 흡수용 $RemainingPath 로 **분리**하면 위 3가지가 모두 해소된다.
    #     ($Path 에 Position=0 이 붙는 순간 $RepoRoot 는 자동으로 이름 지정 전용이 된다 — 실측.)
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingPath = @()
)

$ErrorActionPreference = 'Stop'

# 이 PC 의 콘솔 기본 출력 인코딩은 cp932(shift_jis) 라서, 한글 출력이 호출측(bash 훅 등)에서
# '?' 로 뭉개진다. UTF-8 로 고정해 훅이 그대로 사용자에게 보여줄 수 있게 한다. (giip #2429)
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }

# 판정 1(BOM 게이트)과 판정 2(구문 게이트)가 같은 바이트 배열을 보도록 읽기를 한 번으로 모은다.
# (파일을 두 번 읽으면 그 사이에 파일이 바뀌었을 때 두 판정의 대상이 달라진다.)
function Get-ScriptBytes {
    param([string]$FullPath)
    return [System.IO.File]::ReadAllBytes($FullPath)
}

# PowerShell 5.1 이 인코딩을 확실히 알아볼 수 있는 BOM 이 붙어 있는가.
# UTF-8 BOM 뿐 아니라 UTF-16 LE/BE BOM 도 해당한다 — 셋 다 `powershell -File` 이 올바로 디코딩한다.
function Test-ScriptBom {
    param([byte[]]$Bytes)
    if ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF) { return $true }
    if ($Bytes.Length -ge 2 -and $Bytes[0] -eq 0xFF -and $Bytes[1] -eq 0xFE) { return $true }
    if ($Bytes.Length -ge 2 -and $Bytes[0] -eq 0xFE -and $Bytes[1] -eq 0xFF) { return $true }
    return $false
}

# 0x80 이상인 바이트 개수. 0 이면 순수 ASCII 라 cp932 로 읽으나 UTF-8 로 읽으나 결과가 같다.
function Get-NonAsciiByteCount {
    param([byte[]]$Bytes)
    $n = 0
    foreach ($b in $Bytes) { if ($b -gt 127) { $n++ } }
    return $n
}

function ConvertTo-ScriptText {
    param([byte[]]$Bytes)
    if ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF) {
        return [System.Text.Encoding]::UTF8.GetString($Bytes, 3, $Bytes.Length - 3)
    }
    if ($Bytes.Length -ge 2 -and $Bytes[0] -eq 0xFF -and $Bytes[1] -eq 0xFE) {
        return [System.Text.Encoding]::Unicode.GetString($Bytes, 2, $Bytes.Length - 2)
    }
    if ($Bytes.Length -ge 2 -and $Bytes[0] -eq 0xFE -and $Bytes[1] -eq 0xFF) {
        return [System.Text.Encoding]::BigEndianUnicode.GetString($Bytes, 2, $Bytes.Length - 2)
    }
    # BOM 없음 → UTF-8 로 간주 (이 레포의 .ps1 기본 인코딩). 잘못된 바이트는 예외 대신 U+FFFD 로.
    # NOTE: 여기서 UTF-8 로 읽는 것은 **판정 2(구문)의 오탐을 막기 위한 선택**이며, 실행 엔진이
    #       실제로 이렇게 읽는다는 뜻이 아니다. 그 간극은 판정 1(BOM 게이트)이 따로 막는다(giip #2591).
    $utf8 = New-Object System.Text.UTF8Encoding($false, $false)
    return $utf8.GetString($Bytes)
}

if (-not $RepoRoot) {
    try { $RepoRoot = (& git rev-parse --show-toplevel 2>$null) } catch { $RepoRoot = '' }
    if (-not $RepoRoot) { $RepoRoot = (Get-Location).Path }
}
$RepoRoot = $RepoRoot.Trim()

# 위치 0($Path) + 나머지($RemainingPath) 를 합친 실제 검사 요청 목록.
# NOTE: 변수명을 $path / $staged / $all 처럼 파라미터와 같은 철자로 쓰면 안 된다 — PowerShell 변수는
#       대소문자를 구분하지 않아 파라미터 자체를 덮어쓰고 형변환 에러로 죽는다(실측, giip #2429/#2436).
$targetPaths = @(@($Path) + @($RemainingPath) | Where-Object { $_ })

# -Staged / -All 과 파일 인자를 섞으면 파일 인자가 조용히 무시된다 → 의도가 모호하므로 사용법 오류로 막는다.
if (($Staged -or $All) -and $targetPaths.Count -gt 0) {
    Write-Host "[PS1-PARSE][FAIL] -Staged / -All 과 파일 인자는 함께 쓸 수 없습니다(파일 인자가 무시됨): $($targetPaths -join ', ')"
    Write-Host "사용법: check-ps1-parse.ps1 <파일1> [파일2 ...] | -Path <파일...> | -Staged | -All"
    exit 2
}

$targets = @()
# 지정된 인자 개수와 실제 검사 대상 개수를 대조하기 위한 카운터.
# (giip #2436: 인자가 조용히 누락돼도 exit 0 이 나오던 게 이 게이트가 무동작이 된 원인이다.)
$requestedCount = 0
$missingCount = 0

if ($Staged) {
    # NOTE: 변수명을 $staged 로 쓰면 안 된다 — PowerShell 변수는 대소문자를 구분하지 않아
    #       [switch]$Staged 파라미터와 같은 변수가 되고, git 출력(Object[]) 대입 순간
    #       "Cannot convert System.Object[] to SwitchParameter" 로 죽는다(실측, giip #2429).
    $stagedFiles = & git -C $RepoRoot diff --cached --name-only --diff-filter=ACM -- '*.ps1' '*.PS1'
    foreach ($rel in $stagedFiles) {
        if (-not $rel) { continue }
        $full = Join-Path $RepoRoot $rel
        if (Test-Path -LiteralPath $full -PathType Leaf) { $targets += $full }
    }
} elseif ($All) {
    # 제외 대상: git 내부 / 의존성 / 임시 worktree. 여기에 **자기 레포가 아닌 것**을 넣는다.
    # (원본 lowyworkenv 판은 nested repo 인 `giipprj` / `giipfaw` 를 추가로 제외했다. 이 레포에는
    #  그 nested repo 가 없으므로 뺐다. 다른 배포에서 nested repo 를 두게 되면 -ExcludeDirPattern
    #  으로 넘긴다 — 정규식을 여기 하드코딩하지 않는다.)
    $excludeRe = if ($ExcludeDirPattern) { $ExcludeDirPattern } else { '\\(\.git|node_modules)\\' }
    $targets = Get-ChildItem -Path $RepoRoot -Recurse -Filter *.ps1 -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch $excludeRe -and $_.FullName -notmatch '\\\.claude\\worktrees\\' } |
        ForEach-Object { $_.FullName }
} elseif ($targetPaths.Count -gt 0) {
    foreach ($p in $targetPaths) {
        if (-not $p) { continue }
        $requestedCount++
        $full = if ([System.IO.Path]::IsPathRooted($p)) { $p } else { Join-Path $RepoRoot $p }
        if (Test-Path -LiteralPath $full -PathType Leaf) { $targets += $full }
        else {
            # 예전에는 [SKIP] 만 찍고 exit 0 으로 통과시켰다 — 인자 오타/경로 착오가 "통과"로 보여
            # 게이트가 무동작이 되는 경로였다. 명시적으로 지정한 파일은 없으면 실패로 본다(giip #2436).
            Write-Host "[PS1-PARSE][FAIL] 지정한 파일을 찾을 수 없음: $p"
            $missingCount++
        }
    }
    Write-Host "[PS1-PARSE] 인자 $requestedCount 개 지정 -> 검사 대상 $($targets.Count) 개"
} else {
    Write-Host "사용법: check-ps1-parse.ps1 <파일1> [파일2 ...] | -Path <파일...> | -Staged | -All"
    exit 2
}

if ($missingCount -gt 0) {
    Write-Host ""
    Write-Host "[PS1-PARSE] 결과: 지정한 $requestedCount 개 중 $missingCount 개를 찾을 수 없음 — 차단"
    exit 1
}

if ($targets.Count -eq 0) {
    Write-Host "[PS1-PARSE] 검사 대상 .ps1 없음 — 통과"
    exit 0
}

$badCount = 0
$bomBadCount = 0
$bomBadFiles = @()
foreach ($full in $targets) {
    $rel = $full
    if ($full.StartsWith($RepoRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        $rel = $full.Substring($RepoRoot.Length).TrimStart('\', '/')
    }

    $bytes = $null
    try {
        $bytes = Get-ScriptBytes -FullPath $full
    } catch {
        Write-Host "[PS1-PARSE][FAIL] ${rel}: 읽기 실패 — $($_.Exception.Message)"
        $badCount++
        continue
    }

    # ── 판정 1 — BOM 게이트 (giip #2591) ────────────────────────────────────────────────
    # 판정 2 는 항상 UTF-8 로 읽으므로 이 실패를 구조적으로 볼 수 없다. 실행 엔진
    # (`powershell -File`)은 BOM 없는 파일을 cp932 로 읽어 한글 출력이 깨지고, 한글이 든
    # here-string 하나만 들어와도 파싱 자체가 실패해 스크립트가 한 줄도 실행되지 않는다.
    if (-not (Test-ScriptBom -Bytes $bytes)) {
        $nonAscii = Get-NonAsciiByteCount -Bytes $bytes
        if ($nonAscii -gt 0) {
            $bomBadCount++
            $bomBadFiles += $rel
            Write-Host "[PS1-BOM][FAIL] ${rel}: UTF-8 BOM 없음 + 비ASCII 바이트 $nonAscii 개"
            Write-Host "    PowerShell 5.1 이 이 파일을 시스템 ANSI 코드페이지(cp932)로 읽습니다."
            Write-Host "    -> 한글 출력이 깨지고, 한글이 든 문자열이 추가되는 순간 실행 자체가 실패합니다."
        }
    }

    # ── 판정 2 — 구문 게이트 (giip #2429 이후 기존 검사, 변경 없음) ──────────────────────
    $errors = $null
    $tokens = $null
    try {
        $text = ConvertTo-ScriptText -Bytes $bytes
        [System.Management.Automation.Language.Parser]::ParseInput($text, [ref]$tokens, [ref]$errors) | Out-Null
    } catch {
        Write-Host "[PS1-PARSE][FAIL] ${rel}: 디코딩 실패 — $($_.Exception.Message)"
        $badCount++
        continue
    }
    if ($errors -and $errors.Count -gt 0) {
        $badCount++
        Write-Host "[PS1-PARSE][FAIL] ${rel}: 파싱 에러 $($errors.Count)건"
        foreach ($e in ($errors | Select-Object -First 5)) {
            Write-Host ("    L{0} C{1}: {2}" -f $e.Extent.StartLineNumber, $e.Extent.StartColumnNumber, $e.Message)
        }
        if ($errors.Count -gt 5) { Write-Host "    ... (외 $($errors.Count - 5)건)" }
    }
}

if ($bomBadCount -gt 0) {
    Write-Host ""
    Write-Host "[PS1-BOM] 결과: 검사 $($targets.Count)개 중 $bomBadCount 개 파일이 'BOM 없음 + 비ASCII' — 차단"
    Write-Host "보정 방법 (내용은 그대로 두고 BOM 3바이트만 추가 — 멱등):"
    Write-Host "  `$utf8Bom   = New-Object System.Text.UTF8Encoding(`$true)"
    Write-Host "  `$utf8NoBom = New-Object System.Text.UTF8Encoding(`$false)"
    Write-Host "  # [System.IO.File] 은 .NET 메서드라 상대경로를 PowerShell 현재 위치가 아니라"
    Write-Host "  # 프로세스 작업 디렉터리 기준으로 푼다. 반드시 Resolve-Path 로 절대경로를 만들어 넘긴다."
    foreach ($f in $bomBadFiles) {
        Write-Host "  `$t = (Resolve-Path '$f').Path; `$b = [System.IO.File]::ReadAllBytes(`$t); if (-not (`$b.Length -ge 3 -and `$b[0] -eq 0xEF -and `$b[1] -eq 0xBB -and `$b[2] -eq 0xBF)) { [System.IO.File]::WriteAllText(`$t, `$utf8NoBom.GetString(`$b), `$utf8Bom) }"
    }
    Write-Host "보정 후 바이트 길이가 정확히 3 늘었는지 확인할 것(내용이 바뀌면 안 된다)."
}

if ($badCount -gt 0) {
    Write-Host ""
    Write-Host "[PS1-PARSE] 결과: 검사 $($targets.Count)개 중 $badCount 개 파일에 파싱 에러 — 차단"
}

if ($bomBadCount -gt 0 -or $badCount -gt 0) { exit 1 }

Write-Host "[PS1-PARSE] 결과: 검사 $($targets.Count)개 전부 통과 (구문 + BOM)"
exit 0
