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

Write-Host 'PASS test-token-usage'
