# KNOW-046 — Q&A 경로는 한 프로젝트로 닫고, 엔진 실행에는 하드 타임아웃을 두지 않는다

> 근거: giip 5144(원본 giip 4902 의 slack-bot 수정을 slack-bot/slack-bot-minimax 로 이식) · 발행: 2026-11-13 · 상태: 검증됨(이식 후 회귀 테스트 실행)

## 요지

1. **Q&A 안전망이 형제 저장소까지 스냅샷하면 오귀속이 생긴다.** 답변 뒤 자동 브랜치/PR 안전망
   (`snapshotCandidateRepos`)이 `PROJECTS_ROOT` 형제 저장소까지 보면, 같은 PC 의 다른 세션이 다른 프로젝트에서
   만든 변경이 "이 질문의 변경"으로 잡혀 무관한 채널에 PR/수동필요 알림이 올라간다.
   → Q&A 는 `snapshotCandidateRepos(workDir, { siblings: false })`(workDir 저장소 + nested 만). 태스크 경로는
   `siblings` 기본 true 로 불변.
2. **엔진 `--add-dir` 에 `PROJECTS_ROOT` 를 넣으면 다른 프로젝트 내용이 답변에 섞인다.** 기본은 workDir+agentDir 만,
   `SLACKBOT_QNA_ALL_PROJECTS=1` 이 롤백 스위치(기본 off).
3. **DM 대화 기록 키는 프로젝트별로 분리한다**(`convHistoryKey(channelId, projectName)`). 기본 프로젝트는 기존
   키 `channelId` 유지(진행 중 대화 보존), 그 밖은 `channelId:projectName`.
4. **엔진(`claude -p`) 20분 하드 타임아웃은 긴 Q&A 응답을 유실시킨다.** 기본 무제한,
   `SLACKBOT_ENGINE_TIMEOUT_MIN`(양의 정수 분) 으로만 상한을 둔다. 무제한 실행의 좀비 식별용으로
   `SLACKBOT_ENGINE_HEARTBEAT_MIN`(기본 30, 0=off) 경과 로그(`spawnAsync` 경로만 — `runClaude` 는 `spawnSync`).

## 적용 위치 (이식본)

- `slack-bot/` 와 `slack-bot-minimax/` 의 `claude-cli.js`·`handlers.js`·`task-manager.js`.
- 회귀 테스트: 각 봇 `tools/test-qna-isolation.js`, `tools/test-engine-timeout.js`.
- 변경은 **pm2 재시작 후** 적용된다.

## 재발 방지

- 두 봇은 코드가 갈라져 있어 한쪽만 고치면 다른 쪽에 같은 결함이 남는다 — 이식 시 두 봇 모두 grep 으로
  `20 * 60 * 1000`/`--add-dir`/`snapshotCandidateRepos(` 를 확인한다.
- 하드코딩된 사용자 경로(`slack-bot-minimax/config.js` 의 `PROJECTS_ROOT`)는 별도 후속 과제다(이 노트 범위 밖).
