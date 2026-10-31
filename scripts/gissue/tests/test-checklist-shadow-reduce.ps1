# test-checklist-shadow-reduce.ps1 - Shadow 비용 축소(giip #4334 후속) 테스트
#
# 고정하는 것:
#   (1) 기록: 로그 폴더가 없으면 만들고, BOM 없는 UTF-8 한 줄 JSON 으로 쌓이며 입력해시 필드가 들어간다.
#   (2) 캐시: 입력해시가 같으면 LLM 을 부르지 않고 직전 판정을 재사용(cached=true), 입력이 바뀌면(본문/코멘트/PR) 재호출한다.
#   (3) 평가 대상 축소: 같은 (isn, source) 최근 기록이면 스킵, 다른 source 는 스킵 안 함, 틱 호출 상한 초과 시 스킵.
#   (4) 실패 백오프: 호출 실패는 failures 로그에 남고 백오프 시간 동안 같은 (isn, source) 를 재시도하지 않는다.
#   (5) 끄기: GISSUE_CHECKLIST_SHADOW_REDUCE=off 면 캐시·스킵이 모두 꺼진다(이전 동작).
#   (6) Live 불변: Live 가 쓰는 Invoke-ChecklistAssessment 는 캐시/기록을 전혀 쓰지 않는다(매번 새로 판정).
#   (7) 동시 쓰기: 여러 프로세스가 동시에 같은 파일에 써도 줄이 유실/손상되지 않는다.
# LLM/네트워크 없이 돈다 - Invoke-GissueJudge 를 스텁으로 교체한다.
#
# 실행: powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gissue/tests/test-checklist-shadow-reduce.ps1

$ErrorActionPreference = 'Stop'
$gissueDir = Split-Path -Parent $PSScriptRoot
. (Join-Path $gissueDir 'gissue-audit-lib.ps1')
. (Join-Path $gissueDir 'gissue-gate-tally-lib.ps1')

$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  ok   $msg" }
    else { Write-Host "  FAIL $msg" -ForegroundColor Red; $script:fail++ }
}

# 임시 로그 폴더(없는 경로로 시작 -> 폴더 자동 생성도 함께 검증).
$tmpRoot = Join-Path ([IO.Path]::GetTempPath()) ("shadow-reduce-test-" + [guid]::NewGuid().ToString('N'))
$env:GISSUE_CHECKLIST_SHADOW_DIR = Join-Path $tmpRoot 'logs'
$envKeys = 'GISSUE_CHECKLIST_SHADOW_REDUCE', 'GISSUE_CHECKLIST_SHADOW_TTL_HOURS', 'GISSUE_CHECKLIST_SHADOW_MAX_PER_TICK', 'GISSUE_CHECKLIST_SHADOW_MAX_PER_HOUR', 'GISSUE_CHECKLIST_SHADOW_FAIL_BACKOFF_MIN'
function Reset-Env { foreach ($k in $envKeys) { [Environment]::SetEnvironmentVariable($k, $null) } }
function Reset-Logs { if (Test-Path -LiteralPath $tmpRoot) { Remove-Item -LiteralPath $tmpRoot -Recurse -Force }; $script:ChecklistShadowJudgedThisRun = 0; $script:calls = 0 }

$script:calls = 0
$script:stubResult = @{ ok = $true; text = "ITEM|other|UNMET|문서를 등록한다|증거 없음`nITEM|other|MET|보고한다|코멘트 1"; exit = 0 }
function Invoke-GissueJudge($prompt, $model = 'x') { $script:calls++; return $script:stubResult }

$logFile = Join-Path $env:GISSUE_CHECKLIST_SHADOW_DIR 'checklist-shadow.jsonl'
$failFile = Join-Path $env:GISSUE_CHECKLIST_SHADOW_DIR 'checklist-shadow-failures.jsonl'
function Read-Recs($f) { if (Test-Path -LiteralPath $f) { @(Get-Content -LiteralPath $f -Encoding UTF8 | Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json }) } else { @() } }

$c1 = @([pscustomobject]@{ regdate = '2026-10-31T01:00:00Z'; author = 'a'; issuetype = 'note'; cSn = 1; content = '착수 한글 코멘트' })
$c2 = $c1 + @([pscustomobject]@{ regdate = '2026-10-31T02:00:00Z'; author = 'a'; issuetype = 'note'; cSn = 2; content = '추가 코멘트' })
$pr0 = @{ Known = $true; HasMerged = $false; HasAny = $false; Text = '- 머지된 대응 PR: 없음 / 대응 PR 존재: 없음' }
$pr1 = @{ Known = $true; HasMerged = $true; HasAny = $true; Text = '- 머지된 대응 PR: 있음 / 대응 PR 존재: 있음' }

Write-Host '== (1) 기록: 폴더 자동 생성 / BOM 없음 / 한글 / 입력해시 =='
Reset-Env; Reset-Logs
$r = Invoke-ChecklistShadowJudge 9001 'REVERT' 'review-done-audit:DONE' '의뢰 본문' $c1 $pr0
Assert ($r.Action -eq 'judged' -and $script:calls -eq 1) '최초 호출은 judged 이고 LLM 1회'
Assert (Test-Path -LiteralPath $logFile) '로그 폴더가 없어도 checklist-shadow.jsonl 이 생성된다'
$b = [IO.File]::ReadAllBytes($logFile)
Assert (-not ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)) 'BOM 없는 UTF-8 로 쓴다'
$recs = @(Read-Recs $logFile)
Assert ($recs.Count -eq 1 -and $recs[0].isn -eq 9001 -and $recs[0].legacy -eq 'REVERT' -and $recs[0].source -eq 'review-done-audit:DONE') '레코드 1건: isn/legacy/source'
Assert ($recs[0].inputHash -match '^[0-9a-f]{64}$' -and $recs[0].cached -eq $false) 'inputHash(SHA-256) 와 cached=false 기록'
Assert ($recs[0].items[0].text -eq '문서를 등록한다') '한글 항목 텍스트가 깨지지 않는다'
Assert ($recs[0].checklist -eq 'REVERT') '미충족 항목이 있으면 신룰 REVERT'

Write-Host '== (2) 캐시: 같은 입력 재사용 / 입력 변경 시 재호출 =='
$r = Invoke-ChecklistShadowJudge 9001 'REVERT' 'review-done-audit:REVIEW' '의뢰 본문' $c1 $pr0
Assert ($r.Action -eq 'cached' -and $script:calls -eq 1) '동일 입력(다른 source) -> LLM 호출 없이 cached'
$recs = @(Read-Recs $logFile)
Assert ($recs.Count -eq 2 -and $recs[1].cached -eq $true -and $recs[1].reusedFromTs -eq $recs[0].ts -and $recs[1].checklist -eq $recs[0].checklist) '캐시 적중도 기록(cached=true, 원본 ts, 같은 판정)'
$r = Invoke-ChecklistShadowJudge 9001 'REVERT' 'x' '의뢰 본문(수정)' $c1 $pr0
Assert ($r.Action -eq 'judged' -and $script:calls -eq 2) '본문이 바뀌면 재호출'
$r = Invoke-ChecklistShadowJudge 9001 'REVERT' 'x' '의뢰 본문' $c2 $pr0
Assert ($r.Action -eq 'judged' -and $script:calls -eq 3) '코멘트가 추가되면 재호출'
$r = Invoke-ChecklistShadowJudge 9001 'REVERT' 'x' '의뢰 본문' $c1 $pr1
Assert ($r.Action -eq 'judged' -and $script:calls -eq 4) 'PR 증거가 바뀌면 재호출'
$r = Invoke-ChecklistShadowJudge 9002 'REVERT' 'x' '의뢰 본문' $c1 $pr0
Assert ($r.Action -eq 'judged' -and $script:calls -eq 5) '다른 isn 은 같은 입력이어도 캐시를 공유하지 않는다'
$h1 = Get-ChecklistInputHash '본문' $c1 'pr'
$h2 = Get-ChecklistInputHash '본문' $c1 'pr' 'other-model'
Assert ($h1.inputHash -ne $h2.inputHash) '판정 모델이 다르면 해시가 다르다(캐시 무효화)'

Write-Host '== (3) 평가 대상 축소: TTL / 틱 상한 / 시간당 상한 =='
Reset-Env; Reset-Logs
Assert (-not (Test-ChecklistShadowSkip 9100 'pr-gate-sweep:PR-gate').Skip) '기록 없음 -> 스킵 안 함'
[void](Invoke-ChecklistShadowJudge 9100 'REVERT' 'pr-gate-sweep:PR-gate' 'c' $c1 $pr0)
$s = Test-ChecklistShadowSkip 9100 'pr-gate-sweep:PR-gate'
Assert ($s.Skip -and $s.Why -match 'TTL') '같은 (isn, source) 최근 기록 -> 스킵'
Assert (-not (Test-ChecklistShadowSkip 9100 'pr-gate-sweep:scope-gate').Skip) '같은 isn 이라도 다른 구룰 사유(source)는 스킵 안 함'
Assert (-not (Test-ChecklistShadowSkip 9101 'pr-gate-sweep:PR-gate').Skip) '다른 isn 은 스킵 안 함'
$env:GISSUE_CHECKLIST_SHADOW_TTL_HOURS = '0'
Assert (-not (Test-ChecklistShadowSkip 9100 'pr-gate-sweep:PR-gate').Skip) 'TTL=0 -> TTL 스킵 끔'
Reset-Env; Reset-Logs
$env:GISSUE_CHECKLIST_SHADOW_MAX_PER_TICK = '2'
[void](Invoke-ChecklistShadowJudge 9201 'REVERT' 's' 'c1' $c1 $pr0)
Assert (-not (Test-ChecklistShadowSkip 9202 's').Skip) '상한(2) 미만 -> 스킵 안 함'
[void](Invoke-ChecklistShadowJudge 9202 'REVERT' 's' 'c2' $c1 $pr0)
$s = Test-ChecklistShadowSkip 9203 's'
Assert ($s.Skip -and $s.Why -match '틱 호출 상한') '틱 호출 상한 초과 -> 스킵'
$script:ChecklistShadowJudgedThisRun = 0
Assert (-not (Test-ChecklistShadowSkip 9203 's').Skip) '새 프로세스(카운터 0)에서는 다시 평가'
[void](Invoke-ChecklistShadowJudge 9203 'REVERT' 's' 'c3' $c1 $pr0)
Reset-Env; Reset-Logs
$env:GISSUE_CHECKLIST_SHADOW_MAX_PER_HOUR = '2'
[void](Invoke-ChecklistShadowJudge 9301 'REVERT' 's' 'c1' $c1 $pr0)
[void](Invoke-ChecklistShadowJudge 9302 'REVERT' 's' 'c2' $c1 $pr0)
$script:ChecklistShadowJudgedThisRun = 0
$s = Test-ChecklistShadowSkip 9303 's'
Assert ($s.Skip -and $s.Why -match '1시간') '최근 1시간 합산 호출 상한 초과(다른 프로세스 기록 포함) -> 스킵'
$callsBefore = $script:calls
[void](Invoke-ChecklistShadowJudge 9301 'REVERT' 's2' 'c1' $c1 $pr0)
Assert ($script:calls -eq $callsBefore) '캐시 적중(cached)은 시간당 호출 수에 세지 않는다'

Write-Host '== (4) 실패 백오프 =='
Reset-Env; Reset-Logs
$script:stubResult = @{ ok = $false; text = 'timeout'; exit = 124 }
$r = Invoke-ChecklistShadowJudge 9400 'REVERT' 's' 'c' $c1 $pr0
Assert ($r.Action -eq 'failed') '호출 실패 -> failed'
Assert (-not (Test-Path -LiteralPath $logFile)) '실패는 checklist-shadow.jsonl(판정 기록)에 섞지 않는다'
Assert (@(Read-Recs $failFile).Count -eq 1) '실패는 checklist-shadow-failures.jsonl 에 기록'
$s = Test-ChecklistShadowSkip 9400 's'
Assert ($s.Skip -and $s.Why -match '백오프') '백오프 시간 안에는 같은 (isn, source) 재시도 안 함 -> 재시도 폭주 없음'
Assert (-not (Test-ChecklistShadowSkip 9400 'other').Skip) '다른 source 는 영향 없음'
$env:GISSUE_CHECKLIST_SHADOW_FAIL_BACKOFF_MIN = '0'
Assert (-not (Test-ChecklistShadowSkip 9400 's').Skip) '백오프=0 -> 끔'
$script:stubResult = @{ ok = $true; text = '항목 없는 설명'; exit = 0 }
Reset-Env; Reset-Logs
$r = Invoke-ChecklistShadowJudge 9401 'REVERT' 's' 'c' $c1 $pr0
Assert ($r.Action -eq 'failed' -and (Test-ChecklistShadowSkip 9401 's').Skip) '파싱 실패도 실패로 취급되어 백오프'
$script:stubResult = @{ ok = $true; text = "ITEM|other|UNMET|문서를 등록한다|증거 없음`nITEM|other|MET|보고한다|코멘트 1"; exit = 0 }

Write-Host '== (5) 끄기: GISSUE_CHECKLIST_SHADOW_REDUCE=off =='
Reset-Env; Reset-Logs
$env:GISSUE_CHECKLIST_SHADOW_REDUCE = 'off'
[void](Invoke-ChecklistShadowJudge 9500 'REVERT' 's' 'c' $c1 $pr0)
Assert (-not (Test-ChecklistShadowSkip 9500 's').Skip) 'off -> TTL 스킵 없음'
$before = $script:calls
$r = Invoke-ChecklistShadowJudge 9500 'REVERT' 's' 'c' $c1 $pr0
Assert ($r.Action -eq 'judged' -and $script:calls -eq $before + 1) 'off -> 같은 입력도 캐시 없이 재호출(이전 동작)'
$env:GISSUE_CHECKLIST_SHADOW_MAX_PER_TICK = '1'
Assert (-not (Test-ChecklistShadowSkip 9501 's').Skip) 'off -> 상한도 적용 안 함'
Reset-Env

Write-Host '== (6) Live 경로 불변: 캐시/기록을 쓰지 않는다 =='
Reset-Logs
$before = $script:calls
$a1 = Invoke-ChecklistAssessment 9600 'c' $c1 $pr0
$a2 = Invoke-ChecklistAssessment 9600 'c' $c1 $pr0
Assert ($script:calls -eq $before + 2) 'Invoke-ChecklistAssessment 는 같은 입력도 매번 LLM 호출(캐시 없음)'
Assert (-not (Test-Path -LiteralPath $logFile) -and -not (Test-Path -LiteralPath $failFile)) 'Invoke-ChecklistAssessment 는 Shadow 로그를 쓰지 않는다'
Assert ($a1.Decision -eq $a2.Decision) 'Live 판정 결과는 입력이 같으면 같다'
$body = (Get-Command Invoke-ChecklistAssessment).ScriptBlock.ToString()
Assert ($body -notmatch 'Shadow') 'Invoke-ChecklistAssessment 본문이 Shadow 함수를 참조하지 않는다'
$rda = Get-Content -LiteralPath (Join-Path $gissueDir 'review-done-audit.ps1') -Raw -Encoding UTF8
$shadowIdx = $rda.IndexOf('Test-ChecklistShadowSkip'); $liveIdx = $rda.IndexOf('Get-AuditChecklistAssessment $iss $comments $repos')
Assert ($shadowIdx -gt 0 -and $liveIdx -gt $shadowIdx -and ([regex]::Matches($rda, 'Test-ChecklistShadowSkip')).Count -eq 1) 'review-done-audit: 스킵 검사는 Shadow 분기 안에만 있고 Live 분기(else)는 그대로 직접 판정'

Write-Host '== (6b) 입력 인코딩: 판정 LLM 에 한글을 stdin 으로 넘기는 스크립트는 UTF-8 을 고정한다 =='
foreach ($sn in 'review-done-audit.ps1', 'pr-gate-sweep.ps1') {
    $src = Get-Content -LiteralPath (Join-Path $gissueDir $sn) -Raw -Encoding UTF8
    Assert (($src -match '(?m)^\$OutputEncoding\s*=\s*\[System\.Text\.Encoding\]::UTF8') -and ($src -match '(?m)^\[Console\]::OutputEncoding\s*=\s*\[System\.Text\.Encoding\]::UTF8')) "$sn 가 `$OutputEncoding/Console 출력을 UTF-8 로 고정(없으면 한글이 깨져 Shadow 판정이 파싱 실패)"
}
Write-Host '== (7) 동시 쓰기: 3 프로세스 x 15줄 =='
Reset-Logs
$libPath = Join-Path $gissueDir 'gissue-audit-lib.ps1'
$jobs = 1..3 | ForEach-Object {
    $w = $_
    Start-Job -ArgumentList $libPath, $env:GISSUE_CHECKLIST_SHADOW_DIR, $w -ScriptBlock {
        param($lib, $dir, $w)
        $env:GISSUE_CHECKLIST_SHADOW_DIR = $dir
        . $lib
        $ok = 0
        1..15 | ForEach-Object { if (Add-ChecklistShadowJsonLine 'checklist-shadow.jsonl' ([ordered]@{ ts = (Get-Date).ToUniversalTime().ToString('o'); isn = $w * 100 + $_; text = '동시쓰기 한글' })) { $ok++ } }
        $ok
    }
}
$res = @($jobs | Wait-Job -Timeout 120 | Receive-Job)
$jobs | Remove-Job -Force
$lines = @(Get-Content -LiteralPath $logFile -Encoding UTF8 | Where-Object { $_.Trim() })
$parsed = 0; foreach ($l in $lines) { try { [void]($l | ConvertFrom-Json); $parsed++ } catch { } }
Assert (($res | Measure-Object -Sum).Sum -eq 45) '45건 모두 쓰기 성공 반환(잠금 시 재시도)'
Assert ($lines.Count -eq 45 -and $parsed -eq 45) '45줄 전부 유실·손상 없이 파싱된다'

if (Test-Path -LiteralPath $tmpRoot) { Remove-Item -LiteralPath $tmpRoot -Recurse -Force }
$env:GISSUE_CHECKLIST_SHADOW_DIR = $null
if ($fail -gt 0) { Write-Host "`n$fail 건 실패" -ForegroundColor Red; exit 1 }
Write-Host "`n전체 통과"
exit 0
