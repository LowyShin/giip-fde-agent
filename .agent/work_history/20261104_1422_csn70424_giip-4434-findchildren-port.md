# CSN 70424 — giip 4434 find-children 조회 결함의 정본 기준선 확정 (2026-11-04 14:22 KST)

## 세션 정체

- 작업 CSN: **70424** · 프로젝트: `giip-fde-agent`
- 이슈: **giip 4434** — "[gissue] 2시간 초과 Live 처리 find-children 조회 — execSQLFile 출력 모드 불일치로 항상 실패, 중복 서브이슈 감지 무력화 (원본 giip 4429 후속)"
  (https://giip.littleworld.net/ko/admin/giip-issues/4434)
- **실행 공학 세션** — 코드를 직접 구현·검증·PR 올리는 것이 목표.
- 공유 체크아웃(`C:\Users\lowys\Downloads\projects\giip-fde-agent`)의 전용 브랜치 `bot/gissue4434-overtime-findchildren-port` 에서만 작업했다.

| 브랜치 | 기준 | 비고 |
|---|---|---|
| `bot/gissue4434-overtime-findchildren-port` | `origin/main` = `38b7a4e` | 공유 체크아웃에서 전용 브랜치로 작업 |

## 이슈 범위 (본문 "범위 (정본 = giip-fde-agent)" 3항목) → 산출물 매핑

| # | 본문 범위 | 산출물 | 상태 |
|---|---|---|---|
| 1 | k-layer 노트 신설 — "execSQLFile.ps1 출력은 SqlServer 모듈 유무에 따라 텍스트/객체로 갈린다" + "러너 포트는 API 경로를 써야 한다" | `.agent/k_layer/notes/KNOW-029_*.md` 신규 + `INDEX.md` 행 + tKB 등록 | **완료** (tKB kbSn **6943**) |
| 2 | 회귀 테스트 신설 — 정본 러너의 `FindOpenChildren` 포트가 DB 직접 조회에 의존하지 않음을 고정 | `scripts/gissue/tests/test-overtime-findchildren-port.ps1` 신규 | **완료** |
| 3 | (선택) 행 파서 헬퍼 + 그 헬퍼의 테스트 | `scripts/gissue/lib/overtime-split.ps1` 에 `Get-GissueIssueRowsFromQueryOutput` 추가 | **완료** |
| 4 | (범위 밖 · 별개 결함) 세션 중 새로 측정한 PS 5.1 JSON 배열 미전개 결함의 사실 등록 | `.agent/k_layer/notes/KNOW-035_*.md` 신규 + `INDEX.md` 행 + tKB 등록 | **완료** (tKB kbSn **6945**) — 정본 러너 동작 수정은 후속 |

> **k-layer 번호는 `KNOW-028` 이 아니라 `KNOW-029`** — 2026-11-03 저장소 정비 79차가 issue note(cSn 37467)로
> 정정한 번호를 그대로 따랐다. `KNOW-028` 은 이미 "규칙 인용은 이 저장소에 실제로 존재하는 파일명만 쓴다"
> (tKB kbSn 6870) 로 점유되어 있다. **번호를 재배정하지 않았다.**

## 사실 확인 (이슈 본문 주장 + 원인, 모두 실측 재확인)

| 주장 | 실측 명령 | 결과 |
|---|---|---|
| `Get-Module -ListAvailable SqlServer` → SqlServer 22.3.0 | `Get-Module -ListAvailable SqlServer` | **SqlServer 22.3.0** ✓ (이 PC 에서 `Invoke-Sqlcmd` 분기가 항상 탄다) |
| `execSQLFile.ps1` 출력 모드가 둘 | `giipdb/mgmt/execSQLFile.ps1` 57~83행 | `if (Get-Module -ListAvailable SqlServer)` → `Invoke-Sqlcmd` 분기(**PowerShell 객체** · 0건이면 `$null`) / `else` → `sqlcmd -f 65001` 분기(**텍스트** · 첫 컬럼 `line` · 구분선 행 포함) ✓ |
| 정본 러너 `FindOpenChildren` 포트 = API 경로 | `scripts/gissue/run-gissue-claude.ps1` 의 `FindOpenChildren` 포트 블록 | `node $ListIssuesScript --csn ... --status '...' --json` — DB 호출 없음 ✓ |
| 정본 헤더에 "DB/API 혼용 금지" 규정 유지 | 러너 헤더 | `혼용(일부만 DB, 일부만 API)은 금지` ✓ |
| `scripts/gissue/` 어디에도 DB 직접조회 **실제 호출** 없음 | 신규 회귀 테스트 [C] 절 (AST · 문자열 분류) | **0건** ✓ (주석·프롬프트 템플릿 언급은 제외) |
| 로그 증거 2행 | 이슈 본문 인용 | 79차 note 가 이미 실측 확인 — 본 세션에서 재확인 (아래 "정합성" 절) |

## 설계 결정 (근거 포함)

1. **정본 러너(`run-gissue-claude.ps1`)는 고치지 않는다.**
   이슈 비범위가 "운영 사본(lowyworkenv) 러너 포트 수정·이식 — 해당 레포 담당 범위. 본 이슈는 **정본 기준선과 사실 관계만 확정한다**" 라고 명시한다.
   게다가 정본 포트는 이미 API 경로라서 **이번 이슈가 지목한(DB 출력 모드) 결함은 정본에 없다.**
   → 정본을 "고치는" 것은 산출물이 아니라 변명이 된다.
   → **단, 아래 §"세션 중 새로 측정한 사실" 의 별개 결함은 정본에 존재한다.** 그것은 "고칠" 대상이 아니라
     **측정·기록할 대상**이며(같은 이슈의 범위가 "사실 확정"이므로), 정정·후속 등록으로 처리한다.
2. **회귀 테스트는 포트의 "복사본"이 아니라 "원본"을 시험한다.**
   소스를 옮겨 적어 두면 테스트는 구현이 아니라 **decoration** 이 된다 → 러너 파일을 **AST 로 파싱**해
   `FindOpenChildren` 키의 스크립트 블록을 **그 텍스트 그대로** 추출하고, 임시 스텁 `list-issues.js` 와 통신시켜 실제로 구동한다.
   (`[scriptblock]::Create($portText)` 로 실행 — 그래서 `[B]` 소스 계약 + `[D]` 동작 검사가 **같은 원본**을 가리킨다.)
3. **성공 판정 근거를 출력 모양으로 삼지 않는다** — 이게 이 이슈의 핵심 교훈.
   `(?m)^\s*line\s*$` 헤더 정규식으로 성공을 판정하면 `Invoke-Sqlcmd` 분기(객체 모드)에서 **절대 안 맞아** exit=0 인데 "조회 실패" 가 된다.
   → `[B]` 절에서 "포트에 헤더 정규식 판정이 없음"을 명시적으로 **금지**하고, `[E]` 절에서
   "객체 모드 출력(헤더 없음)이 정상 파싱된다"를 **고정**했다.
4. **fail-closed 를 유지한다** — 조회 실패를 성공으로 넘기지 않는다.
   `[D]` 절에서 "JSON 파싱 실패"·"stderr/비정상 종료"가 **예외**로 올라오는지 확인한다.
   (분해 보류로 이어져야 한다 — 중복 등록보다 안전한 쪽.)
5. **행 파서 헬퍼는 "정본에 DB 경로를 쓰게 될 경우 대비"의 정규본으로만 둔다.**
   이 저장소에는 DB 직접접근 수단이 없고(러너 헤더 규칙) 이슈 조회·코멘트·상태전이는 전부 API 다 →
   **런타임 호출자가 없는 헬퍼**를 넣는 것이 규칙 48(정규본 한 곳)에 맞다. 파일 헤더에 "호출자 없음"을 명시했다.
6. **PS 버전을 가정을 걸지 않는다.** 스케줄러는 `powershell.exe`(5.1) 다. 5.1 의
   `ConvertFrom-Json` 은 파이프라인에서 배열을 전개하지 않아 `@($json | ConvertFrom-Json)` 가
   **배열 하나를 담은 원소 1개**가 된다 — 테스트는 그 차이를 가정하지 않고 행을 **펼치는 쪽**으로 작성했다.
   (이 차이는 아래 §"세션 중 새로 측정한 사실" 에 `KNOW-035` 로 등록했고, 테스트가 그 사실을
   **감추지 않도록** 헤더와 [D] 절에 명시했다.)

## 실행 증거

| 검증 | 명령 | 결과 |
|---|---|---|
| 신규 회귀 테스트 (완료조건) | `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gissue/tests/test-overtime-findchildren-port.ps1` | **exit 0** — [A] 2 · [B] 10 · [C] 1 · [D] 11 · [E] 10 = **34 assert 전부 통과** |
| ps1 구문+BOM 게이트 | `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gissue/check-ps1-parse.ps1 scripts/gissue/tests/test-overtime-findchildren-port.ps1 scripts/gissue/lib/overtime-split.ps1 scripts/gissue/run-repo-gates.ps1` | **exit 0** — 검사 3개 전부 통과 |
| 저장소 게이트 전수 | `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gissue/run-repo-gates.ps1` | **exit 0** — ps1 **32**건 / mjs **5**건 / 마크다운 **587** 파일 · 링크 **1193**개(상대 **807**개 · 스캐폴딩 21건) · **실제 결함 0건** |
| tKB 등록 | `tkb.js sync-klayer --csn 70424 --dir <repo>/.agent/k_layer/notes --project giip-fde-agent --note "KNOW-029_*"` | `OK created kbSn=6943` (합계 1건 · created 1 / updated 0 / 실패 0) |
| tKB 등록 (별개 결함) | 같은 명령 · `--note "KNOW-035_*"` | `OK created kbSn=6945` (합계 1건 · created 1 / updated 0 / 실패 0) |

### 테스트가 실제로 확인한 것 ([D] 절 — 스텁 API 실측)

- 포트가 API JSON 2건의 isn(`9001,9002`)을 모두 노출한다.
- 포트가 실측 인자 `--csn 777 --status PENDING,READY,IN_PROGRESS,REVIEW,TESTED,NEEDS_DECISION --json` 으로 호출했다.
- 1건 응답 → **행 1개** · `Isn` 이 스칼라(`9001`)다 · 제목이 API JSON 과 일치한다.
- 빈 배열 응답 → 자식 0건(오류 아님).
- 파싱 실패 → **예외**(fail-closed) · stderr/비정상 종료 → **예외**.
- 다건(2건) 응답의 **행 개수는 단언하지 않는다** — PS 5.1 의 배열 미전개(`KNOW-035`)를 이 테스트가
  가려내지 못하게 하려고 **의도적으로 제외**했다. 대신 행 개수를 `info` 로 출력해 측정값을 남긴다.

## 세션 중 새로 측정한 사실 (범위 밖 · 별개 결함 · `KNOW-035`)

> **진단 연속성** — 이슈 본문의 "정본 대비 차이" 절은 "정본 러너는 API 경로라 **영향 없음**" 이라고 단정한다.
> 그 단정은 **이번 이슈가 지목한 결함(DB 출력 모드)에 대해서는 맞다.** 그런데 같은 조회 경로에서
> **다른 원인**으로 정본 러너의 find-children 가 실패하는 경우를 실측했다. **조용히 넘기지 않고 적는다.**

**측정(2026-11-04 · Windows PowerShell 5.1.19041.6456 · 정본 러너의 실제 포트 블록을 AST 로 추출해 스텁 API 로 구동)**

| API 응답 | 포트가 돌려준 것 | 실제 소비 함수 `Find-GissueOpenSplitChildren` 의 결과 |
|---|---|---|
| 1건 | 행 1개 · `Isn=9001`(스칼라) | 정상 — 자식 1건 |
| **2건** | **행 1개** · `Isn=Object[]{9001,9002}` · `Title`=제목 연결 문자열 | **예외** — `[int]$_.Isn` 캐스트 실패(`Cannot convert the "System.Object[]" value of type "System.Object[]" to type "System.Int32"`) |
| `[]` | 행 1개 · 속성 전부 null | 무해 — 제목 정규식이 안 맞아 걸러짐 |

**원인** — Windows PowerShell 5.1 의 `ConvertFrom-Json` 은 JSON 배열을 **배열 1개(단일 파이프라인 항목)** 로 돌려준다.
`$rows = @($json | ConvertFrom-Json)` 는 **원소 1개**(그 원소가 배열) 가 되고, `ForEach-Object` 는 1번만 돈다.
→ 정본 러너의 `FindOpenChildren` 포트가 2건 이상을 받으면 **행 1개 + 배열 속성**이 되고,
소비 함수의 `[int]$_.Isn` 캐스트가 예외를 던져 → `find-children` 실패 → **rule 69-4 중복 서브이슈 감지 무력화**.

**운영 런타임이 5.1 이라는 근거** — 실측: Windows 작업 스케줄러 태스크 `GIIP_Gissue_Claude` 의 액션이
`C:\WINDOWS\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File …\run-gissue-claude.ps1` 이고,
등록 스크립트(`scripts/register-hourly-issue-scheduler.ps1`)도 `powershell.exe` 로 등록한다.

**이번 이슈에서 고치지 않은 이유** — 이슈 비범위가 "본 이슈는 **정본 기준선과 사실 관계만 확정한다**" 라고 명시한다.
이 결함은 (1) **별개 결함**이고 (2) 고치면 Live 모드의 분할 동작이 바뀐다(지금까지 보류되던 분할이 진행될 수 있다).
→ **측정·기록만** 하고(`KNOW-035` + tKB kbSn **6945**), 정본 러너의 동작 수정은 **별도 후속**으로 남긴다.

**테스트가 이 사실을 감추지 않게 한 방법** — 신규 회귀 테스트는 **내용**(이슈 번호 집합·제목·fail-closed)만 단언하고
**다건 응답의 행 개수는 단언하지 않는다**(1건 응답에서만 행 개수 계약을 단언). 헤더와 [D] 절에
"별개 결함(`KNOW-035`)이며 여기서 고정하지 않는다"를 명시했다.

## 문서 동기화 (giip 2377 4항목)

1. **정본 사양서 갱신** — **갱신 대상 없음**. 이번 이슈는 코드·회귀 테스트·k-layer 사실 등록이며 사양서 계약 변경이 없다.
2. **유저가이드 갱신** — **갱신 대상 없음**. 사용자 대면 동작 변경이 없다(러너 동작 변경 없음 — 정본 포트는 이미 API 경로).
3. **k-layer + tKB** — `KNOW-029` 노트 신규 작성 + `INDEX.md` 에 행 추가(kbSn 칸 **6943**) ·
   새로 측정한 별개 결함은 `KNOW-035` 노트로 등록 + `INDEX.md` 행 추가(kbSn 칸 **6945**).
   tKB 등록은 `sync-klayer` 로 수행했고 `OK created kbSn=6943` · `OK created kbSn=6945`
   (각각 합계 1건 · created 1 / updated 0 / 실패·불일치 0)을 확인했다.
4. **반영 파일 경로 전부** — 아래 §결과 저장처 / 소비처 에 나열.

## 결과 저장처 / 소비처

- 신규 파일:
  - `scripts/gissue/tests/test-overtime-findchildren-port.ps1` — 회귀 테스트(완료조건 verify 블록이 가리키는 파일)
  - `.agent/k_layer/notes/KNOW-029_db_query_output_has_two_modes_do_not_judge_success_by_output_shape.md` — k-layer 노트
  - `.agent/k_layer/notes/KNOW-035_powershell_5_1_convertfrom_json_does_not_enumerate_json_arrays.md` — k-layer 노트(새로 측정한 별개 결함)
  - `.agent/work_history/20261104_1422_csn70424_giip-4434-findchildren-port.md` — 본 기록
- 수정 파일:
  - `scripts/gissue/lib/overtime-split.ps1` — 출력 모드 무관 행 파서 헬퍼 추가
  - `.agent/k_layer/notes/INDEX.md` — `KNOW-029` · `KNOW-035` 행 추가
  - `docs/WHATS_NEW.md` — `## 2026-11-04` 절 항목 추가
  - `scripts/gissue/run-repo-gates.ps1` — 기대 ps1 회귀 테스트 수 23 → 32 (신규 파일 1건 반영)

## 이 저장소(PUBLIC) rule 54 자가 점검

이번 커밋에 **이 저장소 자신의 CSN(70424) 외 다른 CSN 번호 0건**, 고객·환경 특정 정보 0건.
외부 저장소(lowyworkenv)를 언급한 부분은 **이 저장소의 스케줄러가 참조하는 정본 스크립트 경로**이며 고객 정보가 아니다.

## 남은 것 · 비범위

- **운영 사본(lowyworkenv) 러너 포트 수정** — 이슈 비범위(해당 저장소 담당 범위 · 이 저장소의 PUBLIC 규칙에 따라 다른 프로젝트 식별 번호는 기재하지 않는다). 본 이슈는 정본 기준선과 사실 관계만 확정한다.
- **PR 번호·CI 결과** — 아래 표 참조.

## PR · CI

| 레포 | 변경 | PR | CI |
|---|---|---|---|
| **giip-fde-agent** | `scripts/gissue/lib/overtime-split.ps1` · `scripts/gissue/tests/test-overtime-findchildren-port.ps1`(신규) · `.agent/k_layer/notes/KNOW-029_*.md`(신규) · `.agent/k_layer/notes/INDEX.md` · `scripts/gissue/run-repo-gates.ps1` · `docs/WHATS_NEW.md` · 이 작업 기록 | (아래 기입) | (아래 기입) |
