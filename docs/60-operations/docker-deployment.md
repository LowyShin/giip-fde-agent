# Docker 배포 — slack-bot + hourly-issue-scheduler (giip #2665)

새 환경에서 giip-fde-agent를 "auto clone + csn/sk/login_id 등록 + slack-bot·scheduler 기동"까지
한 번에 세팅하기 위한 Docker 배포 정본입니다. 정본 파일은 `docker/`
([`Dockerfile`](../../docker/Dockerfile), [`entrypoint.sh`](../../docker/entrypoint.sh),
[`setup-registration.js`](../../docker/setup-registration.js),
[`docker-compose.yml`](../../docker/docker-compose.yml)) 이며, 이 문서는 그 동작 원리와
전제조건을 설명합니다.

## 1) 무엇을 자동화하는가

기존에는 [§13 배포 절차](./hourly-issue-scheduler.md#13-배포-절차신규-csnpc--복사만으로-이식)와
[`slack-bot/README.md`](../../slack-bot/README.md#per-project-giip-csn-routing)에 있는 수동 절차
(clone → `csn-projects.json`/`giip-accounts.json` 복사 후 값 채움 → 실행)를 사람이 PC마다 직접
반복해야 했습니다. 이 Docker 배포는 그 세 단계를 컨테이너 기동 시 자동으로 수행합니다.

| 수동 절차 | 자동화 담당 |
|---|---|
| 레포 clone/pull | `docker/entrypoint.sh` |
| `csn-projects.json` 채우기 | `docker/setup-registration.js` (env var → JSON) |
| `slack-bot/.secrets/giip-accounts.json` 채우기 | `docker/setup-registration.js` (env var → JSON) |
| slack-bot 실행(pm2) | `docker/entrypoint.sh` |
| scheduler 실행(Windows Task Scheduler 대신 cron, §3의 실행 커맨드 템플릿 그대로) | `docker/entrypoint.sh` |

이미 파일이 있으면(볼륨 마운트로 영속화된 경우) 건드리지 않습니다 — `GIIP_FORCE_REGEN=true`가
아닌 한 idempotent합니다.

## 2) 사용법

```bash
cd docker
cp .env.example .env   # GIIP_LOGIN_ID / GIIP_SK / GIIP_CSN 등 실값 채움
docker compose up -d --build
docker compose logs -f
```

env var 전체 계약은 [`.env.example`](../../docker/.env.example)이 정본입니다.

### 2-1) GIIP web에서 `.env`를 완결시키기 (giip 2665)

`.env`에 값을 직접 채우는 대신, GIIP web(admin > Docker Instances, `giipv3`)에서 "Docker 인스턴스
생성"을 누르면 login_id/sk/csn/slack 토큰 등을 입력받아 **giipfaw가 서버측에서 AES-256-GCM으로
암호화해 DB에 저장**하고 `instanceToken` 1개만 화면에 보여줍니다(재조회 불가 — 생성 시 1회만 노출).
`.env`에는 그 토큰 한 줄만 넣으면 됩니다:

```env
GIIP_INSTANCE_TOKEN=<발급받은 토큰>
```

컨테이너 기동 시 `docker/fetch-instance-env.sh`가 `dockerInstanceFetch` API(`giipfaw`, anonymous
auth, 토큰 자체가 자격증명)를 호출해 나머지 env를 내려받고, 이미 `.env`에 직접 채워둔 키는
그대로 우선합니다(부분 override 가능). 토큰 폐기는 같은 화면의 Revoke 버튼으로 즉시 반영됩니다.

**구성 요소**(giipprj-hub, 이 레포와는 별도 저장소):
- DB: `giipdb/Tables/tDockerInstance.sql` + `giipdb/SP/pApiDockerInstance{Create,List,Revoke}byAK.sql`, `pApiDockerInstanceFetchbyToken.sql`
- API: `giipfaw/giipApiJson/run.ps1`(`DockerInstanceCreate` 특수 처리 — 암호화 후 SP 호출), `giipfaw/dockerInstanceFetch/`(신규 Function, 토큰으로 조회+복호화)
- UI: `giipv3/src/app/[locale]/admin/docker-instances/page.tsx`

**검증 상태(정직하게 명시)**: 코드는 작성했지만 `tDockerInstance` 테이블 생성(DDL)이 하네스 안전
가드("Modify Shared Resources")에 막혀 **실제 DB 배포·end-to-end 실행은 아직 못 했습니다.** 테이블
DDL은 사용자 승인 후 별도로 배포해야 합니다. giipv3 화면도 로컬 빌드 검증(TypeScript 컴파일)은
하지 못했고 괄호/중괄호 균형만 정적으로 확인했습니다.

## 3) 선행 조건 — `run-gissue-claude.ps1`의 Linux/pwsh 포팅 (giip #2665)

기존 §13-1-1은 "이 레포의 `.ps1`은 **Windows PowerShell 5.1 전용**"이라고 명시하고 있었습니다.
이 Docker 배포를 만들면서 실제로 `pwsh`(Linux)에서 `-DryRun` 실행을 검증한 결과, 안전장치
(busy-check/orphan reaper)가 쓰는 **Windows 전용 WMI(`Get-CimInstance Win32_Process`)** 때문에
Linux에서는 조용히 무력화되거나 예외가 나는 것을 실측 확인했고, `Resolve-GissueBashExe`(bash 경로
탐색)도 Linux에서 `'C:\Git'`/`'D:\Git'` 리터럴 경로를 `Join-Path`에 넘겨 "Cannot find drive" 로
크래시하는 것을 확인했습니다. `run-gissue-claude.ps1`에 **$IsWindows 분기로 두 곳을 직접 패치**
했습니다(commit `fc75fc2`):

- `Get-CimInstance Win32_Process` 4곳 → Windows 경로는 그대로, Linux 경로는 `/proc/<pid>/{stat,comm,cmdline}` 직접 파싱으로 대체 (`Get-GissueProcInfo`/`Get-GissueChildIds` 신설)
- `claude.exe` 프로세스명 하드코딩 → Windows는 `claude.exe`, Linux는 `claude`로 분기
- `Resolve-GissueBashExe`의 Windows 전용 탐색 단계(2)/(3) → Linux에서는 건너뛰고 PATH 탐색(1단계, Linux는 bash가 기본 내장)만 사용

**PowerShell 5.1 호환 유의점**: `$IsWindows` 자동변수는 PowerShell 5.1에 없어(`$null`=falsy) 그대로
쓰면 Windows에서도 Linux 분기를 타버립니다. 그래서 `Get-Variable -Name IsWindows ... ` 로 변수
존재 여부를 먼저 보고, **변수가 없으면 무조건 Windows로 취급**하도록 판정했습니다
(`$script:GissueIsWindowsHost`, 함수 정의 순서상 이 변수보다 먼저 호출될 수 있는
`Resolve-GissueBashExe` 안에서는 같은 패턴을 로컬로 다시 계산).

**검증 상태(정직하게 명시)**:
- ✅ 구문+BOM: Windows PowerShell 5.1 / pwsh 7(Linux 컨테이너) 양쪽에서 `check-ps1-parse.ps1` 통과
- ✅ 기능: pwsh 7(Linux 컨테이너)에서 `-DryRun -OnlyCsn <더미CSN>` 실행 시 preflight → CSN guard →
  merge-sweep → 저장소 정비 세션 예정 로그까지 정상 도달 (크래시 없음)
- ❌ **미검증**: 실제 CSN/SK로 Windows PowerShell 5.1에서 `-DryRun`이 아닌 실행, 실제 GIIP issue
  API 호출, `claude -p` 헤드리스 엔진 실행까지의 전체 end-to-end
- ⚠️ **알려진 한계**: 안전 규칙 프롬프트 템플릿(`$CommonSafetyRulesBlock` 등)에 `{AGENT_REPO}\.agent\rules\...`
  형태의 리터럴 백슬래시 경로가 남아 있습니다. 이건 실제 파일시스템 API 호출이 아니라 `claude -p`에게
  보내는 **자연어 프롬프트 텍스트**라 크래시하지는 않지만(에이전트가 보통 `\`/`/` 둘 다 이해),
  Linux 배포에서는 이상적으로는 `/` 로 통일해야 합니다 — 이번 작업 범위에서는 손대지 않았습니다.

Docker 이미지는 `mcr.microsoft.com/powershell:7.4-debian-12` 베이스라 처음부터 `pwsh`가 있습니다.

## 4) `gh` CLI 미포함

`docker/Dockerfile`은 기본적으로 GitHub CLI(`gh`)를 설치하지 않습니다. PR 조회/충돌 확인·CI
수정([0]/[E] 단계) 기능이 필요하면 이미지에 `gh` 설치를 추가하고 `GITHUB_TOKEN`을 주입해야 합니다
(§4 필수 선행조건 참고). 없어도 스케줄러 자체는 `[PREFLIGHT-WARN]`만 남기고 계속 동작합니다.

## 5) 관련 문서

- 스케줄러 본체 스펙: [`./hourly-issue-scheduler.md`](./hourly-issue-scheduler.md)
- slack-bot csn/sk/login_id 매핑, `giip project set/list/del`: [`../../slack-bot/README.md`](../../slack-bot/README.md)
