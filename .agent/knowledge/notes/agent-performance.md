# Agent Performance Claims

## 다국어 프롬프트 예산

CLAIM-001: ASCII 기준 `문자 수 ÷ 4`만으로 설정한 프롬프트 예산은 한글·가나·한자 중심 입력을 보수적으로 제한하지 못하므로, GIIP 실행 프롬프트에는 문자 상한과 다국어 추정 토큰 상한을 함께 적용해야 한다.
- **evidence**: 회귀 fixture에서 ASCII 400자는 100토큰, 한글 100자는 최소 100토큰으로 추정하며, 한글 대용량 최초·재개 프롬프트가 각각의 추정 토큰 상한 안에 있고 고정 안전 절을 보존함을 검증했다. 전체 회귀 결과는 통과 112 / 실패 0이다.
- **source**: [`slack-bot/token-budget.js`](../../../slack-bot/token-budget.js), [`slack-bot/tools/test-cost-optimization.js`](../../../slack-bot/tools/test-cost-optimization.js), [`docs/03-analysis/pi-comparison-token-efficiency.analysis.md`](../../../docs/03-analysis/pi-comparison-token-efficiency.analysis.md), [`earendil-works/pi@b2602be compaction`](https://github.com/earendil-works/pi/blob/b2602be77cb7b0de45dd616407fd210daa48aa75/packages/coding-agent/src/core/compaction/compaction.ts)
- **observed_at**: 20260908
- **invalidated_at**: null
- **confidence**: high
