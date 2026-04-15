# Karpathy Diagram - GIIP 적용 분석

> 작성일: 2026-04-15
> 출처: Lowy Opinion

## [카파시 다이어그램이 제안하는 흐름]

```
Raw Sources → LLM Processing (요약/Q&A/lint/색인) → Curated Wiki → Outputs (docs/slides/charts)
```

핵심은 사람이 위키를 쓰는 게 아니라 LLM이 데이터를 읽고 위키를 쓴다는 점입니다. 기존 RAG와 다르게, 지식이 쌓입니다.

## [실제 예시: 커뮤니티 데이터가 지식이 되기까지]

벤지(BENZIE)라는 AI 에이전트가 매시간 커뮤니티에 글과 댓글을 씁니다. 이 에이전트는 단순히 글을 쓰는 게 아니라, 다양한 "실험"을 설계하고 실행합니다.

예를 들어 question_hook이라는 실험 계열이 있습니다. "질문형 포스트가 일반 포스트보다 engagement가 높을까?"라는 가설을 세우고, question_hook_01부터 question_hook_v99, question_hook_trust_v1까지 89개 이상의 변형 실험을 자동으로 돌립니다.

이 전체 과정이 데이터로 기록되고, 지식으로 변환됩니다:

① 에이전트가 실험 실행
  벤지가 moltbook에 질문형 포스트 작성, botmadang에 댓글 작성
  → actions_raw.jsonl에 기록 (518건 누적)

② 24시간 후 결과 자동 수집
  reply_count, has_reply, engagement 측정
  → outcomes_raw.jsonl에 기록 (743건 누적)

③ 매일 크론이 raw를 읽고 K-layer 위키 노트 자동 생성
  LLM이 518건 행동 + 743건 결과를 분석해서 패턴을 찾고 claim을 만듦

④ 실제 생성된 지식 위키:

  "플랫폼별 engagement 비대칭"
   CLAIM-001: botmadang comment는 374건 관측 기준 reply rate 0.0%
   CLAIM-002: moltbook post는 315건 관측 기준 reply rate 60.1%
   source: outcomes_raw.jsonl#row-176, #row-177, #row-178

  "question_hook 실험 계열의 진화와 engagement 패턴"
   CLAIM-001: question_hook 계열은 89개 이상의 고유 exp_id로 실행된 주요 전략군
   CLAIM-002: question_hook에서 moltbook post는 reply_count >= 2 관측
   source: actions_raw.jsonl#run229, outcomes_raw.jsonl#run231, #run238

⑤ 다음 실험 설계 시 이 위키를 참조
  "botmadang comment는 반응이 없으니 moltbook post에 집중하자"
  "question_hook_trust_v1이 reply를 받았으니 이 방향을 강화하자"
  → 더 나은 실험 설계 → 더 나은 결과 → 더 정확한 지식 (자기강화 루프)

사람이 "botmadang은 반응이 낮더라"를 정리한 게 아닙니다. 에이전트가 데이터를 읽고, 스스로 claim을 만들고, 다음 행동에 반영합니다.

여기에 MiroFish라는 사회 시뮬레이션 엔진까지 연결되어, 시뮬레이션 실험 결과도 자동으로 위키 노트로 변환됩니다.

## [설계에서 제일 중요했던 것]

source-linked claims입니다.

모든 주장에 원본 데이터 링크가 붙습니다. "reply rate 60.1%"라는 claim 뒤에는 반드시 outcomes_raw.jsonl#row-374처럼 추적 가능한 출처가 있습니다. claim 삭제는 금지, invalidated_at으로만 무효화. 위키가 raw를 대체하지 않고, raw 위에 올라가는 정제 계층입니다.

이게 단순 요약과 지식 시스템의 차이입니다.

## [숫자]

- 카파시 12개 개념 중 11개 구현 (92%)
- 커뮤니티: 행동 518건 + 결과 743건 + 89개 실험 변형 → 7개 지식 노트 자동 생성
- Python 150개, 테스트 175개, 에이전트 9개, 크론 17개
- 벡터DB 없이 JSONL append만으로 작동

## [GIIP 도입 적용 → 별도 문서 참조]

→ [DESIGN_20260415_KARPATHY_K_LAYER.md](../30_Designs/DESIGN_20260415_KARPATHY_K_LAYER.md)
