# ANT 검증 게이트 적용 계획

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** `to-nexus/ant`의 결정론적 검증 개념을 GIIP 기존 체크포인트·재개 흐름에 맞게 독립 구현하여, 프로세스 종료 코드 0만으로 실패한 작업이 완료 처리되는 문제를 막는다.

**Architecture:** 새 순수 모듈 `slack-bot/task-verifier.js`가 실제 소스 변경, 최신 테스트 결과, 차단 이벤트, 결과 파일 존재 여부를 입력받아 완료/재시도 판정을 반환한다. `task-manager.js`는 자식 프로세스 종료 후 이 판정을 실행하고, 실패 시 기존 `recordFailure → shouldResume → attempt` 경로를 재사용한다. ANT 코드는 복사하지 않고 Apache-2.0 프로젝트에서 확인한 검증 상태기계의 개념만 GIIP 구조에 맞게 구현한다.

**Tech Stack:** Node.js CommonJS, 내장 `assert`, 기존 `progress-events`·`retry-checkpoint`·`task-manager` 모듈

---

## 이해된 내용

이전 ANT 비교가 실제 반영되었는지 저장소와 전체 Git 이력으로 재확인하고, 이미 존재하는 컨텍스트 선별·비용 계측·체크포인트·축약 재개 기능은 중복 도입하지 않는다. 현재 확인된 가장 작은 고가치 누락은 완료 검증 게이트이며, 이번 변경은 이 기능과 ANT 참조 등록에 한정한다.

## 성공 기준

- 소스 변경이 없는 문서 조회·분석 작업은 테스트 기록 없이도 완료할 수 있다.
- 실제 소스 변경이 있으면 최신 테스트 결과에 성공이 하나 이상 있어야 한다.
- 같은 명령의 과거 실패 뒤 최신 성공이 기록되면 성공으로 판정한다.
- 최신 실패 테스트 또는 해소되지 않은 차단 이벤트가 있으면 완료하지 않고 기존 제한 재시도 흐름을 사용한다.
- 결과 파일이 없으면 완료하지 않는다.
- 비검증 상태는 checkpoint와 비용 로그에서 실패로 기록된다.
- ANT가 한국어·영어·일본어 외부 저장소 목록과 `links.md`에 등록된다.

### Task 1: 순수 완료 판정기 TDD

**Files:**
- Create: `slack-bot/task-verifier.js`
- Modify: `slack-bot/tools/test-cost-optimization.js`

**Step 1: Write the failing tests**

다음 네 동작을 테스트한다: 소스 변경+검증 없음은 실패, 최신 테스트 실패는 실패, 동일 명령의 실패 후 성공은 통과, 소스 변경 없음은 테스트 없이 통과. 결과 파일 누락과 차단 이벤트도 실패하는 경계 테스트를 포함한다.

**Step 2: Run test to verify it fails**

Run: `node slack-bot/tools/test-cost-optimization.js`

Expected: `task-verifier` 모듈이 없어 실패한다.

**Step 3: Write minimal implementation**

테스트 결과를 명령별 최신 상태로 축약하고, 실패/차단/결과 파일/소스 변경 여부를 순서대로 판정하는 순수 함수를 구현한다.

**Step 4: Run test to verify it passes**

Run: `node slack-bot/tools/test-cost-optimization.js`

Expected: 모든 테스트 PASS.

### Task 2: 실행 완료 경로 연결

**Files:**
- Modify: `slack-bot/task-manager.js`
- Modify: `slack-bot/tools/test-cost-optimization.js`

**Step 1: Write the failing integration-structure test**

`task-manager.js`가 종료 코드 0일 때 verifier를 호출하고, 거부 판정을 기존 checkpoint 재시도 경로로 전달하며 비용 로그에 검증 실패를 반영하는지 테스트한다.

**Step 2: Run test to verify it fails**

Run: `node slack-bot/tools/test-cost-optimization.js`

Expected: verifier 연결이 없어 실패한다.

**Step 3: Write minimal implementation**

자식 프로세스 종료 직후 구조화 이벤트와 실제 변경을 입력으로 완료 판정을 만든다. 거부 시 합성 검증 오류를 `recordFailure`에 저장하고 기존 attempt 제한을 그대로 사용하며, 승인 시에만 `recordSuccess`와 `onComplete`를 호출한다.

**Step 4: Run test to verify it passes**

Run: `node slack-bot/tools/test-cost-optimization.js`

Expected: 모든 테스트 PASS.

### Task 3: 참조·이력 문서화

**Files:**
- Modify: `links.md`
- Modify: `docs/50-technical/ai-repositories-index.md`
- Modify: `docs/50-technical/ai-repositories-index_en.md`
- Modify: `docs/50-technical/ai-repositories-index_ja.md`
- Modify: `docs/WHATS_NEW.md`

ANT를 검증·복구 가능한 멀티에이전트 상태기계의 참고 구현으로 등록하고, GIIP에는 체크포인트·컨텍스트 선별이 이미 있으며 이번에는 종료 코드와 실제 검증 상태를 분리한 완료 게이트만 독립 구현했음을 기록한다. 7일 이력 규칙을 유지한다.

### Task 4: 검토·배포

명세 준수 검토 후 코드 품질 검토를 수행한다. `node slack-bot/tools/test-cost-optimization.js`, `node slack-bot/tools/test-live-pipeline.js`의 자격증명 비의존 검사를 실행하고, 변경 파일과 diff를 재검토한다. 구조화 커밋을 생성해 브랜치를 push하고 Pull Request를 만든다.

## 반대 관점 검토

가장 큰 실패 가능성은 테스트 이벤트가 모델 자가보고라는 점과, 오래된 실패가 최신 성공을 덮는 오판이다. 이번 범위에서는 같은 명령의 최신 결과만 사용하고, 소스 변경이 있을 때만 성공 테스트를 의무화한다. 프로젝트별 테스트 명령 자동 탐지는 오탐과 임의 실행 위험이 커서 이번 변경에서 제외하며, 별도 실행 격리·검증 러너 작업으로 남긴다.
