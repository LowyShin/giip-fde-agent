# 🆕 What's New — giip FDE Agent

> 최근 **7일 이내** 갱신 내용만 이 페이지에 유지합니다. 그보다 오래된 항목은 [HISTORY.md](./HISTORY.md)로 이관됩니다.
> Only updates from the **last 7 days** are kept here; older entries move to [HISTORY.md](./HISTORY.md).
> 直近 **7日以内** の更新のみを掲載します。それより古い項目は [HISTORY.md](./HISTORY.md) に移動します。
>
> *(EN/JP 독자는 각 항목을 AI 에이전트에 번역 요청하세요. / Ask your AI assistant to translate entries.)*

**기준일 (as of): 2026-10-22**

---

## 2026-10-22
- **AI 필독 파일 + 범용성·정보 조회 순서 규칙 추가** — 루트 `AI_MUST_READ.md` 신설, 규칙 54(범용 에이전트: 특정 고객정보 금지)·55(tPrivateKB → 사양서 → 코드 조회 순서와 환류). → [AI_MUST_READ.md](../AI_MUST_READ.md)
- **저장소 위생 정비 (CSN 70424)** — 머지 완료가 확인된 원격 브랜치 26건과 로컬 브랜치 77건, 그리고 워크트리 2건을 내용 검증 후 정리했습니다. 워크트리 회수는 규칙 55 절차(링크(정션·심볼릭) 사전검사 → 항목별 삭제 → 인접 레포 HEAD 재검증)를 거쳐 진행했고, 되돌릴 수 없는 판단은 하지 않았습니다. → [작업 기록](../.agent/work_history/20261022_090900_csn70424_repo-maintenance.md)
- **저장소 위생 정비 2차 — 죽은 세션 잔해 구조 (CSN 70424)** — 직전 실행이 타임아웃으로 자동 stash 처리했던 잔해(작업 기록 1건 + What's New 롤링 갱신)를 소관 매칭·사실 검증 후 새 브랜치로 이관해 복구했습니다. stash 는 이관 성공 확인 후 정리했습니다. → [작업 기록](../.agent/work_history/20261022_103400_csn70424_repo-maintenance.md)
- **저장소 위생 정비 3~5차 — 브랜치·워크트리 구조 (CSN 70424)** — 내용 검증(cherry/patch-id, main 반영 여부) 후 로컬 브랜치 4건을 정리하고, 머지 완료·무활동·무결성 재검증 게이트를 통과한 워크트리 2건을 회수했습니다. 원격 브랜치 2건과 로컬 브랜치 1건은 되돌릴 수 없는 판단이 남아 사유를 기록하고 보류했습니다. 최근 코멘트(2시간 창)는 0건이었고 24시간 창의 1건도 사실 주장과 일치해 이슈 쓰기는 없었습니다. → [작업 기록](../.agent/work_history/20261022_165500_csn70424_repo-maintenance.md)

---
*이 페이지는 [규칙 36 — What's New 유지](../.agent/rules/36_whats_new_maintenance.md)에 따라 갱신·정리됩니다.*
