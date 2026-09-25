# pr-attribution-sweep.ps1 — 머지된 PR 이 쓸어담은 "남의 파일 변경"을 원 PR/원 이슈에 귀속 안내
#                             (giip #2459, 2026-09-14)
#
# 사용자 지시(giip #2459, 2026-09-14):
#   "봇 PR 이 남의 파일 변경을 쓸어담으면 죽은 코드가 조용히 머지된다 →
#    이렇게 되면 다른 머지된 코드는 다른 PR 의 위치를 알려주면 되는 거 아냐?"
#   → 쓸어담는 행위를 **차단하지 않는다**. 이미 머지된 사실을 사후에 양쪽에 알려서,
#     원 PR 이 영구 충돌로 남아 아무도 눈치채지 못하는 상태만 없앤다.
#
# 무엇을 하는가(3단):
#   1순위 귀속 안내   — 머지된 PR 의 실제 파일 목록을 그 PR 소관 이슈의 선언 범위와 대조해 범위 밖
#                       파일을 찾고, 그 파일을 동시에 건드리는 다른 PR(open / closed-unmerged)을 찾아
#                       **양쪽 PR + 원 이슈**에 상호 참조 코멘트를 남긴다(커밋 해시·파일 경로 포함).
#   2순위 고아 PR 정리 — 원 PR 브랜치가 origin/main 대비 실질 no-op(주석/공백만) 이면 "내용이 PR #<n>
#                       (커밋 <hash>)로 이미 반영됨" 코멘트 후 close 한다.
#                       ⚠ **원격 브랜치는 절대 삭제하지 않는다** — 공유 체크아웃이 그 브랜치에 올라가
#                       있으면 고아가 된다(2026-09-14 실측). 실질 no-op 이 아니면 close 하지 않고
#                       "충돌 해소 필요" 로 표시만 하고 사람/후속 세션에 넘긴다.
#   3순위 유입 억제   — 이 스크립트가 아니라 run-gissue-claude.ps1 위임 프롬프트의 [공통 절대 규칙]에
#                       "자신이 수정한 파일만 명시적 경로로 스테이징, git add -A / git commit -a 금지"를
#                       명시하는 것으로 처리했다(giip #2459).
#
# 범위 판정은 새로 만들지 않는다 — pr-gate-sweep.ps1 의 scope-gate 가 쓰는 판정 자원
#   (gissue-audit-lib.ps1 의 Get-PrDiffSummary / Get-IssueDetail / Get-IssueComments /
#    ConvertTo-CommentsText / Invoke-GissueJudge)을 그대로 재사용한다. 상세는 pr-attribution-lib.ps1 상단.
#
# 안전 설계:
#   - **기본은 DryRun** — `-Live` 없이는 코멘트도 close 도 하지 않고 판정 결과만 출력한다
#     (review-done-audit.ps1 과 동일한 관례: 스크립트 기본 dry-run, 스케줄러가 -Live 를 명시 전달).
#   - 판정이 모호하거나 실패하면 무조건 "아무것도 하지 않음" 으로 폴백한다(오탐 코멘트가 놓치는 것보다 해롭다).
#   - 같은 PR 쌍에 이미 귀속 코멘트가 있으면 건너뛴다(매시 실행돼도 중복이 쌓이지 않는다).
#   - 원격 브랜치 삭제 / main 직접 수정 / 머지 되돌리기는 어떤 경우에도 하지 않는다.
#
# 사용:
#   # 최근 6시간 내 머지된 PR 전부 판정만(기본 DryRun)
#   powershell -NoProfile -ExecutionPolicy Bypass -File pr-attribution-sweep.ps1 -Workdir "<프로젝트 컨테이너>" -ApiKey <SK>
#   # 특정 PR 1건만 판정(과거 사고 재현/회귀 확인용)
#   powershell -NoProfile -ExecutionPolicy Bypass -File pr-attribution-sweep.ps1 -Workdir "<프로젝트 컨테이너>" -ApiKey <SK> -PrNumber 740
#   # 실제 코멘트/close 수행
#   powershell -NoProfile -ExecutionPolicy Bypass -File pr-attribution-sweep.ps1 -Workdir "<프로젝트 컨테이너>" -ApiKey <SK> -Live
param(
    [Parameter(Mandatory = $true)][string]$Workdir,
    [string]$ApiKey,
    [string]$ApiBaseUrl = "https://giipfaw.azurewebsites.net/api",
    # [string[]] 로 받는 이유: `powershell -File` 로 실행하면 인자가 전부 문자열 한 토큰으로 넘어와
    # `-PrNumber 740,741` 이 [int[]] 에 바인딩되지 못하고 조용히 빈 배열이 된다(2026-09-14 실측 —
    # 대상 PR 0건으로 아무 경고 없이 종료됐다). 문자열로 받아 직접 쉼표/공백 분리한다.
    [string[]]$PrNumber = @(),
    [double]$SinceHours = 6,
    [int]$Limit = 50,
    [switch]$Live
)

$ErrorActionPreference = 'Stop'

# ── [giip #2613] 이 실행의 AI 행위자(actor) 고정 ───────────────────────────────
# 배경(실측 2026-09-16): giip 코멘트 최근 30일 작성자 1위가 `lowyshin.giip` 3,385건이었다.
#   이건 사람 계정이다(tCorpUser usn=156). 코멘트 SP 가 dbo.lwGetUSNbyat(@ak) 로 작성자를 정하는데,
#   이 함수의 마지막 폴백이 "SK 가 가리키는 CSn 의 tCorpUserRel.isPay=1 사용자"라서, csn 스코프 SK 로
#   코멘트를 쓰면 전부 그 CSn 의 결제자(=사람)에게 귀속됐다. authorUsn 도 거의 전부 NULL 이라
#   사후에 "어느 프로세스가 썼는지"를 확인할 방법이 없었다.
# 이 레포는 DB 직접접속 수단이 없으므로(giip #2645 이식) 쓰기 경로는 giipfaw API 하나뿐이다:
#   scripts/gissue/lib/post-comment.js (giipfaw API) -> 이 주체의 AccessToken 으로 인증한다
# 주체 목록/명명 규칙: scripts/gissue/ai-actors.json, 절차: scripts/gissue/AI_ACTOR_ACCOUNTS.md
# PR 귀속 스윕도 :07 스케줄러 계열이다. author 라벨(gissue-pr-attribution)은 유지한다.
$env:GIIP_ACTOR = 'ai.dp01.gissue-scheduler'

# [ENCODING] pr-gate-sweep.ps1 상단과 동일한 이유 — 이 스크립트도 `powershell -File` 로 직접 실행되고
# Invoke-GissueJudge 가 한글 프롬프트를 stdin 파이프로 넘긴다. PowerShell 5.1 기본 코드페이지(949)로
# 인코딩되면 판정 모델이 ENCODING_ERROR 를 돌려준다(giip #1204/#1210 실측 계열).
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

. (Join-Path $PSScriptRoot 'pr-attribution-lib.ps1')

$DryRun = -not $Live
# "740,741" / "740 741" / -PrNumber 740 -PrNumber 741 어느 형태로 와도 int 목록으로 정규화한다.
$TargetPrNumbers = @()
foreach ($tok in @($PrNumber)) {
    foreach ($piece in ("$tok" -split '[,\s]+')) {
        if ("$piece".Trim() -match '^\d+$') { $TargetPrNumbers += [int]$piece }
    }
}

function Write-AttrLog($msg) {
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Output "[$ts] [pr-attribution] $msg"
}

# ── 대상 머지 PR 수집 ────────────────────────────────────────────────────
# -PrNumber 가 주어지면 그 PR 만(과거 사고 재현/회귀 확인). 아니면 최근 $SinceHours 내 머지분 전부.
function Get-TargetMergedPrs($repo, $slug) {
    $repoArgs = if ($slug) { @('--repo', $slug) } else { @() }
    $fields = 'number,title,headRefName,body,state,mergedAt,mergeCommit,files,url'
    $out = @()
    Push-Location $repo
    try {
        if (@($TargetPrNumbers).Count -gt 0) {
            foreach ($n in $TargetPrNumbers) {
                $json = gh pr view $n @repoArgs --json $fields 2>$null
                if ($LASTEXITCODE -ne 0 -or -not $json) { Write-AttrLog "PR #${n}: 조회 실패 — 건너뜀."; continue }
                $out += ($json | ConvertFrom-Json)
            }
        } else {
            $json = gh pr list @repoArgs --state merged --json $fields --limit $Limit 2>$null
            if ($LASTEXITCODE -eq 0 -and $json) {
                $cut = (Get-Date).ToUniversalTime().AddHours(-1 * $SinceHours)
                # [PS 5.1 함정] ConvertFrom-Json 은 JSON 배열을 단일 객체로 파이프에 흘린다 — 먼저
                # 변수에 대입한 뒤 @() 로 감싸야 요소별로 순회된다(pr-attribution-lib.ps1 의 동일 주석 참고).
                $parsedList = $json | ConvertFrom-Json
                foreach ($pr in @($parsedList)) {
                    if (-not $pr.mergedAt) { continue }
                    $m = [datetime]::MinValue
                    if (-not [datetime]::TryParse("$($pr.mergedAt)", [ref]$m)) { continue }
                    if ($m.ToUniversalTime() -ge $cut) { $out += $pr }
                }
            }
        }
    } catch { } finally { Pop-Location }
    return $out
}

# ── GitHub PR 코멘트 등록 ────────────────────────────────────────────────
function Add-PrComment($repo, $slug, $prNumber, $body, $label) {
    if ($DryRun) {
        Write-AttrLog "[DRYRUN] PR #$prNumber 에 귀속 코멘트 등록 예정 ($label). 본문 미리보기:"
        foreach ($l in ($body -split "`r?`n")) { Write-Output "          | $l" }
        return
    }
    $repoArgs = if ($slug) { @('--repo', $slug) } else { @() }
    $tmp = Join-Path $env:TEMP ("gissue_attr_{0}_{1}.md" -f $prNumber, [guid]::NewGuid().ToString('N'))
    try {
        [System.IO.File]::WriteAllText($tmp, $body, (New-Object System.Text.UTF8Encoding $false))
        Push-Location $repo
        try { gh pr comment $prNumber @repoArgs --body-file $tmp 2>&1 | Out-Null } finally { Pop-Location }
        Write-AttrLog "PR #$prNumber 귀속 코멘트 등록 완료 ($label)."
    } finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
}

# ── giip 이슈 코멘트 등록(pr-gate-sweep.ps1 과 동일 경로 재사용) ─────────
function Add-GiipIssueNote($isn, $body, $label) {
    if ($DryRun) {
        Write-AttrLog "[DRYRUN] giip #$isn 에 귀속 안내 코멘트 등록 예정 ($label). 본문 미리보기:"
        foreach ($l in ($body -split "`r?`n")) { Write-Output "          | $l" }
        return
    }
    # [giip #2645 이식] 이 레포는 DB 직접접속(giipdb/mgmt/addIssueComment.ps1)이 없다 —
    # pr-gate-sweep.ps1 / review-done-audit.ps1 과 동일하게 giipfaw API 경로(lib/post-comment.js:
    # 등록 → 즉시 재조회 → mojibake 검증 → 1회 재시도)를 쓴다. 본문은 UTF-8(BOM) 파일로 넘겨
    # 한글/이모지 깨짐을 막는다(giip #1030).
    # author 라벨($script:AttributionAuthor)은 API 경로에서 클라이언트가 지정할 수 없고
    # $env:GIIP_ACTOR 인증 주체로 결정되므로 인자로 넘기지 않는다. 중복 방지는 author 가 아니라
    # 본문 마커 판정(Test-AlreadyAttributed)이 담당하므로 동작에 차이가 없다.
    if (-not $ApiKey) {
        Write-AttrLog "WARN: -ApiKey 가 없어 giip #$isn 이슈 코멘트를 건너뜁니다(PR 코멘트는 정상 등록됨)."
        return
    }
    $tmp = Join-Path $env:TEMP ("gissue_attr_isn{0}_{1}.txt" -f $isn, [guid]::NewGuid().ToString('N'))
    try {
        [System.IO.File]::WriteAllText($tmp, $body, (New-Object System.Text.UTF8Encoding $true))
        # rule 63: 네이티브 호출에 `2>&1` 리다이렉트를 쓰지 않는다($ErrorActionPreference='Stop' 과
        # 만나면 자식이 경고 한 줄만 내도 NativeCommandError 로 스윕 전체가 죽는다).
        $prevEap = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $global:LASTEXITCODE = 0
            & node (Join-Path $PSScriptRoot 'lib\post-comment.js') $isn "@$tmp" $ApiKey $ApiBaseUrl 'note' | Out-Null
            if ($LASTEXITCODE -ne 0) {
                Write-AttrLog "WARN: giip #$isn 이슈 코멘트 등록 실패(post-comment.js exit=$LASTEXITCODE)."
            } else {
                Write-AttrLog "giip #$isn 귀속 안내 코멘트 등록 완료 ($label)."
            }
        } finally { $ErrorActionPreference = $prevEap }
    } finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
}

# ── 고아 PR close (원격 브랜치는 절대 삭제하지 않는다) ───────────────────
function Close-OrphanPr($repo, $slug, $prNumber) {
    if ($DryRun) { Write-AttrLog "[DRYRUN] PR #$prNumber close 예정(실질 no-op — 원격 브랜치는 삭제하지 않음)."; return }
    $repoArgs = if ($slug) { @('--repo', $slug) } else { @() }
    Push-Location $repo
    try {
        # --delete-branch 를 절대 붙이지 않는다: 공유 체크아웃이 그 브랜치에 올라가 있으면 고아가 된다.
        gh pr close $prNumber @repoArgs 2>&1 | Out-Null
        Write-AttrLog "PR #$prNumber close 완료(원격 브랜치 보존)."
    } finally { Pop-Location }
}

# ── 본 처리 ─────────────────────────────────────────────────────────────
$repos = Get-NestedRepoPaths $Workdir
Write-AttrLog "시작: Workdir=$Workdir, repos=$(@($repos | ForEach-Object { Split-Path -Leaf $_ }) -join ',')$(if($DryRun){' [DRYRUN — 코멘트/close 없음]'}else{' [LIVE]'})"

$totalSweepers = 0; $totalAttrib = 0; $totalClosed = 0; $totalKept = 0; $totalSkipNoIntersect = 0; $totalWarn = 0

foreach ($repo in $repos) {
    # [giip #2504] 체크아웃 없는 `slug:OWNER/REPO` 항목은 로컬 git(no-op 판정·Push-Location)이 필요한
    # 이 스윕에서 처리할 수 없다 — 건너뛴다(이전엔 Push-Location 'slug:...' 로 매번 예외).
    if ("$repo" -match '^slug:') { Write-AttrLog "SKIP $repo — 로컬 체크아웃 없음"; continue }
    $originUrl = (git -C $repo remote get-url origin 2>$null)
    $slug = $null
    if ($originUrl -and "$originUrl" -match 'github\.com[:/]([^/]+/[^/]+?)(?:\.git)?\s*$') { $slug = $Matches[1] }

    $merged = Get-TargetMergedPrs $repo $slug
    if (@($merged).Count -eq 0) { continue }
    Write-AttrLog "레포 $(Split-Path -Leaf $repo) ($slug): 대상 머지 PR $(@($merged).Count) 건."

    $candidates = Get-CandidatePrs $repo $slug 0
    Write-AttrLog "  후보 PR(open + closed-unmerged) $(@($candidates).Count) 건: $(@($candidates | ForEach-Object { "#$($_.number)($($_.state))" }) -join ' ')"

    foreach ($pr in $merged) {
        $totalSweepers++
        $prNum = [int]$pr.number
        $sweeperPaths = @(@($pr.files) | ForEach-Object { $_.path })
        $isn = Resolve-PrOwnerIsn $pr.headRefName $pr.title $pr.body
        $mergeHash = if ($pr.mergeCommit -and $pr.mergeCommit.oid) { $pr.mergeCommit.oid } else { '(불명)' }
        Write-AttrLog "  PR #${prNum} '$($pr.title)' 브랜치=$($pr.headRefName) 소관isn=$(if($isn -gt 0){$isn}else{'(해석불가)'}) 파일 $(@($sweeperPaths).Count) 건."

        # 소관 isn 은 브랜치/제목에서만 뽑는다(본문은 "관련 이슈 인용" 오탐 때문에 쓰지 않는다 —
        # pr-attribution-lib.ps1 의 Resolve-PrOwnerIsn 주석, PR #725 실측 사례).
        if ($isn -le 0) { $totalWarn++; Write-AttrLog "    SKIP: 소관 isn 을 브랜치/제목에서 해석하지 못함 → 범위 판정 불가(안전 폴백, 아무 것도 하지 않음)."; continue }

        # ── 1차 필터(LLM 호출 전): 다른 PR 이 동시에 건드리는 파일이 하나도 없으면 귀속 안내 자체가
        #    불필요하다. 여기서 걸러 LLM 판정 비용과 오탐 기회를 함께 없앤다.
        $intersect = @()
        foreach ($p in $sweeperPaths) {
            $owners = @($candidates | Where-Object { $_.paths -contains $p })
            if (@($owners).Count -gt 0) { $intersect += $p }
        }
        if (@($intersect).Count -eq 0) {
            $totalSkipNoIntersect++
            Write-AttrLog "    감지 없음: 이 PR 의 파일을 동시에 건드리는 다른 PR 이 없음(LLM 판정 생략)."
            continue
        }
        Write-AttrLog "    다른 PR 과 겹치는 파일 $(@($intersect).Count) 건: $(@($intersect) -join ', ') → 범위 판정 진행."

        # ── 2차: scope-gate 와 동일한 입력(이슈 content + 코멘트 이력 + PR 파일목록)으로 파일 단위 판정 ──
        $issueDetail = Get-IssueDetail $isn $ApiKey $ApiBaseUrl
        if (-not $issueDetail) { $totalWarn++; Write-AttrLog "    SKIP: giip #$isn 이슈 상세 조회 실패 → 범위 판정 불가(안전 폴백)."; continue }
        $comments = Get-IssueComments $isn $ApiKey $ApiBaseUrl
        $commentsText = ConvertTo-CommentsText $comments
        $prDiff = Get-PrDiffSummary $repo $prNum $slug        # ← scope-gate 가 쓰는 바로 그 수집기
        $allFilesText = if ($prDiff -and $prDiff.files) { $prDiff.files } else { (@($sweeperPaths) -join "`n") }

        # LLM 판정은 결정적이지 않다(실측: 같은 입력의 PR #740 판정이 3회 중 1회 IN_SCOPE 로 뒤집혔다).
        # 프롬프트가 "확신 없으면 IN_SCOPE" 로 편향돼 있어 뒤집힘은 항상 "놓치는" 쪽으로 일어난다 —
        # 놓치면 이 사고(원 PR 이 영구 충돌로 방치)가 그대로 재발하므로, 1차가 전부 IN_SCOPE 일 때만
        # 한 번 더 묻고 **둘 중 하나라도 OUT_OF_SCOPE 면 채택**한다.
        #   - 재질의는 "아무 것도 감지 안 됨" 인 경우에만 일어나므로 감지 케이스의 비용은 그대로다.
        #   - 오탐이 늘지 않는 근거: 이 판정에 도달한 파일은 이미 "다른 이슈 소관의 PR 이 동시에
        #     건드리는 파일" 이라는 구조적 근거를 통과했고, OUT_OF_SCOPE 의 결과는 **코멘트뿐**이다
        #     (close 는 이 판정이 아니라 결정적인 no-op 판정만으로 결정된다).
        #   - 실측(2026-09-14): 정상 PR #745/#730 은 2회 재질의에도 전부 IN_SCOPE 로 안정적이었다.
        $maxJudgeAttempts = 2
        $verdicts = $null
        $outPaths = @()
        for ($attempt = 1; $attempt -le $maxJudgeAttempts; $attempt++) {
            $judge = Invoke-FileScopeJudge $isn $issueDetail.title $issueDetail.content $commentsText $prNum $pr.title $allFilesText $intersect
            if (-not $judge.ok) {
                Write-AttrLog "    판정 호출 실패/차단(attempt=$attempt/$maxJudgeAttempts, exit=$($judge.exit))."
                continue
            }
            Write-AttrLog "    판정 응답(attempt $attempt/$maxJudgeAttempts):"
            foreach ($l in ($judge.text -split "`r?`n")) { if ("$l".Trim()) { Write-Output "          | $l" } }
            $thisVerdicts = Parse-FileScopeVerdicts $judge.text $intersect
            $thisOut = @($intersect | Where-Object { $thisVerdicts[$_].verdict -eq 'OUT_OF_SCOPE' })
            if (@($thisOut).Count -gt 0) { $verdicts = $thisVerdicts; $outPaths = $thisOut; break }
            if (-not $verdicts) { $verdicts = $thisVerdicts }
        }
        if (-not $verdicts) { $totalWarn++; Write-AttrLog "    SKIP: 파일 범위 판정 호출이 전 회차 실패/차단 → 안전 폴백, 아무 것도 하지 않음."; continue }
        if (@($outPaths).Count -eq 0) {
            Write-AttrLog "    감지 없음: 겹치는 파일이 전부 giip #$isn 의 작업 범위 내(IN_SCOPE)로 판정됨($maxJudgeAttempts 회 확인) → 귀속 안내 불필요."
            continue
        }

        # ── 3차: 범위 밖 파일별로 원 PR 을 지목하고 상호 참조 코멘트 구성 ──
        $sweeper = @{ number = $prNum; title = $pr.title; url = $pr.url; isn = $isn; mergeCommit = $mergeHash }
        $byOwner = @{}
        foreach ($p in $outPaths) {
            foreach ($cand in @($candidates | Where-Object { $_.paths -contains $p })) {
                $key = [string]$cand.number
                if (-not $byOwner.ContainsKey($key)) { $byOwner[$key] = @{ pr = $cand; items = @() } }
                $byOwner[$key].items += @{
                    path      = $p
                    ownerPr   = $cand
                    ownerIsn  = (Resolve-PrOwnerIsn $cand.headRefName $cand.title $null)
                    rationale = $verdicts[$p].rationale
                }
            }
        }

        foreach ($key in $byOwner.Keys) {
            $ownerPr = $byOwner[$key].pr
            $items = $byOwner[$key].items
            $ownerIsn = (Resolve-PrOwnerIsn $ownerPr.headRefName $ownerPr.title $null)
            Write-AttrLog "    ▶ 귀속 감지: PR #$prNum (giip #$isn) 이 담은 $(@($items | ForEach-Object { $_.path }) -join ', ') → 원 PR #$($ownerPr.number) ($($ownerPr.state), 브랜치 $($ownerPr.headRefName), 원 이슈 giip #$(if($ownerIsn -gt 0){$ownerIsn}else{'?'}))"
            $totalAttrib++

            if (Test-PrAlreadyAttributed $repo $slug $prNum $ownerPr.number) {
                Write-AttrLog "      SKIP: PR #$prNum 에 이미 #$($ownerPr.number) 를 지목한 귀속 코멘트가 있음(중복 방지)."
                continue
            }

            # 2순위: 원 PR 브랜치의 실질 no-op 판정
            $noop = Test-BranchNoOpAgainstBase $repo 'origin/main' "origin/$($ownerPr.headRefName)"
            if ($noop.error) { Write-AttrLog "      no-op 판정: 실패($($noop.error)) → close 하지 않음." }
            elseif ($noop.noop) { Write-AttrLog "      no-op 판정: 실질 변경 없음(주석/공백 제외) → close 대상." }
            else { Write-AttrLog "      no-op 판정: 실질 변경 $(@($noop.substantive).Count) 줄 남아 있음 → close 하지 않고 '충돌 해소 필요' 로 표시만." }

            Add-PrComment $repo $slug $prNum (New-SweeperPrNote $sweeper $items) "쓸어담은 PR 쪽"
            Add-PrComment $repo $slug $ownerPr.number (New-OwnerPrNote $sweeper $items $noop) "원 PR 쪽"
            if ($ownerIsn -gt 0) {
                Add-GiipIssueNote $ownerIsn (New-OwnerIssueNote $sweeper $ownerPr.number $ownerPr.url $items $noop) "원 이슈"
            } else {
                Write-AttrLog "      원 PR #$($ownerPr.number) 의 소관 isn 을 해석하지 못해 이슈 코멘트는 생략(PR 코멘트만 등록)."
            }

            if ((-not $noop.error) -and $noop.noop -and $ownerPr.state -eq 'OPEN') {
                Close-OrphanPr $repo $slug $ownerPr.number
                $totalClosed++
            } else {
                $totalKept++
            }
        }
    }
}

Write-AttrLog "완료: 검사한 머지 PR $totalSweepers, 겹침없어 생략 $totalSkipNoIntersect, 귀속 감지 $totalAttrib, 고아 close $totalClosed, close 보류(실질 변경 잔존/판정실패/이미 닫힘) $totalKept, 안전 폴백 경고 $totalWarn.$(if($DryRun){' [DRYRUN — 실제 변경 없음]'})"
