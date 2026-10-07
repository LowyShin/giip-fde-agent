# review-merged-presweep.ps1 — REVIEW 이슈의 병합완료 자동 DONE 사전처리 (giip #3556)
#
# 목적: REVIEW 상태 이슈 중 "대응 PR이 모두 병합됨 + 사람의 직접 확인이 필요한
#       미해결 신호 없음" 조건을 LLM 호출 없이 결정적으로 판정해, 그 건을 큐가
#       claude 세션을 배정하기 전에 DONE으로 전이한다.
#
# 배경(giip #3535/#3536): review-done-audit.ps1은 Phase 2(세션 종료 후 스윕)에서
#   호출되므로, PR이 이미 병합된 REVIEW 이슈도 이번 사이클에 claude 세션을 먼저
#   배정받아 예산을 쓴 뒤 Phase 2에서야 DONE 처리된다. 이 사전필터는 Phase 1의
#   Get-GissueIssueQueue 호출 *이전*에 실행되어, 병합완료 REVIEW를 큐 진입 전에
#   DONE으로 전환한다.
#
# 판정 로직은 review-done-audit.ps1 / gissue-audit-lib.ps1의 기존 함수를 재사용한다:
#   - PR 머지 판정: Test-IssueHasMergedPr (gissue-audit-lib.ps1)
#   - Modification 분류: Get-IssueClassification (review-done-audit.ps1)
#   - 사람 확인 EXACT 문구 감지: Get-HumanConfirmSignal (review-done-audit.ps1)
#     (단순 부분일치 + 완료/보고형/인용/세션 진행 헤더/봇 코멘트 제외)
#
# 사용:
#   # DRY-RUN (기본값: 아무것도 바꾸지 않음)
#   powershell -NoProfile -ExecutionPolicy Bypass -File review-merged-presweep.ps1 -Csn 47 -Workdir "C:\...\giip-fde-agent" -ApiKey <SK>
#   # 실 실행 (-Live 명시 필요)
#   powershell -NoProfile -ExecutionPolicy Bypass -File review-merged-presweep.ps1 -Csn 47 -Workdir "C:\...\giip-fde-agent" -ApiKey <SK> -Live
#   # 단일 이슈 진단
#   powershell -NoProfile -ExecutionPolicy Bypass -File review-merged-presweep.ps1 -Workdir "C:\...\giip-fde-agent" -ApiKey <SK> -DiagnoseIsn 3556

param(
    [int]$Csn = 0,
    [Parameter(Mandatory = $true)][string]$Workdir,
    [string]$ApiKey,
    [string]$ApiBaseUrl = "https://giipfaw.azurewebsites.net/api",
    [int]$DiagnoseIsn = 0,
    [switch]$Live,                      # 명시해야만 실제 코멘트/상태변경 — 기본은 dry-run
    [switch]$DryRun,                   # -DryRun 주면 -Live 를 무시하고 강제 dry-run
    [string]$AgentRepo = ''            # giip-fde-agent 루트 — get-issue.sh 경유에 필요. 미지정이면 $Root 기준.
)

$ErrorActionPreference = 'Stop'

# ── [giip #2613] AI 행위자 고정 ────────────────────────────────────────────────
$env:GIIP_ACTOR = 'ai.dp01.gissue-scheduler'

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$LogDir = Join-Path $Root 'logs'
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Force -Path $LogDir > $null }
$LogFile = Join-Path $LogDir 'gissue_presweep.log'
$ListIssuesScript = Join-Path $Root 'list-issues.js'
# AgentRepo가 주어지면 그것을, 없으면 $Root(스크립트 기준)를 쓴다.
# run-gissue-claude.ps1 Start-Job 내부에서 호출될 때는 $AgentRepo가 전달되고,
# DRY-RUN 경로(메인 스코프)에서는 $AgentRepo='' 로기본값이 $Root 가 쓰인다.
$giipRoot = if ($AgentRepo) { $AgentRepo } else { $Root }
$GetIssueScript = Join-Path $giipRoot 'scripts/gissue/get-issue.sh'

# DRY-RUN 강제: -DryRun 이 있으면 -Live 를 무시한다
$IsLive = [bool]$Live -and -not [bool]$DryRun

# ── 공용 라이브러리 로드 (PR 판정 + 코멘트 조회) ─────────────────────────────────
# gissue-audit-lib.ps1 은 함수만 제공하므로 dot-source 한다.
. (Join-Path $Root 'gissue-audit-lib.ps1')

# review-done-audit.ps1 의 사람 확인 신호 감지 함수도 재사용한다.
# review-done-audit.ps1 은 Get-IssueClassification, Get-HumanConfirmSignal,
# Test-IsBotComment, Test-HumanConfirmOccurrence 등을 제공한다.
# 주의: review-done-audit.ps1 은 진입점이 있어서 직접 dot-source 할 수 없으므로
# 필요한 함수만 추출해 이 스크립트 안에局部으로 둔다(복붙이 아니라 의도된 재구성).

# ─────────────────────────────────────────────────────────────────────────────
# 사람 확인 요청 탐지 — review-done-audit.ps1 의 동일 함수 재구성 (giip #3556)
# ─────────────────────────────────────────────────────────────────────────────

$AuditAuthor = 'gissue-review-audit'
$AuditMarkerPrefix = '[REVIEW-AUDIT:'

# 실측 확인된 봇 계정
$BotAuthors = @(
    'gissue-review-audit', 'gissue-agent', 'gissue-pr-gate', 'gissue-scheduler-watchdog',
    'gissue-scope-gate', 'gissue-comment-gate', 'gissue-pr-attribution', 'gissue-csn47'
)
$BotAuthorPrefixes = @('gissue-')

$BotCommentMarkers = @(
    '[SCOPE-GATE-REVERT]', '[SCOPE-GATE-ESCALATED]', '[COMMENT-GATE-REVERT]',
    '[COMMENT-GATE-ESCALATED]', '[REVIEW-AUDIT:', '[PR-GATE-REVERT]', '[GATE-ESCALATED]',
    '[BUDGET]', '[VERIFY-GATE:', '[WATCHDOG]'
)

$HumanConfirmExcerptMarkers = @('감지된 코멘트 발췌(', '감지된 코멘트 발췌:', '인용 원문:', '원문 인용:')

# 완료/보고형 어미 — 요청형 문구 뒤에 이 어미가 오면 요청이 아닌 보고로 본다
$HumanConfirmDoneTailPattern = '^\s*(완료|했|함|됨|되었|하였|끝|없음|없이|불필요|아님|아니|하려면|하시려면|하는 방법|하는 절차|후[\s,])'
$HumanConfirmQuoteChars = @('"', "'", '`', '‘', '’', '“', '”', '「', '」')

function Test-IsBotComment($c) {
    $author = "$($c.author)".Trim()
    if ($BotAuthors -contains $author) { return $true }
    foreach ($p in $BotAuthorPrefixes) {
        if ($author.StartsWith($p, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    if ("$($c.loadedRole)".Trim()) { return $true }
    $content = "$($c.content)".TrimStart()
    foreach ($m in $BotCommentMarkers) {
        if ($content.StartsWith($m)) { return $true }
    }
    if ($content -match '^#{1,6}\s*\[gissue-[^\]]+\]') { return $true }
    return $false
}

function Get-ExcerptStartIndex([string]$content) {
    $best = -1
    foreach ($m in $HumanConfirmExcerptMarkers) {
        $i = $content.IndexOf($m)
        if ($i -ge 0 -and ($best -lt 0 -or $i -lt $best)) { $best = $i }
    }
    return $best
}

$HumanConfirmRequestPhrases = @(
    '테스트 방법(사람 확인용)',
    '사람 확인 필요', '사람의 확인 필요', '사람 판단 필요', '사람의 판단 필요',
    '사람이 직접 확인', '사람이 확인해', '사람의 직접 확인이 필요',
    '사용자 확인 필요', '사용자 확인이 필요', '사용자 판단 필요', '사용자가 직접 확인',
    '오너 확인 필요', '오너 확인이 필요', '오너 판단 필요', '오너 결정 필요', '오너 최종 확인',
    '고객 확인 필요'
)

function Test-HumanConfirmOccurrence([string]$content, [string]$phrase, [int]$idx) {
    $tail = $content.Substring($idx + $phrase.Length)
    $excerptAt = Get-ExcerptStartIndex $content
    if ($excerptAt -ge 0 -and $idx -gt $excerptAt) { return $false }
    if ($tail -match $HumanConfirmDoneTailPattern) { return $false }
    $before = if ($idx -gt 0) { $content.Substring($idx - 1, 1) } else { '' }
    $after = if ($tail.Length -gt 0) { $tail.Substring(0, 1) } else { '' }
    if (($HumanConfirmQuoteChars -contains $before) -and ($HumanConfirmQuoteChars -contains $after)) { return $false }
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
        if (Test-IsBotComment $c) { continue }
        if ($content -match '^\s*\[?\s*(착수|완료|재개|진행|보류|중단)\s*[:：]') { continue }
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

# ─────────────────────────────────────────────────────────────────────────────
# 분류: 분석/조사성 vs 수정/구현성 (review-done-audit.ps1 의 동일 함수 재구성)
# ─────────────────────────────────────────────────────────────────────────────
$ModCues = @('수정', '구현', '추가해', '고쳐', '변경해', '구축', '개발해', '패치', '리팩터', '브랜치', '커밋', '배포', '풀리퀘', '풀 리퀘', '.ps1', '.js', '.tsx', '.ts', '.py', '.sql', '영향 파일', '변경 파일', '수정 파일', '코드 변경')
$AnalysisCues = @('조사', '분석', '원인', '점검해', '확인해줘', '확인 부탁', '리포트', '파악해', '진단해')

function Get-IssueClassification($allText, $latestCommentText) {
    $latestText = if ($latestCommentText) { $latestCommentText } else { '' }
    $hasModInLatest = $false
    foreach ($cue in $ModCues) { if ($latestText -match [regex]::Escape($cue)) { $hasModInLatest = $true; break } }
    if ($hasModInLatest) { return 'Modification' }
    $hasModInAll = $false
    foreach ($cue in $ModCues) { if ($allText -match [regex]::Escape($cue)) { $hasModInAll = $true; break } }
    $hasAnalysisInAll = $false
    foreach ($cue in $AnalysisCues) { if ($allText -match [regex]::Escape($cue)) { $hasAnalysisInAll = $true; break } }
    if ($hasModInAll) {
        if ($hasAnalysisInAll) { return 'AnalysisOnly' }
        return 'Uncertain'
    }
    if ($hasAnalysisInAll) { return 'AnalysisOnly' }
    return 'Uncertain'
}

function Parse-Utc($s) {
    if (-not $s) { return $null }
    try {
        return [datetime]::Parse([string]$s, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime()
    } catch { return $null }
}

# ─────────────────────────────────────────────────────────────────────────────
# 로깅 헬퍼
# ─────────────────────────────────────────────────────────────────────────────
function Write-PresweepLog($msg) {
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$ts] [presweep]$(if(-not $IsLive){' [DRYRUN]'}) $msg"
    $line | Out-File -FilePath $LogFile -Append -Encoding UTF8
    Write-Output $line
}

# ─────────────────────────────────────────────────────────────────────────────
# ISSUE 1건 판정 + 선택적 DONE 전이
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-PresweepIssue($iss) {
    $isn = [int]$iss.isn
    $status = "$($iss.status)"
    if ($status -ne 'REVIEW') {
        Write-PresweepLog "isn=${isn}: status=${status} — REVIEW 가 아니므로 스킵"
        return
    }

    $comments = Get-IssueComments $isn $ApiKey $ApiBaseUrl
    $allTextParts = @($iss.title, $iss.content) + @($comments | ForEach-Object { $_.content })
    $allText = ($allTextParts -join "`n")

    $sortedComments = @($comments | Sort-Object { $t = Parse-Utc $_.regdate; if ($t) { $t } else { [datetime]::MinValue } })
    $latestComment = if ($sortedComments.Count -gt 0) { $sortedComments[-1] } else { $null }
    $latestCommentText = if ($latestComment) { "$($latestComment.content)" } else { '' }

    $classification = Get-IssueClassification $allText $latestCommentText
    Write-PresweepLog "isn=${isn}: 분류=${classification}"

    if ($classification -ne 'Modification') {
        Write-PresweepLog "isn=${isn}: 분석성/불확실 — 큐에 남김"
        return
    }

    $repos = Get-NestedRepoPaths $Workdir
    $hasMerged = Test-IssueHasMergedPr $isn $repos

    if (-not $hasMerged) {
        Write-PresweepLog "isn=${isn}: Modification + PR 없음 또는 미머지 — 큐에 남김"
        return
    }

    # PR 머지 확인됨 — 사람 확인 신호 검사
    $humanConfirmSignal = Get-HumanConfirmSignal $comments
    if ($humanConfirmSignal) {
        $phrase = $humanConfirmSignal.Phrase
        Write-PresweepLog "isn=${isn}: 병합완료 확인됐으나 사람 확인 문구 감지(=`${phrase}`) — NEEDS_DECISION 으로 전이하지 않고 큐에 남김(giip #2374 원칙: 애매하면 보류)"
        return
    }

    # ── 조건 충족: 병합완료 + 사람 확인 신호 없음 → DONE 전이 ──
    # 코멘트 본문 구성
    $prInfo = $null
    $prRepo = ''
    $prNumber = 0
    $prUrl = ''

    # 병합된 PR 정보 조회 (검증용 로그/코멘트에 사용)
    foreach ($repo in $repos) {
        $isnRe = "(?<!\d)$isn(?!\d)"
        $isnBodyRe = "#$isn(?!\d)"
        $exact = Invoke-GhPrQuery $repo @('pr', 'list', '--head', "bot/task-giip-$isn", '--state', 'merged', '--json', 'number,url,title')
        if ($exact.Count -gt 0) {
            $prRepo = $repo
            $prNumber = [int]$exact[0].number
            $prUrl = "$($exact[0].url)"
            break
        }
        $broad = Invoke-GhPrQuery $repo @('pr', 'list', '--state', 'merged', '--search', "giip-$isn", '--json', 'number,url,title')
        foreach ($pr in $broad) {
            if (($pr.headRefName -and $pr.headRefName -match $isnRe) -or ($pr.title -and $pr.title -match $isnRe) -or ($pr.body -and $pr.body -match $isnBodyRe)) {
                $prRepo = $repo
                $prNumber = [int]$pr.number
                $prUrl = "$($pr.url)"
                break
            }
        }
        if ($prNumber -gt 0) { break }
    }

    $repoDisplay = if ($prRepo) { Split-Path -Leaf $prRepo } else { 'unknown' }
    $bodyLines = @(
        "[REVIEW-MERGED-AUTODONE] (처리 시각: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))",
        "병합완료 REVIEW 이슈 자동 DONE 처리 (giip #3556 사전필터 — Phase 1 사전필터).",
        "판정 근거:",
        "  (a) 대응 PR 번호: #$prNumber (${repoDisplay})",
        "  (b) 머지 확인: gh PR 병합 상태 = merged",
        "  (c) 사람 확인 문구 없음: Get-HumanConfirmSignal 탐지 결과 = 없음(EXACT 부분일치 기준)",
        "  (d) 분류: Modification",
        "이 결정적 자동 종료는 LLM 호출 없이 규칙 기반으로 수행됐습니다.",
        "조건 불충족 건(미머지/사람확인 문구 있음/분석성 애매)은 그대로 REVIEW 큐에 남아 있습니다."
    )
    $body = $bodyLines -join "`n"

    Write-PresweepLog "isn=${isn}: 조건 충족 — #$prNumber (${repoDisplay}) merged, 사람 확인 문구 없음 — DONE 전이$(if(-not $IsLive){' [DRYRUN]'})"

    if (-not $IsLive) { return }

    # ── 실 실행: 코멘트 + 상태 전이 ──
    # 코멘트 먼저 등록 (UTF-8 파일 경유)
    $tmpComment = Join-Path ([System.IO.Path]::GetTempPath()) ("presweep_comment_${isn}_$( [guid]::NewGuid().ToString('N') ).txt")
    try {
        [System.IO.File]::WriteAllText($tmpComment, $body, (New-Object System.Text.UTF8Encoding $true))

        # get-issue.sh 로 코멘트 + DONE 전이
        $ErrorActionPreference = 'Continue'
        $global:LASTEXITCODE = 0

        $commentOut = & bash $GetIssueScript $isn $Csn --comment-file $tmpComment 2>&1
        $commentExit = $LASTEXITCODE

        if ($commentExit -ne 0) {
            Write-PresweepLog "isn=${isn}: [WRITE-FAIL] op=comment exit=$commentExit — $commentOut"
            # 코멘트 실패해도 상태 전이는 시도한다
        } else {
            Write-PresweepLog "isn=${isn}: 코멘트 등록 완료"
        }

        # 상태 전이 (同一个 get-issue.sh 호출에 결합해도 된다)
        $statusOut = & bash $GetIssueScript $isn $Csn --status DONE 2>&1
        $statusExit = $LASTEXITCODE

        if ($statusExit -ne 0) {
            Write-PresweepLog "isn=${isn}: [WRITE-FAIL] op=status exit=$statusExit — $statusOut"
        } else {
            Write-PresweepLog "isn=${isn}: 상태 DONE 전이 완료"
        }
    }
    finally {
        if (Test-Path $tmpComment) { Remove-Item -LiteralPath $tmpComment -Force -ErrorAction SilentlyContinue }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# 진단 모드: 단일 isn 만 처리 (상태변경 없음)
# ─────────────────────────────────────────────────────────────────────────────
if ($DiagnoseIsn -gt 0) {
    if (-not $ApiKey) { throw "ApiKey(SK) 가 필요합니다." }
    $repos = Get-NestedRepoPaths $Workdir
    Write-PresweepLog "진단: isn=$DiagnoseIsn, repos=$(@($repos | ForEach-Object { Split-Path -Leaf $_ }) -join ',')"
    $iss = $null
    try {
        $resp = Invoke-GiipApiGet "$ApiBaseUrl/giipIssues?isn=$DiagnoseIsn" $ApiKey
        if ($resp.issue) { $iss = $resp.issue }
        elseif ($resp.isn) { $iss = $resp }
    } catch { Write-PresweepLog "이슈 조회 실패: $($_.Exception.Message)"; return }
    if (-not $iss -or -not $iss.isn) { Write-PresweepLog "이슈를 찾지 못함(isn=$DiagnoseIsn)."; return }
    Invoke-PresweepIssue $iss
    return
}

# ─────────────────────────────────────────────────────────────────────────────
# 스윕 모드: CSN 의 현재 REVIEW 전수를 대상
# ─────────────────────────────────────────────────────────────────────────────
if (-not $ApiKey) { throw "ApiKey(SK) 가 필요합니다." }
if ($Csn -le 0) { throw "Csn 이 필요합니다." }

Write-PresweepLog "시작: Csn=$Csn, Workdir=$Workdir, IsLive=$IsLive"

# list-issues.js 로 현재 REVIEW 전수 조회 (giip #3556 요건 6)
$listArgs = @('node', $ListIssuesScript, '--csn', [string]$Csn, '--status', 'REVIEW', '--json')
$listOut = & node $ListIssuesScript --csn $Csn --status REVIEW --json 2>&1
$listExit = $LASTEXITCODE

if ($listExit -ne 0) {
    Write-PresweepLog "REVIEW 목록 조회 실패(list-issues.js exit=$listExit): $listOut"
    return
}

$listJson = $listOut | Out-String
$issues = @()
try {
    $parsed = $listJson | ConvertFrom-Json
    # list-issues.js --json 은 벌거벗은 배열([{...}])을 반환한다. 배열 분기를 먼저 본다.
    # (giip #3556 후속) $ErrorActionPreference='Stop' 하에서 배열 $parsed 에 대한 멤버열거
    # $parsed.issues 는 존재하지 않는 속성인데도 truthy(요소 수만큼의 $null 배열)로 평가되어
    # if($parsed.issues) 가 먼저 참이 되고 @($parsed.issues) 가 빈/널 배열이 되는 바람에
    # REVIEW 전수가 항상 0건이 되던 버그를 고친다. 객체-래핑({issues:[...]}) 케이스는 속성
    # 존재를 PSObject 로 정확히 확인한 뒤에만 쓴다.
    if ($parsed -is [array]) { $issues = @($parsed) }
    elseif ($parsed -and $parsed.PSObject.Properties['issues']) { $issues = @($parsed.issues) }
    else { $issues = @($parsed) }
} catch {
    Write-PresweepLog "REVIEW 목록 JSON 파싱 실패: $($_.Exception.Message)"
    return
}

$issues = @($issues | Where-Object { $_.isn })
Write-PresweepLog "REVIEW 전수: $($issues.Count)건"

if ($issues.Count -eq 0) {
    Write-PresweepLog "대상 REVIEW 이슈 없음 — 종료."
    return
}

$doneCount = 0
$skipCount = 0
foreach ($iss in $issues) {
    $isn = [int]$iss.isn
    try {
        Invoke-PresweepIssue $iss
        # Invoke-PresweepIssue 는 DRY-RUN 모드에서 상태를 출력만 할 뿐 실제로 DONE 했는지는
        # 로그 끝에 "[DRYRUN]" 이 붙어 있으므로 DRY-RUN 인지 아닌지 여기서 판단한다.
        # 실제로 DONE 된 건: IsLive=true 이고 코멘트/상태 전이가 성공한 경우만.
        if ($IsLive) {
            # 상태를 재확인 — 이미 DONE 이면 카운트하지 않는다(중복 방지)
            $currentStatus = $null
            try {
                $detail = Invoke-GiipApiGet "$ApiBaseUrl/giipIssues?isn=$isn" $ApiKey
                if ($detail.issue) { $currentStatus = "$($detail.issue.status)" }
                elseif ($detail.status) { $currentStatus = "$($detail.status)" }
            } catch {}
            if ($currentStatus -eq 'DONE') { $doneCount++ }
            else { $skipCount++ }
        }
    } catch {
        Write-PresweepLog "isn=${isn}: 처리 중 예외 — $($_.Exception.Message)"
        $skipCount++
    }
}

Write-PresweepLog "완료: 총 $($issues.Count)건 중 사전 DONE=$doneCount 건$(if(-not $IsLive){' [DRYRUN]'}), 스킵=$skipCount 건"
