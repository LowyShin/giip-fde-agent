---
description: Evaluate and integrate investment/trading capabilities into GIIP agent components with safety-first checks.
---

# 투자/트레이딩 기능 평가 워크플로우

이 워크플로우는 외부 투자 레포/아이디어를 GIIP Agent System에 최소 변경으로 통합할 때 사용합니다.

## 1. 목표 확인
- 목적을 아래 중 하나로 명확히 분류합니다.
  - 아키텍처 학습
  - 실전 자동화 준비
  - 연구/벤치마크
  - MCP/데이터 통합

## 2. 후보 평가 (5축)
- 활성도
- 성숙도
- 학습곡선
- 한국 시장 적합성
- 라이선스

## 3. 안전성 점검
- 백테스트 편향(look-ahead/survivorship/data snooping): 미래정보 유출·표본 편향·과최적화로 성능이 과대평가되었는지 확인
- 환각 지표(hallucinated metrics): LLM이 실제 데이터 근거 없이 PER·매출·수익률 숫자를 생성했는지 확인
- 실행 현실성(슬리피지/수수료/유동성): 실거래 체결 조건을 반영했는지 확인
- 규제/개인정보/광고 리스크: 투자자문·데이터보호·과장표현 위반 가능성 점검
- LLM 토큰 비용: 멀티 에이전트 라운드 수 증가에 따른 운영비 급증 여부 점검

## 4. GIIP 구성요소 매핑
- 역할이 필요하면 `roles/`에 추가
- 강제 규칙이 필요하면 `rules/`에 추가
- 반복 작업 패턴이면 `skills/`로 정리
- 실행 절차가 필요하면 `workflows/`에 추가
- 재사용 가능한 교훈은 `knowledge/notes/`에 claim으로 저장

## 5. 결과 패키징
- 추천 후보와 제외 후보를 분리
- 최소 통합안(role/rule/skill/workflow/k-layer)을 제시
- "운영 전 필수 검증 항목"을 체크리스트로 제공
