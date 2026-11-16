# token-usage.ps1 합산 단위 테스트(네트워크 없음 — 임시 폴더에 고정 JSONL 픽스처를 만든다).
# 실행: powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gissue/tests/test-token-usage.ps1
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../lib/token-usage.ps1')
function Assert-Eq($a, $b, $m) { if ($a -ne $b) { throw "FAIL $m : expected [$b] got [$a]" } }
function Assert-True($a, $m) { if (-not $a) { throw "FAIL $m : expected true" } }

# 인코딩 규칙 — 세션 기록 폴더명(영숫자 외 전부 '-')
Assert-Eq (Get-GissueEncodedProjectDirName 'D:\work\repo') 'D--work-repo' 'windows 경로 인코딩'
Assert-Eq (Get-GissueEncodedProjectDirName '/home/u/a b') '-home-u-a-b' 'posix 경로 인코딩'

$tmpRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('tokuse-' + [guid]::NewGuid().ToString('N'))
try {
    $workdir = 'D:\work\csn-repo'
    $projDir = Join-Path (Join-Path $tmpRoot 'projects') (Get-GissueEncodedProjectDirName $workdir)
    New-Item -ItemType Directory -Path $projDir -Force | Out-Null
    $since = [datetime]::Parse('2026-11-16T06:00:00Z', [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal)
    $lines = @(
        '{"type":"assistant","timestamp":"2026-11-16T06:10:00.000Z","message":{"id":"m1","model":"MiniMax-M3","usage":{"input_tokens":100,"cache_creation_input_tokens":10,"cache_read_input_tokens":5000,"output_tokens":40}}}',
        '{"type":"assistant","timestamp":"2026-11-16T06:10:00.000Z","message":{"id":"m1","model":"MiniMax-M3","usage":{"input_tokens":100,"cache_creation_input_tokens":10,"cache_read_input_tokens":5000,"output_tokens":40}}}',
        '{"type":"assistant","timestamp":"2026-11-16T06:20:00.000Z","message":{"id":"m2","model":"MiniMax-M3","usage":{"input_tokens":50,"cache_creation_input_tokens":0,"cache_read_input_tokens":6000,"output_tokens":20}}}',
        '{"type":"assistant","timestamp":"2026-11-16T05:00:00.000Z","message":{"id":"m0","model":"MiniMax-M3","usage":{"input_tokens":999,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":999}}}',
        '{"type":"assistant","timestamp":"2026-11-16T06:30:00.000Z","message":{"id":"m3","model":"claude-opus-4-8","usage":{"input_tokens":7,"cache_creation_input_tokens":3,"cache_read_input_tokens":900,"output_tokens":11}}}',
        '{"type":"user","timestamp":"2026-11-16T06:15:00.000Z","message":{"role":"user","content":"hi"}}'
    )
    $fixture = Join-Path $projDir 's1.jsonl'
    [System.IO.File]::WriteAllLines($fixture, $lines)
    # 파일 선별은 갱신 시각 기준이므로 픽스처 파일의 갱신 시각을 창 안으로 맞춘다
    (Get-Item $fixture).LastWriteTimeUtc = $since.AddMinutes(30)

    $rows = @(Get-GissueTranscriptTokenUsage -Roots @($tmpRoot) -Workdir $workdir -SinceUtc $since)
    Assert-Eq $rows.Count 2 '모델 2종'
    $a = $rows | Where-Object { $_.model -eq 'MiniMax-M3' }
    Assert-Eq $a.calls 2 '모델 A 호출 수(중복 id 제외)'
    Assert-Eq $a.freshIn 150 '모델 A freshIn'
    Assert-Eq $a.cacheCreate 10 '모델 A cacheCreate'
    Assert-Eq $a.cacheRead 11000 '모델 A cacheRead'
    Assert-Eq $a.out 60 '모델 A out'
    $b = $rows | Where-Object { $_.model -eq 'claude-opus-4-8' }
    Assert-Eq $b.calls 1 '모델 B 호출 수'
    Assert-Eq $b.cacheRead 900 '모델 B cacheRead'

    # [회귀] SinceUtc 의 DateTime.Kind 정규화 (2026-11-16 실측 — UTC+9 호스트에서
    # ISO8601 'Z' 문자열이나 네이티브 리터럴을 그대로 넘기면 Kind=Local 로 캐스팅되어
    # 시간창이 UTC 오프셋만큼 밀리고 recent 구간이 0건으로 조용히 사라진다. 오류가
    # 아니라 '측정값 0' 으로 오독되므로 같은 instant 를 어느 Kind 로 넘겨도 같아야 한다).
    #  (a) 같은 instant 를 Local Kind 로 넘겨도 UTC Kind 와 동일한 집계가 나와야 한다.
    $rowsLocal = @(Get-GissueTranscriptTokenUsage -Roots @($tmpRoot) -Workdir $workdir -SinceUtc $since.ToLocalTime())
    Assert-Eq $rowsLocal.Count $rows.Count 'Local Kind SinceUtc = 동일 행 수'
    $aLocal = $rowsLocal | Where-Object { $_.model -eq 'MiniMax-M3' }
    Assert-Eq $aLocal.calls $a.calls 'Local Kind SinceUtc = 동일 호출 수'
    Assert-Eq $aLocal.cacheRead $a.cacheRead 'Local Kind SinceUtc = 동일 cacheRead'
    #  (b) Kind 정규화 헬퍼 계약
    $unspec = [datetime]::SpecifyKind([datetime]'2026-11-16T06:00:00', [System.DateTimeKind]::Unspecified)
    $convUnspec = ConvertTo-GissueUtcDateTime $unspec
    Assert-True ($convUnspec.Kind -eq [System.DateTimeKind]::Utc) 'Unspecified Kind -> Utc'
    Assert-Eq $convUnspec.ToString('yyyy-MM-ddTHH:mm:ss') '2026-11-16T06:00:00' 'Unspecified 는 UTC 로 간주(벽시계 유지)'
    $convUtc = ConvertTo-GissueUtcDateTime $since
    Assert-Eq $convUtc.ToString('o') $since.ToString('o') 'Utc Kind 는 그대로'
    $localVal = [datetime]::SpecifyKind([datetime]'2026-11-16T06:00:00', [System.DateTimeKind]::Local)
    Assert-Eq (ConvertTo-GissueUtcDateTime $localVal).ToString('o') $localVal.ToUniversalTime().ToString('o') 'Local Kind 는 같은 instant 로 변환'

    # 없는 루트는 빈 결과(throw 하지 않음)
    $none = @(Get-GissueTranscriptTokenUsage -Roots @((Join-Path $tmpRoot 'nope')) -Workdir $workdir -SinceUtc $since)
    Assert-Eq $none.Count 0 '없는 루트 = 빈 결과'
} finally {
    Remove-Item -LiteralPath $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
}

# ── [계측 정확도] 0-토큰 로컬 레코드 제외 + 시간창 상한(UntilUtc) ──
# 근거: 엔진 세션 기록(JSONL) 실측 — model=`<synthetic>` 742건은 4분류 토큰이 전부 0이고
# 본문은 "You've hit your weekly limit" / "API Error (429)" 등 CLI 로컬 생성 메시지다.
# message id 가 실제 모델 레코드와 겹치는 건 0/742 → 엔진 호출이 아니라 로컬 알림이다.
# 이런 레코드를 calls 에 세면 호출 수가 부풀고 '호출당 평균 토큰'이 왜곡되며, engines[] 에
# '<synthetic>' 이라는 가짜 모델 행이 생겨 설계 3.3 의 롤업 차원(CSN x 일자 x 모델)에 잡힌다.
# limit/429 발생 사실은 scheduler_alarm(kind=LIMIT) 이 이미 별도로 담당한다.
$tmpRoot2 = Join-Path ([System.IO.Path]::GetTempPath()) ('tokuse2-' + [guid]::NewGuid().ToString('N'))
try {
    $workdir2 = 'D:\work\csn-repo2'
    $projDir2 = Join-Path (Join-Path $tmpRoot2 'projects') (Get-GissueEncodedProjectDirName $workdir2)
    New-Item -ItemType Directory -Path $projDir2 -Force | Out-Null
    $since2 = [datetime]::Parse('2026-11-16T06:00:00Z', [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal)
    $lines2 = @(
        # CLI 로컬 생성 알림 — 4분류 모두 0 이므로 제외되어야 한다
        '{"type":"assistant","timestamp":"2026-11-16T06:40:00.000Z","message":{"id":"s1","model":"<synthetic>","usage":{"input_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0}}}',
        # 같은 message id 로 실제 토큰이 뒤따르는 경우 — 0-토큰 레코드가 먼저 나와도
        # id 를 미리 소비해 버리면 그 호출이 통째로 사라진다. 살아남아야 한다.
        '{"type":"assistant","timestamp":"2026-11-16T06:41:00.000Z","message":{"id":"s1","model":"MiniMax-M3","usage":{"input_tokens":10,"cache_creation_input_tokens":0,"cache_read_input_tokens":20,"output_tokens":2}}}',
        '{"type":"assistant","timestamp":"2026-11-16T07:00:00.000Z","message":{"id":"s2","model":"MiniMax-M3","usage":{"input_tokens":1000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":1000}}}',
        '{"type":"assistant","timestamp":"2026-11-16T07:30:00.000Z","message":{"id":"s3","model":"MiniMax-M3","usage":{"input_tokens":2000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":2000}}}'
    )
    $fixture2 = Join-Path $projDir2 's1.jsonl'
    [System.IO.File]::WriteAllLines($fixture2, $lines2)
    (Get-Item $fixture2).LastWriteTimeUtc = $since2.AddMinutes(30)

    # (1) 상한 없음 — 0-토큰 레코드는 행도 calls 도 만들지 않고, 뒤따르는 동일 id 의
    #     실제 토큰 레코드는 살아남는다.
    $rows2 = @(Get-GissueTranscriptTokenUsage -Roots @($tmpRoot2) -Workdir $workdir2 -SinceUtc $since2)
    Assert-Eq $rows2.Count 1 '0-토큰 레코드 제외 후 모델 1종'
    Assert-Eq $null ($rows2 | Where-Object { $_.model -eq '<synthetic>' }) '<synthetic> 행 없음'
    $r2 = $rows2 | Where-Object { $_.model -eq 'MiniMax-M3' }
    Assert-Eq $r2.calls 3 'calls = 계측된 호출 3건(0-토큰 1건 제외)'
    Assert-Eq $r2.freshIn 3010 'freshIn'
    Assert-Eq $r2.cacheCreate 0 'cacheCreate'
    Assert-Eq $r2.cacheRead 20 'cacheRead'
    Assert-Eq $r2.out 3002 'out'

    # (2) 시간창 상한 — 반열린 구간 [SinceUtc, UntilUtc). 07:30 레코드는 제외되어야 한다.
    $until2 = [datetime]::Parse('2026-11-16T07:15:00Z', [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal)
    $rows3 = @(Get-GissueTranscriptTokenUsage -Roots @($tmpRoot2) -Workdir $workdir2 -SinceUtc $since2 -UntilUtc $until2)
    $r3 = $rows3 | Where-Object { $_.model -eq 'MiniMax-M3' }
    Assert-Eq $r3.calls 2 'UntilUtc 이후 레코드 제외'
    Assert-Eq $r3.freshIn 1010 'UntilUtc 이후 freshIn 제외'
    Assert-Eq $r3.out 1002 'UntilUtc 이후 out 제외'

    # (3) 경계값 자체는 제외(반열린 구간) — 07:00 레코드가 빠진다.
    $until3 = [datetime]::Parse('2026-11-16T07:00:00Z', [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal)
    $rows4 = @(Get-GissueTranscriptTokenUsage -Roots @($tmpRoot2) -Workdir $workdir2 -SinceUtc $since2 -UntilUtc $until3)
    $r4 = $rows4 | Where-Object { $_.model -eq 'MiniMax-M3' }
    Assert-Eq $r4.calls 1 '경계 시각은 제외(반열린 구간)'
    Assert-Eq $r4.freshIn 10 '경계 제외 후 freshIn'
    Assert-Eq $r4.out 2 '경계 제외 후 out'

    # (4) Kind 정규화 — 상한도 하한과 같은 규약(UTC/Local 어느 Kind 로 넘겨도 같은 instant)
    $rows4Local = @(Get-GissueTranscriptTokenUsage -Roots @($tmpRoot2) -Workdir $workdir2 -SinceUtc $since2 -UntilUtc $until3.ToLocalTime())
    Assert-Eq $rows4Local.Count $rows4.Count 'Local Kind UntilUtc = 동일 행 수'
    $r4Local = $rows4Local | Where-Object { $_.model -eq 'MiniMax-M3' }
    Assert-Eq $r4Local.calls $r4.calls 'Local Kind UntilUtc = 동일 호출 수'
    Assert-Eq $r4Local.cacheRead $r4.cacheRead 'Local Kind UntilUtc = 동일 cacheRead'
} finally {
    Remove-Item -LiteralPath $tmpRoot2 -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host 'PASS test-token-usage'
