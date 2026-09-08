# WORKFLOW: Pi-inspired multilingual token budgeting

**Status**: Approved

## Overview

기존 GIIP 프롬프트 조립 흐름에 토큰 상한을 추가한다. 실제 provider tokenizer를 호출하지 않으므로 네트워크·API 비용 없이 결정적으로 동작한다.

## Workflow Tree

### STEP 1: 프롬프트 파트 조립

- **Success**: 고정 파트와 가변 파트를 기존 순서로 구성하고 STEP 2로 이동한다.
- **Failure**: 빈 입력은 빈 문자열로 정규화하고 계속한다.

### STEP 2: 문자 예산 검사

- **이하**: STEP 3으로 이동한다.
- **초과**: 선택 컨텍스트, 과거 실행 결과, 태스크 상세 등 경로별 trim order에 따라 축약하고 STEP 3으로 이동한다.

### STEP 3: 다국어 토큰 예산 검사

- **이하**: 결과를 반환한다.
- **초과**: 동일 trim order로 가변 파트를 추가 축약한다.
- **고정 파트만으로 초과**: 안전 지침을 자르지 않고 경고와 추정치를 남겨 운영자가 tier 설정을 조정할 수 있게 한다.

### STEP 4: 최종 검증

- **Success**: 문자 수와 추정 토큰 수가 모두 상한 이내이며 필수 section이 존재한다.
- **Failure**: 회귀 테스트를 실패시키고 프롬프트를 실행 경로로 보내지 않는다.

## Contracts

| 함수 | 입력 | 출력 |
|---|---|---|
| `estimateTokens(text)` | 임의 Unicode 문자열 | 0 이상의 정수 추정 토큰 수 |
| `truncateToTokens(text, maxTokens, marker)` | 문자열, 토큰 상한, 생략 표식 | `{ text, tokens, truncated }` |
| `fitParts(...)` | 이름 있는 프롬프트 파트와 문자·토큰 예산 | `{ text, trimmed, estimatedTokens }` |

## Cleanup Inventory

런타임 리소스를 새로 만들지 않는다. 테스트가 생성하는 임시 디렉터리는 기존 테스트 스크립트의 종료 정리 흐름을 따른다.

## Derived Test Cases

1. ASCII 400자는 약 100토큰으로 추정한다.
2. 한글 100자는 100토큰 이상으로 보수 추정한다.
3. 절단 결과는 Unicode 문자를 깨뜨리지 않고 토큰 상한을 지킨다.
4. 초기 프롬프트는 CJK 대용량 입력에서도 문자·토큰 상한을 지킨다.
5. 재개 프롬프트는 CJK 대용량 입력에서도 토큰 상한과 60% 규칙을 지킨다.
6. 축약 뒤에도 안전 규칙, 실행 프로토콜, 동적 상태가 남는다.

