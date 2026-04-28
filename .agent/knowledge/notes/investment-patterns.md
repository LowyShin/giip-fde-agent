# 투자/트레이딩 에이전트 패턴 지식 노트

> 카파시 K-Layer: 투자 에이전트 설계 시 재사용 가능한 핵심 교훈
> 모든 claim은 source-linked. 삭제 금지, invalidated_at으로만 무효화.

---

## 레포 평가 프레임

CLAIM-001: 투자 에이전트 레포 비교 시 "활성도/성숙도/학습곡선/한국시장 적합성/라이선스" 5축 평가를 먼저 적용한다
- **evidence**: 큐레이션 문서가 동일 5축으로 모든 후보를 비교하고 강점/약점/적합 사용자까지 표준화
- **source**: `https://github.com/gameworkerkim/vibe-investing/blob/main/Awesome%20vibe%20invest.MD`
- **observed_at**: 20260418
- **invalidated_at**: null
- **confidence**: high

CLAIM-002: 멀티 에이전트 투자 구조는 역할 분리(Bull/Bear/Risk/PM)가 핵심이며, 단일 신호보다 의사결정 추적성과 설명 가능성이 높다
- **evidence**: 다수 상위 레포가 debate/합의 구조를 채택하고 역할별 책임을 명시
- **source**: `https://github.com/gameworkerkim/vibe-investing/blob/main/Awesome%20vibe%20invest.MD#1-멀티-에이전트-프레임워크-multi-agent-frameworks`
- **observed_at**: 20260418
- **invalidated_at**: null
- **confidence**: high

---

## 리스크/운영 패턴

CLAIM-003: 투자 에이전트에서 백테스트 성능보다 먼저 확인해야 할 것은 look-ahead/survivorship/data snooping 같은 편향 통제다
- **evidence**: 공통 함정 섹션에서 가장 먼저 백테스트 신뢰성 리스크를 제시
- **source**: `https://github.com/gameworkerkim/vibe-investing/blob/main/Awesome%20vibe%20invest.MD#12-공통-함정-common-pitfalls`
- **observed_at**: 20260418
- **invalidated_at**: null
- **confidence**: high

CLAIM-004: 운영 단계에서는 슬리피지/수수료/유동성/규제 요인을 반영하지 않으면 백테스트 대비 실전 성능이 크게 괴리된다
- **evidence**: 운영 함정에서 실거래 성능 붕괴의 주요 원인을 거래 현실성 누락으로 제시
- **source**: `https://github.com/gameworkerkim/vibe-investing/blob/main/Awesome%20vibe%20invest.MD#12-공통-함정-common-pitfalls`
- **observed_at**: 20260418
- **invalidated_at**: null
- **confidence**: high

CLAIM-005: 멀티 에이전트 토론 라운드 증가는 LLM 비용 급증으로 이어지므로 스크리닝/최종판단 모델을 분리한 비용 티어링이 필요하다
- **evidence**: LLM 비용 함정 섹션에서 라운드 증가와 월 비용 급증을 명시하고 모델 분리를 권장
- **source**: `https://github.com/gameworkerkim/vibe-investing/blob/main/Awesome%20vibe%20invest.MD#12-공통-함정-common-pitfalls`
- **observed_at**: 20260418
- **invalidated_at**: null
- **confidence**: high
