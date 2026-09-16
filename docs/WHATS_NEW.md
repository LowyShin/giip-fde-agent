# 🆕 What's New — giip FDE Agent

> 최근 **7일 이내** 갱신 내용만 이 페이지에 유지합니다. 그보다 오래된 항목은 [HISTORY.md](./HISTORY.md)로 이관됩니다.
> Only updates from the **last 7 days** are kept here; older entries move to [HISTORY.md](./HISTORY.md).
> 直近 **7日以内** の更新のみを掲載します。それより古い項目は [HISTORY.md](./HISTORY.md) に移動します。
>
> *(EN/JP 독자는 각 항목을 AI 에이전트에 번역 요청하세요. / Ask your AI assistant to translate entries.)*

**기준일 (as of): 2026-09-16**

---

## 2026-09-16
- **작업 입력과 사용자 지시 보존** — Slack 태스크의 선택 컨텍스트 해시를 고정하고 변경 시 재분석을 요구하며, 개정·추가 지시 원문을 재개 프롬프트에도 보존합니다. 실제 종료 상태는 런타임 receipt에 기록합니다. → [실행 경로](../slack-bot/task-manager.js)

---

## 2026-09-10
- **Windows Hook Doctor 추가** — FDE 소유 훅의 Node 실행 가능성·대상 경로·BOM/CRLF를 진단하고 backup-once 복구 후 재검증하며, Windows CI에서 회귀를 차단합니다. → [구현 계획](./plans/2026-09-10-windows-hook-doctor.md)

---
*이 페이지는 [규칙 36 — What's New 유지](../.agent/rules/36_whats_new_maintenance.md)에 따라 갱신·정리됩니다.*
