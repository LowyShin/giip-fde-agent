# RCA: 완료보고 GitHub URL이 사라진 문제

- 발생 인지: 2026-07-03
- 영향: `giipclaude` Slack 봇의 작업 완료보고에서 GitHub 결과 URL이 누락 (어제까지 정상 → 오늘부터 사라짐)
- 상태: 수정·검증 완료 (giip-dev-agent `f047b43`, Lowyworkenv `5d2656d5`), task(20260703143321)

## 증상
완료보고가 어제는 `📋 태스크 결과 보고서: https://github.com/.../blob/.../done/<taskId>.md` 형태로 정상이었으나,
오늘부터 URL 없이 파일 경로만 나오는 폴백 메시지로 바뀌었다.

## 근본 원인 (메모리 문제 아님 — 코드 버그)
완료보고 URL은 `task-manager.js`의 `gitPushResult()`가 **git push 성공 시에만** 반환한다.
`gitPushResult`가 null을 반환한 연쇄:
1. 작업트리가 dirty하거나(추적된 런타임 상태 파일 등) origin보다 뒤처지면,
2. `git pull --rebase`가 dirty 트리에서 거부되고(코드는 결과 미확인),
3. 이어지는 `git push`가 non-fast-forward로 거부 → status≠0 → **null 반환**,
4. → `index.js`가 URL 없는 폴백 메시지 전송.

### 왜 어제는 되고 오늘은 안 됐나
어제는 origin이 앞서지 않아 fast-forward push 성공(URL 정상). 오늘은 origin이 앞서가며 봇 로컬이 뒤처짐 → rebase 불가 → push 거부 → URL 증발. 한 번 뒤처지면 스스로 못 따라잡아 계속 실패.

## 수정
1. **`gitPushResult` 견고화**: `git pull --rebase --autostash` + push 거부 시 `fetch` 후 rebase+push 1회 재시도, rebase 실패 시 `rebase --abort`.
2. **`.gitignore`**: slack-bot 런타임 상태 파일(`.bot-threads.json`/`.task-state.json`/`tasklist.json`) 무시 패턴 유지(재추적 방지). *(giip는 이미 미추적)*
3. **폴백 메시지**: push 실패 시 "원격 미반영이라 URL 미생성" 사유 명시.

## 검증
- dirty 트리에서 `git pull --rebase --autostash` → exit 0(구버그의 거부 지점 통과).
- 수정 파일 `node --check` 통과.

## 재발 방지
- **런타임 상태는 절대 git 추적하지 않는다** + **push는 autostash·재시도로 견고하게**.
- 완료보고에서 URL이 사라지면 메모리가 아니라 **`gitPushResult`의 push 실패**를 먼저 의심하라.
- (Lowyworkenv 정본 규칙: `.agent/rules/38_slackbot_push_reliability.md`)
