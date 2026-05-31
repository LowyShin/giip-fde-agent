---
description: Codex 로컬 상태 점검 및 주기적 유지보수를 안전하게 실행합니다.
---

# Codex 유지보수 워크플로우

이 워크플로우는 keep-codex-fast 스킬을 사용하여 Codex의 로컬 상태를 주기적으로 점검하고 정리합니다.
자동 적용은 하지 않으며, 항상 사용자가 확인 후 수동으로 적용합니다.

출처 스킬: `.agent/skills/keep-codex-fast/SKILL.md`

---

## 실행 트리거

- 수동 요청: "Codex 유지보수 해줘", "codex maintenance", "keep-codex-fast"
- 주기적 알림: 주간 또는 격주 (Codex를 많이 사용하는 경우 주간 권장)

---

## 단계

### 1. 상태 보고 (항상 먼저)

```
Use $keep-codex-fast to inspect my Codex local state and recommend a safe maintenance plan.
```

점검 항목 요약:
- 활성 세션 크기
- 아카이브 세션 크기
- 확장 경로 후보
- 오래된 세션 후보
- 워크트리 후보
- 로그 크기
- 상위 Node/dev 프로세스

**⛔ 이 단계에서는 어떤 파일도 변경하지 않습니다.**

---

### 2. 핸드오프 대상 확인

상태 보고 결과를 바탕으로:
- 계속 이어갈 레포/세션 → 핸드오프 문서 작성 필요
- 더 이상 필요 없는 레포/세션 → 핸드오프 없이 아카이브 가능
- 활성 작업 중인 레포/세션 → 유지

핸드오프 문서 생성 (`SKILL.md` 2단계 프롬프트 참조)

---

### 3. 사용자 확인

유지보수 적용 전 사용자에게 확인:

```
점검 결과를 확인했습니다.
다음 항목에 대해 핸드오프 문서가 존재하거나 필요 없음을 확인해 주세요:
- [목록]

준비가 되면 안전 적용을 시작할 수 있습니다.
Codex가 실행 중이라면 먼저 닫아 주세요.
```

**⛔ 사용자 확인 없이는 절대로 적용하지 않습니다.**

---

### 4. 안전 적용 (사용자 승인 후)

```
Use $keep-codex-fast to apply safe Codex maintenance.

Before changing anything, confirm that important active repo chats have handoff docs
or do not need them.

Then back up first, archive instead of deleting, move stale worktrees, rotate large logs,
prune dead config references, and verify the result.

If Codex is currently running, do not mutate local state. Tell me to close Codex first.
```

---

### 5. 적용 결과 검증

적용 후:
- 변경된 항목 목록 확인
- 백업 위치 확인
- Codex 재시작 후 정상 작동 확인

---

## 스킬 갱신 점검

이 워크플로우를 실행할 때, 원본 레포의 업데이트를 확인합니다:

1. https://github.com/vibeforge1111/keep-codex-fast 최신 변경 사항 확인
2. 중요한 변경이 있으면 `.agent/skills/keep-codex-fast/SKILL.md` 업데이트
3. K-Layer에 변경 내용 기록 (`.agent/knowledge/notes/codex-maintenance.md`)

---

## 제약 사항

- 자동화는 보고(Inspect)에만 적용. 아카이브·이동·삭제·정규화는 자동 실행 금지
- 백업 폴더(`thread-metadata-repairs.jsonl`, `restore-thread-metadata.py`)는 개인 정보 포함 가능 — 공유 금지
- Codex 실행 중에는 로컬 상태 변경 금지
