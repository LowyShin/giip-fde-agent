# 작업 기록 — 스케줄러 tKVS 시작/알람/리포트 + 본체 비AI 원칙 명문화 (giip 5345)

- 일시: 2026-11-15 11:28 JST
- 근거: 사용자 직접 지시 — (1) 스케줄러에서 limit 등 에러가 나면 GIIP KVS(tKVS)에 알람,
  (2) 실행 리포트를 tKVS에 보고하되 실행 PC의 hostname·IP를 함께 기록(같은 CSN을 두 머신에서
  실행하는 경우가 있음), (3) giip-fde-agent를 수정해 GitHub에 올리면 스케줄러가 최신 레포를
  받도록, (4) 스케줄러 본체가 처음부터 AI를 쓰면 limit 순간에 전송할 수 없으므로 GIIP 스타트
  로깅 후 필요할 때만 AI를 호출하는 방식으로 가이드를 잘 만들 것. 등록 이슈 giip 5345 (PENDING).

## 현행 실측 (정본 코드 확인, run-gissue-claude.ps1 4,022줄 기준)

- tKVS 기록은 종료 시점의 `scheduler_run_history` 1건뿐(giip #2384): 건수 + hostname.
  시작 기록 · IP · limit 알람 없음. `finally` 에서만 쓰므로 프로세스가 강제 종료되면 유실 가능.
- SchedulerAgent 상태(giip #3563: upsert/runStart/heartbeat/runEnd)는 DB SP 기록이라 tKVS가
  아니고 IP가 없다(hostname은 upsert에만).
- limit 판정은 엔진 시도 내부(MiniMax 429/quota 서명 → Claude 폴백)에만 있고, 폴백까지 실패하면
  로컬 로그·로컬 알람 파일에만 남았다.
- 자기 갱신은 기존에 있음: 시작 시 self-pull(giip #2386) + NOT-ON-MAIN 복귀 + code-freshness
  가드(giip #2471). 단, 어느 머신이 어느 커밋으로 돌았는지 GIIP에서 볼 방법이 없었다.

## 변경 파일 (7건)

1. `scripts/gissue/lib/kvs-report.ps1` (신규) — `Get-GissueHostIdentity`(hostname+IPv4 목록),
   `Test-GissueLimitSignature`/`Get-GissueAlarmKind`(판정 정본, rule 48), `Send-GissueKvsPut`
   (전송 본체 — giipApiSk4 + token, KVSPut, 무BOM 임시파일, RstVal 검사, fail-open,
   테스트용 전송 포트 `$script:GissueKvsTransport`), 시작/알람/리포트 래퍼 3종.
   kFactor: `scheduler_run_start` / `scheduler_alarm` / `scheduler_run_report`
   (키 공간은 기존과 동일: kType='lssn', kKey=LSSN).
2. `scripts/gissue/run-gissue-claude.ps1` —
   - 매핑 로드 직후 lib 닷소싱.
   - `Send-GissueRunHistory` 본체를 `Send-GissueKvsPut` 경유로 일원화(호출부·로그 표기 유지).
   - NOT-ON-MAIN 체크(self-pull) 직후 시작 기록: runId · csn 목록 · agentCommit · hostname/IP.
     어떤 엔진 호출보다 앞선다.
   - `Complete-Run`: CSN별 종료 리포트 + 알람 판정(잡 출력에서 limit 서명 검출 — DONE이어도
     LIMIT 알람; TIMEOUT/ZOMBIE/OVERTIME/RUN_FAIL).
   - `finally` 종료 집계에 ips + csnResults 추가.
3. `docs/60-operations/hourly-issue-scheduler.md` — §17 신설(본체 비AI 원칙, 기록 4종 표,
   머신 식별, limit 판정, 자기 갱신과의 관계, 테스트).
4. `scripts/gissue/tests/test-kvs-report.ps1` (신규) — 판정·페이로드를 네트워크 없이 검증
   (전송 포트 교체). 게이트 기대 건수 41→42 (`run-repo-gates.ps1`).
5. `docs/WHATS_NEW.md` — 2026-11-15 항목 + 기준일 갱신.
6. 이 작업 기록.

## 설계 판단

- **알람 판정을 Complete-Run 한 곳에 둔 이유**: 잡(Start-Job) 내부의 엔진 판정은 폴백 결정용이라
  스코프가 다르고, 메인 프로세스가 확실히 아는 것(최종 상태 + 잡 출력 전문)은 Complete-Run
  시점뿐이다. limit 서명 검출을 본체 텍스트 판정으로 하면 AI 없이도, 엔진이 어떻게 죽었든
  (폴백 실패 포함) 알람이 나간다.
- **시작 기록의 SK**: 어느 CSN의 SK로도 같은 LSSN 키 공간에 쓸 수 있어(기존 run-history가
  anySk를 쓰는 것과 동일 규약) 매핑의 첫 번째로 잡히는 SK를 쓴다. 없으면 SKIP 로그.
- **자기 갱신 자체는 손대지 않았다**: self-pull(기존)이 전파 경로이고, 이번 작업은 그 위에
  agentCommit이 든 시작 기록을 얹어 "전파됐는가"를 GIIP에서 대조 가능하게 한 것이다.
  복사본 배포(§13-2)처럼 정본 체크아웃 밖에서 도는 러너는 self-pull 대상이 아니라는 한계는
  가이드 §17-5에 명시했다.
- 시작 기록은 DryRun에서도 남는다 — 기존 heartbeat가 DryRun에서도 발신되는 것과 같은 동작이다.

## 검증

- 이 VM에는 PowerShell이 없어 테스트 실행은 CI(repo-gates)와 Windows 호스트 게이트에 맡긴다.
  대신 diff 전수 검토 + 괄호 균형 + BOM(신규 ps1 2건 UTF-8 BOM 부여) 확인.
- 커밋 전 `git diff`로 추가 줄의 타 CSN 번호·고객 식별 문자열을 확인한다(기대 출현: 자 CSN
  70424와 기존 코드가 인용하는 giip 이슈 번호뿐).
- 이 작업의 worktree(`wt-kvsreport`)는 PR 머지 후 rule 57에 따라 정리한다.

## CI 검증 결과 (2026-11-15)

- PR #443 1차 CI: PS1 게이트에서 `test-kvs-report.ps1` 1건 실패 — 원인은 lib의 래퍼 함수가
  `Write-Output`으로 로그를 써서 반환 스트림이 오염되고, 전송 실패($false)가 배열 truthy로
  판정된 것. 실제 러너에서도 `Send-GissueRunHistory`의 OK/FAIL 로그가 잘못 찍힐 수 있는
  실결함이라, 함수 내 로그를 전부 `Write-Host`로 바꾸고 빈 SK/LSSN 가드가 바인딩 단계에서
  막히지 않게 Mandatory를 풀어 수정 커밋을 추가했다(lib 헤더에 재발 방지 주석 명시).
- 2차 CI: PS1 게이트 · MJS 게이트 · GitGuardian 전부 pass.
