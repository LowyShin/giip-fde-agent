# gair-gate.ps1 — gair(giip AI API 라우터, giip #5671) 경유 허용 판정의 공통 라이브러리.
#
# 배경: gair 허용 CSN 목록(env GISSUE_GAIR_CSNS)의 해석이 러너(run-gissue-claude.ps1) 안에
#   인라인으로만 있어, 같은 목록을 봐야 하는 다른 호출부(게이트 판정 — gissue-audit-lib.ps1)가
#   목록 해석을 복제하거나 목록 자체를 모르는 상태였다. 목록 해석의 정본을 이 파일 하나로 모은다.
#   (lib/repomaint-gate.ps1 · lib/unmapped-csn-guard.ps1 와 같은 "판정 정본 분리" 컨벤션.)
#
# 목록 규칙:
#   - 쉼표 구분, 항목 앞뒤 공백은 무시한다.
#   - env GISSUE_GAIR_CSNS 가 **미설정**이면 기본값은 gair 설정이 등록된 플랫폼 CSN 하나뿐이다
#     (gair 설정을 모르는 호스트가 전 CSN 으로 새지 않게 하는 fail-safe — 종전 러너 동작 그대로).
#   - 목록에 '*' 가 포함되면 **전 CSN 허용**이다. 플랫폼 측 gair 허용 등록(tSystemParameter
#     category='gair', param_key='access.enabled')이 전 CSN 으로 확장된 뒤에 쓰는 값이다.
#   - env 가 빈 문자열로 설정돼 있으면 빈 목록 = 아무 CSN 도 허용하지 않는다(종전 동작 그대로).
#
# 이 파일은 판정만 한다(부작용 없음). gair 를 끄는 스위치(GISSUE_GAIR=0 등)와 AK 파생은
#   호출부가 맡는다.

# 허용 목록을 배열로 돌려준다. $Raw 를 주면 그 값을, 안 주면 env(미설정 시 기본값)를 해석한다.
# 주의: [string] 파라미터는 생략 시 $null 이 아니라 빈 문자열로 바인딩되므로(실측),
#   "인자를 줬는가"는 $PSBoundParameters 로 판정한다. -Raw '' 를 명시하면 빈 목록이 된다.
function Get-GissueGairCsnList {
    param([AllowNull()][string]$Raw)
    if (-not $PSBoundParameters.ContainsKey('Raw')) {
        $Raw = if ($null -eq $env:GISSUE_GAIR_CSNS) { '47' } else { $env:GISSUE_GAIR_CSNS }
    }
    if ($null -eq $Raw) { $Raw = '' }
    return @($Raw -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

# CSN 이 허용 목록에 드는가. '*' 항목이 있으면 무조건 허용이다.
# $List 를 안 주면 Get-GissueGairCsnList() 로 현재 env 를 해석한다.
function Test-GissueGairCsnAllowed {
    param([string]$Csn, [array]$List)
    if ($null -eq $List) { $List = @(Get-GissueGairCsnList) }
    if ($List -contains '*') { return $true }
    return ($List -contains "$Csn")
}
