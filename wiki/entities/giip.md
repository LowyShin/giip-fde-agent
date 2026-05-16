# [[GIIP]]

Auto-generated wiki page.

## 🧠 Technical Claims (K-Layer)

| Claim ID | Summary | Source |
| :--- | :--- | :--- |
| CLAIM-001 | GIIP 다국어 시스템에서 `[locale]` 라우팅 기반의 파일 조회는 `lib/guides.ts`의 localization helper 없이는 fallback 처리가 되지 않아 특정 언어(ja, zh)에서 빈 화면 발생 | [debug-patterns.md](file:///.agent/knowledge/notes/debug-patterns.md) |
| CLAIM-002 | Next.js App Router에서 서버 컴포넌트는 `fetch()` 직접 호출 시 인증 헤더가 유지되지 않음. GIIP API 호출은 반드시 서버 액션 또는 API route를 거쳐야 함 | [debug-patterns.md](file:///.agent/knowledge/notes/debug-patterns.md) |
| CLAIM-003 | `pApiGiipIssueListbyAK` 함수는 csn 파라미터 필터링을 지원하나, run.ps1의 파라미터 바인딩이 잘못 구현되어 있었다 | [api-patterns.md](file:///.agent/knowledge/notes/api-patterns.md) |
| CLAIM-004 | Azure Function에서 PUT 메서드로 상태 업데이트 시, 요청 본문 파싱이 Content-Type에 의존. `application/json`이 아닌 경우 본문이 비어있을 수 있음 | [debug-patterns.md](file:///.agent/knowledge/notes/debug-patterns.md) |
| CLAIM-005 | GIIP DB의 CTE(Common Table Expression) 기반 쿼리에서 TOP 50 제한을 걸면 JOIN 이후 집계가 누락될 수 있음. CTE 내부가 아닌 최종 SELECT 단계에서 필터링해야 함 | [debug-patterns.md](file:///.agent/knowledge/notes/debug-patterns.md) |
| CLAIM-006 | GIIP API의 RstVal(결과 코드)은 `tDefRst` 테이블 기준이며, 0이 성공을 의미하지 않을 수 있음. 공식 문서 참조 필수 | [api-patterns.md](file:///.agent/knowledge/notes/api-patterns.md) |
| CLAIM-007 | GIIP 프로젝트에서 GEMINI.md 병합 충돌은 UTF-16 인코딩(null bytes)으로 인한 경우가 있음. 파일 저장 시 항상 UTF-8 (no BOM) 사용 | [debug-patterns.md](file:///.agent/knowledge/notes/debug-patterns.md) |