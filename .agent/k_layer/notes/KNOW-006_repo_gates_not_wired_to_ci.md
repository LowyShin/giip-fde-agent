# KNOW-006: 저장소 자체 게이트가 CI 에 결선돼 있지 않으면 결함이 검증 없이 main 에 유입된다

- 작업 CSN: 70424
- 관련 파일: `scripts/gissue/run-repo-gates.ps1`(신규 — 게이트 단일 진입점),
  `.github/workflows/repo-gates.yml`(신규 — CI 결선), `scripts/gissue/check-ps1-parse.ps1`(기존),
  `scripts/gissue/tests/test-*.ps1`(기존 20건), `scripts/gissue/tests/test-*.mjs`(기존 4건)
- 근거: 2026-10-24 CSN 70424 저장소 정비 세션 실측
  (`.agent/work_history/20261024_051500_csn70424_repo-maintenance.md`)
- 상호링크: [KNOW-005](KNOW-005_child_process_output_tests_are_console_codepage_dependent.md) §3-2.
  KNOW-005 는 **환경 축**, 이 노트는 **자동화 축**.

## 1. 현상

2026-10-24 이전 정비 세션이 회귀 테스트 3건이 **실패한 채 main 에 유입된 상태**를 실측
확인했다(pwsh 하드코딩 / 셸 경유 커밋 본문 소실 / `/tmp` 하드코딩).
PR #234·#235·#236 으로 고쳤지만 **재발 방지 계층은 없었다.**

## 2. 원인 — 게이트는 존재하나 어디에서도 자동으로 돌지 않는다

| 계층 | 파일 | 규모 |
|------|------|------|
| 정본 게이트 | `scripts/gissue/check-ps1-parse.ps1` | `.ps1` 66건 구문 + BOM 검사 |
| ps1 회귀 테스트 | `scripts/gissue/tests/test-*.ps1` | 20건 |
| mjs 회귀 테스트 | `scripts/gissue/tests/test-*.mjs` | 4건 |

`.github/workflows/` 에는 `windows-hook-doctor.yml` 하나뿐이라 위 게이트는 **"사람이 수동으로
돌렸을 때만"** 실행됐다. 그 결과:

- 저장소 게이트(`check-ps1-parse.ps1 -All`)는 **green**(main 에서 exit 0) — 그런데 같은 저장소의
  회귀 테스트는 **3건 실패**하고 있었다. 게이트는 `.ps1` 의 구문·인코딩만 본다.
  **"실행되어 실패하는 것"은 별개의 층**이다.
- 실패한 채로 **main 에 머지됐다** — PR 을 막을 빨간 게이트가 없었으니까. 발견 시점은
  "다음 정비 세션이 우연히 전수 실행"이었다.

## 3. 왜 위험한가

1. **"테스트가 있다" 와 "테스트가 돌아간다" 는 다르다.** 자동 실행 없이 존재만 하는 회귀
   테스트는 문서와 같다.
2. **PR 이 빨간 CI 가 없으면 머지 게이트가 사람이다.** 사람이 매번 전수 돌리려면 결국 안 돌린다 — 실제로 결함 발견까지 여러 세션이 지나갔다.
3. **rule 42 의 "검사기가 0개를 검사하고 PASS" 패턴의 변형** — 게이트의 존재는 게이트의 작동을 보증하지 않는다.

## 4. 조치 — 단일 진입점 + CI 결선

### 4-1 `scripts/gissue/run-repo-gates.ps1` (신규)

- 단계 1: `check-ps1-parse.ps1 -All` 을 **자식 프로세스**로 실행
- 단계 2: `tests/test-*.ps1` **전수**를 `powershell -NoProfile -ExecutionPolicy Bypass -File` 로 1개씩 실행, 종료코드 수집
- 단계 3: `tests/test-*.mjs` **전수**를 `node` 로 실행, 종료코드 수집
- **판정 로직을 YAML 에 복붙하지 않는다**(rule 48). CI 와 로컬이 **똑같은 코드**를 돌린다 →
  "워크트리 green ≠ main green"(KNOW-005) 계열 사고를 구조적으로 차단.
- `RepoRoot` 미지정 시 **스크립트 위치에서 2단계 상위**로 추정.
  (실측 함정: `powershell -File` 호출에서 `$MyInvocation.MyCommand.Path` 가 빈 문자열이 될 수
  있어 `$PSScriptRoot` 를 쓴다.)
- **검사 건수를 반드시 출력**(rule 42). 총 0건이면 exit 1.
- **기대 건수 하한선**(ps1 20건 / mjs 4건): 발견 건수가 적으면 실패 → 테스트 파일이 **조용히 사라져도** "20건 전부 통과" 처럼 보이지 않는다.
- `node` 부재 시 **명확한 FAIL + exit 1** — 무음 PASS 금지.
- `-SkipPs1Tests`/`-SkipMjsTests` 는 건너뛴 단계를 **명시 출력**. **읽기 전용**.

### 4-2 `.github/workflows/repo-gates.yml` (신규)

- `pull_request`(열린 PR) + `push` to `main`, `permissions: contents: read`
- job 2개 병렬: `ps1-gates`(단계 1·2) / `mjs-gates`(단계 3). `windows-latest`,
  `timeout-minutes: 15`
- `actions/checkout@v4` + `actions/setup-node@v4`(node-version: 24 — 기존 워크플로와 동일)
- **Windows PowerShell 5.1 로만 호출**(이 PC/러너에 `pwsh` 가 없다 — 부르면 "command not found" 로 아무 일도 하지 않고 끝난다):
  `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gissue/run-repo-gates.ps1`
  (ps1 job) / `... -SkipPs1Tests` (mjs job).
- 단계별 스텝 분리 안 하고 스크립트 1줄 호출 — 로직은 스크립트 한 곳에 둔다.

### 4-3 rule 53 §3 정합

rule 53 §3 은 "서버사이드 CI 를 정식 enforcement 로 삼고, 클라이언트사이드 가드는 보조로
유지한다 — 둘 중 하나로 줄이지 않는다" 를 규정한다. 이번 조치로 서버사이드 층(CI)=정식
enforcement, 클라이언트사이드 층(로컬 실행 스크립트)=보조 로 **둘 다 유지**한다.

## 5. 재발 방지

1. **게이트는 "실행 진입점" 1개만.** YAML 에 판정 조건 복붙 금지(rule 48).
2. **검사 건수를 출력하고 0건이면 통과로 읽지 않는다**(rule 42). 기대 건수 하한선까지 두면
   "파일 하나 사라짐" 도 잡힌다.
3. **"CI 가 있다" 는 "CI 가 매 PR 에서 돌아그 결과를 사람이 본다" 를 뜻하지 않는다.**
4. **환경 축도 함께 고정한다**(코드페이지 cp437/cp932/65001) — KNOW-005 참조.

## 6. 결과 저장처 / 소비처

- 게이트 진입점 `scripts/gissue/run-repo-gates.ps1` · CI `.github/workflows/repo-gates.yml`
- 이 노트 + `INDEX.md` 색인 · 작업 기록 `.agent/work_history/20261024_051500_csn70424_repo-maintenance.md`
- 소비처: PR 을 만드는 모든 세션(PR 이 빨간 게이트로 뜨는지 확인), 회귀 테스트를 추가·삭제하는
  세션(기대 건수 하한선 갱신 필요)
- **tKB 등록 4000자 한계**: `sync-klayer` 는 4000자를 넘으면 절단한다(조용히 손실) →
  본문을 4000자 미만으로 유지하고, `--no-truncate` 등록이 "N자 > 4000자" 로 실패하면 **원문을 줄인 뒤** 재등록한다.

## 7. 관련 규칙

42 · 48 · 53 §3 · 35 · 50 · 36 · 37 · 61(k-layer 은 커밋으로 성립)
