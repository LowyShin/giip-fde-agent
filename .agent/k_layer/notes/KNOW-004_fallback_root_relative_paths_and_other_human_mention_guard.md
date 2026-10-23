# KNOW-004: 폴백 루트별 상대경로 + 다른 사람 멘션 가드는 회귀 테스트로 고정한다

- 근거: giip 4045 (결함 A: PR #224, 결함 B: PR #225, 회귀 테스트·셋업 문서: 본 노트와 같은 PR)

## 1. 결함 A — 컨텍스트 카탈로그 경로
`slack-bot/context-builder.js` `buildContextCatalog(baseDir, workspaceDir)` 는 대상 프로젝트에 `.agent/roles|rules|skills` 가 없으면 workspaceDir 로 폴백한다. 상대경로를 항상 baseDir 기준으로 계산하면 `../<workspace>/...` 가 되어 `readSelectedContext` 의 `..` 차단 가드가 분석을 중단시킨다. **파일을 실제로 찾은 루트 기준**으로 계산해야 한다. 신규 연결 프로젝트는 항상 이 조건이라 100% 재현된다.

## 2. 결함 B — 활성 스레드의 다른 사람 멘션
활성 태스크 스레드의 후속 입력 자동 허용(`isTaskReply`)이 "다른 사람을 향한 메시지"를 구분하지 않아, 사람끼리의 확인·클로즈 요청에 봇이 태스크를 만들었다. 봇/등록된 다른 봇이 아닌 `<@U…>` 멘션이 있으면 `isTaskReply` 를 억제한다.

## 3. 재발 방지
- 판정을 `slack-bot/mention-engagement.js` `classifyMentions()` 순수 함수로 분리(동작 불변)하고, 외부 상태는 인자로 주입한다. 순수 함수가 아니면 테스트가 어려워 회귀 감지가 안 된다.
- 테스트: `node slack-bot/tools/test-mention-engagement.js`, `node slack-bot/tools/test-context-catalog.js` (`node:test`, 기존 `tools/test-*.js` 관례). 수정 전 코드/가드 제거본에서 FAIL, 현재 코드에서 PASS 임을 통제 비교로 확인했다.
- 새 host 셋업 누락(git 작성자·HTTPS push 자격증명)은 `docs/60-operations/service-account-git-setup.md` 로 문서화했다.
