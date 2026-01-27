# Gemini Multi-API Key Guide

이 가이드는 여러 개의 Gemini API Key를 사용하여 할당량(Quota)을 효율적으로 분산하고 제한을 피하는 방법을 설명합니다.

## ⚙️ 설정 방법 (Configuration)

다수의 API Key를 사용하려면 `settings.json` 파일을 다음과 같이 설정하십시오.

### 1. settings.json 편집
프로젝트 루트의 `.agent/settings.json` 파일을 열고 아래 형식을 참고하여 키와 모드를 추가합니다.

```json
{
  "api_key": "PRIMARY_KEY",
  "api_keys": [
    "KEY_1",
    "KEY_2",
    "KEY_3"
  ],
  "api_key_mode": "sequential"
}
```

### 2. 설정 항목 설명
- **api_key**: 단일 사용 시 기본 키입니다 (하위 호환성용).
- **api_keys**: 사용할 API Key들의 배열입니다.
- **api_key_mode**: 키 선택 방식을 결정합니다.
  - `sequential`: 순차적으로 키를 돌아가며 사용합니다 (Round-robin). 현재 상태는 `.agent/state.json`에 저장됩니다.
  - `random`: 실행할 때마다 무작위로 키를 하나 선택합니다.

## 🔄 작동 원리
- **Sequential 모드**: 시스템이 `.agent/state.json` 파일을 생성하여 마지막으로 사용한 키의 인덱스를 저장합니다. 다음 실행 시 자동으로 다음 키를 선택하여 환경 변수(`GEMINI_API_KEY`)에 설정합니다.
- **Random 모드**: 등록된 키 중에서 매 세션마다 하나를 무작위로 골라 사용합니다.

## 🚨 주의 사항
- `api_keys` 배열이 설정되어 있으면 `api_key` (단일 문자열)보다 우선순위가 높습니다.
- 키가 올바르지 않으면 에이전트 기동 시 인증 오류가 발생할 수 있으니 유효한 키를 입력해 주세요.
