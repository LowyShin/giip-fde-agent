# test-reaper-node-orphan-fingerprint.ps1 — node 고아 지문 판정 회귀 테스트 (giip #2673)
#
# 왜 필요한가:
#   Phase 0 reaper 는 원래 claude.exe 에서만 회수 후보를 열거했다. claude 가 먼저 죽고 node
#   손자만 남으면 열거 출발점이 사라져 후보에 아예 들어오지 않는다(실측 2026-09-18:
#   PID 10720/10036 이 부모 7892/5680 소멸 후 다음 실행에서도 회수되지 않았다).
#   그래서 node 도 후보로 열거하는데, 그때 **pm2/slack-bot 의 node 를 절대 건드리면 안 된다**
#   (원래 안전장치 (3) "claude.exe 만 대상 -> pm2/slack-bot(node)은 원천 비대상" 의 취지).
#
#   이 테스트는 그 양방향을 고정한다:
#     (A) claude CLI 로 뜬 node 는 **후보가 된다**(회수되어야 한다)
#     (B) pm2 / slack-bot / 무관한 node 는 **제외된다**(절대 죽이지 않는다)
#
#   실제로 구현 중 제외 지문에 `npm[\/]` 를 넣었다가 이 테스트에서 걸렸다 — 전역 npm 에 설치된
#   정상 claude CLI(…\npm\node_modules\@anthropic-ai\claude-code\cli.js)까지 제외돼
#   회수 대상이 사라지는 버그였다. 넓은 조각을 제외 지문에 넣지 말 것.
#
# 실행: powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gissue/tests/test-reaper-node-orphan-fingerprint.ps1
#
# 주의: run-gissue-claude.ps1 을 dot-source 하면 스케줄러 본체가 실행된다. 그래서 이 테스트는
#   파일에서 두 정규식 줄만 읽어 평가한다(아래 Get-Content + 정규식 추출).

$ErrorActionPreference = 'Stop'
$target = Join-Path (Split-Path -Parent $PSScriptRoot) 'run-gissue-claude.ps1'
if (-not (Test-Path $target)) { Write-Host "대상 없음: $target" -ForegroundColor Red; exit 1 }
$src = Get-Content -LiteralPath $target -Raw -Encoding UTF8

$m1 = [regex]::Match($src, '(?m)^\$ReaperOrphanNodeFingerprint\s*=\s*(.+)$')
$m2 = [regex]::Match($src, '(?m)^\$ReaperOrphanNodeExclude\s*=\s*(.+)$')
if (-not $m1.Success) { Write-Host 'FAIL 지문 정의를 찾지 못했다' -ForegroundColor Red; exit 1 }
if (-not $m2.Success) { Write-Host 'FAIL 제외 지문 정의를 찾지 못했다' -ForegroundColor Red; exit 1 }
$FP = Invoke-Expression $m1.Groups[1].Value.Trim()
$EX = Invoke-Expression $m2.Groups[1].Value.Trim()

$cases = @(
 @{ n='claude CLI (-p)';    c='node C:\Users\x\AppData\Roaming\npm\node_modules\@anthropic-ai\claude-code\cli.js -p'; want='후보' },
 @{ n='claude .claude';     c='node C:\Users\x\.claude\local\cli.js --print';                                           want='후보' },
 @{ n='pm2 데몬';           c='node C:\npm\node_modules\pm2\lib\ProcessContainer.js';                                   want='제외' },
 @{ n='slack-bot';          c='node /work/giip-fde-agent/slack-bot/index.js';                                               want='제외' },
 @{ n='무관한 node';        c='node server.js';                                                                             want='제외' },
 @{ n='pm2 가 띄운 claude';  c='node C:\npm\node_modules\pm2\x\claude\cli.js';                                          want='제외' }
)
$fail = 0
foreach ($t in $cases) {
  $hit = [bool]($t.c -match $FP)
  $exc = [bool]($t.c -match $EX)
  $v = if ($hit -and -not $exc) { '후보' } else { '제외' }
  if ($v -ne $t.want) { $fail++; Write-Host ("  FAIL {0,-18} -> {1} (기대 {2})" -f $t.n,$v,$t.want) -ForegroundColor Red }
  else { Write-Host ("  ok   {0,-18} -> {1}" -f $t.n,$v) }
}

# 금지 사항: 이미지명 기준 일괄 종료가 코드에 들어가면 안 된다(PID 지정 종료만).
if ($src -match '(?i)taskkill[^\r\n]*/IM') { Write-Host '  FAIL 이미지명 기준 일괄 종료가 코드에 있다' -ForegroundColor Red; $fail++ }
else { Write-Host '  ok   이미지명 기준 일괄 종료 없음' }

# 드라이런이 기본이어야 한다(요구사항 4 — 사람이 한 번 읽고 나서 켠다).
if ($src -notmatch '(?m)^\$ReaperNodeOrphanLiveKill\s*=\s*\$false') { Write-Host '  FAIL 드라이런 기본값이 아니다' -ForegroundColor Red; $fail++ }
else { Write-Host '  ok   node 고아 경로는 드라이런 기본' }

Write-Host ''
if ($fail -eq 0) { Write-Host 'ALL PASS' -ForegroundColor Green; exit 0 }
Write-Host "$fail FAILED" -ForegroundColor Red; exit 1
