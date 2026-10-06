# Gissue Scheduler Run History — admin/catquest/schedulers 표시 문제 해결 (giip #3575)

> **문서 목적**: `admin/catquest/schedulers` 페이지에서 gissue 스케쥴러 실행 이력이 "History" 버튼을 눌러도 표시되지 않는 문제의 근본 원인과, 다른 도커 인스턴스에 동일하게 적용하기 위한 변경 내용을 기술한다.
>
> **정본**: 이 문서가 정본이다. 다른 도커 인스턴스에 적용할 때는 이 문서의 내용을 그대로 참조한다.

## 1. 증상

`admin/catquest/schedulers` 페이지에서:
- gissue 스케쥴러 에이전트는 목록에 정상 표시된다 (tSchedulerAgent 테이블에 등록된 에이전트)
- "History" 버튼을 누르면 이력 모달이 열리지만 **gissue 스케쥴러의 실행 이력이 표시되지 않음**
- 다른 일반 스케줄러(giipAgentLinux/giipAgentWin)는 정상적으로 이력이 표시됨

## 2. 근본 원인

gissue 스케쥴러는 도커 컨테이너의 cron에 의해 `pwsh`로 직접 실행된다:

```bash
# docker/entrypoint.sh (수정 전)
CRON_CMD="pwsh -NoProfile -NonInteractive -File \"$REPO_DIR/scripts/gissue/run-gissue-claude.ps1\"..."
```

`run-gissue-claude.ps1`은 PowerShell 스크립트이므로 bash의 `sar_run_start`/`sar_run_end` 함수(giipAgentLinux의 `lib/scheduler_agent_run.sh` 소속)를 직접 호출할 수 없다. 따라서 **실행 시작/종료를 `tSchedulerAgentRun` 테이블에 기록하는 절차가 아예 없다**.

이에 반해 `giipAgent3.sh`는 `lib/scheduler_agent_run.sh`를 source하여 매 1분 heartbeat 때마다 이력을 기록하므로, 다른 스케줄러와 달리 **gissue 스케쥴러의 이력만 빠져 있다**.

## 3. 해결 방법

### 3.1 생성 파일

**`scripts/gissue/run-gissue-scheduler-wrapper.sh`** (신규 생성)

gissue 스케쥴러 PowerShell 스크립트를 bash 래퍼로 감싸, 실행 전후에 `sar_run_start`/`sar_run_end`를 호출한다. giipAgentLinux의 `lib/scheduler_agent_run.sh`가 제공하는 이 함수는 `pApiSchedulerAgentRunStartBySK` / `pApiSchedulerAgentRunEndBySK` SP를 호출하여 `tSchedulerAgentRun` 테이블에 이력을 기록한다.

```bash
# 사용법: cron에서 pwsh 직접 호출 대신 이 래퍼를 호출
bash /work/giip-fde-agent/scripts/gissue/run-gissue-scheduler-wrapper.sh -OnlyCsn 47
```

giipAgentLinux가 아직 clone되지 않은 경우(sk/apiaddrv2 미설정)는 **기존처럼 pwsh를 직접 호출**한다. 이 경우 이력은 기록되지 않지만 스케쥴러 자체 동작에는 영향이 없다.

### 3.2 수정 파일

**`docker/entrypoint.sh`** (수정)

gissue 스케쥴러 cron의 실행 커맨드를 pwsh 직접 호출에서 bash 래퍼 호출로 교체한다.

```bash
# 수정 전
CRON_CMD="pwsh -NoProfile -NonInteractive -File \"$REPO_DIR/scripts/gissue/run-gissue-claude.ps1\"..."

# 수정 후
CRON_CMD="bash \"$REPO_DIR/scripts/gissue/run-gissue-scheduler-wrapper.sh\"..."
```

## 4. 이력 기록이 작동하는 원리

1. **cron 트리거** → `run-gissue-scheduler-wrapper.sh` 실행 (bash)
2. **래퍼** → giipAgentLinux의 `lib/scheduler_agent_run.sh`를 source하여 `sar_run_start`, `sar_run_end_trap` 함수 로드
3. **`sar_run_start`** → `pApiSchedulerAgentRunStartBySK` SP 호출 → `tSchedulerAgentRun`에 RUNNING 상태의 실행 시작 행 INSERT
4. **래퍼** → `trap 'sar_run_end_trap' EXIT`로 종료 핸들러 등록
5. **`run-gissue-claude.ps1`** → 실제 이슈 처리 PowerShell 스크립트 실행
6. **스크립트 종료** → `sar_run_end_trap` 트랩이 호출됨 → `pApiSchedulerAgentRunEndBySK` SP 호출 → `tSchedulerAgentRun`의 실행 시작 행을 SUCCEEDED/FAILED 상태로 업데이트

> ⚠️ **함정(exec 금지) — giip #3575 재개 시 수정**: 위 6단계가 실제로 동작하려면 래퍼가 `run-gissue-claude.ps1`을 **`exec` 없이** 호출해야 한다. `exec pwsh ...`로 호출하면 bash 프로세스가 pwsh로 **교체**되어 `trap 'sar_run_end_trap' EXIT`가 영영 실행되지 않는다. 그 결과 `sar_run_start`(RunStart)만 기록되고 `sar_run_end`(RunEnd)는 호출되지 않아 이력이 "시작만 있고 끝이 없는" 반쪽 상태로 남는다. 다른 도커 인스턴스에 이 래퍼를 포팅할 때도 이력 기록 경로의 마지막 pwsh 호출에는 절대 `exec`를 붙이지 않는다(sk/apiaddrv2가 없어 이력을 기록하지 않는 폴백 경로는 트랩이 없으므로 `exec`를 써도 무방하다).

## 5. 다른 도커 인스턴스에 적용하는 절차

이미 giip-fde-agent가 기동 중인 도커 인스턴스에 이 수정을 적용하려면:

### 5.1. 파일 복사 (giip-fde-agent/scripts/gissue/run-gissue-scheduler-wrapper.sh)

컨테이너 안에서 아래 명령을 실행하거나, 호스트에서 `docker cp`로 복사한다:

```bash
# 호스트에서
docker cp <container>:/work/giip-fde-agent/scripts/gissue/run-gissue-scheduler-wrapper.sh ./
# 또는 이 레포의 해당 파일을 복사
```

### 5.2. 실행 권한 부여

```bash
chmod +x /work/giip-fde-agent/scripts/gissue/run-gissue-scheduler-wrapper.sh
```

### 5.3. cron 설정 확인

`/etc/cron.d/gissue-scheduler` 파일의 cron 라인을 확인한다:

```bash
# 수정 전
7,27,47 * * * * root cd /work/giip-fde-agent && pwsh -NoProfile -NonInteractive -File "/work/giip-fde-agent/scripts/gissue/run-gissue-claude.ps1" ...

# 수정 후
7,27,47 * * * * root cd /work/giip-fde-agent && bash "/work/giip-fde-agent/scripts/gissue/run-gissue-scheduler-wrapper.sh" ...
```

### 5.4. cron 재로드

```bash
# cron 데몬이 실행 중인 경우
cron  # 재로드 (cron 데몬이 이미 실행 중이면 아무 동작 안 함)
# 또는
service cron restart
```

또는 컨테이너를 재기동하면 `entrypoint.sh`가 새 cron 설정을 적용한다.

## 6. 검증 방법

### 6.1 이력 확인 (즉시)

```bash
# gissue 스케쥴러 실행을 수동 트리거
docker exec <container> bash /work/giip-fde-agent/scripts/gissue/run-gissue-scheduler-wrapper.sh -OnlyCsn <csn> -DryRun
```

### 6.2 DB에서 이력 확인

```sql
-- 가장 최근 gissue 스케쥴러 실행 이력 확인
SELECT TOP 10
    r.runId,
    a.agentKey,
    a.displayName,
    r.executionMode,
    r.status,
    r.startTime,
    r.endTime,
    r.durationSec
FROM tSchedulerAgentRun r
JOIN tSchedulerAgent a ON r.agentId = a.agentId
WHERE a.agentType = 'giipAgentLinux'
ORDER BY r.startTime DESC;
```

### 6.3 UI 확인

`admin/catquest/schedulers` 페이지에서 gissue 스케쥴러 에이전트의 "History" 버튼을 누르고, 이력 모달에 실행이력이 표시되는지 확인한다.

## 7. 관련 파일

| 파일 | 역할 |
|---|---|
| `scripts/gissue/run-gissue-scheduler-wrapper.sh` | gissue 스케쥴러 bash 래퍼 (신규) |
| `docker/entrypoint.sh` | cron 등록 로직 (수정) |
| `lib/scheduler_agent_run.sh` (giipAgentLinux) | `sar_run_start`/`sar_run_end` 함수 정의 |
| `lib/scheduler_agent_register.sh` (giipAgentLinux) | tSchedulerAgent 등록 및 SQL 리터럴 헬퍼 |
| `docker/giipAgentLinux/` | giipAgentLinux clone 디렉터리 |

## 8. 한계 및 주의사항

- **giipAgentLinux clone 필요**: 래퍼는 `/work/giipAgentLinux/lib/scheduler_agent_run.sh`가 존재해야 이력 기록 함수를 사용할 수 있다. giipAgentLinux가 clone되지 않은 상태(예: `GIIP_ENABLE_AGENT=false`)에서는 기존처럼 pwsh를 직접 호출하고 이력은 기록되지 않지만 스케쥴러 자체는 정상 동작한다.
- **API 실패는 스케쥴러 실행에 영향을 주지 않음**: `sar_run_start`/`sar_run_end` API 호출이 실패해도(네트워크 오류, SP 오류 등) 스케쥴러 자체 실행에는 영향이 없다 — WARN 로그만 남기고 계속 진행한다.
- **runIdKey 포맷**: 실행 ID는 UTC 타임스탬프 + PID로 생성되므로, 컨테이너 재기동 후에도 고유하다.
- **적용 시점(중요)**: `entrypoint.sh`는 컨테이너가 기동할 때만 실행되어 `/etc/cron.d/gissue-scheduler`를 쓴다. 따라서 이미 떠 있는 컨테이너는 **재기동 전까지는 기동 당시의 cron 라인을 그대로 유지**한다. 이미 떠 있는 인스턴스에 이 수정을 반영하려면 위 5절처럼 래퍼 파일을 교체하고(필요 시 `/etc/cron.d/gissue-scheduler`의 cron 라인도 래퍼 호출로 바꾼 뒤), 컨테이너를 재기동하거나 cron 설정을 다시 읽히는 것까지 해야 cron 구동 이력이 쌓이기 시작한다.
- **exec 금지(run-end 보장)**: 4절의 함정 참고. 이력 기록 경로에서는 pwsh를 `exec` 없이 호출해야 EXIT 트랩이 떠서 run end가 기록된다.
