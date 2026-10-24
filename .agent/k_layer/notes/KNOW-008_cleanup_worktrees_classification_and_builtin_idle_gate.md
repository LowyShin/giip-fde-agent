# KNOW-008: 정본 정리 도구의 판정 Status 5종 — "24h 가드"는 옵션으로 내장하고, 독립 clone 은 고아가 아니다

- 작업 CSN: 70424
- 관련 파일: 판정 엔진 `scripts/gissue/worktree-safety.ps1` / 진입점 `scripts/gissue/cleanup-worktrees.ps1`
  (이 저장소에도 동일 사본 있음 — `cleanup-worktrees.ps1` 가 `worktree-safety.ps1` 을 dot-source),
  `.agent/rules/47_auto_cleanup_safety_requirements.md`
- 근거: 2026-10-24 CSN 70424 저장소 정비 세션 실측 (work_history 20261024_171600)
- 상호링크: [KNOW-003](KNOW-003_worktree_safety_dotsource_pitfall.md)(fail-open 삭제 위험 축),
  [KNOW-006](KNOW-006_repo_gates_not_wired_to_ci.md)(판정 로직을 진입점에 내장하는 축)

## 1. 현상

자동 정리 세션이 반복해서 부딪힌 질문은 두 가지였다.

1. "이 잔여 디렉터리를 **지금** 지워도 되는가" — 24h idle 가드를 사람이 매번 손으로 계산하면
   세션마다 판정 편차가 생기고, 게이트를 통과한 항목은 다음 세션에서 또 미룬다.
2. "독립 clone 을 지워도 되는가" — `.git` 이 있는 디렉터리라 등록 워크트리가 아닌 "고아"처럼
   보이지만, 실제로는 **정본 저장소의 clone**이라 의미가 다르다.

## 2. 원인 / 판정 클래스

정본 도구 `cleanup-worktrees.ps1` 가 리포트하는 `Status` 는 **5종**이다.

| Status | 의미 | 자동 삭제 대상? |
|---|---|---|
| `Registered` | `git worktree list` 에 등록된 정상 워크트리 | **아니오** (절대 건드리지 않음) |
| `OrphanNoAdmin` | `.git` 은 있으나 워크트리 관리 정보가 없음 | 조건부 |
| `OrphanUnlisted` | `.git` 은 있으나 `git worktree list` 에 없음 | 조건부 |
| `StandaloneClone` | 저장소를 통째로 clone 한 독립 사본 | **아니오** (고아 아님) |
| `Unparsable` | `.git` 파일을 읽었으나 `gitdir:` 형식이 아님 | **아니오** (사람 확인) |

판정 자체는 진입점이 아니라 **판정 엔진 `scripts/gissue/worktree-safety.ps1` 의
`Get-GissueOrphanWorktree`** 가 내고, 진입점 `cleanup-worktrees.ps1` 는 그 결과를
`$_.Status -like 'Orphan*'` 로 한 번 더 거른다. 따라서 `StandaloneClone` · `Unparsable` ·
`Registered` 는 **자동 삭제 경로에 들어가지 않는다.**

즉 **"`.git` 이 있는데 등록 목록에 없다 = 삭제 대상" 이라는 통념은 틀렸다.**
독립 clone 은 삭제 대상이 아니며, idle 시간이 아무리 길어도 자동 삭제되지 않는다.

## 3. 조치 — 게이트를 스크립트에 내장한다

1. **24h 가드를 옵션으로 내장** — `-MinIdleMinutes 1440` 을 주면 rule 47 의 24h 게이트가
   스크립트 판정으로 그대로 적용된다. 사람이 mtime 을 손으로 계산할 필요가 없어지고,
   세션 간 판정 편차가 사라진다. 판정 결과를 그대로 로그로 남기면 추적이 된다.
2. **보존 대상은 명시적으로 지정** — 다른 저장소의 정식 등록 워크트리는 `-Protect`(또는
   `-ProtectFile`) 로 지정해 스캔 대상에서 제외한다. "자동 삭제되지 않는다"는 분류에 기대지 말고
   **보류를 명시적으로 표현**하는 편이 안전하다.
3. **삭제는 정본 도구로만** — `Remove-Item -Recurse` 직접 호출은 대량삭제 훅에 차단된다.
   게이트(심볼릭 링크 사전검사 · 항목별 삭제 · 인접 저장소 무결성 재검증 · 과정 로그)를
   모두 갖춘 정본 도구 경로로만 삭제한다.

## 4. 재발 방지

- **idle 시간을 "직접 계산"하지 않는다** — 도구에 최소 idle 값을 넘겨 판정한다.
- **".git` 이 있다 = 고아" 로 단정하지 않는다** — `StandaloneClone` 은 자동 삭제 대상이 아니다.
  독립 clone 은 남겨 두거나 사람이 판단한다.
- **삭제 실행 후에는 존재 여부를 재확인한다** — 도구 로그의 "삭제됨" 메시지에 의존하지 말고
  경로 존재 여부(`EXISTS_AFTER=False`)를 별도로 확인한다.

## 5. 결과 저장처 / 소비처

- 수정 파일: 도구 코드 변경 없음(정찰 결과만 기록 — 이 저장소에는 `scripts/gissue/worktree-safety.ps1` ·
  `scripts/gissue/cleanup-worktrees.ps1` 사본이 있으나 이번 세션에 코드는 고치지 않았다)
- 작업 기록: `.agent/work_history/20261024_171600_csn70424_repo-maintenance.md`,
  `.agent/work_history/20261024_185100_csn70424_repo-maintenance.md`
- 소비처: 자동 정리 세션(잔여 디렉터리 판정), 규칙 47 의 "수동 판정 편차" 논의를 대체하는 근거

## 6. 관련 규칙

47 · 48 · 55 · 35 · 36 · 61(k-layer 은 커밋으로 성립)
