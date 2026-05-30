---
name: keep-codex-fast
description: |
  Codex의 로컬 상태를 점검하고 정리하여 성능을 유지하는 스킬입니다.
  오래된 채팅·워크트리·로그·데드 프로젝트 참조가 쌓여 Codex가 느려질 때 사용합니다.

  다음 상황에서 사용합니다:
  - Codex가 오래 사용한 후 무거워졌을 때
  - 오래된 채팅·터미널·로그·워크트리가 누적되었을 때
  - 정기 유지보수(주간/격주)가 필요할 때
  - 아카이브 전 핸드오프 문서가 필요할 때

  트리거 키워드: keep-codex-fast, codex 느림, codex 정리, codex 유지보수, codex maintenance,
    codex slow, codex cleanup, codex handoff, 코덱스 속도, 코덱스 정리
  
  출처: https://github.com/vibeforge1111/keep-codex-fast
  갱신 주기: 월 1회 이상 원본 레포 변경 사항 확인 권장 (auto-check 워크플로우: codex-maintenance.md)
---

# keep-codex-fast: Codex 성능 유지 스킬

여러 주간 채팅·터미널·로그·워크트리·프로젝트 이력이 쌓인 후 Codex가 무거워졌을 때,
로컬 상태를 안전하게 점검하고 정리합니다.

> **핵심 원칙**: 핸드오프 먼저. 아카이브로 이동(삭제 금지). 준비가 됐을 때만 적용.

---

## 세 가지 모드

| 모드 | 설명 |
|------|------|
| **Inspect** | 읽기 전용 보고. 파일 변경 없음 |
| **Maintain** | 안전 적용. 백업 후 오래된 세션 아카이브, 스테일 워크트리 이동, 로그 로테이션, 데드 설정 정리 |
| **Optional repair** | `--repair-thread-metadata-bloat` 옵션 사용 시에만 적용. 과도하게 비대해진 SQLite 스레드 제목/미리보기 메타데이터 수정 |

---

## 1단계: 상태 점검 (Inspect)

Codex에 다음 프롬프트를 입력하세요:

```
Use $keep-codex-fast to inspect my Codex local state and recommend a safe maintenance plan.
```

Codex가 먼저 현황을 보여줍니다. 그 후 핸드오프 대상, 유지 대상, 아카이브 대상을 결정합니다.

점검 항목:
- 활성 세션 크기 (active session size)
- 아카이브 세션 크기 (archived session size)
- 확장 경로 후보 (extended path candidates)
- 오래된 세션 후보 (old session candidates)
- 워크트리 후보 (worktree candidates)
- 로그 크기 (log size)
- 상위 Node/dev 프로세스 (top Node/dev processes)

---

## 2단계: 핸드오프 문서 생성 (Handoffs First)

아카이브 전, 계속 이어가고 싶은 레포/세션에 대해 핸드오프 문서를 작성합니다.

핸드오프 문서에 포함할 내용:
- 레포/경로 및 브랜치
- 현재 목표
- 완료된 작업
- 수정/조사한 파일
- 실행한 명령어/테스트
- 알려진 오류·경고·실패
- 미결 결정 사항
- 제약 조건, 사용자 선호도, 건드리지 말아야 할 영역
- 다음 3~7가지 구체적 단계

각 활성 레포 채팅에 아래 프롬프트를 복사하세요:

```
Create a comprehensive handoff document for this repo/session before I archive Codex history.

Include:
- repo/path and branch
- current goal
- what we already completed
- files touched or investigated
- commands/tests already run
- known errors, warnings, or failing checks
- open decisions
- constraints, user preferences, and do-not-touch areas
- the next 3-7 concrete steps

Also include a reactivation prompt I can paste into a fresh Codex chat so it can continue
from this handoff without relying on the old chat context.

Save the handoff in a sensible repo-local place like docs/codex-handoffs/YYYY-MM-DD-topic.md
unless this repo already has a better handoff location.
```

---

## 3단계: 안전 적용 (Safe Apply)

핸드오프 문서가 준비된 후, 다음 프롬프트를 사용합니다:

```
Use $keep-codex-fast to apply safe Codex maintenance.

Before changing anything, confirm that important active repo chats have handoff docs
or do not need them.

Then back up first, archive instead of deleting, move stale worktrees, rotate large logs,
prune dead config references, and verify the result.

If Codex is currently running, do not mutate local state. Tell me to close Codex first.
```

---

## 4단계: 스레드 메타데이터 비대화 수정 (선택)

일부 Codex 빌드에서 첫 번째 사용자 프롬프트가 스레드 제목과 목록 미리보기 모두에 전체 저장될 수 있습니다.
해당 필드가 수십만 자로 커지면 채팅 내비게이션이 느려질 수 있습니다.

점검 결과에서 비정상적으로 큰 제목/미리보기 메타데이터가 보고된 경우에만 실행:

```bash
python scripts/keep_codex_fast.py --apply --repair-thread-metadata-bloat
```

> ⚠️ 이 옵션은 실제 대화 내용(transcript)을 제거하지 않습니다. 표시용 제목/미리보기만 잘라냅니다.

---

## 정기 점검 알림 설정

재귀 유지보수는 자동 적용이 아닌 알림 방식으로 설정합니다:

```
Use $keep-codex-fast to create a recurring Codex maintenance reminder.

Schedule it weekly if I use Codex heavily, or biweekly if that seems safer.

The reminder should:
- run the keep-codex-fast report first
- never pass --apply or run mutating maintenance automatically
- never archive, move, prune, rotate, normalize, delete, or mutate local Codex state
- remind me to create comprehensive handoff docs and reactivation prompts for active repo
  chats before any manual apply
- summarize active session size, archived session size, extended path candidates,
  old session candidates, worktree candidates, log size, and top Node/dev processes
- tell me that manual apply should only happen after I confirm handoffs exist or are not
  needed and Codex is closed
```

---

## 스크립트 직접 사용 (고급)

대부분의 사용자는 위의 프롬프트로 충분합니다. 직접 스크립트를 실행하려면:

```bash
# 읽기 전용 보고 (기본값, 안전)
python scripts/keep_codex_fast.py

# 상세 정보 포함
python scripts/keep_codex_fast.py --details

# 백업만 수행 (이동/변경 없음)
python scripts/keep_codex_fast.py --backup-only

# 핵심 유지보수 적용
python scripts/keep_codex_fast.py --apply --archive-older-than-days 10 --worktree-older-than-days 7

# Codex 종료 대기 후 적용
python scripts/keep_codex_fast.py --apply --wait-for-codex-exit
```

> ⚠️ 백업 폴더에는 개인 Codex 메타데이터가 포함될 수 있습니다. 기기 내에 보관하고 공유하지 마세요.

---

## 정신 모델

- **채팅**은 실행을 위한 것
- **핸드오프 문서**는 기억을 위한 것
- **아카이브**는 이력을 위한 것
- **새 스레드**는 속도를 위한 것

---

## 스킬 갱신 방법

이 스킬은 원본 레포([vibeforge1111/keep-codex-fast](https://github.com/vibeforge1111/keep-codex-fast))의 변경 사항을 주기적으로 반영합니다.

갱신 워크플로우: `.agent/workflows/codex-maintenance.md` 참조

## ⚡ Optimization Integration

중요한 Codex 유지보수 작업은 `/native-trace`로 실행하고, 스킬 품질 개선이 필요하면 `/aioptimize`를 사용합니다.
