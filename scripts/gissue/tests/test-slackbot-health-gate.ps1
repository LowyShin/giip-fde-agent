# slack-bot 헬스체크 블록(Phase 0.5)의 판정 논리 단위 테스트. 가짜 pm2 로 호출 기록만 검사한다(실제 pm2/네트워크 없음).
# 실행: pwsh -File scripts/gissue/tests/test-slackbot-health-gate.ps1
$ErrorActionPreference = 'Stop'
$src = Get-Content (Join-Path $PSScriptRoot '../run-gissue-claude.ps1') -Raw -Encoding UTF8
$a = $src.IndexOf('$SlackBotStaleMin = 25'); $b = $src.IndexOf('# ── Phase 1:')
if ($a -lt 0 -or $b -lt $a) { throw 'Phase 0.5 블록을 찾지 못함' }
# $HOME 은 읽기 전용 자동 변수라 시험용 변수($TestHome)로 치환해 실행한다.
$block = $src.Substring($a, $b - $a).Replace('$HOME', '$TestHome')

function Assert-True($c, $m) { if (-not $c) { throw "FAIL: $m" } }
function Invoke-Case($installed, $pm2Apps) {
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("sbgate_" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path (Join-Path $tmp 'bot') -Force | Out-Null
    if ($installed) { New-Item -ItemType Directory -Path (Join-Path $tmp 'bot/node_modules') -Force | Out-Null }
    $script:calls = New-Object System.Collections.ArrayList
    $script:apps = $pm2Apps
    function pm2 {
        $script:calls.Add(($args -join ' ')) | Out-Null
        if ($args[0] -eq 'describe') {
            $name = $args[1]
            if ($script:apps.ContainsKey($name)) { return @("│ status │ $($script:apps[$name]) │") }
        }
    }
    $DryRun = $false; $LogDir = $tmp; $SlackBotDir = Join-Path $tmp 'bot'; $TestHome = $tmp
    $SlackBotHealthLog = Join-Path $tmp 'health.log'
    Invoke-Expression $block 2>&1 | Out-Null
    $log = if (Test-Path $SlackBotHealthLog) { Get-Content $SlackBotHealthLog -Raw } else { '' }
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    return [pscustomobject]@{ calls = @($script:calls); log = $log }
}

# 1) 설치 안 됨 → pm2 를 아예 부르지 않고 SKIP 만 남긴다(예전: 매 회차 신규 기동 → errored 150회)
$r = Invoke-Case $false @{}
Assert-True ($r.calls.Count -eq 0) "미설치인데 pm2 호출: $($r.calls -join '; ')"
Assert-True ($r.log -match 'SKIP: slack-bot 미설치') "SKIP 로그 없음: $($r.log)"

# 2) 설치됨 + entrypoint 이름(giipclaude-bot) online → 새로 기동하지 않는다(예전: slack-bot 을 못 찾아 이중 기동)
$r = Invoke-Case $true @{ 'giipclaude-bot' = 'online' }
Assert-True (-not ($r.calls | Where-Object { $_ -like 'start*' })) "이중 기동: $($r.calls -join '; ')"
Assert-True ($r.log -notmatch 'MISSING') "MISSING 오판: $($r.log)"

# 3) 설치됨 + 아무 이름도 pm2 에 없음 → 예전 이름(slack-bot)으로 신규 기동
$r = Invoke-Case $true @{}
Assert-True ([bool]($r.calls | Where-Object { $_ -like 'start index.js --name slack-bot*' })) "신규 기동 없음: $($r.calls -join '; ')"

# 4) 설치됨 + giipclaude-bot errored → 그 이름으로 restart
$r = Invoke-Case $true @{ 'giipclaude-bot' = 'errored' }
Assert-True ([bool]($r.calls | Where-Object { $_ -eq 'restart giipclaude-bot' })) "restart 이름 오류: $($r.calls -join '; ')"
Write-Host 'PASS test-slackbot-health-gate'
