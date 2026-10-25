# KNOW-011: 마크다운 상대링크의 기준은 "링크가 있는 파일의 위치"다 — `docs/` 아래의 `../.agent/...` 패턴을 `.agent/work_history/` 아래에 복사하면 깨진다

- 작업 CSN: 70424
- 관련 파일: `.agent/work_history/20261025_214700_csn70424_repo-maintenance-post.md`(깨진 링크가 있던 파일) ·
  `docs/CAPABILITIES.md`(같은 `../.agent/...` 패턴이 **올바른** 파일) · `docs/WHATS_NEW.md`
- 근거: 2026-10-25 CSN 70424 저장소 정비 50차 세션 실측 (work_history `20261025_222700_csn70424_repo-maintenance.md`)
- 상호링크: [KNOW-010](KNOW-010_worktree_missing_accounts_file_breaks_gissue_scripts.md)(워크트리에서 계정 파일 부재 축),
  [KNOW-009](KNOW-009_cleanup_onlypath_separator_silent_zero.md)(경로 표기 정규화 부재 축)

## 1. 현상

49차 사후 기록(`20261025_214700_csn70424_repo-maintenance-post.md`)에 다음 링크가 남아 있었다.

```markdown
(백슬래시 경로 규칙 — [KNOW-009](../.agent/k_layer/notes/KNOW-009_cleanup_onlypath_separator_silent_zero.md))
```

이 파일은 `.agent/work_history/` 아래에 있다. 따라서 `../` 는 `.agent/` 을 가리키고, 링크가 가리키는 것은
`.agent/.agent/k_layer/notes/...` 이다 — **존재하지 않는 경로**.

```
$ node -e "console.log(require('path').resolve('.agent/work_history','../.agent/k_layer/notes/KNOW-009_cleanup_onlypath_separator_silent_zero.md'))"
C:\Users\lowys\Downloads\projects\giip-fde-agent\.agent\.agent\k_layer\notes\KNOW-009_cleanup_onlypath_separator_silent_zero.md   ← 없음

$ node -e "console.log(require('path').resolve('.agent/work_history','../k_layer/notes/KNOW-009_cleanup_onlypath_separator_silent_zero.md'))"
C:\Users\lowys\Downloads\projects\giip-fde-agent\.agent\k_layer\notes\KNOW-009_cleanup_onlypath_separator_silent_zero.md   ← 실존
```

## 2. 원인

- `../.agent/...` 패턴은 **링크가 있는 파일이 저장소 루트 바로 아래(`docs/` 등)일 때만** 성립한다.
  `docs/CAPABILITIES.md` 의 `../.agent/skills/k-layer/SKILL.md` 는 `docs/` → `..` = 저장소 루트 → `.agent/...` 로 **정상**이다.
- `.agent/work_history/` 처럼 **저장소 루트보다 한 단계 깊은** 디렉터리에서는 `..` 가 `.agent/` 을 가리키므로
  `../.agent/...` 는 `.agent/.agent/...` 로 중복된다.
- 즉 링크가 **하나 더 깊으면** 경로 앞에 `.agent/` 이 하나 더 늘어간다. `../k_layer/...` 가 정답.
- 반대로 `.agent/work_history/` 에서 저장소 루트(`docs/`)를 가리켜야 하면 `../../docs/...` 여야 한다
  (`.agent/work_history/20261023_033541_csn70424_repo-maintenance.md` 가 이미 `../../docs/...` 로 쓰고 있음).

## 3. 이번 세션의 조치

- 49차 사후 기록의 링크를 `../.agent/k_layer/notes/...` → **`../k_layer/notes/...`** 로 교정(파일에 링크 1건).
- 저장소 전체 상대링크를 스캔해 **같은 계열의 실결함 1건만** 존재함을 확인했다.
  (실측 결과: 미존재 링크 34건 중 템플릿 스캐폴딩 24건 + 백틱 안 코드 예시 텍스트 9건 + **본 건 1건**)

## 4. 재발 방지

- 새 문서에 상대링크를 쓰기 전에 **"링크가 있는 파일의 디렉터리"**를 기준으로 `../` 횟수를 정한다.
  저장소 루트 기준 경로(`docs/xxx.md`)를 그대로 복사하지 않는다.
- 이전 회차 산출물(`work_history/*.md`, `docs/WHATS_NEW.md`)을 수정할 때도 **같은 기준**을 적용한다.
  특히 `docs/WHATS_NEW.md` 는 `docs/` 아래라 `../.agent/...` 가 정상이지만,
  `work_history` 안의 같은 문자열은 `../k_layer/...` 여야 한다 — **같은 문자열이 문서 위치에 따라 다르게 해석된다.**
- 링크가 깨져도 GitHub 렌더러는 조용히 텍스트로만 보여준다(빌드·CI 실패로 드러나지 않는다).
  **스캔으로만 발견된다.**

## 5. 결과 저장처 / 소비처

- 수정 파일:
  - `.agent/k_layer/notes/KNOW-011_markdown_relative_link_base_is_the_linked_file_location.md`(이 파일 — 신규)
  - `.agent/k_layer/notes/INDEX.md`(색인 1행 추가)
  - `.agent/work_history/20261025_214700_csn70424_repo-maintenance-post.md`(링크 경로 교정 1건)
- 작업 기록: `.agent/work_history/20261025_222700_csn70424_repo-maintenance.md`
- 소비처: 다음 회차의 저장소 정비 세션(상대링크 스캔 판정 기준) · Markdown 링크를 추가·수정하는 모든 세션

## 6. 관련 규칙

22(문서 표준) · 29(도구 사용·검증) · 33(산출물 위생) · 36(What's New 유지) ·
42(실행 근거로만 완료 판정) · 61(k-layer 은 커밋으로 성립) · 72(k-layer·tKB 경로)
