# Moa 레포지토리 분석 보고서

**원본 레포:** https://github.com/stanlee7/moa  
**분석 일자:** 2026-06-23  
**관련 이슈:** #25

---

## 1. 개요

moa는 여러 오픈모델을 하나의 API처럼 묶어 동작시키는 **MoA(Mixture of Agents) 오케스트레이션 게이트웨이**다. 일본 Sakana의 Fugu에서 영감을 받아 한국에서 최소 구현체로 만들어졌으며, 핵심 명제는 "모델이 아니라 **오케스트레이션이 경쟁력**"이다.

### 구조 요약

```
client ──▶ /v1/chat/completions (OpenAI 호환)
                    ▼
     router (휴리스틱) ─ fast │ full
                    ▼
Thinker(계획) ▶ Workers(N개 병렬) ▶ Verifier(교차검증) ▶ Synthesizer(종합)
                    │
                    └─▶ (필요시) 재귀 호출로 1회 정제
```

### 핵심 파일

| 파일 | 역할 |
|------|------|
| `config.py` | 모델 카탈로그, 역할 배정, 환경 설정 |
| `orchestrator.py` | Thinker / Worker / Verifier / Synthesizer 로직 |
| `server.py` | FastAPI OpenAI 호환 엔드포인트 |

---

## 2. 주요 패턴 분석

### 2.1 Thinker → Worker → Verifier → Synthesizer 분리

각 역할이 명확하게 분리되어 있다.

- **Thinker**: 작업을 짧은 계획으로 분해 (temperature 0.3, 추론 모델 사용)
- **Worker(s)**: 계획에 따라 N개 모델이 병렬 실행 (temperature 0.7)
- **Verifier**: Worker 응답들을 교차 검증, `INSUFFICIENT` 여부 판단 (temperature 0.2)
- **Synthesizer**: 신뢰가중치를 반영한 최종 답 종합 (temperature 0.4)

### 2.2 휴리스틱 라우팅 (Heuristic Routing)

```python
def route(task: str) -> str:
    hard = len(task) > 200 or any(k in task for k in ("분석", "비교", "설계", "증명", "코드"))
    return "full" if hard else "fast"
```

단순 작업은 **fast**(단독 모델), 복잡 작업은 **full**(전체 파이프라인)으로 자동 분기한다.

### 2.3 동적 워커 선발 (Dynamic Worker Selection)

```python
def select_workers(task: str) -> list[tuple[str, float]]:
    ko = korean_ratio(task)       # 한글 비율 (0~1)
    code_w = 0.6 if is_code_task(task) else 0.0
    scored = [
        (m, s["general"] + s["ko"] * ko + s["code"] * code_w)
        for m, s in MODELS.items()
    ]
    scored.sort(key=lambda x: -x[1])
    return top_N_with_normalized_weights(scored)
```

작업 언어(한글 비율)와 유형(코딩 여부)에 따라 모델을 점수화해 동적으로 선발한다.

### 2.4 신뢰가중치 기반 종합 (Trust-Weighted Synthesis)

Worker 응답에 신뢰가중치(normalized score)를 부여하고, Synthesizer에 전달해 맹신 없이 가중 종합한다.

### 2.5 재귀적 정제 (Recursive Refinement)

Verifier가 `INSUFFICIENT`로 판단하면 이전 비평을 포함해 최대 1회 재귀적으로 전체 파이프라인을 재실행한다.

### 2.6 Mock 모드

환경변수 `MOA_MOCK=1`로 실제 API 없이 전체 파이프라인 구조를 검증할 수 있다.

---

## 3. giip-dev-agent 활용 가능성 평가

### ✅ 단기 적용 (즉시 활용 가능)

#### 3.1 휴리스틱 라우팅을 오케스트레이터 역할에 반영

현재 `.agent/roles/orchestrator.md`는 모든 요청을 동일한 파이프라인으로 처리한다. moa의 fast/full 분기 개념을 오케스트레이터 의사결정 기준으로 추가할 수 있다.

```
단순 요청 (짧은 설명, 단일 수정)  →  fast: Developer 1인 직접 처리
복잡 요청 (분석, 설계, 비교)      →  full: Thinker → Workers → Verifier → Synthesizer
```

#### 3.2 Verifier 패턴을 Reviewer 역할에 통합

현재 reviewer 역할은 단순 코드 검토지만, moa의 교차검증 개념을 적용해 "충분한 품질인지 (INSUFFICIENT 여부)"를 명시적으로 판단하고 불충분 시 재작업을 자동 트리거하는 기준을 추가할 수 있다.

#### 3.3 한국어 비율 기반 작업 분류

giip-dev-agent는 이미 한국어 우선 저장소다. 요청의 한국어 비율을 분석해 "한국어 운영 보고서", "영어 기술 문서" 등 출력 유형을 자동 결정하는 기준으로 활용할 수 있다.

### 🔵 중기 적용 (설계 필요)

#### 3.4 동적 에이전트 선발을 dispatching-parallel-agents에 반영

현재 `.agent/skills/dispatching-parallel-agents/SKILL.md`는 독립 작업을 병렬 처리하는 방법을 설명하지만, "어떤 역할/에이전트를 선발할지"에 대한 점수화 기준이 없다. moa의 동적 선발 로직(general + ko + code 점수)을 참고해 giip 에이전트 선발 기준 문서를 작성할 수 있다.

#### 3.5 신뢰가중치 기반 결과 종합 패턴

여러 Developer 또는 Analyst가 병렬로 분석한 결과를 종합할 때, 단순 병합이 아니라 각 에이전트의 신뢰도(역할, 이전 성공률, 도메인 전문성)를 가중해 종합하는 Synthesizer 역할을 추가할 수 있다.

### 🟡 장기 적용 (R&D 수준)

#### 3.6 모델 카탈로그를 에이전트 역할 카탈로그로 확장

moa의 `MODELS` 딕셔너리(ko/code/general 점수)처럼, giip의 에이전트 역할을 "한국어 작업 적합도, 코딩 전문성, 운영 도메인 전문성" 기준으로 점수화해 오케스트레이터가 자동으로 최적 역할을 선발하는 메커니즘을 구현할 수 있다.

---

## 4. 적용 우선순위 및 권장안

| 우선순위 | 항목 | 적용 위치 | 난이도 |
|----------|------|-----------|--------|
| 1 | 휴리스틱 라우팅 기준 추가 | `orchestrator.md` | 낮음 |
| 2 | Verifier(INSUFFICIENT) 판단 기준 | `reviewer.md` | 낮음 |
| 3 | 한국어 비율 기반 작업 분류 기준 | `orchestrator.md` | 낮음 |
| 4 | 동적 에이전트 선발 기준 문서화 | `dispatching-parallel-agents/SKILL.md` | 중간 |
| 5 | Synthesizer 역할 추가 | `.agent/roles/synthesizer.md` | 중간 |
| 6 | 에이전트 역할 카탈로그 점수화 | `.agent/config/` | 높음 |

---

## 5. moa에서 직접 채택하지 않는 이유

| 항목 | 이유 |
|------|------|
| FastAPI 서버 전체 구조 | giip-dev-agent는 AI 에이전트 프레임워크이며 HTTP 게이트웨이가 아님 |
| OpenRouter 모델 카탈로그 | giip는 특정 LLM에 종속되지 않는 문서 기반 구조 |
| 실제 API 호출 코드 | 코딩 아티팩트보다 역할/규칙/스킬 문서 중심의 구조 |

---

## 6. 결론

moa의 핵심 가치는 코드보다 **설계 철학**에 있다.

> "모델이 아니라 오케스트레이션이 경쟁력"

이 철학은 giip-dev-agent의 방향과 정확히 일치한다. giip도 특정 모델을 훈련하는 것이 아니라 역할(Role) / 규칙(Rule) / 스킬(Skill) / 워크플로우(Workflow)를 조합해 에이전트 품질을 높이는 구조다.

따라서 moa의 코드를 직접 가져오기보다, **Thinker-Verifier-Synthesizer 분리 철학**과 **휴리스틱 라우팅 패턴**을 giip의 오케스트레이터 역할 개선과 dispatching 스킬 강화에 반영하는 것이 가장 현실적이고 효과적인 활용 방안이다.

### 즉시 실행 가능한 액션

1. `orchestrator.md`에 fast/full 라우팅 판단 기준 섹션 추가
2. `reviewer.md`에 INSUFFICIENT 판단 기준 및 재작업 트리거 기준 명시
3. `dispatching-parallel-agents/SKILL.md`에 작업 유형별 에이전트 선발 기준 추가
