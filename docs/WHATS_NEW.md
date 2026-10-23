# 🆕 What's New — giip FDE Agent

> 최근 **7일 이내** 갱신 내용만 이 페이지에 유지합니다. 그보다 오래된 항목은 [HISTORY.md](./HISTORY.md)로 이관됩니다.
> Only updates from the **last 7 days** are kept here; older entries move to [HISTORY.md](./HISTORY.md).
> 直近 **7日以内** の更新のみを掲載します。それより古い項目は [HISTORY.md](./HISTORY.md) に移動します。
>
> *(EN/JP 독자는 각 항목을 AI 에이전트에 번역 요청하세요. / Ask your AI assistant to translate entries.)*

**기준일 (as of): 2026-10-23**

---

## 2026-10-23
- **저장소 위생 정비 9차 — 최근 코멘트 사실 주장 7건 재확인 (CSN 70424)** — 직전 실행이 남긴 **원격 추적 ref(stale ref) 1건**을 정리했습니다(GitHub 측 ref 는 이미 삭제되어 있었고, `git fetch --prune` 로 로컬 추적 ref 만 제거). 최근 24시간 코멘트 4건(isn 1968·2855·2648·2349)의 검증 가능한 사실 주장 **7건이 모두 사실과 일치**해 giip 이슈 쓰기는 하지 않았습니다 — 특히 "`## Test Procedure` 헤딩 부재", "`c1048ae` 의 origin/main 반영", "`csn-projects.json` 의 70424 등록", "csnguard 로그의 70424 경고 0건"을 실제 파일·커밋·로그(803,470줄)로 직접 재확인했습니다. 충돌 PR·실패 CI·orphan stash 는 0건이었고, nested 저장소(`bkit` 서브모듈)의 PR #160 은 충돌 없이 CI pass 였습니다. → [작업 기록](../.agent/work_history/20261023_111700_csn70424_repo-maintenance.md)
- **저장소 위생 정비 8차 — 잔여 워크트리·샌드박스 회수 + 안전 모듈 dot-source 함정 (CSN 70424)** — 직전 실행이 남긴 검증용 워크트리 1건과 샌드박스 사본 4건을 **내용 동일성 확인 후** 회수했습니다(정본 도구 `cleanup-worktrees.ps1` 사용, 인접 저장소 22곳 무결성 재검증 통과). 또한 **안전 모듈(`worktree-safety.ps1`)을 다른 디렉터리에서 dot-source 하면 안전 함수가 조용히 미정의가 되어 링크 선검사 없이 삭제 진행되는 함정**을 확인해, fail-open 위험과 재발방지 절차를 k-layer(KNOW-003)로 남겼습니다. 충돌 PR·실패 CI·orphan stash 는 0건이었고, 최근 코멘트의 사실 주장 3건은 모두 일치해 giip 이슈 쓰기는 하지 않았습니다. → [작업 기록](../.agent/work_history/20261023_091900_csn70424_repo-maintenance.md)
- **giip 제품 변경 규칙 개정 반영 — "CSN 47 로만" 폐기, CSN 무관 PR 허용 (CSN 70424)** — 2026-10-15 사용자 직접 지시("전체 제품 레포에 CSN 무관 PR 허용")에 맞춰, 이 레포에 남아 있던 **폐기된** "CSN 47 로만" 규칙을 갱신했습니다. 규칙 1건(과거 본문은 삭제 없이 `[개정으로 폐지]` 표시로 보존) + 에이전트 진입점 7개 + 규칙 색인/참조 3개가 함께 갱신되어, 이제 이 레포의 에이전트가 적법한 제품 레포 수정·PR 요청을 거부가 아닌 **PR 경유로** 처리합니다. 유지되는 것: 작업 CSN 규칙 · PR 경유 · 전 CSN 공통 · giipdb SQL 규칙. → [규칙 51](../.agent/rules/51_giip_product_changes_csn47_only.md)
- **PUBLIC 레포의 고객 특정 식별자 일반화 (CSN 70424)** — 규칙 54에 따라 코드 주석·문서 예시에 남아 있던 실제 CSN 숫자·고객 프로젝트명·고객 PC 절대경로·lssn 번호를 플레이스홀더로 교체했습니다(러너·스케줄러·보안점검 스크립트의 **동작 로직은 무수정**). → [작업 기록](../.agent/work_history/20261023_081900_csn70424_repo-maintenance.md)
- **wiki 링크 생성기 결함 수정 — 죽은 링크 13건 (CSN 70424)** — wiki 동기화 스크립트가 만들던 링크가 파일시스템 루트 기준 절대경로 + 없는 `file://` 스킴이라 **전량이 죽어 있었고**, 표 치환 정규식도 실제 헤더(3열·CRLF)와 어긋나 **한 번도 페이지를 갱신하지 못한** 채 남아 있었습니다. 상대경로 링크 생성 + 정규식 정정 후 격리 샌드박스에서 checked=30 / broken=0 을 확인했고, 저장소의 wiki 링크도 broken=0 입니다. → [위키 동기화 스크립트](../docs/51-features/wiki-sync/wiki_sync.js)
- **스케줄러 러너 3건 결함 수정 — PS 5.1 파싱 불가 + 조상 판정 상수 false + upstream 없는 브랜치에서 기동 사망 (CSN 70424)** — 이 PC 에 `pwsh` 가 없는 Windows PowerShell 5.1 에서 러너 파일이 **파싱 에러 16건**으로 아예 뜨지 않던 문제(PS 7 전용 `??` 연산자), `git merge-base --is-ancestor` 의 **stdout 출력**을 검사해 항상 `false` 를 반환하던 문제(NOT-ON-MAIN 자동 복귀가 한 번도 동작하지 않던 근본 원인), 그리고 체크아웃이 upstream 없는 브랜치일 때 **러너가 기동하자마자 죽던** 문제(stderr 가 terminating → `NativeCommandError`)를 고쳤습니다. → [러너 스크립트](../scripts/gissue/run-gissue-claude.ps1)
- **NOT-ON-MAIN 회귀 테스트 실측 가동 — 거짓 통과 제거 (CSN 70424)** — 테스트가 실제로는 **검사 0건**인데 "ALL TESTS PASSED" 로 보고되던 구조를 고쳤습니다(러너에 함수만 적재하는 진입점 추가 · 픽스처가 "원격 브랜치 삭제" 시나리오를 재현하도록 수정 · 함수 미적재/검사 0건 가드 추가). **12 checks, 0 failures** 를 실측 확인했고, 결함을 되살린 사본으로 음성 검증까지 했습니다(C1·C3·D2 3건 실패 확인). → [회귀 테스트](../scripts/gissue/tests/test-selfpull-not-on-main.ps1)
- **슬랙 봇 명령 문서의 죽은 출처 교정 + `giip ...` 명령군 문서화 (CSN 70424)** — `COMMANDS.md` 가 "소스의 진실은 `index.js`" 라고 적었으나 실제로는 `handlers.js` 였습니다(`giip ...` 系는 `giip-commands.js`). 실제 코드와 대조해 미문서화돼 있던 `giip account/issue/project/channel/api` 명령 5개군을 문서화했습니다. → [COMMANDS.md](../slack-bot/COMMANDS.md)
- **저장소 위생 정비 7차 — What's New 롤링 창 정리 + 죽은 링크 교정 (CSN 70424)** — 기준일이 하루 지나면서 7일 창을 벗어난 `2026-10-15` 섹션 2건을 [HISTORY.md](./HISTORY.md) 로 이관했습니다. 저장소 전체 마크다운 상대링크를 스캔해 실제로 없는 파일을 가리키는 링크 1건(`ANTIGRAVITY_USAGE_GUIDE.md` → `GIIP_DEV_AGENT_FRAMEWORK.md`)을 실재하는 문서로 교체했습니다. 충돌 PR·실패 CI·orphan stash·재검증 대상 코멘트는 모두 0건이었고 giip 이슈 쓰기는 하지 않았습니다. → [작업 기록](../.agent/work_history/20261023_033541_csn70424_repo-maintenance.md)

## 2026-10-22
- **저장소 위생 정비 6차 — 머지 완료 후 잔존 브랜치 삭제 (CSN 70424)** — 직전 실행이 재생성해 둔 `fix/giip-3535-gitguardian-config` 와 `feat/is3905-privatekb-client` 원격 브랜치 2건과 로컬 브랜치 1건을, PR MERGED 상태와 blob 해시 동일성(내용 무손실)을 확인한 뒤 삭제했습니다. 충돌 PR·실패 CI·orphan stash 는 0건이었고 최근 코멘트(2시간 창)도 0건이라 이슈 쓰기는 하지 않았습니다. → [작업 기록](../.agent/work_history/20261022_233622_csn70424_repo-maintenance.md)
- **GitGuardian 제외 설정 근거 주석 보강 (CSN 70424)** — 설정 파일에 "SaaS 쪽에는 `version: 2` + `paths-ignored:` 형태의 변형도 실제로 쓰인다" 는 근거를 주석으로 남겨, 같은 설정을 뒤에서 다시 논쟁하지 않게 했습니다. 실제로는 문서에서 확인된 키(`secret.ignored_paths`)만 사용합니다. → [.gitguardian.yaml](../.gitguardian.yaml)
- **역할 문서 죽은 링크 교정 (CSN 70424)** — 소개문서 퍼블리셔 역할이 가리키던 `reference-doc-manager.md` 링크가 이 저장소에는 대상 파일이 없어 404 였던 것을 제거하고, "존재 검증 후 링크" 원칙 문구를 본문에 그대로 남겼습니다. → [역할 정의](../.agent/roles/intro_docs_publisher.md)
- **GitGuardian 비밀 스캔 제외 설정 정상화** — 문서화된 설정 파일명(`.gitguardian.yaml`)과 스키마(`secret.ignored_paths`)로 바꿔, `log-ship.js` 의 비밀 마스킹 정규식 패턴이 비밀로 오탐 탐지되지 않게 했습니다. 이전 `.gitguardian.yml` 은 파일명과 키가 모두 문서화되지 않은 형태라 제외가 적용된 적이 없었습니다. → [.gitguardian.yaml](../.gitguardian.yaml)
- **What's New 누락 항목 보완 (CSN 70424)** — 최근 7일 창(2026-10-15~2026-10-22)에 머지되었는데 이 페이지에 항목이 없던 변경을 모두 확인해 항목 30건을 추가했습니다(규칙 36 준수). → [작업 기록](../.agent/work_history/20261022_172849_csn70424_repo-maintenance.md)
- **완료 검증 게이트 순수 판정기 도입 (slack-bot)** — ANT 유산에서 쓸 만한 동작만 추려 태스크 완료 판정을 `slack-bot/task-verifier.js` 순수 함수로 분리하고 회귀 테스트를 함께 추가했습니다. → [계획서](./plans/2026-09-10-ant-verification-gate.md)
- **다른 봇 멘션 판정을 allowlist 로 변경 (slack-bot)** — 봇은 허용 사용자 DM·자기 앞 멘션·활성 태스크 스레드에만 응답하고, 봇-봇 대화는 `.env` 의 `OTHER_BOT_IDS` 에 상대 봇을 등록했을 때만 열립니다(기본값은 비활성). → [사양서](../slack-bot/README.md)
- **tPrivateKB 등록 클라이언트의 SK 호출 전환 (giipApiSk3 → giipApiSk4)** — SK 가 응답에 평문으로 담기거나 JSON 이스케이프가 깨지던 결함을 구조적으로 없애기 위해 `SqlParameter` 바인딩 경로로 전환했습니다. → [클라이언트 문서](../scripts/privatekb/README.md)
- **다국어 토큰 이중 예산 도입 (slack-bot)** — 선택 컨텍스트·체크포인트 재개·고정 prefix 는 유지하면서, 한글·일본어·한자 입력에도 최초·재개 프롬프트의 추정 토큰 상한을 적용합니다. → [비교 및 적용 결과](./03-analysis/pi-comparison-token-efficiency.analysis.md)
- **AI 필독 파일 + 범용성·정보 조회 순서 규칙 추가** — 루트 `AI_MUST_READ.md` 신설, 규칙 54(범용 에이전트: 특정 고객정보 금지)·55(tPrivateKB → 사양서 → 코드 조회 순서와 환류). → [AI_MUST_READ.md](../AI_MUST_READ.md)
- **저장소 위생 정비 (CSN 70424)** — 머지 완료가 확인된 원격 브랜치 26건과 로컬 브랜치 77건, 그리고 워크트리 2건을 내용 검증 후 정리했습니다. 워크트리 회수는 규칙 55 절차(링크(정션·심볼릭) 사전검사 → 항목별 삭제 → 인접 레포 HEAD 재검증)를 거쳐 진행했고, 되돌릴 수 없는 판단은 하지 않았습니다. → [작업 기록](../.agent/work_history/20261022_090900_csn70424_repo-maintenance.md)
- **저장소 위생 정비 2차 — 죽은 세션 잔해 구조 (CSN 70424)** — 직전 실행이 타임아웃으로 자동 stash 처리했던 잔해(작업 기록 1건 + What's New 롤링 갱신)를 소관 매칭·사실 검증 후 새 브랜치로 이관해 복구했습니다. stash 는 이관 성공 확인 후 정리했습니다. → [작업 기록](../.agent/work_history/20261022_103400_csn70424_repo-maintenance.md)
- **저장소 위생 정비 3~5차 — 브랜치·워크트리 구조 (CSN 70424)** — 내용 검증(cherry/patch-id, main 반영 여부) 후 로컬 브랜치 4건을 정리하고, 머지 완료·무활동·무결성 재검증 게이트를 통과한 워크트리 2건을 회수했습니다. 원격 브랜치 2건과 로컬 브랜치 1건은 되돌릴 수 없는 판단이 남아 사유를 기록하고 보류했습니다. 최근 코멘트(2시간 창)는 0건이었고 24시간 창의 1건도 사실 주장과 일치해 이슈 쓰기는 없었습니다. → [작업 기록](../.agent/work_history/20261022_165500_csn70424_repo-maintenance.md)

## 2026-10-21
- **bkit 서브모듈 매핑 복구 (.gitmodules)** — gitlink 만 있고 `.gitmodules` 가 커밋된 적이 없어 `git submodule status` 가 실패하던 문제를 복구했습니다. → [.gitmodules](../.gitmodules)

## 2026-10-20
- **tPrivateKB 등록 클라이언트 + AI용 문서 신설** — `scripts/privatekb/privatekb.py`(put/get/list/sync-klayer)와 AI 작업자용 `README.md` 를 추가했습니다. → [README](../scripts/privatekb/README.md)

## 2026-10-19
- **sec_monitor 파서 정착 + AI 지시서를 조직 cLang 언어로 생성** — 수집 입력 파싱(`sec_monitor`)을 정착시키고, monitor 가 다음 조치를 AI 지시서로 내보내도록 했습니다. 지시서는 조직의 cLang 언어로 생성되며 정본 `csn-lang-cache` 를 읽습니다. → [AI 온보딩 문서](./60-operations/secwatch-ai-onboarding.md)
- **유출 가능성 근거(resp_bytes·resp_series) 수집 + 공격자 실제 IP 전달** — 수집기가 응답 바이트 수·응답 계열을 근거로 담고, 공격자의 실제 IP 를 함께 전송합니다. → [수집기](../scripts/secwatch/secevt_collect.py)
- **scope-gate 여러 PR 합산 판정** — 하나의 이슈를 여러 PR 로 나누어 구현한 경우에도 합산 판정해 REVIEW↔READY 무한 되돌림을 근본 수정했습니다. → [PR 게이트 스윕](../scripts/gissue/pr-gate-sweep.ps1)
- **최근 코멘트 판정 최적화 — 코멘트 조회 98% 감소** — 목록 응답의 `last_comment_date` 로 판정을 끝내 이슈별 코멘트 조회를 1,202회에서 23회로 줄이고, 판정 로직을 공용 순수 함수로 분리했습니다. → [공용 판정 라이브러리](../scripts/gissue/gissue-audit-lib.ps1)
- **hung watchdog 로그 무출력 AND 조건 추가** — lock 경과 시간만으로 hung 을 판정하지 않고 로그 N분 무출력 조건을 함께 요구하도록 고쳤습니다. → [스케줄러 스크립트](../scripts/gissue/run-gissue-claude.ps1)
- **tKVS 읽기모델 증분 이관 cron 등록** — 컨테이너 기동 시 매분 `pApiKVSReadModelSyncbySk` 를 호출하는 cron 을 등록했습니다. → [실행 스크립트](../scripts/exec-kvs-readmodel-sync.sh)
- **reaper 의 node 고아 열거 확장** — claude.exe 가 먼저 죽어 node 손자만 남는 경우에도 회수 후보가 잡히도록 열거를 확장했습니다(기본값 드라이런). → [스케줄러 스크립트](../scripts/gissue/run-gissue-claude.ps1)

## 2026-10-18
- **Azure 로그 수집기(PG audit / App Service HTTP → generic) PoC** — Azure 로그를 범용 수집 경로로 모으는 PoC 와 온보딩 사양을 추가했습니다. → [수집 사양](./60-operations/secwatch-azure-onboarding-spec.md)
- **hung worker watchdog — lock 시작시각 기록 후 soft_budget×2 초과 시 강제 정리** — 워커가 멈춘 뒤엔 lock 에 기록된 시작 시각으로 경과를 계산해 강제 정리합니다. → [스케줄러 스크립트](../scripts/gissue/run-gissue-claude.ps1)

## 2026-10-17
- **cp932 이중전송 버그 수정 + 탐지규칙·초출(novel)·생존신호 추가** — → [secwatch README](../scripts/secwatch/README.md)
- **monitor 가 giipdb 저장 커맨드(kscOriginCmd)를 우선 사용** — → [모니터](../scripts/secwatch/monitor.py)
- **monitor 에이전트 생존 배지(하트비트) 표시** — 판정 0건이어도 에이전트가 살아 있음을 배지로 보여줍니다. → [모니터](../scripts/secwatch/monitor.py)
- **monitor.py 사용자 노출·소스 문자열 영어화** — → [모니터](../scripts/secwatch/monitor.py)
- **monitor 웹 UI 25건 페이징 + 24시간 기본 윈도우** — → [모니터](../scripts/secwatch/monitor.py)

## 2026-10-16
- **간이 해킹 감시 모니터(monitor.py) 신설 + 보안점검 입력 4분류(secevt_batch_audit/waf/cf/signal)** — → [secwatch README](../scripts/secwatch/README.md)
- **수집부·등록 스캐폴딩과 운영 문서 진입점 신설** — "새로 받아 secwatch 등록" 절차가 한 번에 완결되도록 만들었습니다. → [운영 문서](./60-operations/secwatch-agent.md)
- **에이전트를 Jev 게이트웨이 전송 구조로 개편 + consumer 판정기 추가** — 키가 없는 수집 PC 구조로 전환했습니다. → [secwatch README](../scripts/secwatch/README.md)
- **monitor 를 판정 결과(tKVSSecurityCheck) 조회로 전환 + collect 정리** — → [모니터](../scripts/secwatch/monitor.py)
- **monitor 웹 UI 영어화 + 다국어 준비(i18n 구조)** — → [모니터](../scripts/secwatch/monitor.py)
- **게이트웨이 HTTP 4xx/5xx 원인 노출 + alert/review 행에 라우팅 이유(why) 인라인 표시** — → [실행 스크립트](../scripts/secwatch/secevt_run.py)
- **Origin 다운로드 명령(복사) + 컬럼 Help 페이지 + 데이터 윈도우·보존 사양 문서화** — → [운영 문서](./60-operations/secwatch-agent.md)
- **docker 재생성 대응 — bootstrap 이 claude 를 dev 소유 네이티브로 + monitor 폴링 1분** — → [부트스트랩](../scripts/bootstrap-instance.sh)

---
*이 페이지는 [규칙 36 — What's New 유지](../.agent/rules/36_whats_new_maintenance.md)에 따라 갱신·정리됩니다.*
