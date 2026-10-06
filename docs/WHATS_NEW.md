# 🆕 What's New — giip FDE Agent

> 최근 **7일 이내** 갱신 내용만 이 페이지에 유지합니다. 그보다 오래된 항목은 [HISTORY.md](./HISTORY.md)로 이관됩니다.
> Only updates from the **last 7 days** are kept here; older entries move to [HISTORY.md](./HISTORY.md).
> 直近 **7日以内** の更新のみを掲載します。それより古い項目は [HISTORY.md](./HISTORY.md) に移動します。
>
> *(EN/JP 독자는 각 항목을 AI 에이전트에 번역 요청하세요. / Ask your AI assistant to translate entries.)*

**기준일 (as of): 2026-10-06**

---

## 2026-10-06
- **dev NOPASSWD sudo 부팅 시 자동 부여** — `docker-bypass.sh` 의 root 구간(사용자 전환 직전)이 `setup-dev-sudo.sh` 를 자동 호출하도록 했습니다. 이제 수동 2단계 없이 부팅만으로 dev 가 sudo 를 쓸 수 있습니다(예: `/usr` 전역 npm `claude` 자동업데이트). 끄려면 `FDE_GRANT_SUDO=0`. → [운영 문서](./60-operations/docker-dev-user-and-sudo.md)

## 2026-10-04
- **dev 사용자 sudo 스크립트 + docker-bypass 이동** — `scripts/setup-dev-sudo.sh` 로 dev 에게 NOPASSWD sudo 를 부여하고, 루트의 `docker-bypass.sh` 를 `scripts/` 로 옮겼습니다. → [운영 문서](./60-operations/docker-dev-user-and-sudo.md)

---
*이 페이지는 [규칙 36 — What's New 유지](../.agent/rules/36_whats_new_maintenance.md)에 따라 갱신·정리됩니다.*
