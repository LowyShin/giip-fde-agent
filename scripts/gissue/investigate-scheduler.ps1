# investigate-scheduler.ps1 -- gissue scheduler standard investigation script.
#
# Purpose (giip #6331, investigation architecture giip #6333):
#   Emit the fixed evidence set for "why is the queue starving / how did runs
#   behave" in ONE execution, so investigations stop being ad-hoc queries.
#   Runs on the host via CQE; results come back through the CQE output and
#   are stored in tKVS by the caller when needed.
#
# Fixed rules baked in (do not re-derive per investigation):
#   - '[BUDGET]' is matched with CHARINDEX, never LIKE (T-SQL LIKE treats
#     brackets as a character class -- a 2026-11-25 ad-hoc query inflated the
#     count and had to be discarded).
#   - Run history lives in tKVS with kType='lssn', kKey=<LSSN> and
#     kFactor in ('scheduler_run_start','scheduler_run_report',
#     'scheduler_run_history') -- see lib/kvs-report.ps1. It is NOT keyed by
#     a 'scheduler_run_history' kType.
#   - One SELECT per execSQLFile call (multi-result output gets truncated).
#   - This file is ASCII-only, no BOM: PS 5.1 ANSI-misreads non-ASCII in a
#     BOM-less file, and the CQE agent's wrapper turns a BOM into a stray
#     command error (verified 2026-11-25, run 2). ASCII needs neither.
#
# Configuration (CONFIG section below):
#   Csn        Project CSN to investigate (default 47).
#   Days       Look-back window for comment-based counts (default 14).
#   GiipdbBase giipdb checkout on this host (mgmt\execSQLFile.ps1 lives here).
#   Lssn       Optional host LSSN to narrow run-history rows by kKey.
# NOTE: no param() block -- the CQE agent wraps the script with its own
# preamble, so param() is not the first statement and fails to parse
# (verified 2026-11-25, first run). Values come from the CONFIG section,
# overridable via INVSCHED_* environment variables when the host sets them.

$Csn = 47
if ($env:INVSCHED_CSN) { $Csn = [int]$env:INVSCHED_CSN }
$Days = 14
if ($env:INVSCHED_DAYS) { $Days = [int]$env:INVSCHED_DAYS }
$GiipdbBase = 'C:\Users\lowys\Downloads\Projects\giipprj\giipdb'
if ($env:INVSCHED_GIIPDB) { $GiipdbBase = $env:INVSCHED_GIIPDB }
$Lssn = ''
if ($env:INVSCHED_LSSN) { $Lssn = $env:INVSCHED_LSSN }

$ErrorActionPreference = 'Continue'
$exec = Join-Path $GiipdbBase 'mgmt\execSQLFile.ps1'
$enc = New-Object System.Text.UTF8Encoding($true)
$tmpDir = [System.IO.Path]::GetTempPath()

function Run-Q([string]$label, [string]$sql) {
    Write-Output ("== " + $label + " ==")
    $f = Join-Path $tmpDir ("invsched_" + $label + ".sql")
    [System.IO.File]::WriteAllText($f, $sql, $enc)
    try { & $exec -SqlFile $f -Raw } catch { Write-Output ("ERR: " + $_.Exception.Message) }
    Write-Output ""
}

# 1) Status distribution for the CSN.
Run-Q 'status_dist' ("SELECT status, COUNT(*) AS cnt FROM tGiipIssue WHERE csn = $Csn GROUP BY status ORDER BY cnt DESC")

# 2) READY aging: wait = latest comment time, else registration time.
Run-Q 'ready_aging' ("SELECT COUNT(*) AS readyNow, SUM(CASE WHEN DATEDIFF(HOUR, COALESCE(lc.lastAt, i.regdate), GETUTCDATE()) >= 24 THEN 1 ELSE 0 END) AS ready24hPlus, MAX(DATEDIFF(HOUR, COALESCE(lc.lastAt, i.regdate), GETUTCDATE())) AS maxWaitHours FROM tGiipIssue i LEFT JOIN (SELECT isn, MAX(regdate) AS lastAt FROM tGiipIssueComment GROUP BY isn) lc ON lc.isn = i.isn WHERE i.csn = $Csn AND i.status = 'READY'")

# 3) PENDING aging.
Run-Q 'pending_aging' ("SELECT COUNT(*) AS pendingNow, SUM(CASE WHEN DATEDIFF(HOUR, COALESCE(lc.lastAt, i.regdate), GETUTCDATE()) >= 24 THEN 1 ELSE 0 END) AS pending24hPlus, MIN(i.regdate) AS oldestPending FROM tGiipIssue i LEFT JOIN (SELECT isn, MAX(regdate) AS lastAt FROM tGiipIssueComment GROUP BY isn) lc ON lc.isn = i.isn WHERE i.csn = $Csn AND i.status = 'PENDING'")

# NOTE: tGiipIssueComment has NO csn column (verified 2026-11-25, run 2:
# 'Invalid column name csn'). Comment-based counts filter the CSN by
# joining tGiipIssue on isn.

# 4) [BUDGET] skip comments in the window (CHARINDEX -- never LIKE).
Run-Q 'budget_skips' ("SELECT COUNT(*) AS budgetComments, COUNT(DISTINCT c.isn) AS issues FROM tGiipIssueComment c JOIN tGiipIssue i ON i.isn = c.isn WHERE i.csn = $Csn AND CHARINDEX('[BUDGET]', c.content) > 0 AND c.regdate >= DATEADD(DAY, -$Days, GETUTCDATE())")

# 5) Status transitions in the last 7 days (review-audit records them as
#    'A -> B' inside the comment text).
Run-Q 'transitions_7d' ("SELECT SUM(CASE WHEN CHARINDEX('-> READY', c.content) > 0 THEN 1 ELSE 0 END) AS toReady, SUM(CASE WHEN CHARINDEX('-> IN_PROGRESS', c.content) > 0 THEN 1 ELSE 0 END) AS toInProgress, SUM(CASE WHEN CHARINDEX('-> REVIEW', c.content) > 0 THEN 1 ELSE 0 END) AS toReview, SUM(CASE WHEN CHARINDEX('-> DONE', c.content) > 0 THEN 1 ELSE 0 END) AS toDone, SUM(CASE WHEN CHARINDEX('-> PENDING', c.content) > 0 THEN 1 ELSE 0 END) AS toPending FROM tGiipIssueComment c JOIN tGiipIssue i ON i.isn = c.isn WHERE i.csn = $Csn AND c.regdate >= DATEADD(DAY, -7, GETUTCDATE())")

# 6) Watchdog comments in the last 7 days.
Run-Q 'watchdog_7d' ("SELECT COUNT(*) AS watchdogComments, COUNT(DISTINCT c.isn) AS issues FROM tGiipIssueComment c JOIN tGiipIssue i ON i.isn = c.isn WHERE i.csn = $Csn AND c.author = 'gissue-scheduler-watchdog' AND c.regdate >= DATEADD(DAY, -7, GETUTCDATE())")

# 7) Run records in tKVS: kType='lssn', kFactor in
#    ('scheduler_run_start','scheduler_run_report','scheduler_run_history').
#    First the per-factor counts (absence must be explicit, not silent),
#    then raw samples -- the CSN lives inside the JSON value, and run 2
#    showed pre-filtering on it can hide the actual value shape.
#    DISPLAY WARNING (run 3, 2026-11-25): some kValue cells render BLANK in
#    execSQLFile tabular output although the value exists (the newest
#    scheduler_run_history row printed its JSON in the same result where
#    older rows printed blank). Never conclude 'no value' from a blank
#    cell -- the per-factor counts and latest timestamps are the evidence.
$lssnFilter = ''
if ($Lssn -ne '') { $lssnFilter = " AND kKey = '$Lssn'" }
Run-Q 'run_factors_7d' ("SELECT kFactor, COUNT(*) AS cnt, MAX(kRegdt) AS latest FROM tKVS WHERE kType = 'lssn' AND kFactor IN ('scheduler_run_start','scheduler_run_report','scheduler_run_history') AND kRegdt >= DATEADD(DAY, -7, GETUTCDATE())$lssnFilter GROUP BY kFactor")
Run-Q 'run_reports_raw' ("SELECT TOP 5 kRegdt, LEFT(kValue, 500) AS report FROM tKVS WHERE kType = 'lssn' AND kFactor = 'scheduler_run_report'$lssnFilter ORDER BY kRegdt DESC")
Run-Q 'run_history_raw' ("SELECT TOP 5 kRegdt, LEFT(kValue, 500) AS history FROM tKVS WHERE kType = 'lssn' AND kFactor = 'scheduler_run_history'$lssnFilter ORDER BY kRegdt DESC")

# 8) Run starts from tKVS (same key space).
Run-Q 'run_starts' ("SELECT TOP 5 kRegdt, LEFT(kValue, 300) AS startInfo FROM tKVS WHERE kType = 'lssn' AND kFactor = 'scheduler_run_start'$lssnFilter ORDER BY kRegdt DESC")

Write-Output 'INVESTIGATE-SCHEDULER-DONE'
