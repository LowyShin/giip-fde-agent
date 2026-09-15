# 🆕 What's New — giip FDE Agent

> 최근 **7일 이내** 갱신 내용만 이 페이지에 유지합니다. 그보다 오래된 항목은 [HISTORY.md](./HISTORY.md)로 이관됩니다.
> Only updates from the **last 7 days** are kept here; older entries move to [HISTORY.md](./HISTORY.md).
> 直近 **7日以内** の更新のみを掲載します。それより古い項目は [HISTORY.md](./HISTORY.md) に移動します。
>
> *(EN/JP 독자는 각 항목을 AI 에이전트에 번역 요청하세요. / Ask your AI assistant to translate entries.)*

**기준일 (as of): 2026-09-15**

---

## 2026-09-15
- **K-Layer 프로젝트 범위 및 유효성 검사** — 다른 작업 공간·프로젝트·CSN의 Claim을 실행 컨텍스트에서 제외하고, 재확인 기한·원본 변경·컨텍스트 예산을 확인합니다. → [K-Layer 선택기](../slack-bot/k-layer.js)
- **태스크 완료 증거 구분** — 봇이 관측한 준비·실행·종료와 독립 검증을 구분하고 Slack 및 GIIP REVIEW에 검증 대기를 명시합니다. → [태스크 증거 기록](../slack-bot/task-evidence.js)

---

## 2026-09-10
- **Windows Hook Doctor 추가** — FDE 소유 훅의 Node 실행 가능성·대상 경로·BOM/CRLF를 진단하고 backup-once 복구 후 재검증하며, Windows CI에서 회귀를 차단합니다. → [구현 계획](./plans/2026-09-10-windows-hook-doctor.md)

---
*이 페이지는 [규칙 36 — What's New 유지](../.agent/rules/36_whats_new_maintenance.md)에 따라 갱신·정리됩니다.*
