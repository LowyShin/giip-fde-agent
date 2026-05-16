# 에이전트 생태계 지식 노트 (Agent Ecosystem)

> 카파시 K-Layer: 프로젝트 환경에 최적화된 에이전트 구성 및 역할 변화 기록
> 모든 claim은 source-linked. 삭제 금지, invalidated_at으로만 무효화.

---

## 전문가 팀 구성 (Expert Squad)

CLAIM-001: GIIP 프로젝트는 복잡한 API 인증 및 PowerShell 기반의 Azure Function을 다루므로, 단순 개발자 외에 `API Tester`와 `Reality Checker` 역할의 결합이 필수적이다.
- **evidence**: `api-patterns.md`의 CLAIM-001~004에서 반복된 401/500 에러 패턴. 단순 구현 후 ' fantasy approval'(동작한다고 착각함) 방지를 위해 실제 증거 기반 검증이 필요함.
- **source**: `testing-api-tester.md`, `testing-reality-checker.md`, 작업 기록 20260516 14:06:40
- **observed_at**: 20260516
- **invalidated_at**: null
- **confidence**: high

CLAIM-002: `/gaupdate` 워크플로우는 프로젝트의 K-Layer 지식(기술 스택, 발견된 이슈)을 업데이트 필터링의 기준으로 삼아, 프로젝트 특성에 맞는 최적의 도구만 선택적으로 유지 관리한다.
- **evidence**: 사용자 요청에 따른 `/gaupdate.md` 및 `15_workflow_guidelines.md` 수정 완료.
- **source**: `.agent/workflows/gaupdate.md`, `.agent/rules/15_workflow_guidelines.md`
- **observed_at**: 20260516
- **invalidated_at**: null
- **confidence**: high
