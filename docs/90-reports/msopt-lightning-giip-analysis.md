# SkillOpt와 Agent Lightning의 GIIP Dev Agent 적용 비교 분석

원본 자료:
`C:\Users\lowys\Downloads\Projects\lowyworkenv\agents\msopt-lightning.md`

## 요약

SkillOpt와 Agent Lightning은 모두 에이전트 개선과 관련이 있지만, 해결하는
문제가 다르다. GIIP Dev Agent 관점에서는 SkillOpt를 먼저 적용해 스킬,
런북, 프롬프트, 운영 절차를 개선하고, 이후 실제 실행 trace와 reward 데이터가
충분히 쌓이면 Agent Lightning 계열의 학습 인프라를 검토하는 순서가 적절하다.

권장 방향은 다음과 같다.

1. GIIP 운영 스킬을 SkillOpt 방식으로 먼저 개선한다.
2. 실제 GIIP Agent 실행 과정에서 trace, 결과, 평가 케이스를 수집한다.
3. 충분한 trajectory와 reward 기준이 확보된 뒤 Agent Lightning 적용 여부를 판단한다.

## 핵심 차이

| 구분 | SkillOpt | Agent Lightning |
| --- | --- | --- |
| 목적 | 자연어 skill artifact 최적화 | 실행 trace 기반 agent behavior 학습 및 최적화 |
| 주요 산출물 | `best_skill.md`, 재사용 가능한 skill 문서 | policy, prompt resource, reward-guided behavior |
| 필요한 기반 | 평가 케이스와 validation loop | trace store, reward 설계, trainer, algorithm, runtime 통합 |
| GIIP 적합 영역 | runbook, prompt, diagnostic, checklist 개선 | 장기 agent training platform, multi-agent 최적화 |
| 도입 난이도 | 낮음 | 높음 |
| 실용 가치 도달 속도 | 빠름 | 중장기 |

## SkillOpt가 GIIP에 주는 의미

SkillOpt는 현재 GIIP Dev Agent 구조와 잘 맞는다. 이 저장소는 이미 rule, role,
workflow, skill을 파일 기반 운영 자산으로 다루고 있으므로, 모델 fine-tuning이나
무거운 RL 인프라 없이도 문서형 스킬을 개선할 수 있다.

우선 적용하기 좋은 대상은 다음과 같다.

- SQL Server / RDS 진단 skill
- MySQL / TiDB troubleshooting skill
- Linux topology 수집 skill
- AWS cost optimization skill
- security audit checklist
- incident response runbook
- Korean-first engineering workflow prompt

실용적인 산출물은 검토 가능한 skill 파일이어야 한다. 개선된 결과는 평가 케이스를
통과한 뒤 `.agent/skills`나 관련 workflow 폴더로 승격하는 흐름이 적절하다.

## Agent Lightning이 GIIP에 주는 의미

Agent Lightning은 단순 prompt 개선 도구라기보다 agent 학습 인프라에 가깝다.
따라서 GIIP Agent의 실제 실행 기록, tool call 결과, 사람의 correction,
성공/실패 판단, reward 기준이 충분히 쌓였을 때 가치가 커진다.

적합한 적용 영역은 다음과 같다.

- diagnostic session의 tool-call trace 수집
- incident resolution 성공 여부에 대한 reward scoring
- multi-agent handoff behavior 최적화
- 성공/실패한 support workflow 기반 학습
- 반복되는 GIIP 업무의 policy 및 execution strategy 개선

즉, Agent Lightning은 빠른 문서 개선 트랙이 아니라 장기 training infrastructure
트랙으로 보아야 한다.

## GIIP 도입 로드맵

### 1단계: Skill Optimization

먼저 작은 GIIP 평가 케이스 세트를 만들고, 선택된 skill을 개선한다.

초기 후보:

- `sqlserver_rds_diagnosis.md`
- `mysql_connection_diagnosis.md`
- `linux_topology_collection.md`
- `aws_cost_optimization.md`
- `security_audit_checklist.md`

기대 결과:

- 더 좋은 skill 문서
- 반복 가능한 validation case
- `best_skill.md` 결과를 GIIP skill로 승격하는 명확한 흐름

### 2단계: Trace Discipline

Agent Lightning을 바로 붙이기 전에 GIIP Agent 작업 trace를 구조화해 모은다.

최소 trace 필드:

- 사용자 요청 분류
- 선택된 role, rule, skill, workflow
- tool call과 command outcome
- 사람의 correction
- 최종 해결 상태
- 실패 원인 또는 개선 메모

기대 결과:

- 재사용 가능한 trajectory 데이터
- skill regression test 기반
- Agent Lightning 도입 판단 근거

### 3단계: Agent Training Infrastructure

충분한 trace와 reward 기준이 생긴 뒤 Agent Lightning 계열 인프라를 검토한다.

전제 조건:

- 안정적인 trace schema
- 명확한 reward definition
- 반복되는 task category
- 안전한 evaluation environment
- 업데이트된 agent behavior의 rollback path

기대 결과:

- prompt resource 또는 policy 최적화
- multi-agent dispatch 개선
- 반복 GIIP workflow의 측정 가능한 품질 개선

## 판단 매트릭스

| GIIP 요구 | 권장 접근 | 이유 |
| --- | --- | --- |
| prompt와 skill 품질을 빠르게 개선 | SkillOpt | 검토 가능한 text artifact를 만든다 |
| 운영 runbook을 재사용 가능하게 정리 | SkillOpt | GIIP의 파일 기반 skill 구조와 맞다 |
| tool-call 성공/실패를 평가 | trace 수집 후 Agent Lightning | 실행 데이터가 먼저 필요하다 |
| multi-agent coordination 최적화 | Agent Lightning | trace와 reward 기반 학습이 필요하다 |
| 가벼운 PoC | SkillOpt | setup 비용이 낮다 |
| 장기 agent training platform 구축 | Agent Lightning | infrastructure-level optimization에 적합하다 |

## 최종 권장안

현재 GIIP Dev Agent에는 다음 순서가 가장 현실적이다.

```text
SkillOpt 먼저 적용
  -> GIIP skill / runbook 개선
  -> evaluation case와 trace 수집
  -> Agent Lightning 필요성 평가
  -> 반복 가능한 agent workflow에 Agent Lightning 적용
```

이 접근은 지금 저장소의 구조를 유지하면서도, 나중에 더 깊은 agent optimization으로
확장할 수 있는 경로를 남긴다.

## 참고 링크

- [Microsoft SkillOpt](https://github.com/microsoft/SkillOpt)
- [Microsoft Agent Lightning](https://github.com/microsoft/agent-lightning)
- [SkillOpt paper](https://arxiv.org/abs/2605.23904)
- [Agent Lightning paper](https://arxiv.org/abs/2508.03680)
