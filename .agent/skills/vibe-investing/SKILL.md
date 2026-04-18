---
name: vibe-investing
description: |
  투자/트레이딩 관련 오픈소스·에이전트 스택을 객관적으로 평가하고,
  GIIP Agent System의 role/rule/skill/workflow/k-layer에 안전하게 이식할 때 사용합니다.

  다음 상황에서 사용합니다:
  - 투자/트레이딩용 에이전트 구조를 설계하거나 개선할 때
  - 특정 레포를 도입할지 비교·검토할 때
  - 백테스트/리스크/거버넌스 체크리스트가 필요할 때

  트리거 키워드: 투자, 트레이딩, invest, trading, quant, backtest, risk, vibe investing
---

# Vibe Investing Integration Skill

AI/LLM 기반 투자·트레이딩 기능을 GIIP 에이전트 체계에 이식하기 위한 실무 스킬입니다.

## 1) 필수 원칙

1. **비권유 원칙**: 결과는 교육/연구 목적이며 투자 권유가 아님을 명시합니다.
2. **근거 우선**: 모든 제안은 소스 링크, 평가 시점(as-of), 라이선스 정보를 포함합니다.
3. **안전 우선**: 백테스트 통계보다 리스크 통제(슬리피지·유동성·수수료·규제)를 먼저 점검합니다.

## 2) 적용 절차

### Step A. 목표 타입 분류
- 학습용 아키텍처 연구
- 한국/미국 실전 자동화 준비
- 논문/벤치마크 중심 연구
- MCP(Model Context Protocol)/도구 통합 중심 개발

### Step B. 후보 레포 평가 (5축)
- **활성도** (최근 유지보수)
- **성숙도** (POC / Research / Production-ish)
- **학습곡선** (도입 난이도)
- **한국 시장 적합성** (KOSPI/KOSDAQ/국내 API)
- **라이선스** (MIT/Apache/GPL/Custom)

### Step C. GIIP 구성요소 매핑
- **Role**: 시장 리서치/리스크 해석 전담 역할 분리
- **Rule**: 백테스트 편향·규제·비용 관련 안전 규칙 강제
- **Skill**: 레포 비교평가, 전략 검증, 도구 선택 가이드
- **Workflow**: 평가 → PoC → 검증 → 운영전 점검 단계화
- **K-Layer**: 재사용 가능한 교훈을 source-linked claim으로 축적

### Step D. 공통 함정 체크
- Look-ahead / Survivorship / Data snooping
- Hallucinated metrics / Recency bias / Authority bias
- Slippage·수수료·유동성·공매도 가능성 누락
- 라이선스/규제/개인정보 위반 가능성
- 멀티 에이전트 토큰 비용 폭증

### Step E. 산출물 형식
1. 도입 후보(왜 필요한지)
2. 제외 후보(왜 제외하는지)
3. 최소 통합 설계(role/rule/skill/workflow)
4. 운영 전 체크리스트(리스크/규제/비용)

## 3) 최소 출력 템플릿

```markdown
## 투자 에이전트 통합 제안 (as-of: YYYY-MM-DD)
- 목적:
- 추천 스택:
- 제외 스택:
- 필수 리스크 체크:
- GIIP 반영안:
  - role:
  - rule:
  - skill:
  - workflow:
  - k-layer claims:
```

## ⚡ Optimization Integration
중요한 투자/트레이딩 설계 작업은 `/native-trace`로 실행하고, 필요 시 `/aioptimize`로 스킬 품질을 개선합니다.
