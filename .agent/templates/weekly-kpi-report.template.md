---
template: weekly-kpi-report
version: 1.0
---

# 주간 운영 KPI 리포트

- 기간: {YYYY-MM-DD ~ YYYY-MM-DD}
- 작성자: {name}
- 팀/프로젝트: {team}

## 1. KPI 요약

| KPI | 이번 주 | 지난 주 | 증감 | 상태 |
|---|---:|---:|---:|---|
| 리드타임(중앙값, 시간) | {value} | {prev} | {delta} | {🟢/🟡/🔴} |
| 자동화 성공률(%) | {value} | {prev} | {delta} | {🟢/🟡/🔴} |
| 재작업률(%) | {value} | {prev} | {delta} | {🟢/🟡/🔴} |
| 인간개입률(%) | {value} | {prev} | {delta} | {🟢/🟡/🔴} |
| 장애 건수(건) | {value} | {prev} | {delta} | {🟢/🟡/🔴} |

상태 기준(권장):
- 🟢: 목표 범위 내
- 🟡: 목표 대비 경미한 이탈(10% 이내)
- 🔴: 목표 대비 중대한 이탈(10% 초과) 또는 장애 건수 증가

## 2. 주요 변동 원인 (Top 3)

1. {원인 1}
2. {원인 2}
3. {원인 3}

## 3. 장애 및 복구 요약

- Incident ID: {id}
- 영향 범위: {scope}
- 복구 시간: {time}
- 재발 방지 액션: {action}

## 4. 다음 주 액션 (최대 3개)

- [ ] {action 1}
- [ ] {action 2}
- [ ] {action 3}

## 5. 승인

- 작성자: {name}
- 검토자: {name}
- 승인일: {YYYY-MM-DD}
