# 🆕 What's New — giip FDE Agent

> 최근 **7일 이내** 갱신 내용만 이 페이지에 유지합니다. 그보다 오래된 항목은 [HISTORY.md](./HISTORY.md)로 이관됩니다.
> Only updates from the **last 7 days** are kept here; older entries move to [HISTORY.md](./HISTORY.md).
> 直近 **7日以内** の更新のみを掲載します。それより古い項目は [HISTORY.md](./HISTORY.md) に移動します。
>
> *(EN/JP 독자는 각 항목을 AI 에이전트에 번역 요청하세요. / Ask your AI assistant to translate entries.)*

**기준일 (as of): 2026-07-06**

---

## 2026-07-06
- **What's New 롤링 페이지 신설** — README 최상단에 링크. 최근 7일 갱신을 이 페이지에서 확인, 유지 규칙은 [`36_whats_new_maintenance`](../.agent/rules/36_whats_new_maintenance.md).
- **paperthin 스킬 14종 이식 + 외부 레포 목록 등록** — [LilMGenius/paperthin](https://github.com/LilMGenius/paperthin)(MIT)의 "clean & true" 저수준 스킬(re0·shower·factchk·ssotchk·hate 등)을 `.agent/skills/`에 이식하고, `links.md` 및 `ai-repositories-index`(KR/EN/JP)에 등록. → [`.agent/skills/PAPERTHIN_NOTICE.md`](../.agent/skills/PAPERTHIN_NOTICE.md)
- **keep-codex-fast 외부 레포 목록 등록** — [vibeforge1111/keep-codex-fast](https://github.com/vibeforge1111/keep-codex-fast)(MIT, Codex 성능 유지 스킬)를 `links.md`·`ai-repositories-index`에 등록. 스킬은 기존 이식 완료(`codex-maintenance` 워크플로 포함).

## 2026-07-03
- **README를 FDE Agent 정체성 중심으로 재구성** — FDE 정의를 Palantir "Forward Deployed Engineer"로 정정하고 EN/JP 동기화.
- **QUICK_START 개선** — Claude 최우선 추천 + Slack 봇 연결 가이드 추가.
- **범용 워크플로 규칙 3종 추가** — `33` repo-URL 보고 / `34` edit-approval / `35` commit-push-per-task. → [`.agent/rules/`](../.agent/rules/)
- **slack-bot 다수 개선** — `taskmerge`(미완료 중복 태스크 통합), 처리 타임아웃 5→20분, 태스크번호 포함 수정요청 라우팅 버그 수정, `wfrun`/`wflist` 워크플로 실행·목록 명령 추가, 결과 URL 유실 버그 수정.

## 2026-07-01
- **k-layer.js 키워드 업데이트 및 `BASE_DIR` 처리 개선.**

---
*이 페이지는 [규칙 36 — What's New 유지](../.agent/rules/36_whats_new_maintenance.md)에 따라 갱신·정리됩니다.*
