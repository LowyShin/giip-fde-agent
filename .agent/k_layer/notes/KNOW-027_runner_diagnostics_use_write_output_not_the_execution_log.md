# KNOW-027 — 러너 진단은 Write-Output( stdout )이라 실행 로그에 남지 않는다

> 근거: 2026-11-02 저장소 정비 71차 세션 실측 (work_history 20261102_1723) · 발행: 2026-11-02 · 상태: 검증됨(실측)

## 요지

**러너가 `Write-Output` 으로 찍는 진단 줄은 `logs/gissue_csn<N>.log` 에 남지 않는다. 로그 파일에 남는 건 `Write-Log` 뿐이다.**

`scripts/gissue/run-gissue-claude.ps1` 의 진단 출력 경로가 두 개로 갈린다.

| 경로 | 목적지 | 실행 로그 파일에 남는가 |
|---|---|---|
| `Write-Log $r.Csn "<msg>"` | `logs/gissue_csn<csn>.log` (파일 append) **+ stdout** | **예** |
| `Write-Output "<msg>"` | stdout 만 | **아니오** |

스케줄러 태스크(`GIIP_Gissue_Claude`)의 실행 정의는 stdout 을 파일로 리다이렉트하지 않는다 →
러너 stdout 은 태스크 호스트 콘솔로 흘러 사라진다.

## 왜 위험한가

"다음 :07 실행 로그에서 `<TAG>` 을 확인하면 된다" 는 형태의 검증 지침이 **`Write-Output` 대상이면 영원히 확인되지 않는다.**
지침을 따라 grep 하면 0 건이 나오는데, 기능 자체는 정상일 수 있다(로그에 안 쓰는 것이지 안 나오는 것이 아니다).

실측 사례 — giip 4429 (2시간 초과 처리 규칙 Live 전환, lowyworkenv PR #1068):

- lowyworkenv 러너는 시작 시 `run-gissue-claude.ps1:284` 에서
  `Write-Output "[OVERTIME] mode=$($OvertimeSettings.Mode) source=$($OvertimeModeInput.Source) raw=..."` 를 출력한다.
- lowyworkenv `scripts/gissue/lib/overtime-host-default.ps1:13` 의 주석은 이 줄이
  "러너 stdout(=logs/ 실행 로그)" 에 남는다고 적어 놓았는데 — **stdout 과 logs/ 실행 로그 는 서로 다르다.**
- 2026-11-02 17:23:47 회차(PR #1068 머지 뒤 첫 :07) 이후에도
  `grep -c "OVERTIME" scripts/gissue/logs/gissue_csn70424.log` → **0**,
  `grep -rh "mode=Live" scripts/gissue/logs/` → **0** 이었다.

## 판정 규칙

1. **검증 지침이 로그 파일을 지목할 때, 그 줄이 `Write-Log` 인지 `Write-Output` 인지 먼저 확인한다.**
   `grep -n 'Write-Output "\[TAG' scripts/gissue/run-gissue-claude.ps1` 로 1줄이면 `Write-Output` 이다.
2. `Write-Output` 진단을 로그로 확인해야 하면 **작업 지침을 먼저 고친다**(러너를 `Write-Log` 로 바꾸거나
   스케줄러 태스크에 stdout 리다이렉트를 추가한다). 지침만 남기고 확인을 미루면 되돌아오지 않는다.
3. **정본(giip-fde-agent)의 러너는 시작 모드 줄 자체가 없다** —
   `grep -n 'OVERTIME\] mode=' scripts/gissue/run-gissue-claude.ps1` → 0 건.
   모드 관련 `[OVERTIME]` 출력은 `Write-Log` 결과 줄(과시간 초과가 실제로 발생할 때만)뿐이다.
   → 정본에서 "현재 모드가 뭐냐" 를 로그로 확인하는 일은 애초에 성립하지 않는다. 소스/상수로 판단한다.
4. **stdout 이 사라지는 게 문제인 게 아니라, "로그에서 확인하라" 는 지침이 거짓말을 하게 되는 게 문제다.**
   지침을 쓴 사람이 실제로 확인 가능한 경로로 바꿔 주지 않으면 다음 세션이 같은 지침을 다시 검증하고
   또 0 건을 보고 "기능이 안 된다" 는 오진단을 낼 수 있다.

## 관련

- `KNOW-021` — 스케줄러 생존은 로그 신선도로 판정
- `KNOW-025` — 긴 한글 요약 문장은 음절이 틀려도 유효 UTF-8 로 저장된다
- 작업 기록: `.agent/work_history/20261102_1723_csn70424_repo-maintenance.md`
