# test-scope-gate-pr-identification.ps1 — scope-gate 의 "평가 대상 PR 특정" 양방향 회귀 테스트
#                                          (giip #2504)
#
# 왜 필요한가 (2026-09-14 실사고):
#   scope-gate 는 "무관한 PR 로 완료 처리되는 것"을 막는 실제 방어선이다(giip #1195 실증).
#   그런데 2026-09-14 에 이 게이트가 **PR 번호를 특정하지 못한 채**(되돌림 코멘트에 `PR #()`)
#   "무관하다"고 판정해 csn 47 의 REVIEW 36건을 하루 만에 일괄 READY 로 되돌렸다.
#
#   원인은 Windows PowerShell 5.1 의 ConvertFrom-Json 빈 배열 함정이었다:
#       @('[]' | ConvertFrom-Json).Count  →  0 이 아니라 **1** (빈 Object[] 가 아이템 1개로 옴)
#   `gh pr list` 가 PR 0건일 때 내는 `[]` 가 "1건 찾음"으로 뒤집혀, Get-IssuePrInfo 가
#   `number=''` 인 가짜 PR 객체를 돌려줬다. 그 뒤 `gh pr view '' --json files` 는 번호 인자가
#   드롭돼 **현재 체크아웃 브랜치의 PR** diff 를 물어왔고, 그 무관한 diff 가 판정 입력이 됐다.
#
# 이 테스트가 고정하는 것(양방향 — 한쪽만 고정하면 게이트가 무력화되거나 오탐이 재발한다):
#   (A) 오탐 차단   : PR 을 특정하지 못한 상태는 **판정 자체가 불가능**해야 한다.
#                     빈 결과가 0건으로 정규화되고, 빈/비정상 번호는 거부되며,
#                     그런 번호로는 diff 조회(gh 호출)가 아예 일어나지 않는다.
#   (B) 게이트 유지 : 정상 PR 번호는 **그대로 통과**해야 한다. 여기서 과하게 막으면
#                     scope-gate 가 영구히 스킵돼 giip #1195 류 위조 완료를 못 막는다.
#
# 네트워크/SK/gh 불필요 — 전부 순수 함수에 합성 입력을 먹인다.
#   (Get-PrDiffSummary 케이스는 "존재하지 않는 레포 경로"를 넘긴다. 가드가 살아 있으면 gh 를
#    부르기 전에 반환하므로 통과하고, 가드가 사라지면 Push-Location 에서 터져 FAIL 로 드러난다.)
#
# 실행:
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gissue/tests/test-scope-gate-pr-identification.ps1
# 종료코드: 0 = 전건 PASS, 1 = 1건 이상 FAIL

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'
# 예기치 못한 종료성 예외가 나면 조용히 끝나 exit 0 으로 보이지 않도록 명시적으로 실패시킨다.
trap { Write-Output "  [FAIL] 예기치 못한 예외로 테스트가 중단됐다: $_"; exit 1 }

# gissue-audit-lib.ps1 은 최상위 실행부가 없어 dot-source 해도 부작용이 없다
# (gh/네트워크 호출은 전부 함수 안에서만 일어난다).
. (Join-Path $PSScriptRoot '..\gissue-audit-lib.ps1')

$fail = 0
$pass = 0
function Assert-Equal($name, $expected, $actual) {
    if ("$expected" -eq "$actual") {
        Write-Output "  [PASS] $name"
        $script:pass++
    } else {
        Write-Output "  [FAIL] $name — 기대='$expected' 실제='$actual'"
        $script:fail++
    }
}

Write-Output '=== (0) 재발 방지용 근본 원인 고정: PS 5.1 ConvertFrom-Json 빈 배열 함정 ==='
# 이 단언이 깨지는 날(=PowerShell 이 동작을 바꾼 날)에는 아래 정규화가 불필요해진 것이지만,
# 그때까지는 이 함정이 실재한다는 사실 자체를 코드로 못박아 둔다. 누가 ConvertFrom-GhJsonRows 를
# 걷어내고 `@(... | ConvertFrom-Json)` 관용구로 되돌리려 할 때 이 줄이 이유를 설명한다.
Assert-Equal '구 관용구 @("[]" | ConvertFrom-Json).Count 는 0 이 아니라 1 이다(함정 실재 확인)' 1 (@('[]' | ConvertFrom-Json).Count)

Write-Output '=== (A) 오탐 차단: PR 을 특정하지 못하면 판정 자체가 불가능해야 한다 ==='
Assert-Equal 'A1. gh 빈 결과 "[]" → 0건으로 정규화' 0 (ConvertFrom-GhJsonRows '[]').Count
Assert-Equal 'A2. gh 무응답(빈 문자열) → 0건'        0 (ConvertFrom-GhJsonRows '').Count
Assert-Equal 'A3. gh 무응답($null) → 0건'            0 (ConvertFrom-GhJsonRows $null).Count
Assert-Equal 'A4. 깨진 JSON → 0건(예외 대신 안전값)' 0 (ConvertFrom-GhJsonRows '{not json').Count

Assert-Equal 'A5. 빈 문자열 PR 번호는 거부(이번 사고의 `PR #()`)' $false (Test-ValidPrNumber '')
Assert-Equal 'A6. $null PR 번호는 거부'                            $false (Test-ValidPrNumber $null)
Assert-Equal 'A7. 공백뿐인 PR 번호는 거부'                         $false (Test-ValidPrNumber '   ')
Assert-Equal 'A8. 0 은 PR 번호가 될 수 없다'                       $false (Test-ValidPrNumber 0)
Assert-Equal 'A9. 음수는 PR 번호가 될 수 없다'                     $false (Test-ValidPrNumber -3)
Assert-Equal 'A10. 비숫자 문자열은 거부'                           $false (Test-ValidPrNumber 'abc')
Assert-Equal 'A11. "#816" 처럼 장식이 붙은 값은 거부(숫자만 허용)' $false (Test-ValidPrNumber '#816')
# 빈 Object[](= 이번 사고에서 $arr[0] 로 들어왔던 바로 그 값)의 .number 는 빈 문자열이다.
$trapRow = @('[]' | ConvertFrom-Json)[0]
Assert-Equal 'A12. 함정 행의 .number 로 만든 가짜 PR 객체는 거부된다' $false (Test-ValidPrNumber $trapRow.number)

# 번호가 유효하지 않으면 gh 를 아예 부르지 않는다 — 존재하지 않는 레포 경로를 넘겨 증명한다.
# (가드가 없으면 Push-Location 에서 예외가 나 이 케이스가 FAIL 로 드러난다.)
$ghost = 'C:\__no_such_repo_giip2504__'
$d1 = Get-PrDiffSummary $ghost '' $null
Assert-Equal 'A13. 빈 번호 → gh 호출 없이 files 빈 값' '' "$($d1.files)"
Assert-Equal 'A14. 빈 번호 → gh 호출 없이 diff 빈 값'  '' "$($d1.diff)"
$d2 = Get-PrDiffSummary $ghost $null $null
Assert-Equal 'A15. $null 번호 → gh 호출 없이 빈 값'    '' "$($d2.files)$($d2.diff)"

Write-Output '=== (B) 게이트 유지: 정상 PR 은 그대로 판정 대상이어야 한다(과잉 차단 금지) ==='
Assert-Equal 'B1. 정수 PR 번호는 유효'                 $true (Test-ValidPrNumber 816)
Assert-Equal 'B2. 문자열 PR 번호도 유효'               $true (Test-ValidPrNumber '759')
Assert-Equal 'B3. 앞뒤 공백이 있어도 유효'             $true (Test-ValidPrNumber ' 349 ')
Assert-Equal 'B4. 1 도 유효(경계값)'                   $true (Test-ValidPrNumber 1)
Assert-Equal 'B5. 큰 번호도 유효'                      $true (Test-ValidPrNumber 999999)

# gh 가 실제로 행을 돌려준 경우는 정상적으로 건수가 세어져야 한다(정규화가 과하면 게이트가 죽는다).
$oneRow = '[{"number":816,"url":"https://github.com/SHINSEMA/giipv3/pull/816","title":"t","headRefName":"feat/giip-2490-enter-project","state":"MERGED"}]'
$rows = @(ConvertFrom-GhJsonRows $oneRow)
Assert-Equal 'B6. PR 1건 응답 → 1건으로 센다'          1 $rows.Count
Assert-Equal 'B7. 그 행의 번호는 유효 판정'            $true (Test-ValidPrNumber $rows[0].number)
Assert-Equal 'B8. 필드가 보존된다(headRefName)'        'feat/giip-2490-enter-project' $rows[0].headRefName
$twoRows = '[{"number":750,"state":"MERGED"},{"number":751,"state":"OPEN"}]'
Assert-Equal 'B9. PR 2건 응답 → 2건으로 센다'          2 (ConvertFrom-GhJsonRows $twoRows).Count
# 단일 객체(배열이 아닌) 응답도 1건으로 다뤄야 한다(giipApi 단일행 응답 계열 대비).
Assert-Equal 'B10. 단일 객체 응답 → 1건'               1 (@(ConvertFrom-GhJsonRows '{"number":349}')).Count

Write-Output '=== (C) 슬러그 추출(판정 코멘트 증거에 쓰인다) ==='
Assert-Equal 'C1. PR URL → owner/repo' 'SHINSEMA/giipv3' (Get-RepoSlugFromUrl 'https://github.com/SHINSEMA/giipv3/pull/816')
Assert-Equal 'C2. 이상한 URL → $null'  '' "$(Get-RepoSlugFromUrl 'https://example.com/nope')"

Write-Output '=== (D) 체크아웃 없는 레포(slug:OWNER/REPO) 탐지 범위 — giip #2504 두 번째 결함 ==='
# 배경: giip #2477 의 산출물 PR 은 LowyShin/giipAgentLinux #33(MERGED) 인데, Get-NestedRepoPaths 가
#   "workdir 자신 + 바로 아래 + lowyworkenv" 만 훑어서 이 레포를 영원히 못 봤다 → PR-gate 가
#   "PR 없음"으로 REVIEW 를 되돌렸다. 이제 audit-extra-repos.json 의 슬러그를 덧붙인다.
$slugs = @(Get-ExtraAuditRepoSlugs)
Assert-Equal 'D1. audit-extra-repos.json 을 읽어 슬러그가 1개 이상 로드된다' $true ($slugs.Count -ge 1)
Assert-Equal 'D2. giipAgentLinux 가 목록에 있다(이번 사고의 실제 누락 레포)' $true ($slugs -contains 'LowyShin/giipAgentLinux')

# 안전장치 보존: workdir 트리에서 레포를 하나도 못 찾으면(=경로가 틀림) 추가 슬러그를 붙이면 안 된다.
#   붙여 버리면 "workdir 을 못 읽었다"가 "그 레포들엔 PR 이 없다"로 둔갑해, 나머지 레포의 PR 이
#   전부 '없음'으로 뒤집히고 대량 오탐 되돌림이 난다(Node 쪽 동일 가드는 test-pr-lookup.mjs 의
#   "존재하지 않는 workdir → 0개" 케이스가 지킨다).
#   lowyworkenv 자신은 $PSScriptRoot 에서 유도돼 **항상** 잡히므로 기대 건수는 그 1개다 —
#   가드가 없으면 여기에 슬러그 2개가 더 붙어 3이 된다(수정 전 실측값).
$bogusRepos = @(Get-NestedRepoPaths 'C:\__no_such_workdir_giip2504__')
Assert-Equal 'D3. workdir 탐색 실패 → lowyworkenv 1개뿐(추가 슬러그 미부착)' 1 $bogusRepos.Count
Assert-Equal 'D3b. 그 결과에 slug: 항목이 하나도 없다' 0 (@($bogusRepos | Where-Object { "$_" -like 'slug:*' })).Count

# Invoke-GhPrQuery 는 어떤 실패에도 예외를 던지지 않고 빈 목록을 돌려줘야 한다
# (여기서 예외가 새어 나가면 스윕 전체가 중단돼 그날 게이트가 통째로 안 돈다).
Assert-Equal 'D5. 존재하지 않는 로컬 경로 → 예외 없이 0건' 0 (@(Invoke-GhPrQuery 'C:\__no_such_repo_giip2504__' @('pr','list','--json','number'))).Count
Assert-Equal 'D6. 빈 repoSpec → 예외 없이 0건'              0 (@(Invoke-GhPrQuery '' @('pr','list','--json','number'))).Count

# slug 스펙인데 --repo 슬러그가 같이 안 넘어오면 Push-Location 도 못 하므로 조회를 포기해야 한다
# (예전 코드라면 Push-Location 에서 예외가 났다).
$dslug = Get-PrDiffSummary 'slug:LowyShin/giipAgentLinux' 33 $null
Assert-Equal 'D7. slug 스펙 + 슬러그 미전달 → 예외 없이 빈 값' '' "$($dslug.files)$($dslug.diff)"

Write-Output ''
Write-Output "결과: PASS=$pass FAIL=$fail"
if ($fail -gt 0) { exit 1 }
exit 0
