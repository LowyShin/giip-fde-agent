# svcguard — 서비스 상주 메모리 측정 + 조건부 자동 재기동

> Windows 서비스가 **svchost.exe 안에 호스팅**되어 있을 때, 그 호스팅 프로세스의
> `PrivateBytes` 가 임계값 이상으로 오래 상주하면 조건부로 서비스를 재기동하고,
> 동시에 **"메모리 증가 속도 vs 프로세스 생성량"** 을 추적할 수 있는 측정 로그를 남긴다.

## 왜 측정 로그가 우선인가

재기동은 **증상을 없앨 뿐 원인을 규명하지 않는다.** 어떤 서비스가
"많이 실행된 프로그램 수에 비례해" 메모리를 누적하는지는 로그를 시간 단위로
모아야 알 수 있다. 그래서 이 도구의 1순위는 **재기동이 아니라 측정**이고,
재기동은 임계 초과가 *지속될 때* 작동하는 안전장치다.

## 구성 파일

| 파일 | 역할 |
| :--- | :--- |
| `restart-service-on-memory.ps1` | 측정 + 조건부 재기동 러너 (예약 태스크가 실행하는 본체) |
| `register-svcguard-scheduler.ps1` | 예약 태스크 등록/해제/상태 조회 도구 (사람이 관리자 권한으로 1회 실행) |
| `logs/` | 측정 로그(JSONL)·상태 파일이 쌓이는 폴더 (git 추적 대상 아님) |

## 빠른 시작

### 1) 등록 미리보기 (권한 불필요 · 아무것도 바꾸지 않음)

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\svcguard\register-svcguard-scheduler.ps1 -Action Register -WhatIf
```

### 2) 실제 등록 (관리자 권한 Powershell 에서 1회)

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\svcguard\register-svcguard-scheduler.ps1 `
    -Action Register -ServiceName PcaSvc -ThresholdMB 1024 -SampleIntervalMinutes 10
```

- 태스크는 **SYSTEM 계정**으로 등록된다. SYSTEM 이 아니면 서비스 재기동이
  `Cannot open <서비스>` 로 실패한다(관리자 권한 없이는 재기동 불가).
- 등록은 **사람이 1회** 수행한다(스크립트가 자동 등록하지 않는다).
- 등록 스크립트는 이 저장소의 정상 체크아웃에서 실행해야 한다 — 임시 worktree 경로의 등록은
  `task-target-guard.ps1` 가 거부한다(태스크가 사라진 임시 경로를 가리키는 것을 막는다).
- 기본 실행 주기는 10분, 재기동 최소 간격은 60분이다.

### 3) 상태 조회 / 해제

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\svcguard\register-svcguard-scheduler.ps1 -Action Status
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\svcguard\register-svcguard-scheduler.ps1 -Action Unregister
```

### 4) 재기동 없이 측정만 해보기

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\svcguard\restart-service-on-memory.ps1 -WhatIf
```

## 측정 항목

`logs\svcguard-<서비스>.jsonl` 에 **샘플 1건 = 1줄(JSON)** 로 쌓인다. 핵심 필드:

| 필드 | 뜻 |
| :--- | :--- |
| `timestampUtc` | 샘플 시각 (UTC, ISO 8601) |
| `servicePid` / `serviceState` | 대상 서비스의 호스팅 PID 와 상태 |
| `privateBytesMB` | 호스팅 프로세스의 PrivateBytes (MB) — **재기동 판정 기준값** |
| `workingSetMB` | 호스팅 프로세스의 WorkingSet (MB) |
| `baselinePrivateBytesMB` | **기준선** = 최근 N개 샘플의 최솟값 (아래 참고) |
| `systemProcessCount` | 시스템 전체 프로세스 수 |
| `deltaPrivateBytesMB` / `deltaProcessCount` | 직전 샘플 대비 메모리·프로세스 수 변화 |
| `growthMBPerHour` | 직전 샘플 대비 **증가 속도(MB/시간)** |
| `growthMBPerNewProcess` | 프로세스 수 증가 대비 증가량 (MB/프로세스) |
| `processCreateEventCount` | Security 4688(프로세스 생성 이벤트) 카운트 — `-UseSecurityAuditCount` opt-in, 기본 off |
| `restartEligible` / `restartTriggered` / `restartBlockedReason` | 재기동 판정 결과 |
| `privateBytesBeforeRestartMB` / `privateBytesAfterRestartMB` | 재기동 직전·직후 값 |

### 기준선이 "최근 최솟값"인 이유

어떤 서비스는 수 초 동안 메모리가 순간적으로 2배로 튀었다가 원래 값으로 돌아온다.
이 순간 값을 그대로 "상주 메모리"로 보면 **급증에 과민반응**해 재기동할 수 있다.
그래서 재기동 판정은 **직전 샘플 값이 아니라 최근 N개(기본 24개) 샘플의 최솟값**으로 한다.
최솟값은 순간 급증의 영향을 받지 않는다. 분 단위 샘플로는 수 초짜리 급증 자체가 잡히지 않지만,
분 단위로도 확실히 잡히는 배증은(값이 오래 높은 채로 남는 경우) 기준선으로 판정된다.

수 초 단위 급증을 직접 보고 싶으면 `-DiagnoseBurst`(1초 간격 N초 연속 샘플)를 쓴다.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\svcguard\restart-service-on-memory.ps1 -DiagnoseBurst -BurstSeconds 30
```

### 재기동이 일어나는 조건

1. `baselinePrivateBytesMB >= ThresholdMB` — 기준선이 임계 이상
2. 마지막 재기동 이후 `MinRestartIntervalMinutes`(기본 60분) 경과
3. `-WhatIf` 가 아님

하나라도 만족하지 않으면 `restartBlockedReason` 에 사유(`below-threshold` / `min-interval` /
`whatif` / `measurement-incomplete`)가 기록되고 **측정만** 이어간다.
관리자 권한이 없어 재기동이 실패해도(`restart-failed`) 로그는 남기고 정상 종료한다 —
예약 태스크가 실패로 죽으면 다음 샘플이 사라져 측정이 끊기기 때문이다.

## 로그 해석법 — "실행 프로그램 수에 비례해 메모리가 늘어나는가"

가설: *이 서비스는 실행된 프로그램(프로세스) 수에 비례해 상주 메모리를 누적한다.*

### ① 프로세스 수가 늘 때 증가 속도도 오르는가

```powershell
$rows = Get-Content .\scripts\svcguard\logs\svcguard-<서비스>.jsonl |
    ForEach-Object { $_ | ConvertFrom-Json } |
    Where-Object { $_.mode -eq 'sample' -and $null -ne $_.growthMBPerHour }
$rows | Sort-Object growthMBPerHour -Descending |
    Select-Object -First 20 timestampUtc, privateBytesMB, systemProcessCount, deltaProcessCount, growthMBPerHour |
    Format-Table -AutoSize
```

- `deltaProcessCount` 가 큰 샘플에서 `growthMBPerHour` 도 크면 **비례 가설과 일치**한다.
- `deltaProcessCount` 가 작거나 음수인데 `growthMBPerHour` 가 크면 → 프로세스 수와 무관한
  다른 원인(내부 캐시·누수·배증)을 의심한다.

### ② 프로세스 수 구간별 평균 증가 속도

```powershell
$rows | Group-Object { [math]::Floor($_.systemProcessCount / 20) * 20 } | ForEach-Object {
    [pscustomobject]@{
        프로세스수구간 = $_.Name
        표본수        = $_.Count
        평균증가속도  = [math]::Round((($_.Group | Measure-Object growthMBPerHour -Average).Average), 3)
        평균MBper프로세스 = [math]::Round((($_.Group | Measure-Object growthMBPerNewProcess -Average).Average), 4)
    }
} | Sort-Object { [int]$_.프로세스수구간 } | Format-Table -AutoSize
```

프로세스 수 구간이 올라갈수록 평균 증가 속도가 단조 증가하면 비례 가설이 지지된다.

### ③ 재기동이 실제로 메모리를 내리는지

`restartTriggered = true` 인 샘플에서 `privateBytesBeforeRestartMB` 와
`privateBytesAfterRestartMB` 를 비교한다. 재기동 직후 값이 거의 그대로면
**재기동이 효과 없는 구조**(예: 메모리가 서비스가 아니라 공유 svchost 프로세스에 귀속)라는 뜻이므로
임계값을 올리거나 태스크를 해제하는 판단이 필요하다.

### ④ 프로세스 생성 이벤트까지 보려면 (선택)

Security 4688 기록이 켜져 있는 환경에서만 잡힌다. 감사 정책(계정 잠금 이벤트 감사 포함)을
먼저 켜고, 러너를 `-UseSecurityAuditCount` 로 실행한다.

## 주의사항

- **재기동 후에도 메모리가 줄지 않으면 1시간마다 다시 재기동한다.** 최소 간격 가드는
  과빈 재기동만 막고 횟수 제한은 두지 않는다. 무한 재기동이 걱정되면 태스크를 해제하거나
  `-ThresholdMB` 를 올려 등록을 다시 하라.
- 측정만 원하면 예약 태스크를 등록하지 않고 `-WhatIf` 로 수동 실행하는 편이 안전하다.
- `logs/` 는 머신 로컬 산출물이다(커밋하지 않는다).
- 스크립트는 특정 PC·특정 서비스에 묶지 않는다. 대상 서비스·임계값·주기는 모두 인자로 바꾼다.

## 참고

- 이슈: [giip 5142](https://giip.littleworld.net/ko/admin/giip-issues/5142)
- 등록 게이트는 이 저장소 공용 게이트를 재사용한다 —
  대상 파일 존재·파싱·worktree 경로 검사는 `scripts/gissue/task-target-guard.ps1`,
  태스크 이름과 실제 주기의 일치 검사는 `scripts/gissue/task-cadence-guard.ps1`.
