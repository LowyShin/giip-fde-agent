# KNOW-029 — DB 조회 스크립트의 출력은 "모드가 둘"이다 — 출력 모양으로 성공을 판정하지 않는다

> 근거: 2026-11-04 CSN 70424 세션 실측 (giip 4434 · 정본 러너 `FindOpenChildren` 포트 감사) · 발행: 2026-11-04 · 상태: 검증됨(회귀 테스트 `scripts/gissue/tests/test-overtime-findchildren-port.ps1` PASS)

## 요지

`giipdb/mgmt/execSQLFile.ps1` 는 **같은 SQL 이 환경에 따라 서로 다른 모양으로 나온다.**

| 환경 | 분기 | 출력 | 실패 시 종료코드 |
|---|---|---|---|
| `Get-Module -ListAvailable SqlServer` 가 참 | `Invoke-Sqlcmd` | **PowerShell 객체**(결과 0건이면 `$null` — 아무것도 안 나옴) | 1 |
| 거짓 | `sqlcmd -f 65001` | **텍스트**(첫 컬럼명이 `line` , 구분선 `---- ----` 행 포함) | 1 |

두 분기 모두 **"조회가 성공했는데 결과가 0건"과 "조회가 실패"를 구분해 주지 않는다**(둘 다 exit=0 또는 exit=1
로만 드러난다). 그래서 "출력이 `line` 헤더를 포함하는가"를 성공 판정 근거로 쓰면,
**객체 모드 환경에서는 항상 "조회 실패" 로 오판**된다 — SqlServer 모듈이 설치된 PC 에서만 재현되는 사고다(giip 4434).

> **규칙 — 성공 판정 근거를 출력 모양(헤더·정규식)으로 삼지 않는다.**
> `exit=0` 이면서 "기대 형태가 안 보인다" 는 **실패**다. 기대 형태를 못 찾는 것은 성공의 증거가 아니다.

## 사례 (giip 4434 — 중복 서브이슈 감지 무력화)

운영 사본(lowyworkenv) 러너의 find-children 조회가 `(?m)^\s*line\s*$` 정규식으로 "성공"을 판정했다.
SqlServer 22.3.0 이 설치된 환경(=객체 모드)에서는 출력이 PowerShell 객체라 정규식이 **절대 안 맞는데**,
실행은 정상 종료되어 "조회 실패" 로 넘어갔다. 그 결과 **rule 69-4 중복 서브이슈 감지가 항상 무력화**됐다.

정본(giip-fde-agent) 러너의 `FindOpenChildren` 포트는 **API 경로**(`list-issues.js --json`)를 쓰므로
같은 사고에 노출되지 않는다. 다만 "환경에 따라 출력 모드가 갈린다"는 사실 자체는 그대로 남아 있으므로,
DB 조회 경로를 쓰는 쪽에서는 아래 규칙을 지켜야 한다.

## 규칙

1. **성공 판정은 오류로 한다.** 종료코드 0 은 "오류가 없었다"일 뿐 "조회 결과가 원하는 형태였다"는 뜻이 아니다.
2. **행 파서는 모드를 먼저 판별한다** — 객체 / JSON / 텍스트 3모드를 공통 행(`Isn`/`Status`/`Title`)으로 정규화한다.
   정규본: `scripts/gissue/lib/overtime-split.ps1` 의 `Get-GissueIssueRowsFromQueryOutput`.
   · `Object` = PowerShell 객체(Invoke-Sqlcmd 분기) · `Json` = API 경로 · `Text` = sqlcmd 표 · `Empty` = 결과 0건
3. **판별 불가 출력은 예외(fail-closed)** — 성공으로 넘기지 않는다. 조회 실패는 분해를 **보류**해야 한다.
4. **텍스트 모드는 헤더 컬럼명으로 행을 만든다.** isn/title 컬럼이 없으면 예외다(헤더 모양이 곧 성공 뜻은 아님).
5. **이 저장소(giip-fde-agent)의 러너 포트는 DB 경로를 쓰지 않는다.** 이슈 조회·코멘트·상태전이는 전부
   API(`list-issues.js --json` / `get-issue.sh`)로만 한다 — 러너 헤더의
   "DB 직접접근 없음 · 혼용(일부만 DB, 일부만 API) 금지" 규칙과 같다.

## 적용

- DB 조회 결과의 **빈 결과와 실패를 구분**해야 하는 스크립트를 만들 때.
- "이 스크립트는 어떤 DB 도구를 부르는가"가 **환경(모듈 설치 여부)에 따라 달라질 때** — 호출부를 하나만 가정하지 않는다.
- 정규식 매칭(`(?m)^\s*line\s*$` 같은)으로 **성공/실패를 판정하는** 기존 코드를 새벽 우회할 때.

## 관련

- `scripts/gissue/lib/overtime-split.ps1` — 출력 모드 무관 행 파서 정규본(`Get-GissueIssueRowsFromQueryOutput`)
- `scripts/gissue/tests/test-overtime-findchildren-port.ps1` — 회귀 테스트(정본 러너의 실제 포트를 AST 로 추출해 구동)
- `scripts/gissue/run-gissue-claude.ps1` — 정본 러너(`FindOpenChildren` 포트 = API 경로)
- `KNOW-028` — 규칙 인용은 이 저장소에 실제로 존재하는 파일명만 쓴다
- `KNOW-024` — 러너 마감과 외부 강제 종료(같은 러너의 다른 운영 함정)
