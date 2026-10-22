# Pi 토큰 효율 기능 비교 및 GIIP 적용 결과

## 분석 범위

- GIIP 기준: [`LowyShin/giip-fde-agent@4c946f6`](https://github.com/LowyShin/giip-fde-agent/tree/4c946f6f432e55dc5c540ce75ec4b48419895401)
- 비교 대상: [`earendil-works/pi@b2602be`](https://github.com/earendil-works/pi/tree/b2602be77cb7b0de45dd616407fd210daa48aa75)
- Pi 라이선스: [MIT](https://github.com/earendil-works/pi/blob/b2602be77cb7b0de45dd616407fd210daa48aa75/LICENSE)
- 적용 원칙: Pi 코드를 복사하지 않고, GIIP의 Slack → CLI 실행 구조에 맞는 예산 관리 원칙만 독립 구현했다.

## 결론

GIIP에는 Pi가 compaction으로 해결하는 문제와 목적이 같은 선택 컨텍스트, 체크포인트 재개, 제한된 진행 출력, 고정 prompt prefix와 우선순위 축약이 이미 있었다. 이 기능은 유지했다. 실제 격차는 기존 `문자 수 ÷ 4` 추정이 한글·일본어·한자 중심 입력을 ASCII와 같은 비율로 계산한다는 점이었다. 따라서 문자 상한을 없애지 않고 다국어 추정 토큰 상한을 추가하는 이중 예산 방식을 도입했다.

## 기능별 비교와 결정

| Pi 기능 | GIIP 근거 | 결정과 이유 |
|---|---|---|
| 컨텍스트 사용량이 `contextWindow - reserveTokens`를 넘으면 이전 내용을 요약하고 최근 메시지를 보존 | [`context-builder.js`](../../slack-bot/context-builder.js)는 메타데이터 카탈로그에서 관련 파일만 선택하고 파일별·전체 문자 상한과 중복 제거를 적용한다. | **기존 기능 유지.** GIIP는 대화 세션을 직접 운영하지 않고 실행 전에 필요한 프로젝트 컨텍스트를 선별하므로 동일한 compaction 구현을 추가하지 않았다. Pi 근거: [`compaction.ts`](https://github.com/earendil-works/pi/blob/b2602be77cb7b0de45dd616407fd210daa48aa75/packages/coding-agent/src/core/compaction/compaction.ts), [`compaction.md`](https://github.com/earendil-works/pi/blob/b2602be77cb7b0de45dd616407fd210daa48aa75/packages/coding-agent/docs/compaction.md). |
| 이전 요약과 최근 작업을 이어 붙이고 read/modified 파일을 누적 추적 | [`retry-checkpoint.js`](../../slack-bot/retry-checkpoint.js), [`resume-context-builder.js`](../../slack-bot/resume-context-builder.js), [`progress-events.js`](../../slack-bot/progress-events.js)는 완료·미완료 단계, 실제 읽기·변경 파일, 오류와 재개 컨텍스트를 별도로 보존한다. | **기존 기능 유지.** 실패 후 전체 원문을 다시 보내지 않고 체크포인트 이후의 필요한 상태만 재개 프롬프트에 싣는다. Pi 근거: [`compaction.ts`](https://github.com/earendil-works/pi/blob/b2602be77cb7b0de45dd616407fd210daa48aa75/packages/coding-agent/src/core/compaction/compaction.ts), [`utils.ts`](https://github.com/earendil-works/pi/blob/b2602be77cb7b0de45dd616407fd210daa48aa75/packages/coding-agent/src/core/compaction/utils.ts). |
| 요약 입력의 tool result를 최대 2,000자로 제한 | [`progress-events.js`](../../slack-bot/progress-events.js)는 진행 출력에 2,000자 상한을 적용하고 오래된 중복 이벤트를 정리한다. | **기존 기능 유지.** 같은 종류의 무제한 출력 재주입을 이미 막고 있다. Pi 근거: [`utils.ts`](https://github.com/earendil-works/pi/blob/b2602be77cb7b0de45dd616407fd210daa48aa75/packages/coding-agent/src/core/compaction/utils.ts). |
| 재사용 가능한 prefix와 일회성 요약 호출의 provider cache 제어 | [`prompt-templates.js`](../../slack-bot/prompt-templates.js)는 역할·안전 규칙·실행 프로토콜을 고정 prefix로 두고 선택 컨텍스트와 과거 출력을 먼저 축약한다. | **고정 prefix와 우선순위 축약은 유지. Provider cache-write 억제와 routing ID 제어는 미도입.** GIIP는 외부 CLI를 호출하며 provider 요청 옵션을 소유하지 않는다. Pi 근거: [`completeSummarization()`](https://github.com/earendil-works/pi/blob/b2602be77cb7b0de45dd616407fd210daa48aa75/packages/coding-agent/src/core/compaction/compaction.ts#L570-L598). |
| JSONL 세션 트리와 `/tree` 이동 시 branch summary | GIIP issue 실행은 준비된 브랜치에서 하나의 태스크를 선형으로 실행하고, CLI 내부 대화 트리를 저장·탐색하지 않는다. | **미도입.** 세션 트리 소유권 없이 별도 branch summary 계층을 만들면 중복 상태와 동기화 실패가 생긴다. Pi 근거: [`session-format.md`](https://github.com/earendil-works/pi/blob/b2602be77cb7b0de45dd616407fd210daa48aa75/packages/coding-agent/docs/session-format.md), [`branch-summarization.ts`](https://github.com/earendil-works/pi/blob/b2602be77cb7b0de45dd616407fd210daa48aa75/packages/coding-agent/src/core/compaction/branch-summarization.ts). |
| 실제 사용량과 추정치를 결합한 토큰 임계치 | GIIP 기준 버전의 [`model-config.js`](https://github.com/LowyShin/giip-fde-agent/blob/4c946f6f432e55dc5c540ce75ec4b48419895401/slack-bot/model-config.js)는 프롬프트 토큰 추정값을 문자 상한의 1/4로 계산했다. | **다국어 토큰 추정과 문자·토큰 이중 예산을 도입.** 새 [`token-budget.js`](../../slack-bot/token-budget.js)가 ASCII, CJK/가나, 기타 비ASCII를 구분해 추정하고 [`prompt-templates.js`](../../slack-bot/prompt-templates.js)가 두 상한을 함께 적용한다. |

## 도입한 동작

[`token-budget.js`](../../slack-bot/token-budget.js)는 의존성 없이 다음 규칙으로 보수적인 추정치를 만든다.

- ASCII: 약 4 code point당 1토큰
- 한글·가나·한자 등 CJK: 약 1 code point당 1토큰
- 그 외 비ASCII: 약 2 code point당 1토큰

[`model-config.js`](../../slack-bot/model-config.js)는 티어별 문자 상한과 별도의 추정 토큰 상한을 반환한다. [`prompt-templates.js`](../../slack-bot/prompt-templates.js)는 먼저 선택 컨텍스트, 과거 오류·출력, 태스크 상세처럼 가변적인 저우선순위 파트를 줄이고, 문자 수와 추정 토큰 수가 모두 예산 안에 들어왔는지 검사한다. 안전 규칙·실행 프로토콜·동적 상태 같은 고정 파트만으로 상한을 넘는 경우에는 이를 자르지 않고 초과량을 경고한다.

운영 환경에서 다음 변수로 기본값을 재정의할 수 있다.

| 환경변수 | 용도 |
|---|---|
| `PROMPT_INITIAL_MAX_TOKENS` | 최초 실행 프롬프트의 추정 토큰 상한 |
| `PROMPT_RESUME_MAX_TOKENS` | 재개 프롬프트의 추정 토큰 상한 |

기존 `PROMPT_INITIAL_MAX_CHARS`, `PROMPT_RESUME_MAX_CHARS` 문자 상한과 재개 프롬프트 60% 규칙도 그대로 적용된다.

## 검증

실행 명령:

```bash
node slack-bot/tools/test-cost-optimization.js
```

2026-09-08 실행 결과는 **통과 112 / 실패 0**이다. 회귀 테스트는 ASCII 400자 추정, 한글 100자 추정, Unicode 경계를 지키는 절단, 한글 대용량 최초·재개 프롬프트의 이중 상한, 고정 안전 절 보존, 재개 60% 상한을 포함한다. 테스트 구현은 [`test-cost-optimization.js`](../../slack-bot/tools/test-cost-optimization.js)에 있다.

## 한계와 운영 주의

- 이 값은 공급자 tokenizer의 실제 결과가 아니라 네트워크 호출 없이 사용하는 보수적 추정치다. 모델·공급자별 토큰 수와 정확히 일치한다고 해석하면 안 된다.
- 절단 경계는 Unicode **code point**를 보존하지만 grapheme cluster까지 보장하지 않는다. 결합 문자나 ZWJ 이모지 시퀀스는 시각적 문자 중간에서 나뉠 수 있다.
- 고정 안전 파트 자체가 예산보다 크면 지시 보존을 우선하므로 최종 프롬프트가 설정 상한을 넘을 수 있다. 이 경우 경고의 문자·토큰 초과량을 보고 티어 또는 환경변수 상한을 조정해야 한다.
- 실제 provider 사용량은 기존 비용 계측 경로에서 계속 관찰해야 한다. 이 변경만으로 절감률을 단정하지 않는다.

## 작업 이력

- 20260908 02:01:03 UTC — Pi 비교 결과를 문서화하고 다국어 추정 토큰 이중 예산의 적용·제외 근거와 검증 결과를 기록했다.
