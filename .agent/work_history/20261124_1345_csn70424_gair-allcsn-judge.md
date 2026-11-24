# 작업 기록 — gair 허용 목록 전 CSN 확장('*') + 게이트 판정 gair 경유

- 일시: 2026-11-24 13:45 JST (Lowy님 지시: "gair을 안쓰고 다이렉트 claude를 쓰는데가 있는지 체크해서 gair로 적용")
- 배경: 플랫폼 측 gair 허용 등록(tSystemParameter category='gair', param_key='access.enabled')은
  전 CSN 허용 완료. 남은 차단점은 스케줄러 쪽 허용 목록(env GISSUE_GAIR_CSNS, 미설정 시 기본 1개 CSN)뿐이었다.

## 읽은 문서

- AI_MUST_READ.md, AGENTS.md
- .agent/rules/35_commit_push_per_task.md, 36_whats_new_maintenance.md, 11_structured_commit.md
  (그 외 AI_MUST_READ 가 가리키는 54(공개 레포 고객정보 금지)·57(워크트리 정리)을 함께 따랐다)

## 사전 조사 (코드 실측)

- **Get-GissueGairPlan 은 정본에 없다.** gair "계획"은 run-gissue-claude.ps1 의 CSN 처리 스코프에
  인라인으로 있다: 베이스 URL 상수 + Get-GissueGairApiKey(SK→AK 파생) + Required 플래그.
  GISSUE_GAIR_CSNS 를 소비하는 게이트는 그 인라인 판정 1곳뿐이다.
- Invoke-GissueJudge(gissue-audit-lib.ps1)는 pr-gate-sweep.ps1 / review-done-audit.ps1 /
  run-gate-escalation-recheck.ps1 가 -Csn 1개로 도는 별도 프로세스에서 닷소싱해 쓴다.
  pr-attribution-sweep.ps1 은 단일 CSN 스코프가 없다(→ 아래 폴백 조항 적용).
- 판정 호출부 전부는 ok=$false 를 "판정 호출 실패/차단 → 안전 폴백(REVIEW 유지)" 으로 처리하고,
  스윕의 이슈 루프에는 이슈별 try/catch 가 없다.

## 설계 판단 (지시 설계에서 벗어난 2건과 근거)

1. **필수인데 비활성인 경우, throw 가 아니라 ok=$false(exit=-2, route='gair-blocked') 반환으로 표면화.**
   지시 설계는 throw(#6229 방식)였으나, 엔진의 throw 는 잡 프레임워크가 세션 단위로 받아 실행 기록에
   남기는 구조라 전파 범위가 세션 1개로 한정된다. 판정에서 throw 하면 그 CSN 스윕 전체(이슈 루프에
   try/catch 없음)가 중단돼 무관한 이슈의 게이트까지 멈춘다. 직접 폴백 금지 + 실패 표면화라는 핵심은
   유지된다: 호출부의 기존 실패 로그("판정 호출 실패/차단(exit=-2)")와 [GAIR] 로그 줄로 남는다.
2. **계획 해석은 감사 라이브러리 안(Get-GissueJudgeGairPlan)에 두고, 목록 해석만 공통 라이브러리
   (lib/gair-gate.ps1)로 분리.** 러너의 인라인 계획(AK 파생·잡 경계 인자 전달)을 계획 객체로
   재구성하면 4천 줄 러너의 동작 변경 범위가 커진다. 허용 판정(목록 해석)만 정본을 하나로 모으고,
   판정 쪽 계획은 같은 목록 함수를 쓰게 했다.

## 폴백 조항 적용 (종전 동작 유지)

- pr-attribution-sweep.ps1 은 단일 CSN 을 특정할 수 없어 판정 계획이 세워지지 않는다 →
  그 경로의 판정(Invoke-FileScopeJudge → Invoke-GissueJudge)은 종전 직접 호출 유지.
- 비교 도구(compare-checklist-vs-legacy.ps1) 등 $Csn 이 없는 스코프도 마찬가지.

## 이번 범위에서 바꾸지 않은 직접 호출 지점 (후속 판단 대상)

- run-gissue-claude.ps1 의 CJK-QA 2차 판정(claude -p --model 고정): 엔진 시도 함수 안의 QA 게이트.
- run-gissue-claude.ps1 의 Invoke-GissueMinimaxAttempt 안 무처리(NO_ACTION) 판정: 시도 함수에
  내장돼 잡 초기화 스크립트로 복사되는 구조라, 감사 라이브러리 판정과 경로가 다르다.
- page-feedback-analyze.ps1 의 판정 호출: gissue 스케줄러가 아닌 별도 도구.
- ForceClaude(REVIEW/TESTED 재검증의 claude 직행)는 지시대로 건드리지 않았다.

## 구현 중 발견한 함정 (실측)

- [string] 파라미터는 생략 시 $null 이 아니라 빈 문자열로 바인딩된다 → Get-GissueGairCsnList 는
  $PSBoundParameters 로 "인자를 줬는가"를 판정한다(안 그러면 env 해석 분기가 영원히 안 탄다).
- 계획 함수의 로컬 변수가 $csn 이면 Get-Variable 이 그 빈 로컬을 먼저 잡아 호스트의 $Csn 을
  못 본다 → 로컬 이름을 $hostCsn 으로 뒀다(주석에 이유 명기).
- $env: 에 빈 문자열을 대입하면 변수 자체가 지워진다 → 빈 목록 검증은 -Raw '' 로 한다.

## 변경 파일

- scripts/gissue/lib/gair-gate.ps1 (신규): Get-GissueGairCsnList / Test-GissueGairCsnAllowed.
  '*' 포함 시 전 CSN 허용, 미설정 시 기본값 종전 그대로.
- scripts/gissue/run-gissue-claude.ps1: 인라인 목록 해석을 공통 라이브러리 호출로 교체.
- scripts/gissue/gissue-audit-lib.ps1: Get-GissueJudgeGairPlan / Resolve-GissueJudgeGairAk 신설,
  Invoke-GissueJudge 가 계획 Active 면 env 오버라이드(베이스 URL·AK·함수 키 헤더)로 gair 경유
  (--model 미고정, 호출 뒤 env 원복, [GAIR] 로그 1줄), Required 인데 비활성이면 gair-blocked 반환.
  AK 는 CSN 단위로 프로세스 내 캐시. 키 값은 어디에도 출력하지 않는다.
- scripts/gissue/tests/test-gair-gate.ps1 (신규): 목록 해석 10 + 판정 계획 8 + 배선 5 + 차단 경로 2 = 25건.
- docs/60-operations/hourly-issue-scheduler.md: GISSUE_GAIR_CSNS 행에 '*' 의미와 판정 경유를 명기.
- docs/WHATS_NEW.md: 2026-11-24 항목 추가, 기준일 갱신. (7일 초과분의 HISTORY 이관은 직전
  PR 들도 수행하지 않은 상태라 이번 PR 에서는 현행 유지 — 별도 정비 대상.)

## 테스트

- 신규 test-gair-gate.ps1: ALL PASS (25건).
- 기존 회귀(변경 전 main 과 변경 후 워크트리 대조): test-run-summary(64건) ALL PASS,
  test-repomaint-gate ALL PASS, test-checklist-judgement 전체 통과, test-scope-gate-multi-pr ALL PASS,
  test-comment-model-tagging PASS=17 FAIL=0 — 전부 동일.
- test-checklist-shadow-reduce 는 양쪽 모두에서 간헐 실패(45줄 동시 쓰기 무결성 케이스)가
  재현되는 기존 flaky 로 판정 — 변경 전 main 에서도 같은 실패를 확인했다.
- check-ps1-parse.ps1: 변경·신규 4개 파일 전부 통과(구문 + BOM).

## 후속 과제

- 판정 코멘트의 모델 표기(Invoke-ChecklistAssessment 의 Model)는 종전 해석값 그대로다.
  gair 경유 시 실제 라우팅 모델과 다를 수 있어, 표기 정합은 별도 판단이 필요하다.
