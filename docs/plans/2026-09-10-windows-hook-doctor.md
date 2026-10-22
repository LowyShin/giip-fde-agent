# Windows Hook Doctor 구현 계획

> **For Claude:** REQUIRED SUB-SKILL: Use test-driven-development to implement this plan task by task.

**Goal:** Windows에서 FDE 소유 훅의 인코딩·경로·실행 가능성을 자동 진단하고, 안전한 항목만 백업 후 복구한다.

**Architecture:** `.agent/lib/windows-hook-doctor.js`가 순수 진단·복구 로직을 제공하고, `.agent/scripts/windows-hook-doctor.js`가 CLI 종료 코드와 출력을 담당한다. SessionStart는 조용한 복구 모드로 호출하며, `PreToolUse` 훅 결함은 차단 상태와 종료 코드 2로, 나머지 훅 결함은 경고로 처리한다. 외부 플러그인과 사용자 설정은 범위에서 제외한다.

**Tech Stack:** Node.js CommonJS, 내장 `fs/path/child_process`, GitHub Actions Windows runner

---

### Task 1: 실패 테스트로 안전 경계 고정

**Files:**
- Create: `.agent/tests/windows-hook-doctor.test.js`

1. 비-Windows 무변경, BOM/CRLF 탐지, backup-once, 루트 이탈 차단, 중요 훅 fail-closed 테스트를 작성한다.
2. 테스트를 실행해 구현 모듈 부재로 실패하는지 확인한다.

### Task 2: 최소 진단·복구 코어 구현

**Files:**
- Create: `.agent/lib/windows-hook-doctor.js`

1. FDE 훅 매니페스트를 읽고 command 훅을 열거한다.
2. Node 런타임을 실제 실행으로 확인하고, 참조 대상이 agent root 안에 존재하는지 검증한다.
3. BOM/CRLF만 `.agent/runtime/hook-backups/`의 backup-once 방식으로 복구하고 다시 검증한다.
4. 절대 경로와 명령 원문을 제외한 로컬 상태 로그를 최대 50건으로 유지한다.
5. 단위 테스트를 통과시킨다.

### Task 3: CLI와 SessionStart 연결

**Files:**
- Create: `.agent/scripts/windows-hook-doctor.js`
- Modify: `.agent/hooks/hooks.json`

1. `--repair`, `--quiet`, `--json` 옵션과 종료 코드 0/2를 구현한다.
2. SessionStart 첫 훅으로 quiet repair를 연결한다.
3. Linux에서는 명시적 skip, Windows 중요 훅 오류에서는 종료 코드 2인지 검증한다.

### Task 4: Windows 회귀 테스트와 문서화

**Files:**
- Create: `.github/workflows/windows-hook-doctor.yml`
- Modify: `.agent/knowledge/notes/claude-code-hooks.md`
- Modify: `docs/WHATS_NEW.md`

1. `windows-latest`에서 단위 테스트와 doctor CLI를 실행한다.
2. 운영 범위와 fail-open/fail-closed 경계를 문서화한다.
3. 기존 Node 회귀 테스트와 새 테스트를 함께 실행한다.
