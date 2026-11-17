# test-comment-model-tagging.ps1 — gissue 엔진이 쓰는 코멘트의 "사용 모델" 표기 회귀 테스트 (giip #5449)
#
# 왜 필요한가:
#   #5449 요구 — AI 엔진이 작성하는 모든 이슈 코멘트에 그 코멘트를 만든 실제 모델명이 표기되어야 한다.
#   엔진(claude 프로세스)은 자기 모델을 알 수 없고 러너(호스트)만 안다 → 러너가 프롬프트 맨 앞에
#   [실행 모델] 라인을 주입해 엔진이 그 값을 코멘트에 적게 한다. 이 주입/표기가 어느 한 경로에서
#   조용히 빠지면 그 경로가 만든 코멘트는 모델 표기 없이 나간다(정적으로는 티가 안 나는 회귀).
#
# 고정하는 것 — run-gissue-claude.ps1 안의 "AI 엔진이 코멘트를 쓰는" 모든 경로:
#   1) MiniMax 우선 시도(Invoke-GissueMinimaxAttempt): [실행 모델] 라인을 프롬프트 앞에 붙여 호출
#   2) claude 폴백(Invoke-GissueEngine): 폴백 프롬프트 앞에 [실행 모델] 라인
#   3) claude 직접 실행(Invoke-GissueEngine): 직접 프롬프트 앞에 [실행 모델] 라인
#   4) CJK-QA 2차 판정(Test-GissueCjkContamination): claude 판정 결과 코멘트에 "사용 모델: <모델>" 표기
#   또한 공통 블록(러너 프롬프트)이 "모든 코멘트에 사용 모델 표기" 지시를 담고 있는지.
#   음성 가드: 모델 라인을 붙이지 않은 원본 프롬프트 변수($PromptText/$fallbackPrompt)가 claude 로
#   직접 파이프되지 않는지(= 주입을 우회하는 호출이 새로 생기지 않았는지).
#
# 왜 소스 단언 방식인가:
#   위 함수들은 run-gissue-claude.ps1 안의 잡 스크립트블록($jobScript) 내부에 정의돼 있어 개별
#   dot-source 가 불가능하다. 엔진은 실제 `& claude` 프로세스를 띄우므로 행위 테스트는 claude 스텁과
#   잡 블록 추출이 필요하다. 이 레포의 가드 테스트 관례(test-stale-code-guard.ps1 등과 동일)에 따라,
#   주입/표기 코드가 각 경로에 실재하는지를 소스 단언으로 고정해 "조용한 제거"를 막는다.
#
# 실행:
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gissue/tests/test-comment-model-tagging.ps1
# 종료코드: 0 = 전건 PASS, 1 = 1건 이상 FAIL

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'

$script:Pass = 0
$script:Fail = 0
function Assert-True($cond, $name, $detail = '') {
    if ($cond) { $script:Pass++; Write-Output "  PASS  $name" }
    else { $script:Fail++; Write-Output "  FAIL  $name$(if ($detail) { " — $detail" })" }
}

$runnerPath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\run-gissue-claude.ps1')).Path
$src = Get-Content -LiteralPath $runnerPath -Raw

Write-Output '1. MiniMax 우선 경로 — [실행 모델] 주입'
Assert-True ($src.Contains('$mmModelLine = "[실행 모델]')) '1a MiniMax 모델 라인 정의'
Assert-True ($src.Contains("MiniMax 모델 '`$MinimaxModel'")) '1b 실제 MiniMax 모델 변수 사용'
Assert-True ($src.Contains('$mmPrompt = "$mmModelLine')) '1c 모델 라인을 프롬프트 앞에 결합'
Assert-True ($src.Contains('$mmPrompt | & claude')) '1d claude 호출이 모델 포함 프롬프트를 사용'

Write-Output ''
Write-Output '2. claude 폴백 경로 — [실행 모델] 주입'
Assert-True ($src.Contains('$claudeModelLine = "[실행 모델]')) '2a claude 모델 라인 정의'
Assert-True ($src.Contains('$fallbackPromptWithModel = "$claudeModelLine')) '2b 폴백 프롬프트 앞에 모델 라인 결합'
Assert-True ($src.Contains('$fallbackPromptWithModel | & claude')) '2c claude 폴백 호출이 모델 포함 프롬프트 사용'

Write-Output ''
Write-Output '3. claude 직접 실행 경로 — [실행 모델] 주입'
Assert-True ($src.Contains('$promptWithModel = "$claudeModelLine')) '3a 직접 프롬프트 앞에 모델 라인 결합'
Assert-True ($src.Contains('$promptWithModel | & claude')) '3b claude 직접 호출이 모델 포함 프롬프트 사용'

Write-Output ''
Write-Output '4. CJK-QA 2차 판정 코멘트 — 판정 모델 표기 (giip #5449 갭 보완)'
Assert-True ($src.Contains("`$qaJudgeModel = 'claude-haiku-4-5'")) '4a 판정 모델을 단일 출처로 정의'
Assert-True ($src.Contains('--model $qaJudgeModel')) '4b claude 판정 호출이 그 변수를 모델로 사용'
Assert-True ($src.Contains('사용 모델: $qaJudgeModel')) '4c 혼입 의심 코멘트 본문에 판정 모델 표기'

Write-Output ''
Write-Output '5. 공통 블록(러너 프롬프트) — 모든 코멘트에 사용 모델 표기 지시'
Assert-True ($src -match '그 코멘트를 작성한 AI 모델') '5a 공통 블록이 코멘트 모델 표기를 지시'

Write-Output ''
Write-Output '6. 음성 가드 — 모델 미주입 원본 프롬프트가 claude 로 직접 파이프되지 않음'
Assert-True (-not ($src -match '\$PromptText\s*\|\s*&\s*claude')) '6a $PromptText 원본이 claude 로 직접 파이프되지 않음'
Assert-True (-not ($src -match '\$fallbackPrompt\s*\|\s*&\s*claude')) '6b $fallbackPrompt 원본이 claude 로 직접 파이프되지 않음'

Write-Output ''
Write-Output "결과: PASS=$($script:Pass) FAIL=$($script:Fail)"
if ($script:Fail -gt 0) { exit 1 }
exit 0
