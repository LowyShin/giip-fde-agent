# test-overtime-findchildren-port.ps1 — 2시간 초과 처리(find-children) 포트의 DB 비의존성 회귀 테스트
#
# 고정하는 것 (giip 4434 완료조건):
#   (1) 정본 러너의 FindOpenChildren 포트는 DB 직접 조회(execSQLFile/sqlcmd/Invoke-Sqlcmd)에 의존하지 않는다
#   (2) 그 포트는 API 경로(list-issues.js --json)를 쓴다
#   (3) 그 포트는 DB 텍스트 출력 헤더('line')를 **성공 판정 근거**로 쓰지 않는다
#       — 운영 사본(lowyworkenv) 러너가 이 헤더 정규식으로 성공을 판정해서, SqlServer 모듈이 있는
#         환경(=객체 모드)에서는 exit=0 인데 "조회 실패" 로 오판했다. 그 결과 find-children 조회가
#         항상 실패해 rule 69-4 중복 서브이슈 감지가 무력화되었다. 같은 사고 재발 방지.
#   (4) 조회 실패는 fail-closed 다 — 실패를 성공으로 넘기지 않는다(분해 보류로 이어져야 한다)
#   (5) scripts/gissue/ 아래 어떤 스크립트도 DB 직접 조회를 **실제로 호출하지 않는다**(주석 언급은 무관)
#   (6) 출력 모드 무관 행 파서 헬퍼(Get-GissueIssueRowsFromQueryOutput)가 객체/JSON/텍스트 3모드를
#       모두 처리하고, 판별 불가 출력은 예외(fail-closed)로 남긴다
#
# 알려진 한계 (기준선 밖 · 별개 결함 — 이 테스트가 고정하지 않는다):
#   정본 러너의 포트는 Windows PowerShell 5.1(운영 런타임)에서 `ConvertFrom-Json` 결과를 **전개하지
#   않아**, API 가 2건 이상을 주면 **행이 1개**로 합쳐지고 Isn/Status/Title 가 배열이 된다.
#   그 상태에서 실제 소비 함수 `Find-GissueOpenSplitChildren` 는 `[int]$_.Isn` 캐스트에서 예외를 던져
#   find-children 가 실패한다 → rule 69-4 중복 서브이슈 감지가 무력화(giip 4434 와 **다른** 원인).
#   → `KNOW-035` 로 사실 등록했고, 정본 러너의 동작 수정은 별도 후속이다(giip 4434 의 비범위:
#     "본 이슈는 정본 기준선과 사실 관계만 확정한다").
#   → 그래서 이 테스트는 **내용**(이슈 번호 집합 · 제목 · fail-closed)만 고정하고,
#     다건 응답의 **행 개수**는 고정하지 않는다(1건 응답에서만 행 개수 계약을 단언한다).
#
# 실행: powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gissue/tests/test-overtime-findchildren-port.ps1
# 실제 DB·네트워크·giip 이슈에는 손대지 않는다 — 러너 소스에서 포트를 AST 로 추출해
# 임시 스텁 API 스크립트와만 통신한다.

$ErrorActionPreference = 'Stop'
$gissueDir = Split-Path -Parent $PSScriptRoot
. (Join-Path $gissueDir 'lib/overtime-split.ps1')

$script:fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  ok   $msg" }
    else { Write-Host "  FAIL $msg" -ForegroundColor Red; $script:fail++ }
}

# ── [A] 러너에서 FindOpenChildren 포트를 실제로 추출한다 ──────────────────────
# 복사본이 아니라 **러너 소스의 그 블록**을 시험해야 한다(소스를 옮겨 타면 검증이 아니라 decoration 이 된다).
function Get-FindOpenChildrenPortText {
    param([string]$RunnerPath)
    $text = [System.IO.File]::ReadAllText($RunnerPath, [System.Text.Encoding]::UTF8)
    $tokens = $null; $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($text, $RunnerPath, [ref]$tokens, [ref]$parseErrors)
    if (@($parseErrors).Count -gt 0) { return $null }

    $hits = @()
    $tables = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.HashtableAst] }, $true)
    foreach ($ht in $tables) {
        foreach ($kv in $ht.KeyValuePairs) {
            if ("$($kv.Item1.Extent.Text)".Trim() -eq 'FindOpenChildren') { $hits += $kv.Item2 }
        }
    }
    if ($hits.Count -ne 1) { return $null }

    $v = $hits[0]
    while ($v -is [System.Management.Automation.Language.PipelineAst]) { $v = $v.PipelineElements[0] }
    while ($v -is [System.Management.Automation.Language.CommandExpressionAst]) { $v = $v.Expression }
    if ($v -isnot [System.Management.Automation.Language.ScriptBlockExpressionAst]) { return $null }
    $sba = $v.ScriptBlock
    if ($sba.EndBlock) { return $sba.EndBlock.Extent.Text }
    if ($sba.Body) { return $sba.Body.Extent.Text }
    return $null
}

Write-Host '[A] 정본 러너에서 FindOpenChildren 포트 추출'
$runnerPath = Join-Path $gissueDir 'run-gissue-claude.ps1'
Assert (Test-Path -LiteralPath $runnerPath) '러너 파일이 존재한다'
$runnerText = if (Test-Path -LiteralPath $runnerPath) { [System.IO.File]::ReadAllText($runnerPath, [System.Text.Encoding]::UTF8) } else { '' }
$portText = Get-FindOpenChildrenPortText $runnerPath
Assert ($null -ne $portText -and $portText.Trim().Length -gt 0) '러너의 FindOpenChildren 포트 블록을 AST 로 추출했다'

# ── [B] 포트 소스 계약 ─────────────────────────────────────────────────────
Write-Host '[B] 포트 소스 계약 — DB 직접조회 의존 없음 / API 경로 사용'
if ($null -ne $portText) {
    Assert ($portText -notmatch '(?i)execSQLFile') '포트: execSQLFile 참조 없음'
    Assert ($portText -notmatch '(?i)sqlcmd') '포트: sqlcmd / Invoke-Sqlcmd 참조 없음'
    Assert ($portText -notmatch '(?i)dbconfig') '포트: dbconfig 참조 없음'
    Assert ($portText -notmatch '(?m)^\s*line\s*$') '포트: DB 텍스트 헤더("line") 성공 판정 정규식 없음'
    Assert ($portText -notmatch 'LASTEXITCODE') '포트: 프로세스 종료코드(LASTEXITCODE) 로 성공을 판정하지 않는다'
    Assert ($portText -match 'ConvertFrom-Json') '포트: 출력은 JSON 으로 읽는다'
    Assert ($portText -match '--json') '포트: API 호출이 --json 모드다'
    Assert ($portText -match '\$ListIssuesScript') '포트: 목록 조회 스크립트($ListIssuesScript)를 쓴다'
}
Assert ($runnerText -match "(?m)^\`$ListIssuesScript\s*=\s*Join-Path \`$Root 'list-issues\.js'") '러너의 $ListIssuesScript 는 list-issues.js(API 경로)다'
Assert ($runnerText -match '혼용\(일부만 DB, 일부만 API\)은 금지') '러너 헤더에 "DB/API 혼용 금지" 규정이 남아 있다'

# ── [C] 저장소 전수 — DB 직접조회를 실제로 호출하는 코드가 없어야 한다 ──────────
Write-Host '[C] scripts/gissue 전수 — DB 직접조회 실제 호출 0건(주석 언급은 제외)'
function Get-DbCallHitsInPs1 {
    param([string]$Path)
    $hits = @()
    $text = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
    $tokens = $null; $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($text, $Path, [ref]$tokens, [ref]$parseErrors)
    if (@($parseErrors).Count -gt 0) { return @("$Path : 파싱 오류로 검사 불가") }
    foreach ($c in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)) {
        $n = $c.GetCommandName()
        if ($n -and $n -match '(?i)(^|[\\/])(execSQLFile|sqlcmd)$' -or ($n -and $n -match '(?i)^Invoke-Sqlcmd$')) {
            $hits += "$Path : 명령 호출 [$n]"
        }
    }
    foreach ($s in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true)) {
        if ("$($s.Value)" -notmatch '(?i)execSQLFile\.ps1') { continue }
        $p = $s.Parent; $execCmd = ''
        while ($null -ne $p) {
            if ($p -is [System.Management.Automation.Language.CommandAst]) { $execCmd = "$($p.GetCommandName())"; break }
            $p = $p.Parent
        }
        # 파일을 실행하는 명령의 인자면 호출이다.
        if ($execCmd -and $execCmd -notmatch '(?i)^(powershell|pwsh|start-process|invoke-expression|iex)') { continue }
        # 프롬프트 템플릿(here-string) 등 "설명 문자열"은 호출이 아니다 — 제외한다.
        # (PS 5.1 에는 HereString 멤버가 없고 SingleQuotedHereString / DoubleQuotedHereString 이 있다)
        if (-not $execCmd -and "$($s.StringConstantType)" -match 'HereString') { continue }
        $hits += "$Path : 실행 대상 문자열 [$($s.Value)] (명령: $execCmd)"
    }
    return @($hits)
}
function Get-DbCallHitsInJs {
    param([string]$Path)
    $hits = @()
    $lines = [System.IO.File]::ReadAllLines($Path, [System.Text.Encoding]::UTF8)
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $t = "$($lines[$i])".Trim()
        if ($t -eq '' -or $t.StartsWith('//') -or $t.StartsWith('*') -or $t.StartsWith('/*')) { continue }
        if ($t -match '(?i)execSQLFile|Invoke-Sqlcmd|\bsqlcmd\b') { $hits += "$Path : $($i + 1)행 [$t]" }
    }
    return @($hits)
}
$dbHits = @()
foreach ($f in @(Get-ChildItem -LiteralPath $gissueDir -Recurse -File -ErrorAction SilentlyContinue)) {
    if ($f.Extension -eq '.ps1' -or $f.Extension -eq '.psm1') { $dbHits += @(Get-DbCallHitsInPs1 $f.FullName) }
    elseif ($f.Extension -eq '.js' -or $f.Extension -eq '.mjs') { $dbHits += @(Get-DbCallHitsInJs $f.FullName) }
}
Assert ($dbHits.Count -eq 0) ("scripts/gissue 전수에서 DB 직접조회 실제 호출 0건" + $(if ($dbHits.Count) { " — 발견: " + ($dbHits -join ' | ') } else { '' }))

# ── [D] 동작 — 추출한 실제 포트를 스텁 API 와 함께 실행 ───────────────────────
Write-Host '[D] 동작 — 실제 포트를 스텁 API 로 구동'
function Set-StubScript {
    param([string]$Path, [string]$RecordPath, [string]$StdoutJs, [int]$ExitCode = 0)
    $rec = $RecordPath.Replace('\', '\\').Replace("'", "\'")
    $js = @"
const fs = require('fs');
try { fs.writeFileSync('$rec', JSON.stringify(process.argv.slice(2))); } catch (e) {}
$StdoutJs
process.exit($ExitCode);
"@
    [System.IO.File]::WriteAllText($Path, $js, (New-Object System.Text.UTF8Encoding $false))
}
function Get-PortIsns($Rows) {
    $out = @()
    foreach ($r in @($Rows)) {
        if ($null -eq $r) { continue }
        foreach ($v in @($r.Isn)) {
            if ($null -ne $v -and "$v".Trim() -ne '') { $out += [int]$v }
        }
    }
    return @($out)
}

$nodeCmd = Get-Command node -ErrorAction SilentlyContinue
Assert ($null -ne $nodeCmd) 'node 를 찾을 수 있다(스텁 API 실행에 필요)'
$tmpRoot = $null
if ($null -ne $nodeCmd -and $null -ne $portText) {
    $tmpRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('gissue4434_' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmpRoot -Force | Out-Null
    $stubPath = Join-Path $tmpRoot 'list-issues-stub.js'
    $recordPath = Join-Path $tmpRoot 'argv.json'

    # 러너와 같은 이름·같은 뜻의 스코프 변수(포트가 참조하는 것)
    $ListIssuesScript = $stubPath
    $script:OvertimeCtxRun = [pscustomobject]@{ Csn = '777' }
    $port = [scriptblock]::Create($portText)

    Set-StubScript $stubPath $recordPath "console.log(JSON.stringify([{isn:9001,status:'READY',title:'first child'},{isn:9002,status:'IN_PROGRESS',title:'second child'}]));" 0
    $rows = & $port 1234
    $isns = @(Get-PortIsns $rows) | Sort-Object
    Assert (($isns -join ',') -eq '9001,9002') "포트가 API JSON 2건의 isn 을 모두 노출한다(실측: $($isns -join ','))"
    Write-Host ("  info 포트 행 개수 = {0} (PS {1} · 다건 응답의 행 형태는 별개 결함 KNOW-035 — 이 테스트는 고정하지 않는다)" -f @($rows).Count, $PSVersionTable.PSVersion)

    Assert (Test-Path -LiteralPath $recordPath) '스텁 API 스크립트가 실제로 호출되었다(포트가 살아 있는 경로를 쓴다)'
    $argv = @()
    if (Test-Path -LiteralPath $recordPath) {
        $parsedArgv = ConvertFrom-Json ([System.IO.File]::ReadAllText($recordPath))
        $argv = @($parsedArgv)
    }
    Assert ($argv -contains '--json') "포트가 API 를 --json 으로 호출한다(실측 인자: $($argv -join ' '))"
    $csnIdx = [array]::IndexOf($argv, '--csn')
    Assert ($csnIdx -ge 0 -and ($csnIdx + 1) -lt $argv.Count -and "$($argv[$csnIdx + 1])" -eq '777') "포트가 조회 CSN 을 넘긴다(실측 인자: $($argv -join ' '))"

    Set-StubScript $stubPath $recordPath "console.log(JSON.stringify([]));" 0
    $rowsEmpty = & $port 1234
    Assert (@(Get-PortIsns $rowsEmpty).Count -eq 0) '빈 배열 응답 → 자식 0건(오류 아님)'

    Set-StubScript $stubPath $recordPath "console.log(JSON.stringify([{isn:9001,status:'READY',title:'only child'}]));" 0
    $rowsOne = @(& $port 1234)
    Assert ($rowsOne.Count -eq 1) "1건 응답 → 행 1개(행 개수 계약 · 실측: $($rowsOne.Count))"
    Assert ("$($rowsOne[0].Isn)" -eq '9001') "1건 응답 → isn 이 스칼라다(실측: $($rowsOne[0].Isn))"
    $titles = @($rowsOne[0].Title)
    Assert ("$($titles[0])" -eq 'only child') "행 제목이 API JSON 과 일치한다(실측: $($titles[0]))"

    Set-StubScript $stubPath $recordPath "console.log('not json at all');" 0
    $threw = $false; $errMsg = ''
    try { $null = & $port 1234 } catch { $threw = $true; $errMsg = "$($_.Exception.Message)" }
    Assert $threw "포트는 파싱 실패를 예외로 올린다(fail-closed) — 메시지: $errMsg"

    Set-StubScript $stubPath $recordPath "process.stderr.write('boom');" 3
    $threw2 = $false
    try { $null = & $port 1234 } catch { $threw2 = $true }
    Assert $threw2 '포트는 stderr/비정상 종료도 예외로 올린다(fail-closed)'
}

# ── [E] 출력 모드 무관 행 파서 헬퍼 + 그 테스트 ───────────────────────────────
Write-Host '[E] 행 파서 헬퍼 — 출력 모드(객체/JSON/텍스트)에 의존하지 않는다'
$objRows = @([pscustomobject]@{ isn = 9001; status = 'READY'; title = 'object mode' })
$hObj = Get-GissueIssueRowsFromQueryOutput $objRows
Assert ($hObj.Mode -eq 'Object' -and @($hObj.Rows).Count -eq 1) '헬퍼: 객체 모드(Invoke-Sqlcmd 분기) → 행 1건'
Assert ("$($hObj.Rows[0].Title)" -eq 'object mode') "헬퍼: 객체 모드 제목(실측: $($hObj.Rows[0].Title))"

$hJson = Get-GissueIssueRowsFromQueryOutput '[{"isn":9001,"status":"READY","title":"json mode"}]'
Assert ($hJson.Mode -eq 'Json' -and @($hJson.Rows).Count -eq 1) '헬퍼: JSON 모드(API 경로) → 행 1건'
Assert ("$($hJson.Rows[0].Title)" -eq 'json mode') "헬퍼: JSON 모드 제목(실측: $($hJson.Rows[0].Title))"

$sqlcmdText = @"
line  isn   status  title
----  ----  ------  -----
1     9001  READY   first child
2     9002  REVIEW  second child
"@
$hText = Get-GissueIssueRowsFromQueryOutput $sqlcmdText
Assert ($hText.Mode -eq 'Text' -and @($hText.Rows).Count -eq 2) "헬퍼: 텍스트 모드(sqlcmd 표) → 행 2건(실측: $(@($hText.Rows).Count))"
Assert ("$($hText.Rows[0].Isn)" -eq '9001' -and "$($hText.Rows[1].Isn)" -eq '9002') '헬퍼: 텍스트 모드 isn 매핑'
Assert ("$($hText.Rows[1].Title)" -eq 'second child') "헬퍼: 텍스트 모드 제목(실측: $($hText.Rows[1].Title))"

$hEmpty = Get-GissueIssueRowsFromQueryOutput ''
Assert ($hEmpty.Mode -eq 'Empty' -and @($hEmpty.Rows).Count -eq 0) '헬퍼: 빈 출력 → 0행(성공, 오류 아님)'

$threw3 = $false
try { $null = Get-GissueIssueRowsFromQueryOutput '이건 표가 아니다' } catch { $threw3 = $true }
Assert $threw3 '헬퍼: 판별 불가 출력은 예외(fail-closed) — 성공으로 넘기지 않는다'

# 이 사고의 핵심 입력: 운영 사본 러너가 항상 실패하던 바로 그 출력(객체 모드 = 'line' 헤더가 없다)
$incidentRows = @([pscustomobject]@{ isn = 9001; status = 'READY'; title = '원본 giip 4434 후속' })
$hIncident = Get-GissueIssueRowsFromQueryOutput $incidentRows
Assert ($hIncident.Mode -eq 'Object' -and @($hIncident.Rows).Count -eq 1) '헬퍼: 운영 사본이 실패하던 객체 모드 출력을 정상 파싱한다(헤더 모양으로 성공을 판정하지 않는다)'

# ── 마무리 ────────────────────────────────────────────────────────────────────
if ($tmpRoot -and (Test-Path -LiteralPath $tmpRoot)) {
    try { Remove-Item -LiteralPath $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue } catch { }
}
if ($script:fail -gt 0) { Write-Host "`n실패 $($script:fail)건" -ForegroundColor Red; exit 1 }
Write-Host "`n전체 통과"
exit 0
