# 디버그 패턴 지식 노트

> 카파시 K-Layer: 반복적으로 발생한 버그 패턴 및 해결 교훈
> 모든 claim은 source-linked. 삭제 금지, invalidated_at으로만 무효화.

---

## Next.js / 다국어(i18n) 패턴

CLAIM-001: GIIP 다국어 시스템에서 `[locale]` 라우팅 기반의 파일 조회는 `lib/guides.ts`의 localization helper 없이는 fallback 처리가 되지 않아 특정 언어(ja, zh)에서 빈 화면 발생
- **evidence**: 일본어 가이드 페이지 404 현상, 한국어만 정상 표시
- **source**: `giipv3/src/app/[locale]/guides/page.tsx`, `giipv3/src/lib/guides.ts`, 작업 기록 20260414
- **observed_at**: 20260414
- **invalidated_at**: null
- **confidence**: high

CLAIM-002: Next.js App Router에서 서버 컴포넌트는 `fetch()` 직접 호출 시 인증 헤더가 유지되지 않음. GIIP API 호출은 반드시 서버 액션 또는 API route를 거쳐야 함
- **evidence**: 클라이언트에서 직접 API 호출 시 CORS 및 인증 오류 발생 패턴 반복
- **source**: `giipv3/src/app/[locale]/admin/giip-issues/page.tsx`, 작업 기록 20260129
- **observed_at**: 20260129
- **invalidated_at**: null
- **confidence**: high

---

## PowerShell / Azure Functions 패턴

CLAIM-003: PowerShell run.ps1에서 쿼리 파라미터 접근 시 `$Request.Query.파라미터명`은 null을 반환할 수 있으며, `$Request.Query['파라미터명']` 형식을 사용해야 안전
- **evidence**: csn 파라미터 필터링 버그 수정 과정에서 발견
- **source**: `giipfaw/giipIssues/run.ps1`, 작업 기록 20260202 10:45:01
- **observed_at**: 20260202
- **invalidated_at**: null
- **confidence**: high

CLAIM-004: Azure Function에서 PUT 메서드로 상태 업데이트 시, 요청 본문 파싱이 Content-Type에 의존. `application/json`이 아닌 경우 본문이 비어있을 수 있음
- **evidence**: giip-issue force DONE 기능 디버깅 과정 (20260201)
- **source**: `giipfaw/giipIssues/run.ps1`, 작업 기록 20260201 17:00:00
- **observed_at**: 20260201
- **invalidated_at**: null
- **confidence**: mid

---

## Knowledge Graph / DB 패턴

CLAIM-005: GIIP DB의 CTE(Common Table Expression) 기반 쿼리에서 TOP 50 제한을 걸면 JOIN 이후 집계가 누락될 수 있음. CTE 내부가 아닌 최종 SELECT 단계에서 필터링해야 함
- **evidence**: Knowledge Graph top-50 태그 제한 구현 후 태그 전체 미표시 버그 발생
- **source**: 작업 기록 20260414, 지식 그래프 CTE 수정 커밋
- **observed_at**: 20260414
- **invalidated_at**: null
- **confidence**: high

CLAIM-006: `mgmt/execSQLFile.ps1`을 통한 SQL 실행은 Invoke-Sqlcmd 직접 호출 대비 트랜잭션 처리와 오류 로깅이 표준화되어 있음. 직접 SQL 호출은 절대 금지
- **evidence**: GEMINI.md Strict Rule #1로 명시
- **source**: `GEMINI.md#Core-Principles`
- **observed_at**: 20260129
- **invalidated_at**: null
- **confidence**: high

---

## Git / 버전 관리 패턴

CLAIM-007: GIIP 프로젝트에서 GEMINI.md 병합 충돌은 UTF-16 인코딩(null bytes)으로 인한 경우가 있음. 파일 저장 시 항상 UTF-8 (no BOM) 사용
- **evidence**: GEMINI.md null byte 오염 발견 (20260415), PowerShell로 정리 필요
- **source**: 작업 기록 20260415 14:36:01
- **observed_at**: 20260415
- **invalidated_at**: null
- **confidence**: high
