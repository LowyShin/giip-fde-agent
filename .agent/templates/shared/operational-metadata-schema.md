# Skill/Role 운영 책임 메타데이터 스키마

Skill/Role 카탈로그의 운영 가능성을 높이기 위해 아래 필드를 표준으로 사용합니다.

## 1) 공통 필드

| 필드 | 타입 | 필수 | 설명 |
|---|---|---|---|
| `owner` | string | Yes | 운영 책임자 또는 책임 역할 |
| `when_to_use` | string[] | Yes | 사용 조건 |
| `do_not_use_when` | string[] | Yes | 금지 조건 |
| `failure_response` | string[] | Yes | 실패 시 대응 절차 |

## 2) Skill 파일 예시 (YAML front matter)

```yaml
---
name: example-skill
description: Example skill description
owner: orchestrator
when_to_use:
  - 반복 작업이 명확하고 자동화 이점이 클 때
  - 입력/출력 형식이 안정적일 때
do_not_use_when:
  - 민감 데이터 접근 승인이 없을 때
  - 실패 시 복구 경로가 정의되지 않았을 때
failure_response:
  - 실행 중단 후 상태를 Pending으로 복귀
  - incident-playbook 문서 기준으로 복구
---
```

## 3) Role 문서 메타데이터 블록 예시

Role 문서는 현재 자유 형식이므로, 문서 상단에 아래 블록을 추가하는 것을 표준으로 합니다.

```markdown
## 운영 책임 메타데이터
- Owner: orchestrator
- 사용조건:
  - 작업 범위가 명확하고 담당자 분리가 필요할 때
- 금지조건:
  - 승인 게이트 대상인데 승인 기록이 없을 때
- 실패 시 대응:
  - 작업 중지
  - 원인 분석 후 재할당
```

## 4) 적용 원칙

- 신규 Skill/Role에는 반드시 이 메타데이터를 포함합니다.
- 기존 Skill/Role은 수정 시점에 점진적으로 이관합니다.
- `failure_response`는 반드시 실행 가능한 행동 단위로 작성합니다.

