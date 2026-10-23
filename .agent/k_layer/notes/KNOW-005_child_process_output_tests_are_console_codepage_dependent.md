# KNOW-005: 자식 프로세스 출력을 비교하는 테스트는 콘솔 코드페이지에 종속된다 + "워크트리 green ≠ main green"

- 작업 CSN: 70424
- 관련 파일:
  `scripts/gissue/tests/test-page-feedback-analyze.ps1` (교정 대상),
  `scripts/gissue/tests/test-lang-check.mjs` (같은 세션에서 발견된 별개 결함),
  `scripts/gissue/page-feedback-analyze.ps1` (제품 코드 — 무수정),
  `scripts/gissue/check-ps1-parse.ps1` (저장소 자체 게이트)
- 근거: 2026-10-24 CSN 70424 저장소 정비 세션 실측
  (`.agent/work_history/20261024_043000_csn70424_repo-maintenance.md` §부수 정비 T1-1 · §정정 A)

## 1. 현상

`scripts/gissue/tests/test-page-feedback-analyze.ps1` 가 **PR #234 머지 후에도 exit 1** 로 실패했다.
그런데 같은 커밋을 **워크트리에서 stdout 을 파이프로** 돌렸을 때는 **exit 0** 이었다.
→ "코드는 고쳤는데 왜 빨간가" 를 재현하는 과정에서 **환경 의존**임이 드러났다.

## 2. 원인 — 콘솔 코드페이지(cp932)와 자식 프로세스 출력

- 이 PC 의 콘솔 코드페이지 = **cp932(shift_jis)** (`chcp` → "Active code page: 932").
- Windows PowerShell 5.1 은 자식 프로세스의 stdout 을 **콘솔 코드페이지로 인코딩**해 내보내고,
  부모는 **같은 코드페이지로 디코딩**한다.
- cp932 는 한글을 표현할 수 없어, 자식(`powershell.exe`)이 낸 `"[SKIP] 비활성"` 이 `?` 로 깨진다.
  실측 코드포인트:
  - 자식 출력 = `91,83,75,73,80,93,32,63,63,63` (`?` 3개)
  - 테스트 리터럴(UTF-8 BOM 파일에서 읽음) = `91,83,75,73,80,93,32,48652,49404,44277` (한글 3자)
  → `g8` 의 문자열 비교가 성립하지 않는다.
- 반대로 **코드페이지가 UTF-8(65001) 인 셸**에서는 왕복이 정상이라 **통과**한다.
  즉 결과가 **셸/리디렉션 방식에 따라 갈렸다**.

## 3. 왜 위험한가

1. **"워크트리에서 green" 이 "머지된 main 에서 green" 을 보장하지 않는다.**
   머지 전 검증과 머지 후 검증의 **환경**(cwd, 출력 리디렉션, 콘솔 코드페이지)이 달라질 수 있고,
   그 차이 자체가 결함의 은폐 수단이 된다.
2. **게이트가 CI 에 없으면** 회귀 테스트는 사람이 수동으로 돌릴 때만 발견된다.
   이 저장소는 `.github/workflows/` 에 `windows-hook-doctor.yml` 만 있고
   `check-ps1-parse.ps1` 과 회귀 테스트는 **CI 에 물려 있지 않다**.
   → **2026-10-24 조치**: [KNOW-006](KNOW-006_repo_gates_not_wired_to_ci.md) —
   단일 진입점 `scripts/gissue/run-repo-gates.ps1` + CI 워크플로 `.github/workflows/repo-gates.yml`
   로 결선했다. 자동화 축의 재발 방지는 KNOW-006, 환경(코드페이지) 축은 이 노트가 맡는다.
3. 자식 출력을 **텍스트로 비교하는 테스트는** 인코딩을 명시하지 않으면
   **그 PC 의 코드페이지가 테스트의 합격 기준**이 된다 — 테스트가 "환경 검사"가 된다.

## 4. 재발방지

1. **자식 프로세스 출력을 비교할 때는 양쪽 인코딩을 명시적으로 고정한다.**
   - 부모: 호출 전 `[Console]::OutputEncoding = [System.Text.Encoding]::UTF8`, 호출 후 `finally` 에서 원복
   - 자식: `-Command '[Console]::OutputEncoding=[System.Text.Encoding]::UTF8; ...'`
   - 경로 인자는 **환경변수**로 넘긴다(공백·따옴표 포함 경로의 셸 인용 함정 회피) — 호출 후 제거
2. **검증은 최소 3가지 축으로 돌린다.**
   ① 워크트리/로컬 브랜치 ② **머지된 main 을 공유 체크아웃에서** ③ 출력 리디렉션·콘솔 코드페이지 변경
   (예: `> /dev/null`, `> 파일`, 파이프). 하나만 돌리고 "통과"로 보고하지 말 것.
3. **제품 코드(스크립트)의 출력 메시지를 테스트가 문자열로 비교해야 한다면**,
   스크립트가 **UTF-8 로 출력하도록** 하는 쪽이 근본 해결이다(이번 세션에서는
   `page-feedback-analyze.ps1` 는 Linux 컨테이너 전용 배포라 무수정 — 필요 시 그때 수정).
4. **같은 세션에서 발견한 별개 결함**: `test-lang-check.mjs` 는 `execSync('git commit -m "…\n…"')`
   로 실제 개행이 든 커밋 본문을 만들려 했으나, **셸(cmd.exe) 을 거치며 개행 지점에서 명령이 잘려**
   "본문 둘째 줄 中 있음" 이 **커밋 자체에 저장되지 않았다**. → 검출 0건 = 조용한 통과 실패.
   셸을 우회하는 `execFileSync('git', [...])` 인자 배열로 고쳤다.
   **원칙: 셸로 만든 인자에 개행/특수문자를 실어 넣으면 셸이 지운다 — 인자 배열로 넘길 것.**

## 5. 결과가 저장되는 곳 / 소비처

- 이 노트: `.agent/k_layer/notes/KNOW-005_child_process_output_tests_are_console_codepage_dependent.md`
  + `INDEX.md` 색인 행.
- 작업 기록: `.agent/work_history/20261024_043000_csn70424_repo-maintenance.md`(T1-1 · §정정 A).
- PR: #234(엔진 해석) · #235(UTF-8 고정) — 둘 다 `main` 머지 완료.
- 소비처: 자식 프로세스를 띄워 출력을 비교하는 테스트를 만드는 세션,
  그리고 "PR 머지 후 재검증" 을 하는 세션.
