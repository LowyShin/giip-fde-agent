# SkillOpt와 Agent Lightning의 GIIP Dev Agent 적용 비교 분석

분석 원문:
`C:\Users\lowys\Downloads\Projects\lowyworkenv\agents\msopt-lightning.md`

## 요약

SkillOpt와 Agent Lightning은 모두 에이전트를 개선하기 위한 Microsoft 계열 프로젝트지만, 적용 계층이 다르다.

- SkillOpt는 모델 가중치를 변경하지 않고 `best_skill.md` 같은 자연어 skill 문서를 반복 개선한다.
- Agent Lightning은 에이전트 실행 trace, tool call, reward를 수집해 RL/SFT/APO 같은 학습 루프에 연결하는 프레임워크다.
- GIIP Dev Agent에는 단기적으로 SkillOpt 방식의 운영 skill 자동 개선 레이어가 더 현실적이다.
- GIIP의 실행 trace와 reward 데이터가 충분히 쌓이면 Agent Lightning 방식의 agent training infrastructure로 확장하는 것이 적합하다.

## 핵심 차이

| 항목 | SkillOpt | Agent Lightning |
| --- | --- | --- |
| 목적 | 자연어 skill 문서 자동 개선 | 에이전트 실행을 학습 가능한 구조로 전환 |
| 최적화 대상 | `best_skill.md`, runbook, prompt, checklist | prompt, policy, reward-guided behavior, model/resource |
| 모델 가중치 변경 | 없음 | 가능 |
| 주요 입력 | 성공/실패 사례, validation case, 기존 skill 문서 | trace, tool call, reward, trajectory |
| 주요 산출물 | 개선된 skill 문서 | training loop, store, trainer, algorithm, updated resource |
| GIIP 적용 난이도 | 낮음 | 높음 |
| 실무 PoC 적합도 | 높음 | 중장기 R&D에 적합 |

## SkillOpt를 GIIP에 적용하는 방향

SkillOpt는 GIIP Dev Agent의 운영 지식과 진단 절차를 문서 기반 skill로 정리한 뒤, 실패 사례와 성공 사례를 이용해 skill을 개선하는 방식에 적합하다.

적용 가능한 skill 예시는 다음과 같다.

- SQL Server / RDS 진단 skill
- MySQL / TiDB 연결 장애 진단 skill
- Linux topology 수집 skill
- AWS 비용 최적화 skill
- 보안 점검 checklist
- 장애 대응 runbook
- 한국어 우선 운영 보고서 작성 workflow

권장 구조는 다음과 같다.

```text
GIIP 운영 로그 / 실패 사례 / 성공 사례
  -> SkillOpt로 skill 문서 개선
  -> best_skill.md 생성
  -> GIIP Agent의 규칙, 진단 절차, 장애 대응 runbook으로 배포
```

이 접근은 모델 fine-tuning, GPU 기반 RL infrastructure, 대규모 trainer 없이도 PoC가 가능하다. 현재 GIIP Dev Agent처럼 운영 문서, 진단 규칙, 고객사별 절차를 축적하는 저장소에는 가장 먼저 적용할 수 있는 방식이다.

## Agent Lightning을 GIIP에 적용하는 방향

Agent Lightning은 GIIP Agent의 실제 실행을 학습 가능한 데이터로 바꾸는 데 적합하다. 단순한 문서 개선보다 아래 계층의 training infrastructure에 가깝다.

GIIP 관점에서 필요한 데이터는 다음과 같다.

- 사용자의 요청 내용
- 적용된 role, rule, skill, workflow
- tool call과 command outcome
- 에이전트 판단 및 수정 이력
- 성공/실패 결과
- 사람이 판단한 품질 점수 또는 reward

권장 구조는 다음과 같다.

```text
GIIP Agent 실행
  -> prompt / tool call / reward / trace 수집
  -> Agent Lightning Store
  -> RL / SFT / APO 학습
  -> prompt, policy, model, behavior resource 개선
```

이 방식은 multi-agent handoff, tool-call 성공률 개선, 장애 원인 추론 정확도 향상, 고객사별 운영 판단 최적화처럼 장기적인 agent behavior 개선에 적합하다. 다만 trace schema, reward definition, trainer, rollback path가 필요하므로 초기 적용 비용이 높다.

## 권장 적용 순서

### 1단계: Skill Optimization

GIIP의 반복 업무와 장애 대응 절차를 skill 문서로 정리하고, validation case를 만들어 SkillOpt 방식으로 개선한다.

예상 산출물:

- `sqlserver_rds_diagnosis.md`
- `mysql_connection_diagnosis.md`
- `linux_topology_collection.md`
- `aws_cost_optimization.md`
- `security_audit_checklist.md`
- 고객사별 `best_skill.md`

### 2단계: Trace Discipline

Agent Lightning 적용 전 단계로 GIIP Agent의 실행 trace를 표준화한다. 이 단계는 SkillOpt 평가 데이터와 Agent Lightning 학습 데이터 양쪽에 모두 필요하다.

필수 trace 항목:

- 요청과 목표
- 적용 문서와 workflow
- 실행 command와 결과
- 판단 근거
- 실패와 correction
- 최종 결과와 사용자 피드백

### 3단계: Agent Training Infrastructure

충분한 trace와 reward 데이터가 쌓이면 Agent Lightning 방식의 학습 시스템을 검토한다.

필요 요소:

- trace schema
- reward definition
- task category
- evaluation environment
- updated prompt/resource 배포 방식
- rollback path

## 결론

GIIP Dev Agent에는 먼저 SkillOpt 방식으로 운영 skill 자동 개선 레이어를 붙이는 것이 현실적이다. 이 방식은 기존 문서 중심 구조와 잘 맞고, 단기 PoC 비용이 낮다.

Agent Lightning은 GIIP Agent의 실행 trace와 reward 데이터가 충분히 축적된 뒤 도입하는 것이 좋다. 장기적으로는 GIIP를 단순 자동화 agent가 아니라 지속적으로 행동을 개선하는 agent training platform으로 확장할 수 있다.

최종 권장안은 다음과 같다.

```text
SkillOpt 우선 적용
  -> GIIP skill / runbook 개선
  -> trace와 evaluation case 축적
  -> Agent Lightning 적용 가능성 검증
  -> 장기 agent training infrastructure로 확장
```

## 참고 자료

- [Microsoft SkillOpt](https://github.com/microsoft/SkillOpt)
- [Microsoft Agent Lightning](https://github.com/microsoft/agent-lightning)
- [SkillOpt paper](https://arxiv.org/abs/2605.23904)
- [Agent Lightning paper](https://arxiv.org/abs/2508.03680)
