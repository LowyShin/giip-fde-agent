# 판정류 직접 호출 3곳의 gair 경유 배선 검증 (CJK-QA 2차 판정 / 무처리(NO_ACTION) 판정 / 페이지 피드백 판정).
# 실행: powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gissue/tests/test-gair-judges.ps1
# 네트워크·실제 claude 호출 없음 — 러너는 잡 스코프 안에서만 정의되는 함수들이라 소스 배선 점검으로
# 확인하고(게이트 판정 테스트 test-gair-gate.ps1 의 배선 점검과 같은 방식), 페이지 피드백은 순수
# 경로 결정 함수(Resolve-PfaJudgeRoute)를 직접 검증한다.
$ErrorActionPreference = 'Stop'
$gissueDir = Split-Path -Parent $PSScriptRoot

$fail = 0
function Check($name, [bool]$ok, $detail) {
    if ($ok) { Write-Output "[PASS] $name" } else { $script:fail++; Write-Output "[FAIL] $name - $detail" }
}

$runner = Get-Content -LiteralPath (Join-Path $gissueDir 'run-gissue-claude.ps1') -Raw -Encoding UTF8

# ── A. 무처리(NO_ACTION) 판정 — Invoke-GissueMinimaxAttempt ──────────────────
Check 'A1 시도 함수가 gair 계획 인자(GairBaseUrl/GairApiKey/GairRequired)를 받는다' ($runner -match '\[string\]\$GairBaseUrl = ''' -and $runner -match '\[string\]\$GairApiKey = ''' -and $runner -match '\[bool\]\$GairRequired = \$false') ''
Check 'A2 무처리 판정 gair 경유 로그가 있다' ($runner -match '\[GAIR\] 무처리 판정 gair 경유') ''
Check 'A3 무처리 판정 gair 필수·AK 없음이면 판정 생략으로 표면화한다' ($runner -match '\[GAIR\] 무처리 판정 gair 필수이나 AK 없음') ''
$attemptCalls = ([regex]::Matches($runner, '-GairBaseUrl \$GairBaseUrl -GairApiKey \$GairApiKey -GairRequired \$GairRequired')).Count
Check 'A4 엔진의 시도 호출 3곳(gair/1차/재시도)이 모두 계획을 넘긴다' ($attemptCalls -ge 3) "count=$attemptCalls"
$judgeDirect = ([regex]::Matches($runner, 'judgePrompt \| & claude -p --tools="" --setting-sources="" --model claude-haiku-4-5')).Count
Check 'A5 직접 판정은 종전 1곳(계획 없을 때)만 남는다' ($judgeDirect -eq 1) "count=$judgeDirect"

# ── B. CJK-QA 2차 판정 — Test-GissueCjkContamination ─────────────────────────
Check 'B1 CJK-QA 함수가 gair 계획 인자를 받는다' ($runner -match 'function Test-GissueCjkContamination\([^)]*\$GairBaseUrl') ''
Check 'B2 CJK-QA gair 경유 로그가 있다' ($runner -match '\[GAIR\] CJK-QA 판정 gair 경유') ''
Check 'B3 CJK-QA gair 필수·AK 없음이면 판정 생략으로 표면화한다' ($runner -match '\[GAIR\] CJK-QA 판정 gair 필수') ''
Check 'B4 CJK-QA 호출부가 이슈 세션 계획을 넘긴다' ($runner -match 'Test-GissueCjkContamination .*?-GairApiKey \$issueGairApiKey -GairRequired \$issueGairRequired') ''
Check 'B5 CJK-QA 코멘트 모델 표기가 경로 표기($qaModelNote)를 쓴다' ($runner -match '사용 모델: \$qaModelNote') ''
# 손상 가드 — 편집 전송 과정에서 키 대입문이 깨져 들어간 사고(2026-11-24, PR #557 사후 정정)의 재발 방지
Check 'B6 러너에 손상 토큰(<redacted>)이 없다' (-not $runner.Contains('<redacted>')) ''
Check 'B7 판정 2곳의 AK env 설정이 SetEnvironmentVariable 형태다' (([regex]::Matches($runner, [regex]::Escape("[Environment]::SetEnvironmentVariable('ANTHROPIC_API_KEY'"))).Count -ge 2) ''

# ── C. 페이지 피드백 판정 경로 결정 (순수 함수) ──────────────────────────────
. (Join-Path $gissueDir 'page-feedback-analyze.ps1')
$r1 = Resolve-PfaJudgeRoute $null
Check 'C1 계획 없으면 direct' ($r1.Route -eq 'direct') $r1.Route
$r2 = Resolve-PfaJudgeRoute @{ Active = $true; Required = $true; Csn = '47'; BaseUrl = 'https://example.invalid/api/gair'; Ak = 'AK-TEST'; CustomHeaders = 'x-functions-key: FK' }
Check 'C2 계획 Active 면 gair(모델 미고정)' ($r2.Route -eq 'gair' -and $r2.BaseUrl -eq 'https://example.invalid/api/gair' -and $r2.ApiKey -eq 'AK-TEST' -and $r2.Model -eq '') ''
$r3 = Resolve-PfaJudgeRoute @{ Active = $false; Required = $true; Csn = '47'; BaseUrl = ''; Ak = ''; CustomHeaders = '' }
Check 'C3 계획 Required·비활성이면 blocked' ($r3.Route -eq 'blocked') $r3.Route
$r4 = Resolve-PfaJudgeRoute @{ Active = $false; Required = $false; Csn = '47'; BaseUrl = ''; Ak = ''; CustomHeaders = '' }
Check 'C4 계획 비활성·비필수면 direct' ($r4.Route -eq 'direct') $r4.Route
$pfa = Get-Content -LiteralPath (Join-Path $gissueDir 'page-feedback-analyze.ps1') -Raw -Encoding UTF8
Check 'C5 판정 호출이 계획을 받아 경로를 정한다' ($pfa -match 'Invoke-PfaClaude\(\[string\]\$SystemPrompt, \[string\]\$UserPrompt, \[string\]\$MiniMaxKey, \[int\]\$TimeoutSec = 150, \[hashtable\]\$GairPlan') ''
Check 'C6 진입점이 계획을 해석해 Ctx 로 넘긴다' ($pfa -match 'Get-PfaGairPlan' -and $pfa -match 'GairPlan = \$gairPlan') ''

if ($fail -gt 0) { Write-Output "FAILED: $fail 건"; exit 1 }
Write-Output 'ALL PASS'
exit 0
