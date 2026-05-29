# Incident + Rollback 표준 플레이북

AI 에이전트 기반 자동화 환경에서 발생하는 장애를 빠르게 통제/복구하기 위한 표준 절차입니다.

## 1) 장애 유형

1. **에이전트 오판**: 잘못된 작업 분류/위임/수정
2. **외부 API 장애**: API 타임아웃, 인증 오류, rate limit
3. **잘못된 자동수정**: 코드/문서/설정 자동 변경으로 품질 저하

## 2) 공통 대응 흐름

1. **탐지**: 이상 징후(실패율 급증, 오류 반복, 사용자 신고) 식별
2. **격리**: 자동 실행 일시 중지, 영향 범위 고정
3. **분류**: 장애 유형/심각도(Critical/High/Medium/Low) 판단
4. **롤백**: 마지막 정상 상태로 복귀
5. **검증**: 핵심 시나리오 재검증
6. **재개**: 재발 방지책 적용 후 자동화 재개

## 3) 롤백 체크리스트

- [ ] 영향 범위(서비스/문서/데이터) 확인
- [ ] 롤백 대상 버전/커밋 식별
- [ ] 롤백 수행 및 결과 기록
- [ ] 사용자/팀 공지
- [ ] 후속 RCA 등록

## 4) 장애 기록 최소 포맷

- Incident ID:
- 발생 시각 (Detected At):
- 탐지 경로 (Detection Source):
- 영향 범위 (Impact Scope):
- 즉시 조치 (Immediate Mitigation):
- 롤백 시각 (Rollback At):
- 근본 원인 (Root Cause):
- 재발 방지 액션 (Prevention Action):

## 5) 연결 문서

- 승인 게이트: `/.agent/workflows/human-approval-gate.md`
- KPI 표준: `/docs/60-operations/ai-native-kpi.md`
