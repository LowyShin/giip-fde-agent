# review-done-audit.ps1 — REVIEW/DONE 사후검증 확장 (giip #1123, pr-gate-sweep.ps1 상위 확장)
#
# 배경(giip #1123): pr-gate-sweep.ps1(giip #1077)은 REVIEW 큐에서 "대응 PR이 아예 없는" 이슈만
#   READY 로 되돌리고, DONE 은 의도적으로 손대지 않았다(오너 승인 필요 판단, giip #1077 조치 1번 갭).
#   이 스크립트는 그 갭을 메운다 — 매 시간 "최근 2시간 내 코멘트된 모든 REVIEW/DONE 이슈"를 대상으로:
#     - 분석/조사성 이슈(코드 변경 의도 없음) → 결과(result) 코멘트가 있으면 그대로 둔다(가짜-DONE
#       오탐 방지 — giip #1077 에서 DONE 을 통째로 제외했던 이유가 정확히 이 케이스였다).
#     - 수정/구현성 이슈 → PR 존재+머지 여부를 실제로 재검증해서:
#         · 머지 완료 확인 → DONE 확정 유지(REVIEW 는 이 스크립트가 강제로 DONE 승격하지 않는다 —
#           최종 판단은 사람 몫, giip #1123 결정표).
#         · DONE 인데 PR 이 없거나 미머지 → READY 로 되돌려 재처리(완료 위조 방지, 원 우려는 #1076류).
#         · REVIEW 인데 PR 은 있지만 미머지인 채 -StalePrHours(기본 24h) 넘게 방치 → READY.
#         · "다음 단계 필요"류 언급이 있는데 후속 이슈 번호가 스레드에 전혀 없으면 register-issue.js
#           로 후속 이슈를 자동 등록하고 그 번호를 코멘트(PROTOCOL_PROGRESS_COMMENT.md §7과 동일 원칙).
#
# pr-gate-sweep.ps1과의 역할 분담(중복 방지, giip #1123 명시 요구): "REVIEW + PR 이 아예 없음" 은
#   여전히 pr-gate-sweep.ps1 소관이다 — 이 스크립트는 그 케이스를 건드리지 않고 로그만 남긴다(두
#   스크립트가 서로 다른 마커로 같은 이슈를 동시에 되돌리는 혼선을 피하기 위함). 이 스크립트가 REVIEW
#   쪽에 새로 더하는 값은 "PR은 있지만 머지 없이 방치"뿐이고, 나머지(DONE 전체, 분석성 오탐 방지,
#   후속 이슈 자동화)가 순수 신규 영역이다. PR 존재/머지 판정 로직 자체는 gissue-audit-lib.ps1 에서
#   가져다 쓴다(중복 구현 금지 — 이슈 본문 명시 요구).
#
# 무한루프 방지(giip #1123 필수 요건 3가지, 각각 아래 코드에 대응 구현):
#   1. 동일 코멘트 반복 감지: 이번에 남기려는 코멘트를 정규화(타임스탬프/이슈번호/GUID 제거)해서
#      바로 직전 이 스크립트의 코멘트와 비교 — 같으면(=2회 연속 동일 결론) 그 코멘트 대신 WARN 전환
#      + 원인 코멘트를 남기고, 이후 이 이슈에 대한 자동 조치를 중단한다(사람이 룰을 고칠 때까지).
#   2. 후속이슈 생성 루프 차단: 같은 부모 이슈에서 트레일링 -RecentWindowHours(2h) 내
#      [REVIEW-AUDIT:FOLLOWUP-CREATED] 마커가 -FollowupLoopThreshold(기본 2)개 이상 이미 있으면
#      다음(=N+1번째) 생성을 하지 않고 부모를 WARN 전환.
#   3. 자기참조 방지(멱등성): 이슈의 "최신" 코멘트가 이 스크립트 자신이 남긴 것이면(그 이후 다른
#      작성자의 코멘트가 전혀 없으면) 이미 이번 상태를 확정 처리한 것으로 보고 재감사를 스킵한다.
#      → 이 스크립트 자신의 코멘트가 "최근 2시간 내 코멘트됨" 조건을 스스로 계속 갱신해 매시간
#        같은 이슈를 영원히 재검사하는 자기순환을 차단한다.
#
# WARN 상태값(giip #1123 완료조건 중 하나): giipdb/SP/pApiGiipIssuePutbyAK.sql 확인 결과
#   @status NVARCHAR(50) 이고 SP 안에 enum/CHECK 검증이 전혀 없다(status = ISNULL(@status, status)
#   뿐). tGiipIssue 테이블(Tables/tGiipIssue.sql, create_tGiipIssue.sql)에도 CHECK 제약이 없다.
#   즉 status 는 자유 문자열이라 WARN 은 스키마/SP 변경 없이 바로 쓸 수 있다 — 이 스크립트는 그대로
#   status=WARN 을 사용한다(대체 표현 방식으로 우회할 필요 없음).
#
# 배포 방식(giip #1123, 오너 확정): dry-run 우선. -Live 스위치를 "명시적으로" 주지 않으면(기본값)
#   어떤 코멘트 등록·상태 변경·이슈 생성도 하지 않고 "이렇게 판단했을 것"만 로그로 남긴다.
#   run-gissue-claude.ps1 의 Complete-Run 에는 아직 연결하지 않았다 — 별도 오너 승인 후 그 함수에서
#   Invoke-GissuePrGateSweep 바로 다음 줄에 이 스크립트 호출을 추가하면 되지만, 그건 이 이슈의 범위
#   밖이다(의도적 보류).
#
# NEEDS_DECISION 분기(giip #2374, 2026-09-12 신설, 우선순위: 아래 PASS 자동-DONE 로직보다 먼저 검사):
#   Modification 분류 + PR 머지 확인된 REVIEW 이슈는 원래 giip #2379 정책에 따라 곧바로 PASS→DONE
#   자동전이되지만, 이슈 코멘트 안에 사람의 직접 확인이 필요하다는 명시적 문구("사람 확인"/"직접
#   확인"/"테스트 방법(사람 확인용)", giip #2173 실사례 기준 EXACT 부분일치만 — 유사어/줄기 매칭 확장
#   금지, giip #1123 "애매하면 보류, 확실할 때만 전이" 원칙 계승)가 하나라도 있으면 그 PASS/자동-DONE
#   대신 `NEEDS_DECISION` 으로 전이하고, 감지된 문구와 그 코멘트 원문을 그대로 인용한 코멘트를 남긴다.
#   `NEEDS_DECISION` 은 giipdb `SPEC_GISSUE_SCHEDULER.md` §3 정의상 "구현·자동검증은 끝났고 사람의
#   직접 확인만 남은" 상태이며, `Get-GissueIssueQueue`(run-gissue-claude.ps1)가 이 상태를 조회 대상에
#   포함하지 않으므로 자동 처리 루프에서 안전하게 빠진다(사람이 DONE/READY/REVIEW 로 직접 전이하기
#   전까지 무한 재처리되지 않는다).
#
# 사용:
#   # 실 REVIEW/DONE 큐 관찰(항상 안전 — -Live 를 명시하지 않는 한 아무것도 바꾸지 않음)
#   powershell -NoProfile -ExecutionPolicy Bypass -File review-done-audit.ps1 -Csn 47 -Workdir "C:\...\giipprj" -ApiKey <SK>
#   # 프로덕션 전환 시(오너 승인 후에만): 위와 동일 호출에 -Live 추가
#   powershell -NoProfile -ExecutionPolicy Bypass -File review-done-audit.ps1 -Csn 47 -Workdir "C:\...\giipprj" -ApiKey <SK> -Live
#   # 단일 이슈 진단(상태 변경 없음 — 판정 로직 확인/루프브레이커 테스트용)
#   powershell -NoProfile -ExecutionPolicy Bypass -File review-done-audit.ps1 -Workdir "C:\...\giipprj" -ApiKey <SK> -DiagnoseIsn 1123
param(
    [int]$Csn = 0,
    [Parameter(Mandatory = $true)][string]$Workdir,
    [string]$ApiKey,

    [string]$ApiBaseUrl = "https://giipfaw.azurewebsites.net/api",
    [int]$DiagnoseIsn = 0,
    [switch]$Live,                      # 명시해야만 실제 코멘트/상태변경/이슈생성 — 기본은 dry-run(로그만)
    [switch]$DryRun,                    # pr-gate-sweep.ps1 관례와의 호환용 별칭 — 주면 -Live 를 무시하고 강제 dry-run
    [int]$FollowupLoopThreshold = 2,    # 트레일링 윈도 내 이 개수 이상 이미 생성됐으면 다음 생성을 막는다
    [int]$RecentWindowHours = 2,        # "최근 코멘트됨" 필터 윈도. 0 또는 음수 = 최근-코멘트 필터 무제한(수동 전체점검용, giip #2587). 루프브레이커#2 트레일링 윈도는 아래에서 최소 2h 로 별도 유지.
    [int]$StalePrHours = 24,            # REVIEW+PR있음(미머지)일 때 "방치"로 보는 기준(시간)
    [switch]$AllowWideLiveWindow        # "창 무제한(-RecentWindowHours 0) + -Live" 조합 허용. giip #2586(VERIFY-GATE fail-open) 수정 후에만 명시 — 없으면 그 조합을 거부한다(giip #2587 요건4, 자동 DONE 전이 범위 확대 방지).
)

$ErrorActionPreference = 'Stop'

# ── [giip #2613] 이 실행의 AI 행위자(actor) 고정 ───────────────────────────────
# 배경(실측 2026-09-16): giip 코멘트 최근 30일 작성자 1위가 `lowyshin.giip` 3,385건이었다.
#   이건 사람 계정이다(tCorpUser usn=156). 코멘트 SP 가 dbo.lwGetUSNbyat(@ak) 로 작성자를 정하는데,
#   이 함수의 마지막 폴백이 "SK 가 가리키는 CSn 의 tCorpUserRel.isPay=1 사용자"라서, csn 스코프 SK 로
#   코멘트를 쓰면 전부 그 CSn 의 결제자(=사람)에게 귀속됐다. authorUsn 도 거의 전부 NULL 이라
#   사후에 "어느 프로세스가 썼는지"를 확인할 방법이 없었다.
# 이 레포는 DB 직접접속 수단이 없으므로(giip #2645 이식) 쓰기 경로는 giipfaw API 하나뿐이다:
#   scripts/gissue/lib/post-comment.js / giipIssues PUT (giipfaw API) -> 이 주체의 AccessToken 으로 인증한다
# 주체 목록/명명 규칙: scripts/gissue/ai-actors.json, 절차: scripts/gissue/AI_ACTOR_ACCOUNTS.md
# 이 스크립트는 :07 스케줄러 계열 게이트다. author 라벨(gissue-review-audit)은 그대로 두고 계정만 붙인다 — 라벨은 자기 과거 코멘트를 찾는 멱등성 판정에 쓰이므로 갈아치우면 처리한 이슈를 다시 처리한다.
$env:GIIP_ACTOR = 'ai.dp01.gissue-scheduler'

# PR-존재/머지 판정 + 코멘트 조회 공유 로직(중복 구현 금지, giip #1123 명시 요구) — pr-gate-sweep.ps1
# 과 이 스크립트가 함께 dot-source 한다.
. (Join-Path $PSScriptRoot 'gissue-audit-lib.ps1')

$IsLive = [bool]$Live -and -not [bool]$DryRun   # -DryRun 이 있으면 무조건 dry-run 강제(둘 다 줘도 안전 쪽)
$WindowUnlimited = ($RecentWindowHours -le 0)   # 0/음수 = 최근-코멘트 필터 무제한(수동 전체점검, giip #2587)
$AuditAuthor = 'gissue-review-audit'
$RegisterIssueScript = Join-Path $PSScriptRoot 'register-issue.js'

function Write-AuditLog($msg) {
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Output "[$ts] [review-done-audit]$(if(-not $IsLive){' [DRYRUN]'}) $msg"
}

# ── VERIFY-GATE 러너 호출(giip #2586, rule 63 정본 형태) ──────────────────────────
# 용도: 이 스크립트의 VERIFY-GATE(아래 Invoke-AuditIssue 안)가 verify-runner.mjs 를 실행하고
#       그 **종료코드**(0=PASS/1=FAIL/2=블록없음/3=조회실패)를 받아오기 위한 유일한 통로.
# 처리: node 를 네이티브로 호출하고 stdout 만 변수로 받는다. 결과는 어디에도 저장하지 않고
#       호출자에게 [pscustomobject]{Exit, Output} 로 돌려줄 뿐이다(파일/DB 기록 없음).
#       실제 이슈 코멘트 기록은 러너 자신이 -WithComment(= -Live) 일 때만 수행한다.
# 소비처: Invoke-AuditIssue 의 VERIFY-GATE 분기(Exit → PASS/FAIL/SKIP/실행오류 판정,
#         Output → 실행오류 시 로그 본문).
#
# 왜 이 형태여야 하나(rule 63 = .agent/rules/63_ps51_native_stderr_is_terminating.md):
#   - 이전 구현은 `& node ... 2>&1 | Out-String` 이었다. Windows PowerShell 5.1 은
#     `$ErrorActionPreference='Stop'` + 네이티브 stderr 리다이렉트 조합에서 stderr 한 줄만 나와도
#     NativeCommandError 를 **종료성 오류**로 던진다. 그래서 $LASTEXITCODE 분기에 도달조차 못하고
#     바깥 try/catch 로 떨어져 게이트가 전 경로 fail-open 했다(giip #2586 실측: 10건 전부).
#   - 그래서 (a) 리다이렉트를 쓰지 않고 stderr 는 콘솔로 그냥 흘려보내며,
#     (b) 이 **함수 스코프에서만** Continue 로 내리고(스크립트 전체는 Stop 유지, rule 63 규칙 2),
#     (c) try/catch 로 삼키지 않고 $LASTEXITCODE 로 분기한다(rule 63 규칙 3).
#   - $LASTEXITCODE 를 127 로 선초기화하는 이유: node 자체가 없어 CommandNotFoundException 이 나면
#     $LASTEXITCODE 가 갱신되지 않는데, 0 으로 초기화했다면 그게 "PASS" 로 오독된다.
function Invoke-VerifyRunner {
    param(
        [Parameter(Mandatory = $true)][int]$Isn,
        [int]$Csn = 0,
        [switch]$WithComment
    )
    $ErrorActionPreference = 'Continue'
    $runner = Join-Path $PSScriptRoot 'verify-runner.mjs'
    $argv = @($runner, [string]$Isn)
    if ($Csn -gt 0) { $argv += [string]$Csn }
    if ($WithComment) { $argv += '--comment' }
    $global:LASTEXITCODE = 127
    $stdout = & node @argv
    $code = $LASTEXITCODE
    return [pscustomobject]@{
        Exit   = $code
        Output = (($stdout | Out-String).Trim())
        Argv   = ($argv -join ' ')
    }
}

# ISO8601('...Z') 문자열을 UTC DateTime 으로 정확히 파싱(RoundtripKind — 로컬 변환 오차 방지).
function Parse-Utc($s) {
    if (-not $s) { return $null }
    try {
        return [datetime]::Parse([string]$s, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime()
    } catch { return $null }
}

# 타임스탬프/이슈번호/GUID 등 매 실행마다 바뀌는 동적 부분을 제거해 "실질적으로 같은 결론"을 비교.
function Get-NormalizedText($s) {
    if (-not $s) { return '' }
    $t = [string]$s
    $t = [regex]::Replace($t, '\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}', '<TS>')
    $t = [regex]::Replace($t, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}', '<GUID>')
    $t = [regex]::Replace($t, '#\d+', '#N')
    $t = [regex]::Replace($t, '(?i)isn[=\s]+\d+', 'isn=N')
    $lines = $t -split '\r?\n' | ForEach-Object { $_.Trim() }
    return (($lines -join "`n").Trim())
}

# ── [giip #2645 이식] "이 코멘트를 내가 썼는가" 판정 ────────────────────────────
# 이 레포는 giipfaw API 로만 코멘트를 쓴다. API 경로에서는 author 를 클라이언트가 지정할 수 없고
# (pApiGiipIssueComment*byAK 가 인증 주체의 tCorpUser.uname 으로 강제한다) 서버가 정한다 — 그래서
# `author -eq 'gissue-review-audit'` 한 줄로만 판정하면 이 레포에서는 **자기 과거 코멘트를 영원히
# 못 찾아** 멱등성/루프브레이커가 전부 무력화되고 같은 이슈에 코멘트가 무한히 쌓인다.
# (pr-gate-sweep.ps1 이 같은 이유로 "마커 문자열만으로 판별한다"로 이미 바뀌어 있다.)
# 따라서 author 일치(직접-DB 경로 호환) **또는** 이 스크립트만 쓰는 `[REVIEW-AUDIT:` 마커 포함
# 으로 판정한다. 두 경로 어디서 쓴 코멘트든 동일하게 잡힌다.
$AuditMarkerPrefix = '[REVIEW-AUDIT:'
function Test-IsAuditComment($c) {
    if ($null -eq $c) { return $false }
    if ("$($c.author)" -eq $AuditAuthor) { return $true }
    return ($c.content -and "$($c.content)".Contains($AuditMarkerPrefix))
}

# 요건 3(멱등성): 최신 코멘트가 이 스크립트 자신이면 이미 확정 처리된 것으로 본다.
function Test-AlreadyFinalized($comments) {
    if (@($comments).Count -eq 0) { return $false }
    $sorted = @($comments | Sort-Object { $t = Parse-Utc $_.regdate; if ($t) { $t } else { [datetime]::MinValue } })
    $latest = $sorted[-1]
    return (Test-IsAuditComment $latest)
}

# 이 스크립트가 마지막으로 남긴 코멘트(가장 최근 1건). 없으면 $null.
function Get-LastAuditComment($comments) {
    $mine = @($comments | Where-Object { Test-IsAuditComment $_ } | Sort-Object { $t = Parse-Utc $_.regdate; if ($t) { $t } else { [datetime]::MinValue } })
    if (@($mine).Count -eq 0) { return $null }
    return $mine[-1]
}

# 요건 2용: 트레일링 -RecentWindowHours 내 [REVIEW-AUDIT:FOLLOWUP-CREATED] 마커 개수.
function Get-RecentFollowupCreatedCount($comments, $sinceUtc) {
    $n = 0
    foreach ($c in $comments) {
        if (-not (Test-IsAuditComment $c)) { continue }
        if (-not $c.content -or $c.content -notmatch '\[REVIEW-AUDIT:FOLLOWUP-CREATED\]') { continue }
        $rd = Parse-Utc $c.regdate
        if ($rd -and $rd -ge $sinceUtc) { $n++ }
    }
    return $n
}

# "다음 단계 필요"류 언급 탐지 + 이미 참조된 후속 이슈 번호 탐지(자기 자신 isn 은 제외).
$NextStepCues = @('다음 단계 필요', '다음 단계가 필요', '후속 이슈', '별도 이슈로 분리', '별도 이슈 등록', '추가 작업 필요', '남은 작업은', '후속 작업 필요',
    # giip #1364 추가(giip #1322 실제 관찰 문구 기준 — 기존 큐는 "다음 단계"류 명시적 표현만 잡아 이 케이스를
    # 놓쳤다): "코드 수정은 별도 세션에서 진행", "다음 세션이 이어받을 것" 같은, 이 세션이 스스로 마무리하지
    # 못하고 다른 세션/작업으로 넘긴다는 서술.
    '다음 세션', '별도 세션', '이어받을 것', '이어받아', '접수', '接手',
    '이 세션에서 완료할 수 없', '이 세션은 코드 수정을 완료할 수 없')
function Test-HasNextStepLanguage($allText) {
    foreach ($cue in $NextStepCues) { if ($allText -match [regex]::Escape($cue)) { return $true } }
    return $false
}
function Get-ReferencedIssueNumbers($allText, $selfIsn) {
    $nums = @()
    foreach ($m in [regex]::Matches($allText, '#(\d+)')) {
        $n = [int]$m.Groups[1].Value
        if ($n -ne $selfIsn) { $nums += $n }
    }
    return @($nums | Select-Object -Unique)
}

# 분류: 분석/조사성 vs 수정/구현성. 근사치 휴리스틱(giip #1123: "애매하면 UNCERTAIN 으로 스킵").
# 모디파이 신호가 하나라도 있으면 Modification 우선(실제로 코드가 바뀌었을 위험이 있으면 검증부터
# 하는 쪽이 안전 — 분석성으로 오분류해 검증을 건너뛰는 것보다 낫다).
$ModCues = @('수정', '구현', '추가해', '고쳐', '변경해', '구축', '개발해', '패치', '리팩터', '브랜치', '커밋', '배포', '풀리퀘', '풀 리퀘', '.ps1', '.js', '.tsx', '.ts', '.py', '.sql', '영향 파일', '변경 파일', '수정 파일', '코드 변경')
$AnalysisCues = @('조사', '분석', '원인', '점검해', '확인해줘', '확인 부탁', '리포트', '파악해', '진단해')
function Get-IssueClassification($allText, $latestCommentText) {
    # giip #1594: /errorproc 템플릿이 남긴 정형 문구(.ps1, .sql, "SP/쿼리 수정" 등)로
    # 오분류되는 문제를 방지하기 위해, 가장 최근 코멘트(실제 처리자의 최종 결론)를 우선 검사한다.
    # - 최신 코멘트에 ModCue가 있으면 → Modification (실제 구현이 있었음)
    # - 최신 코멘트에 ModCue가 없는데 전체 텍스트에는 있으면 → /errorproc 템플릿 오탐
    #   가능성. 이 경우 AnalysisCue를 먼저 봐서 분석 전용이면 AnalysisOnly로 우회.
    $latestText = if ($latestCommentText) { $latestCommentText } else { '' }
    $hasModInLatest = $false
    foreach ($cue in $ModCues) { if ($latestText -match [regex]::Escape($cue)) { $hasModInLatest = $true; break } }

    if ($hasModInLatest) { return 'Modification' }

    # 전체 텍스트에서 ModCue 검출 → 템플릿 오탐인지 분석 전용인지 판단
    $hasModInAll = $false
    foreach ($cue in $ModCues) { if ($allText -match [regex]::Escape($cue)) { $hasModInAll = $true; break } }

    $hasAnalysisInAll = $false
    foreach ($cue in $AnalysisCues) { if ($allText -match [regex]::Escape($cue)) { $hasAnalysisInAll = $true; break } }

    if ($hasModInAll) {
        # ModCue가 전체 텍스트에서만 잡혔고, 최신 코멘트에서는 안 잡혔음
        # → /errorproc 템플릿 오탐 가능성. 분석 전용 cue가 있으면 AnalysisOnly로 우회
        if ($hasAnalysisInAll) { return 'AnalysisOnly' }
        # ModCue만 있고 분석 cue가 없으면 UNCERTAIN(giip #1123: 애매하면 스킵)
        return 'Uncertain'
    }
    if ($hasAnalysisInAll) { return 'AnalysisOnly' }
    return 'Uncertain'
}

# REVIEW+PR있음(미머지)일 때 그 PR 이 얼마나 방치됐는지(시간) — 없으면 -1.
function Get-PrUpdatedAtHours($isn, $repos) {
    $isnRe = "(?<!\d)$isn(?!\d)"
    foreach ($repo in $repos) {
        Push-Location $repo
        try {
            $broad = gh pr list --state open --search "giip-$isn" --json headRefName,title,updatedAt 2>$null
            if ($LASTEXITCODE -eq 0 -and $broad) {
                $arr = $broad | ConvertFrom-Json
                foreach ($pr in @($arr)) {
                    if (($pr.headRefName -and $pr.headRefName -match $isnRe) -or ($pr.title -and $pr.title -match $isnRe)) {
                        $u = Parse-Utc $pr.updatedAt
                        Pop-Location
                        if (-not $u) { return -1 }
                        return [int]((Get-Date).ToUniversalTime() - $u).TotalHours
                    }
                }
            }
        } catch { }
        Pop-Location
    }
    return -1
}

function Write-AuditComment($isn, $body, $marker) {
    $firstLine = ($body -split "`n" | Select-Object -First 1)
    Write-AuditLog "isn=${isn}: [코멘트 예정 $marker] $firstLine"
    if (-not $IsLive) { return }
    # rule 63(giip #2586 동반 보완): 네이티브 호출에 stderr 리다이렉트를 쓰지 않는다. 이전 구현은
    # `... 2>&1 | Out-Null` 이었는데, 상단 $ErrorActionPreference='Stop' 과 만나면 자식 powershell 이
    # 경고 한 줄만 내도 NativeCommandError 가 종료성 오류가 되어 감사 전체가 그 줄에서 죽는다.
    # 이 함수 스코프에서만 Continue 로 내리고 $LASTEXITCODE 로 성패를 직접 확인한다.
    $ErrorActionPreference = 'Continue'
    $tmp = Join-Path $env:TEMP ("gissue_reviewaudit_note_{0}_{1}.txt" -f $isn, [guid]::NewGuid().ToString('N'))
    try {
        [System.IO.File]::WriteAllText($tmp, $body, (New-Object System.Text.UTF8Encoding $true))
        $global:LASTEXITCODE = 0
        # [giip #2645 이식] 이 레포는 DB 직접접속(giipdb/mgmt/addIssueComment.ps1)이 없다 —
        # pr-gate-sweep.ps1 과 동일하게 giipfaw API 경로(lib/post-comment.js: 등록 → 재조회 →
        # mojibake 검증 → 1회 재시도)를 쓴다. 본문은 UTF-8(BOM) 파일로 넘겨 한글/이모지 깨짐을
        # 막는다(giip #1030). author 라벨은 API 경로에서 클라이언트가 지정할 수 없고 $env:GIIP_ACTOR
        # 로 결정되므로($AuditAuthor 는 마커 기반 멱등성 판정에만 쓰인다) 인자로 넘기지 않는다.
        & node (Join-Path $PSScriptRoot 'lib\post-comment.js') $isn "@$tmp" $ApiKey $ApiBaseUrl 'note' | Out-Null
        if ($LASTEXITCODE -ne 0) { Write-AuditLog "isn=${isn}: [경고] 코멘트 등록 실패(post-comment.js exit=$LASTEXITCODE)" }
    } finally {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }
}

function Set-IssueStatusAudit($isn, $status, $reason) {
    Write-AuditLog "isn=${isn}: [상태변경 예정] -> $status"
    if (-not $IsLive) { return }
    if (-not $reason) { $reason = "review-done-audit: $status 로 전이" }
    # rule 63(giip #2586 동반 보완): 이 함수 스코프만 Continue 로 내려, 한 줄의 오류로 감사 전체가
    # 죽지 않게 한다. 상태전이는 감사의 최종 산출물이라 조용히 죽으면 안 된다.
    $ErrorActionPreference = 'Continue'
    # [giip #2645 이식] 이 레포는 DB 직접접속(giipdb/mgmt/updateIssueStatus.ps1)이 없다 —
    # pr-gate-sweep.ps1 의 Invoke-GissueReadyRevert 와 동일하게 giipfaw `PUT /giipIssues`
    # (status-only. pApiGiipIssuePutbyAK 가 title/content 를 ISNULL 로 보존한다) 를 쓴다.
    # -Actor/-Reason 은 이 API 에 대응 파라미터가 없다 — 사유 전문은 이 함수 직전에 Add-AuditComment
    # 가 남기는 `[REVIEW-AUDIT:...]` 결정 코멘트에 이미 들어가 있고, 행위자는 $env:GIIP_ACTOR
    # (ai.dp01.gissue-scheduler) 인증 주체로 기록되므로 정보 손실은 없다. 값이 JSON 본문으로만
    # 나가므로 giip #2404 의 커맨드라인 따옴표 이스케이프 함정도 이 경로에는 존재하지 않는다.
    try {
        $reqBody = @{ isn = $isn; status = $status } | ConvertTo-Json -Compress
        Invoke-RestMethod -Uri "$ApiBaseUrl/giipIssues" -Method Put -Body $reqBody -ContentType 'application/json' -Headers @{ 'x-api-key' = $ApiKey } | Out-Null
        Write-AuditLog "isn=${isn}: 상태전이 완료 -> $status (사유: $reason)"
    } catch {
        Write-AuditLog "isn=${isn}: [경고] 상태전이 실패(giipIssues PUT -> $status): $_"
    }
}

function New-FollowupIssueAudit($parentIsn, $title, $contentBody, $csn) {
    # 주의(실측 발견 버그, giip #1123): 이 함수는 호출부에서 `$newIsn = New-FollowupIssueAudit ...`
    # 처럼 반환값을 캡처한다 — 함수 내부에서 Write-AuditLog(=Write-Output)를 그냥 호출하면 그 출력도
    # 함수의 파이프라인 출력에 섞여 반환값이 배열로 오염된다(실측: 로그 줄이 코멘트 본문 중간에 그대로
    # 끼어들어가는 사고가 실제로 재현됨). 그래서 내부 로그 호출은 전부 `| Out-Null` 로 파이프라인에서
    # 제거한 뒤 `return` 으로만 값을 내보낸다.
    Write-AuditLog "isn=${parentIsn}: [후속 이슈 생성 예정] title='$title'" | Out-Null
    if (-not $IsLive) { return $null }
    # rule 63(giip #2586 동반 보완): stderr 리다이렉트 제거 + 이 스코프만 Continue.
    # 이전 구현(`... 2>&1`)은 node 가 경고 한 줄만 내도 NativeCommandError 로 죽었다. 이제 stdout 만
    # 캡처한다 — register-issue.js 는 등록 결과("giip issue #N")를 stdout 으로 낸다.
    $ErrorActionPreference = 'Continue'
    $tmp = Join-Path $env:TEMP ("gissue_reviewaudit_followup_{0}_{1}.txt" -f $parentIsn, [guid]::NewGuid().ToString('N'))
    try {
        [System.IO.File]::WriteAllText($tmp, $contentBody, (New-Object System.Text.UTF8Encoding $true))
        $global:LASTEXITCODE = 127
        $out = & node $RegisterIssueScript --title $title --content-file $tmp --status READY --csn $csn
        $registerExit = $LASTEXITCODE
        if ($registerExit -ne 0) {
            Write-AuditLog "isn=${parentIsn}: [경고] 후속 이슈 등록 실패(register-issue.js exit=$registerExit)" | Out-Null
        }
        foreach ($line in @($out)) {
            if ("$line" -match 'giip issue #(\d+)') { return [int]$Matches[1] }
        }
        Write-AuditLog "isn=${parentIsn}: 후속 이슈 등록 응답에서 isn 파싱 실패: $out" | Out-Null
        return $null
    } finally {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }
}

# 명시적 최종검수 PASS가 최신 외부 판단이면 PR 휴리스틱보다 우선한다.
# 운영복구/정상 보안동작/타 저장소 PR처럼 "nested PR 필수"가 성립하지 않는 완료를
# review-done-audit가 READY로 되돌리는 오탐(giip #1455/#1458/#1459) 방지.
function Test-HasCurrentFinalAcceptance($comments) {
    # ── 기존: [FINAL-REVIEW: PASS] 명시 마커 검사 ──
    $passComments = @($comments | Where-Object {
        "$($_.content)" -match '(?im)^##\s*(?:\[FINAL-REVIEW:\s*PASS\]|Final verification:\s*PASS)\s*$'
    })
    if ($passComments.Count -gt 0) {
        $latestPass = $passComments |
            Sort-Object { $t = Parse-Utc $_.regdate; if ($t) { $t } else { [datetime]::MinValue } } |
            Select-Object -Last 1
        $passTime = Parse-Utc $latestPass.regdate
        if ($passTime) {
            # PASS 뒤에 새 외부 피드백이 생겼으면 재검수를 허용한다.
            # 이 감사 자신이 남긴 REVERT/상태전이 코멘트는 PASS를 무효화하지 않는다.
            $newerExternal = @($comments | Where-Object {
                $t = Parse-Utc $_.regdate
                $t -and $t -gt $passTime -and -not (Test-IsAuditComment $_)
            })
            if ($newerExternal.Count -eq 0) { return $true }
        }
    }

    # ── giip #1570 / giip #1594 보강: inquiryStatus=DONE 검사 ──
    # gissue-agent가 DONE 상태로 전환한/latest 외부 코멘트가 있으면
    # ([FINAL-REVIEW: PASS] 없이도) 명시적 완료_confirmation으로 간주.
    # 단, 그 코멘트 이후 새 외부(비감사) 코멘트가 있으면 재검증 허용.
    $sortedComments = @($comments | Sort-Object {
        $t = Parse-Utc $_.regdate; if ($t) { $t } else { [datetime]::MinValue }
    })
    if ($sortedComments.Count -eq 0) { return $false }
    $latestNonAudit = $null
    for ($i = $sortedComments.Count - 1; $i -ge 0; $i--) {
        if (-not (Test-IsAuditComment $sortedComments[$i])) {
            $latestNonAudit = $sortedComments[$i]
            break
        }
    }
    if ($latestNonAudit -and "$($latestNonAudit.inquiryStatus)" -eq 'DONE') {
        $doneTime = Parse-Utc $latestNonAudit.regdate
        if ($doneTime) {
            $newerExternal = @($comments | Where-Object {
                $t = Parse-Utc $_.regdate
                $t -and $t -gt $doneTime -and -not (Test-IsAuditComment $_)
            })
            if ($newerExternal.Count -eq 0) { return $true }
        }
    }

    return $false
}

# ── giip #2424: "사람 확인 신호" 탐지 오탐 제거 ─────────────────────────────────────
# 배경(실측 표본 giip #2394, #2123, #2148, #2423): 원래 판정은 '사람 확인' / '직접 확인' 이라는
#   문자열의 단순 부분일치였다. 그 탓에 세션이 .agent/rules/51_verify_before_concluding.md 를
#   지켜 남긴 자기 검증 완료 보고("... 직접 확인 완료", "재조사 불필요")까지 사람 확인 요청으로
#   오판했다 — 규칙을 잘 지킨 이슈일수록 사람에게 떠넘겨지는 역설이 성립했다.
#
# 판정 규칙(giip #1123 "애매하면 REVIEW 유지, 확실할 때만 전이" 원칙은 그대로 유지한다):
#   1) 작성자 필터 — 봇/세션 계정이 쓴 코멘트, 그리고 loadedRole 이 채워진 코멘트(= 세션이 자기
#      역할을 기재하며 남긴 자기 기록)는 사람 확인 신호의 출처가 될 수 없으므로 통째로 건너뛴다.
#   2) 세션 진행 헤더 필터 — "[착수:" / "[완료:" / "[재개:" 등으로 시작하는 코멘트는 세션 자신의
#      진행 기록이다(작성자가 사람 계정 이름으로 기록돼 있어도 마찬가지다).
#   3) 요청형 문구 EXACT 부분일치 — 아래 $HumanConfirmRequestPhrases 의 "요청형" 문구만 신호로
#      인정한다. 완료형/보고형('직접 확인 완료', '직접 확인함' 등)은 애초에 목록에 없으므로
#      매치될 수 없다. 유사어/줄기 매칭은 하지 않는다(giip #2374 원설계 계승).
#   4) 출현 단위 검사 — 같은 문구가 한 코멘트에 여러 번 나올 수 있으므로 출현마다 따로 본다.
#      (a) 문구 바로 뒤에 완료/부정 어미가 붙으면(예: "사용자 확인 필요 없음") 요청이 아니다.
#      (b) 문구가 따옴표/백틱으로 감싸여 있거나 인용줄(">" 로 시작)에 있으면 다른 글의 인용이므로
#          요청이 아니다 — 판정 규칙 자체를 논의하는 코멘트가 스스로를 트리거하는 것을 막는다.
#      (c) [2026-09-16 추가] "발췌 구역"(아래 $HumanConfirmExcerptMarkers) 뒤쪽은 이 코멘트 자신의
#          주장이 아니라 다른 코멘트를 통째로 옮겨 붙인 인용이므로 요청이 아니다.
#
# [주의] 2026-09-14 이전 구현은 2)~4)를 if 블록 안에서 전부 `continue` 로 처리해, '테스트
#   방법(사람 확인용)' 분기까지 도달 불가능해지면서 Get-HumanConfirmSignal 이 항상 $null 을
#   반환했다(= NEEDS_DECISION 분기 전체가 죽은 코드). 아래 구조는 "요청형이면 return" 을 단일
#   경로로 두어 그 유형의 회귀가 재발하지 않게 한다.
#
# ── [giip #2424 2차, 2026-09-16] 봇 코멘트를 사람 신호로 오독하던 2단 연쇄 차단 ───────────────
# 실측(전 CSN 순회, NEEDS_DECISION 30건 중 csn 47 의 26건): 아래 2단 연쇄가 NEEDS_DECISION 을
#   대량 생산하고 있었다. 사람이 손으로 치울 때마다 다음 회차에 같은 수만큼 다시 쌓였다(33→28→32).
#     1단) `gissue-scope-gate` 가 PR 번호를 특정하지 못한 채(`PR #()`) MISMATCH 로 판정하고
#          `[SCOPE-GATE-REVERT]` 코멘트를 남긴다. 그 코멘트 말미에는 게이트 자신의 안내 문구
#          "최대 3 회를 초과하면 … REVIEW 유지 + **사람 확인 필요**로 전환됩니다." 가 들어 있다.
#     2단) 이 스크립트가 그 문구를 사람 확인 요청으로 감지해 REVIEW → NEEDS_DECISION 으로 전이한다.
#   즉 **봇이 남긴 정형 안내문을 다른 봇이 사람 신호로 오독**한 것이다. 사람은 아무 말도 하지 않았다.
#
# 왜 기존 $BotAuthors 로 못 막았나: 목록이 4개 하드코딩이었고 `gissue-scope-gate` 가 빠져 있었다.
#   2026-09-16 라이브 조회로 확인한 실제 author 값(추측 아님, giipIssueComments 응답 실측):
#     gissue-agent / gissue-review-audit / gissue-scope-gate / gissue-comment-gate /
#     gissue-scheduler-watchdog / gissue-pr-gate / gissue-pr-attribution / gissue-csn47 /
#     slack-bot / "Lowy Shin"
#   게이트가 새로 생길 때마다 `gissue-<이름>` 계정이 늘어나므로, 목록 나열만으로는 같은 사고가
#   반드시 재발한다. 그래서 **`gissue-` 접두사 전체를 봇으로 본다**(아래 $BotAuthorPrefixes).
#
# slack-bot 은 의도적으로 제외하지 않는다: 실측 표본은 전부 AI 세션 기록이었지만, 사람의 Slack
#   메시지가 그 계정으로 중계될 가능성을 배제할 근거를 찾지 못했다. 봇으로 오분류하면 진짜 사람
#   요청을 놓쳐 자동 DONE 으로 흘려보내게 되고(되돌릴 수 없는 방향), 사람으로 남겨두면 사람이 한 번
#   더 보게 될 뿐이다(되돌릴 수 있는 방향). 근거가 없을 때는 안전한 쪽에 둔다(giip #1123 원칙).
#
# $BotCommentMarkers: 게이트/감사 봇이 남기는 정형 마커. 계정명이 사람 이름으로 기록돼 있어도
#   본문이 이 마커로 시작하면 봇 출력이다(실제로 상태전이 코멘트가 "Lowy Shin" 명의로 남는 경로가
#   있다 — 봇 마스터 계정 uSn 29 를 공유하기 때문이다).

# 실측 확인된 봇 계정(2026-09-16 giipIssueComments 응답). 접두사 규칙과 중복되지만, 접두사 규칙이
# 회귀해도 최소한 이 목록은 막히도록 남겨 둔 다중 방어선이다.
$BotAuthors = @(
    'gissue-review-audit', 'gissue-agent', 'gissue-pr-gate', 'gissue-scheduler-watchdog',
    'gissue-scope-gate', 'gissue-comment-gate', 'gissue-pr-attribution', 'gissue-csn47'
)

# gissue 계열 봇 계정은 게이트가 늘어날 때마다 새로 생긴다 — 이름을 나열하지 않고 접두사로 막는다.
$BotAuthorPrefixes = @('gissue-')

# 본문이 이 마커로 시작하면 계정명과 무관하게 봇 출력이다.
$BotCommentMarkers = @(
    '[SCOPE-GATE-REVERT]', '[SCOPE-GATE-ESCALATED]', '[COMMENT-GATE-REVERT]',
    '[COMMENT-GATE-ESCALATED]', '[REVIEW-AUDIT:', '[PR-GATE-REVERT]', '[GATE-ESCALATED]',
    '[BUDGET]', '[VERIFY-GATE:', '[WATCHDOG]'
)

# 코멘트 본문에서 "여기부터는 다른 코멘트의 인용"이 시작되는 지점을 알리는 마커.
# review-done-audit 자신이 NEEDS_DECISION 코멘트에 쓰는 형식이 대표적이다:
#   "감지된 코멘트 발췌(author=gissue-scope-gate, regdate=...):" 다음 줄부터 원문을 통째로 붙인다.
$HumanConfirmExcerptMarkers = @('감지된 코멘트 발췌(', '감지된 코멘트 발췌:', '인용 원문:', '원문 인용:')

# 이 코멘트가 봇/세션이 남긴 것인가($true 면 사람 확인 신호의 출처가 될 수 없다).
function Test-IsBotComment($c) {
    $author = "$($c.author)".Trim()
    if ($BotAuthors -contains $author) { return $true }
    foreach ($p in $BotAuthorPrefixes) {
        if ($author.StartsWith($p, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    # loadedRole 이 채워졌다 = 세션이 자기 역할을 기재하며 남긴 자기 기록(사람 코멘트엔 없다).
    if ("$($c.loadedRole)".Trim()) { return $true }
    $content = "$($c.content)".TrimStart()
    foreach ($m in $BotCommentMarkers) {
        if ($content.StartsWith($m)) { return $true }
    }
    # "## [gissue-review-audit] ISN 1234 상태전이: ..." 처럼 머리말이 붙는 형태도 봇 출력이다.
    if ($content -match '^#{1,6}\s*\[gissue-[^\]]+\]') { return $true }
    return $false
}

# 이 코멘트에서 "인용 발췌 구역"이 시작되는 문자 인덱스. 없으면 -1.
function Get-ExcerptStartIndex([string]$content) {
    $best = -1
    foreach ($m in $HumanConfirmExcerptMarkers) {
        $i = $content.IndexOf($m)
        if ($i -ge 0 -and ($best -lt 0 -or $i -lt $best)) { $best = $i }
    }
    return $best
}

# 사람에게 확인/판단을 "요청"하는 문구만 담는다. 완료형/보고형은 절대 넣지 않는다.
$HumanConfirmRequestPhrases = @(
    '테스트 방법(사람 확인용)',
    '사람 확인 필요', '사람의 확인 필요', '사람 판단 필요', '사람의 판단 필요',
    '사람이 직접 확인', '사람이 확인해', '사람의 직접 확인이 필요',
    '사용자 확인 필요', '사용자 확인이 필요', '사용자 판단 필요', '사용자가 직접 확인',
    '오너 확인 필요', '오너 확인이 필요', '오너 판단 필요', '오너 결정 필요', '오너 최종 확인',
    '고객 확인 필요'
)

# 요청형 문구 바로 뒤에 붙으면 "요청"이 아니라 완료 보고/부정이 되는 어미들.
$HumanConfirmDoneTailPattern = '^\s*(완료|했|함|됨|되었|하였|끝|없음|없이|불필요|아님|아니)'
# 인용 표시로 쓰이는 따옴표류(문구 양쪽을 감싸면 다른 글의 인용으로 본다).
$HumanConfirmQuoteChars = @('"', "'", '`', '‘', '’', '“', '”', '「', '」')

# 문구의 특정 출현이 "실제 사람 확인 요청"인지 판정한다($true 면 신호로 채택).
function Test-HumanConfirmOccurrence([string]$content, [string]$phrase, [int]$idx) {
    $tail = $content.Substring($idx + $phrase.Length)

    # (c) 인용 발췌 구역(giip #2424 2차) — "감지된 코멘트 발췌(...)" 이후는 다른 코멘트를 통째로
    #     옮겨 붙인 인용이다. 그 안의 문구는 이 코멘트 작성자의 요청이 아니다.
    $excerptAt = Get-ExcerptStartIndex $content
    if ($excerptAt -ge 0 -and $idx -gt $excerptAt) { return $false }

    # (a) 완료/부정 어미가 뒤따르면 요청이 아니라 보고다.
    if ($tail -match $HumanConfirmDoneTailPattern) { return $false }

    # (b) 양쪽이 따옴표/백틱이면 다른 글(사양 문구 등)의 인용이다.
    $before = if ($idx -gt 0) { $content.Substring($idx - 1, 1) } else { '' }
    $after = if ($tail.Length -gt 0) { $tail.Substring(0, 1) } else { '' }
    if (($HumanConfirmQuoteChars -contains $before) -and ($HumanConfirmQuoteChars -contains $after)) { return $false }

    # (b') 마크다운 인용줄(">" 로 시작) 안이면 다른 코멘트의 인용이다.
    $lineStart = 0
    if ($idx -gt 0) {
        $nl = $content.LastIndexOf("`n", $idx - 1)
        if ($nl -ge 0) { $lineStart = $nl + 1 }
    }
    if ($content.Substring($lineStart, $idx - $lineStart) -match '^\s*>') { return $false }

    return $true
}

function Get-HumanConfirmSignal($comments) {
    $sorted = @($comments | Sort-Object { $t = Parse-Utc $_.regdate; if ($t) { $t } else { [datetime]::MinValue } })
    for ($i = $sorted.Count - 1; $i -ge 0; $i--) {
        $c = $sorted[$i]
        $content = "$($c.content)"
        if (-not $content) { continue }

        # ── 1. 작성자/출처 필터 ──────────────────────────────────────────────────────
        # 봇 계정(gissue-* 접두사 포함) · loadedRole 이 채워진 세션 자기 기록 · 게이트 정형 마커로
        # 시작하는 본문은 전부 봇 출력이므로 사람 확인 신호의 출처가 될 수 없다(giip #2424).
        if (Test-IsBotComment $c) { continue }

        # ── 2. 세션 진행 헤더 코멘트("[착수: ...]", "[완료: ...]", "[재개: ...]") ─────
        if ($content -match '^\s*\[?\s*(착수|완료|재개|진행|보류|중단)\s*[:：]') { continue }

        # ── 3~4. 요청형 문구 EXACT 부분일치 + 출현 단위 검사 ─────────────────────────
        foreach ($phrase in $HumanConfirmRequestPhrases) {
            $idx = $content.IndexOf($phrase)
            while ($idx -ge 0) {
                if (Test-HumanConfirmOccurrence $content $phrase $idx) {
                    return [pscustomobject]@{ Comment = $c; Phrase = $phrase }
                }
                if (($idx + 1) -ge $content.Length) { break }
                $idx = $content.IndexOf($phrase, $idx + 1)
            }
        }
    }
    return $null
}

# ── 이슈 1건 감사 ──
function Invoke-AuditIssue($iss, $repos) {
    $isn = [int]$iss.isn
    $status = "$($iss.status)"
    $comments = Get-IssueComments $isn $ApiKey $ApiBaseUrl
    # 루프브레이커#2 트레일링 윈도는 최소 2h 로 유지 — 최근-코멘트 필터를 무제한(-RecentWindowHours 0)으로
    # 돌려도 후속이슈 생성폭주 감지가 꺼지지 않게 한다(giip #2587).
    $followupWindowHours = if ($RecentWindowHours -gt 0) { $RecentWindowHours } else { 2 }
    $sinceRecent = (Get-Date).ToUniversalTime().AddHours(-$followupWindowHours)

    # 사람이 원문·전체 코멘트·현재 소스/운영을 대조해 남긴 최종 PASS는
    # PR 탐색 휴리스틱보다 높은 완료 증거다. PASS 이후 새 외부 피드백이 없을 때만 적용한다.
    if ($status -eq 'DONE' -and (Test-HasCurrentFinalAcceptance $comments)) {
        Write-AuditLog "isn=${isn}: 명시적 FINAL-REVIEW PASS 확인 — PR 휴리스틱 재되돌림 스킵."
        return
    }

    # 요건 3: 멱등성 — 이미 확정 처리됐고 그 이후 새 외부(비-감사) 코멘트가 없으면 재감사 스킵.
    if (Test-AlreadyFinalized $comments) {
        Write-AuditLog "isn=${isn}: 이미 확정 처리됨(최신 코멘트가 감사 자신) — 재감사 스킵(요건 3 멱등성)."
        return
    }

    $allTextParts = @($iss.title, $iss.content) + @($comments | ForEach-Object { $_.content })
    $allText = ($allTextParts -join "`n")

    # giip #1594: 최신 코멘트(실제 처리자의 최종 결론)를 추출해 Get-IssueClassification에 전달
    $sortedComments = @($comments | Sort-Object { $t = Parse-Utc $_.regdate; if ($t) { $t } else { [datetime]::MinValue } })
    $latestComment = if ($sortedComments.Count -gt 0) { $sortedComments[-1] } else { $null }
    $latestCommentText = if ($latestComment) { "$($latestComment.content)" } else { '' }

    $classification = Get-IssueClassification $allText $latestCommentText
    Write-AuditLog "isn=${isn} status=${status}: 분류=$classification"

    if ($classification -eq 'Uncertain') {
        Write-AuditLog "isn=${isn}: UNCERTAIN — 분류 애매, 추측하지 않고 조치 보류(스킵)."
        return
    }

    $decisionBody = $null; $decisionMarker = $null; $decisionNewStatus = $null

    if ($classification -eq 'AnalysisOnly') {
        $hasResultComment = @($comments | Where-Object { $_.issuetype -eq 'result' }).Count -gt 0
        if (-not $hasResultComment) {
            Write-AuditLog "isn=${isn}: 분석성이나 result 코멘트 없음 — 추측하지 않고 스킵."
            return
        }
        # giip #2402: Modification 분류의 "이미 DONE이면 FINAL/무해확인"과 대칭되는 가드 — 분석성
        # 이슈가 이미 DONE으로 확정됐으면, 무관한 새 코멘트가 붙을 때마다 PASS 코멘트를 반복 생성하지
        # 않는다(패턴B 실사례: isn=2110/2021이 재감사 때마다 동일 PASS를 반복해 loop-breaker#1에 걸림).
        if ($status -eq 'DONE') {
            Write-AuditLog "isn=${isn}: 분석성, 이미 DONE 확정 — 새 PASS 코멘트 생성 없이 조용히 스킵 (giip #2402)."
            return
        }
        $decisionBody = "[REVIEW-AUDIT:PASS] (재검증 시각: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))`n분석/조사성 이슈로 판단(결과 코멘트 확인됨) — DONE으로 전이합니다. (giip #1123 정책개정, 2026-09-12 사용자 지시: PASS는 자동 DONE)"
        $decisionMarker = 'PASS'; $decisionNewStatus = 'DONE'
    }
    elseif ($classification -eq 'Modification') {
        $hasMerged = Test-IssueHasMergedPr $isn $repos
        $hasAny = Test-IssueHasPr $isn $repos

        if ($hasMerged) {
            if ($status -eq 'DONE') {
                $decisionBody = "[REVIEW-AUDIT:FINAL] (재검증 시각: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))`n수정/구현성 이슈, 머지된 PR 확인됨 — DONE 확정 유지. (giip #1123 사후검증)"
                $decisionMarker = 'FINAL'
            } else {
                # giip #2374: PASS/자동-DONE(아래 else)보다 먼저, 사람의 직접 확인이 필요하다는 명시적
                # 신호가 코멘트에 있는지 검사한다. 있으면 자동 DONE 대신 NEEDS_DECISION 으로 전이한다.
                $humanConfirmSignal = Get-HumanConfirmSignal $comments
                if ($humanConfirmSignal) {
                    $excerpt = "$($humanConfirmSignal.Comment.content)"
                    if ($excerpt.Length -gt 500) { $excerpt = $excerpt.Substring(0, 500) + ' …(생략)' }
                    $decisionBody = "[REVIEW-AUDIT:NEEDS_DECISION] (재검증 시각: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))`n수정/구현성 이슈, 머지된 PR 확인됨 — 그러나 이슈 코멘트에 사람의 직접 확인이 필요하다는 명시적 문구(`"$($humanConfirmSignal.Phrase)`")가 감지되어, 자동 DONE 대신 NEEDS_DECISION 으로 전이합니다. (giip #2374, giip #1123 원칙 계승: 확실한 사람-확인 신호는 사람에게 넘김)`n`n감지된 코멘트 발췌(author=$($humanConfirmSignal.Comment.author), regdate=$($humanConfirmSignal.Comment.regdate)):`n> $excerpt`n`n사람이 직접 확인 후 완료로 판단되면 DONE으로, 문제가 있으면 READY 또는 REVIEW로 전이해 주세요."
                    $decisionMarker = 'NEEDS_DECISION'; $decisionNewStatus = 'NEEDS_DECISION'
                } else {
                    $decisionBody = "[REVIEW-AUDIT:PASS] (재검증 시각: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))`n수정/구현성 이슈, 머지된 PR 확인됨 — DONE으로 전이합니다. (giip #1123 정책개정, 2026-09-12 사용자 지시: PASS는 자동 DONE)"
                    $decisionMarker = 'PASS'; $decisionNewStatus = 'DONE'
                }
            }
        }
        elseif ($hasAny) {
            if ($status -eq 'DONE') {
                $decisionBody = "[REVIEW-AUDIT:REVERT] (재검증 시각: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))`nDONE 이지만 대응 PR이 머지되지 않았습니다(완료 위조 방지, giip #1123). READY 로 되돌려 재처리 대상으로 전환합니다.`n`n다음 작업자가 그대로 실행 가능한 체크리스트(giip #2085):`n- [ ] 이 isn 에 대응하는 PR이 실제로 머지됐는가(gh pr view <PR번호> --json state)`n- [ ] 머지되지 않았다면 왜 DONE 으로 전이됐는지(오판정 여부) 확인했는가`n- [ ] PR을 마저 머지하거나, PR이 불필요한 이슈라면 그 사유를 코멘트로 남겼는가"
                $decisionMarker = 'REVERT'; $decisionNewStatus = 'READY'
            } else {
                $prAgeH = Get-PrUpdatedAtHours $isn $repos
                if ($prAgeH -ge $StalePrHours) {
                    $decisionBody = "[REVIEW-AUDIT:REVERT] (재검증 시각: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))`nREVIEW 이지만 대응 PR이 미머지 상태로 약 ${prAgeH}시간 방치되어 있습니다(기준 ${StalePrHours}h). READY 로 되돌려 재처리 대상으로 전환합니다. (pr-gate-sweep.ps1 은 'PR 자체가 없는' 케이스만 다루므로 이 방치 케이스는 이 스크립트 소관, giip #1123)`n`n다음 작업자가 그대로 실행 가능한 체크리스트(giip #2085):`n- [ ] 열려있는 PR의 CI가 green인지 확인했는가(gh pr checks <PR번호>)`n- [ ] CI가 실패 중이라면 원인을 고쳐 다시 push했는가`n- [ ] 머지 가능한 상태인데 방치됐다면 지금 머지했는가"
                    $decisionMarker = 'REVERT'; $decisionNewStatus = 'READY'
                } else {
                    Write-AuditLog "isn=${isn}: REVIEW + PR 있음(미머지, 약 ${prAgeH}h < ${StalePrHours}h 기준) — 아직 방치로 보지 않음, 조치 없음."
                    return
                }
            }
        }
        else {
            if ($status -eq 'DONE') {
                # ── giip #2415: [NO-PR-REASON] 마커 감지 시 PR-gate REVERT 생략 ──
                if (Test-HasNoPrReasonMarker $comments) {
                    Write-AuditLog "isn=${isn}: DONE + PR 없음 + [NO-PR-REASON] 마커 감지 — review-done-audit REVERT 생략, DONE 유지(giip #2415)."
                } else {
                    $decisionBody = "[REVIEW-AUDIT:REVERT] (재검증 시각: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))`nDONE 이지만 대응 PR이 어느 nested 레포에도 없습니다(완료 위조 방지, giip #1123 — 원 배경은 #1077 조치1번 갭). READY 로 되돌려 재처리 대상으로 전환합니다.`n`n다음 작업자가 그대로 실행 가능한 체크리스트(giip #2085):`n- [ ] 이 isn 에 대응하는 브랜치/PR을 실제로 열었는가`n- [ ] PR이 필요 없는 이슈(설계 결정/조사/코멘트-답변형)라면 그 사유를 명시적으로 코멘트에 남겼는가(giip #2415: `[NO-PR-REASON]` 마커 코멘트를 함께 남기면 이 게이트가 더 이상 되돌리지 않습니다)"
                    $decisionMarker = 'REVERT'; $decisionNewStatus = 'READY'
                }
            } else {
                Write-AuditLog "isn=${isn}: REVIEW + PR 전혀 없음 — pr-gate-sweep.ps1 소관(중복 방지), 이 스크립트는 관여하지 않음."
                return
            }
        }
    }

    if (-not $decisionBody) { return }

    # 요건 1: 동일 코멘트 반복 감지(직전 감사 코멘트와 정규화 비교) — 결정 코멘트를 실제로 남기기 전에 검사.
    # giip #2402: "왕복 반복"의 진짜 신호는 REVERT 반복뿐이다. PASS/FINAL/NEEDS_DECISION이 직전과
    # 동일한 건 문제 재발이 아니라 무관한 새 코멘트가 붙을 때마다 같은 결론이 반복되는 정상 패턴(실제
    # 오탐 사례 giip #2132/#2121/#2119/#2098/#1951/#2110/#2021)이므로, REVERT가 아니면 코멘트도 남기지
    # 않고 조용히 스킵한다.
    $lastAudit = Get-LastAuditComment $comments
    if ($lastAudit) {
        $normNew = Get-NormalizedText $decisionBody
        $normOld = Get-NormalizedText $lastAudit.content
        if ($normNew -and $normNew -eq $normOld) {
            if ($decisionMarker -eq 'REVERT') {
                $warnBody = "[REVIEW-AUDIT:WARN] (감지 시각: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))`n이 이슈에 대해 감사 로직이 2회 연속 동일한 REVERT 판정을 반복했습니다(정규화 비교 일치). 근본 원인 추정: 되돌림(READY) 후에도 같은 문제(PR 미생성/미머지 등)가 그대로 재발했거나, 처리 담당 세션이 매번 같은 지점에서 멈추고 있을 가능성이 높습니다. 무한 왕복을 막기 위해 상태를 WARN 으로 전환하고 이 이슈에 대한 자동 조치를 중단합니다 — 사람이 근본 규칙/막힌 지점을 확인해 주세요. (giip #1123 무한루프 방지 요건 1, giip #2402로 REVERT 전용으로 범위 축소)"
                Write-AuditComment $isn $warnBody 'WARN'
                Set-IssueStatusAudit $isn 'WARN' "루프브레이커#1: 감사 판정이 2회 연속 동일한 REVERT(정규화 비교 일치) — 왕복 반복 의심, 자동조치 중단 (giip #1123, giip #2402)"
                Write-AuditLog "isn=${isn}: 루프브레이커#1(REVERT 반복) 발동 — WARN 전환, 이후 자동조치 중단."
            } else {
                Write-AuditLog "isn=${isn}: 판정 동일하나 REVERT 아니므로($decisionMarker) 무해 스킵 — 코멘트/상태변경 없음 (giip #2402)."
            }
            return
        }
    }

    # [VERIFY-GATE][giip #2418, rule 57] DONE 으로 보내기 전에 이슈에 적힌 기계 실행 가능한
    # 완료조건(verify 블록)을 **실제로 실행**한다. PR 머지 여부나 LLM 자기보고가 아니라 실행
    # 결과가 근거가 되게 하기 위함(2026-09-14: 프론트 PR 은 머지됐으나 SP 미배포로 화면이 죽어
    # 있는 상태를 '정상'으로 보고한 사고). 러너 종료코드 0=PASS/1=FAIL/2=블록없음/3=조회실패.
    # FAIL 이면 DONE 을 취소하고 READY 로 되돌린다. 블록이 없거나 오류면 기존 판정을 유지한다
    # (fail-open — 이 게이트가 스케줄러 전체를 멈추지 않게 한다).
    #
    # giip #2586(2026-09-16): 이 게이트는 위 fail-open 이 **모든 경로에서** 발동해 사실상 죽어 있었다.
    # 러너 호출은 이제 Invoke-VerifyRunner(위쪽 정의) 하나만 쓴다 — 네이티브 stderr 리다이렉트 금지,
    # try/catch 로 삼키지 않기, --comment 는 -Live 일 때만. 회귀 테스트:
    # scripts/gissue/tests/test-verify-gate-exit-contract.ps1
    if ($decisionNewStatus -eq 'DONE') {
        $verifyRunner = Join-Path $PSScriptRoot 'verify-runner.mjs'
        if (Test-Path $verifyRunner) {
            # csn: 스윕 모드는 -Csn 을 그대로 쓰지만 진단 모드(-DiagnoseIsn)는 $Csn 이 0 이다.
            # 0 을 그대로 넘기면 러너가 csn=0 으로 SK 를 찾는다 — 이슈 응답의 cSn 으로 보완한다(giip #2586).
            $verifyCsn = if ($Csn -gt 0) { $Csn }
                         elseif ($iss.cSn) { [int]$iss.cSn }
                         elseif ($iss.csn) { [int]$iss.csn }
                         else { 0 }
            # --comment 는 -Live 일 때만 붙인다. dry-run/진단 실행은 이슈에 아무것도 쓰지 않는다
            # (giip #2586 원인 C: 이전 구현은 -Live 와 무관하게 항상 --comment 를 붙였다).
            $verify = Invoke-VerifyRunner -Isn $isn -Csn $verifyCsn -WithComment:$IsLive
            $verifyExit = $verify.Exit
            $verifyOut = $verify.Output
            # try/catch 로 감싸지 않는다(rule 63 규칙 3) — 삼키면 아래 분기가 통째로 건너뛰어진다.
            if ($verifyExit -eq 0) {
                Write-AuditLog "isn=${isn}: [VERIFY-GATE] PASS - 완료조건 실행 통과, DONE 유지."
                $decisionBody = "$decisionBody`n`n[VERIFY-GATE] PASS - 이슈의 verify 블록을 실제로 실행해 통과했습니다(명령별 출력은 직전 [VERIFY-RUN] 코멘트 참조)."
            } elseif ($verifyExit -eq 1) {
                Write-AuditLog "isn=${isn}: [VERIFY-GATE] FAIL - 완료조건 실행 실패, DONE 취소하고 READY 로 되돌림."
                $decisionMarker = 'VERIFY-FAIL'
                $decisionNewStatus = 'READY'
                $decisionBody = "[VERIFY-GATE:FAIL] 완료조건 실행 실패로 DONE 을 취소합니다.`n이슈에 적힌 verify 블록을 실제로 실행한 결과 하나 이상이 exit!=0 이었습니다(직전 [VERIFY-RUN] 코멘트에 명령별 출력이 있습니다). PR 이 머지됐더라도 실제 동작이 확인되지 않았으므로 완료가 아닙니다. READY 로 되돌려 재처리합니다. (rule 57 / k-layer KNOW-021)"
            } elseif ($verifyExit -eq 2) {
                Write-AuditLog "isn=${isn}: [VERIFY-GATE] SKIP - verify 블록 없음, 기존 판정 유지."
                $decisionBody = "$decisionBody`n`n[VERIFY-GATE] SKIP - 이 이슈에는 기계 실행 가능한 완료조건(verify 블록)이 없어 실행 검증을 하지 못했습니다. 사용자가 제기한 불편이라면 rule 57 에 따라 verify 블록을 추가해야 합니다."
            } else {
                Write-AuditLog "isn=${isn}: [VERIFY-GATE] 실행 오류(exit=$verifyExit) - 기존 판정 유지. 명령: node $($verify.Argv) / 출력: $verifyOut"
            }
        }
    }

    Write-AuditComment $isn $decisionBody $decisionMarker
    if ($decisionNewStatus) {
        $decisionReasonLine = ($decisionBody -split "`n" | Select-Object -Skip 1 | Select-Object -First 1)
        Set-IssueStatusAudit $isn $decisionNewStatus $decisionReasonLine
    }

    # 후속 이슈 언어 스캔 — 위 결정 종류와 독립적으로 항상 확인(루프브레이커#2 적용).
    if (Test-HasNextStepLanguage $allText) {
        $refs = Get-ReferencedIssueNumbers $allText $isn
        if (@($refs).Count -gt 0) {
            Write-AuditLog "isn=${isn}: '다음 단계' 언급 있으나 이미 참조된 이슈 번호 발견($($refs -join ',')) — 중복 생성 안 함."
        } else {
            $recentFollowups = Get-RecentFollowupCreatedCount $comments $sinceRecent
            if ($recentFollowups -ge $FollowupLoopThreshold) {
                $warnBody = "[REVIEW-AUDIT:WARN] (감지 시각: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))`n이 이슈에서 트레일링 ${followupWindowHours}시간 내 후속 이슈가 이미 ${recentFollowups}건 자동 생성되어 임계값(${FollowupLoopThreshold})에 도달했습니다. 후속 이슈가 계속 생성되는데도 원 이슈가 해소되지 않는 폭주 패턴으로 판단해 추가 생성을 중단하고 WARN 으로 전환합니다 — 사람 확인 필요. (giip #1123 무한루프 방지 요건 2)"
                Write-AuditComment $isn $warnBody 'WARN'
                Set-IssueStatusAudit $isn 'WARN' "루프브레이커#2: 트레일링 ${followupWindowHours}시간 내 후속 이슈 ${recentFollowups}건 자동생성으로 임계값(${FollowupLoopThreshold}) 도달 — 추가 생성 중단, WARN 전환 (giip #1123)"
                Write-AuditLog "isn=${isn}: 루프브레이커#2(후속이슈생성폭주) 발동 — 추가 생성 중단, WARN 전환."
            } else {
                $fTitle = "[후속] $($iss.title) - 잔여 작업 (원본 giip #$isn)"
                $lastComment = ($comments | Sort-Object { $t = Parse-Utc $_.regdate; if ($t) { $t } else { [datetime]::MinValue } } | Select-Object -Last 1)
                $fBody = "giip #$isn 의 '다음 단계 필요' 언급을 review-done-audit.ps1(giip #1123) 이 감지해 자동 등록한 후속 이슈입니다.`n`n원본 이슈 제목: $($iss.title)`n원본 상태: $status`n`n원본 최신 코멘트 발췌:`n$($lastComment.content)"
                $newIsn = New-FollowupIssueAudit $isn $fTitle $fBody $Csn
                $refTxt = if ($newIsn) { "#$newIsn" } else { "(dry-run — 실제 등록 안 됨)" }
                $followupBody = "[REVIEW-AUDIT:FOLLOWUP-CREATED] (등록 시각: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))`n'다음 단계 필요' 언급을 감지해 후속 이슈 $refTxt 를 등록했습니다(READY). (giip #1123, PROTOCOL_PROGRESS_COMMENT.md §7과 동일 원칙)"
                Write-AuditComment $isn $followupBody 'FOLLOWUP-CREATED'
            }
        }
    }
}

# ── 진단 모드: 단일 isn 감사(상태변경은 -Live 없이는 안 함 — 루프브레이커 테스트용) ──
if ($DiagnoseIsn -gt 0) {
    if (-not $ApiKey) { throw "ApiKey(SK) 가 필요합니다." }
    $repos = Get-NestedRepoPaths $Workdir
    Write-AuditLog "진단: isn=$DiagnoseIsn, repos=$(@($repos | ForEach-Object { Split-Path -Leaf $_ }) -join ',')"
    $iss = $null
    try {
        $resp = Invoke-GiipApiGet "$ApiBaseUrl/giipIssues?isn=$DiagnoseIsn" $ApiKey
        if ($resp.issue) { $iss = $resp.issue }
        elseif ($resp -is [array]) { $iss = $resp | Select-Object -First 1 }
        elseif ($resp.data) { $iss = @($resp.data) | Select-Object -First 1 }
        else { $iss = $resp }
    } catch { Write-AuditLog "이슈 조회 실패: $($_.Exception.Message)"; return }
    if (-not $iss -or -not $iss.isn) { Write-AuditLog "이슈를 찾지 못함(isn=$DiagnoseIsn)."; return }
    Invoke-AuditIssue $iss $repos
    return
}

# ── 스윕 모드 ──
if (-not $ApiKey) { throw "ApiKey(SK) 가 필요합니다." }
if ($Csn -le 0) { throw "Csn 이 필요합니다." }

$repos = Get-NestedRepoPaths $Workdir
Write-AuditLog "시작: Csn=$Csn, repos=$(@($repos | ForEach-Object { Split-Path -Leaf $_ }) -join ',')"

$allIssues = @()
foreach ($st in @('REVIEW', 'DONE')) {
    try {
        $response = Invoke-GiipApiGet "$ApiBaseUrl/giipIssues?status=$st&csn=$Csn" $ApiKey
    } catch {
        Write-AuditLog "$st 조회 실패: $($_.Exception.Message)"
        continue
    }
    if ($response -is [array]) { $issues = $response }
    elseif ($response.issues) { $issues = $response.issues }   # 실측 응답 모양(giip #1123 확인) — {"issues":[...]}
    elseif ($response.data) { $issues = $response.data }
    elseif ($response.Table) { $issues = $response.Table }
    else { $issues = @($response) }
    $issues = @($issues | Where-Object {
        $csnValue = if ($_.cSn -ne $null) { $_.cSn } elseif ($_.csn -ne $null) { $_.csn } else { $null }
        $stValue = if ($_.status) { $_.status } else { $st }
        ($stValue -eq $st) -and ($csnValue -eq $Csn) -and $_.isn
    })
    $allIssues += $issues
}

if (@($allIssues).Count -eq 0) { Write-AuditLog "대상 REVIEW/DONE 이슈 없음 — 종료."; return }
if ($WindowUnlimited -and $IsLive -and -not $AllowWideLiveWindow) {
    Write-AuditLog "거부: '-RecentWindowHours $RecentWindowHours(창 무제한) + -Live' 조합은 자동 DONE 전이 범위를 넓히므로 giip #2586(VERIFY-GATE fail-open) 수정 전에는 금지됩니다(giip #2587 요건4). 넓은 창 관찰은 -Live 를 빼고(dry-run) 실행하거나, #2586 수정 후 -AllowWideLiveWindow 를 명시하세요."
    return
}
if ($WindowUnlimited) {
    Write-AuditLog "REVIEW+DONE 이슈 $(@($allIssues).Count)건 전체를 감사 — 창 무제한(-RecentWindowHours $RecentWindowHours) 수동 전체점검 모드(giip #2587)."
} else {
    Write-AuditLog "REVIEW+DONE 이슈 $(@($allIssues).Count)건 중 최근 ${RecentWindowHours}시간 내 코멘트된 것만 필터링."
}

$sinceRecent = (Get-Date).ToUniversalTime().AddHours(-$RecentWindowHours)
$targeted = 0
$outOfWindow = 0
foreach ($iss in $allIssues) {
    $isn = [int]$iss.isn
    if ($WindowUnlimited) {
        $targeted++
        Invoke-AuditIssue $iss $repos
        continue
    }
    $comments = Get-IssueComments $isn $ApiKey $ApiBaseUrl
    $hasRecent = $false
    foreach ($c in $comments) {
        $rd = Parse-Utc $c.regdate
        if ($rd -and $rd -ge $sinceRecent) { $hasRecent = $true; break }
    }
    if (-not $hasRecent) { $outOfWindow++; continue }
    $targeted++
    Invoke-AuditIssue $iss $repos
}
if ($WindowUnlimited) {
    Write-AuditLog "완료: 창 무제한 전체점검 — REVIEW+DONE $(@($allIssues).Count)건 전수 감사(대상 $targeted 건)."
} elseif ($targeted -eq 0 -and @($allIssues).Count -gt 0) {
    Write-AuditLog "[WARN] REVIEW+DONE $(@($allIssues).Count)건 중 최근 ${RecentWindowHours}시간 창에 걸린 것 0건 — 창 밖 방치 $outOfWindow 건이 감사되지 않았습니다. 이 '0건'은 정상 완료가 아니라 '창 밖 방치'일 수 있습니다. 수동 전체점검은 -RecentWindowHours 0 으로 실행하세요(giip #2587)."
} else {
    Write-AuditLog "완료: 최근 ${RecentWindowHours}시간 내 코멘트된 대상 $targeted 건 감사(창 밖 $outOfWindow 건 스킵)."
}
