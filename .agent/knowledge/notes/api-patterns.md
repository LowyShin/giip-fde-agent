# API 패턴 지식 노트

> 카파시 K-Layer: GIIP API 호출 패턴에서 관찰된 사실들
> 모든 claim은 source-linked. 삭제 금지, invalidated_at으로만 무효화.

---

## GIIP API 인증 패턴

CLAIM-001: GIIP API는 `x-functions-key` 헤더 방식과 Authorization Bearer 방식 두 가지를 구분하여 사용한다
- **evidence**: giipapisk2/giipapisk3 명세 확인, 잘못된 헤더 사용 시 401/403 발생 확인
- **source**: `giipv3/src/app/[locale]/admin/giip-issues/page.tsx`, `ANALYSIS_20260129_GIIP_ISSUE_LIST_RCA.md`
- **observed_at**: 20260129
- **invalidated_at**: null
- **confidence**: high

CLAIM-002: GIIP API 401 오류는 대부분 Authorization 헤더 누락이 아닌 헤더 형식 오류에서 발생한다
- **evidence**: 실제 오류 재현 3회. Bearer 접두어 누락, API Key 위치 오류 확인
- **source**: traces/giip_issues_auth_fix, `giipfaw/giipIssues/run.ps1#L23`
- **observed_at**: 20260129
- **invalidated_at**: null
- **confidence**: high

CLAIM-003: `pApiGiipIssueListbyAK` 함수는 csn 파라미터 필터링을 지원하나, run.ps1의 파라미터 바인딩이 잘못 구현되어 있었다
- **evidence**: 수정 전 csn 필터 무시됨, 수정 후 정상 작동 확인
- **source**: `giipfaw/giipIssues/run.ps1`, 작업 기록 20260202 10:45:01
- **observed_at**: 20260202
- **invalidated_at**: null
- **confidence**: high

---

## Azure Function 호출 패턴

CLAIM-004: Azure Function의 파라미터명은 대소문자를 구분하며, PowerShell run.ps1의 `$Request.Query.파라미터명` 접근 방식에서 불일치가 500 에러 원인이 됨
- **evidence**: giipfaw 500 에러 RCA, 파라미터명 대소문자 수정 후 해결
- **source**: 작업 기록 20260204 18:45:00, `REPORT_20260204_GIIP_ISSUES_500_ERROR.md`
- **observed_at**: 20260204
- **invalidated_at**: null
- **confidence**: high

CLAIM-005: Azure Function은 환경 변수 변경 후 cold start 없이는 반영되지 않는 경우가 있음. 로컬 수정 후 실 환경에서 동일 오류 지속 가능
- **evidence**: run.ps1 수정 후에도 Azure 환경에서 동일 오류 지속됨 (20260204)
- **source**: 작업 기록 20260204 18:45:00
- **observed_at**: 20260204
- **invalidated_at**: null
- **confidence**: mid

---

## GIIP API 응답 규격

CLAIM-006: GIIP API의 RstVal(결과 코드)은 `tDefRst` 테이블 기준이며, 0이 성공을 의미하지 않을 수 있음. 공식 문서 참조 필수
- **evidence**: API 결과 코드 표준화 작업 (20260414), RstVal 가이드 문서 5개 언어 생성
- **source**: `giipv3/src/app/[locale]/guides/`, 작업 기록 20260414
- **observed_at**: 20260414
- **invalidated_at**: null
- **confidence**: mid
