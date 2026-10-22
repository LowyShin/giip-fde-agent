# tPrivateKB 등록 클라이언트 (AI 작업자용)

조직(csn)별 **비공개** 지식 베이스 `tPrivateKB` 에 지식을 등록·조회하는 클라이언트입니다. giip 3905.

> **이 문서를 읽는 AI 에게**: 아래 "먼저 알아야 할 것"과 "함정 5가지"를 읽기 전에 코드를 쓰지 마십시오. 전부 실제로 겪어서 적은 것이고, 모르면 **DB 에 중복 행을 쌓으면서 실패했다고 착각**하게 됩니다.

---

## 먼저 알아야 할 것 — tPrivateKB 와 /kb 는 다른 것입니다

이름이 둘 다 "KB" 라서 반복적으로 혼동됐고, 그래서 테이블 이름을 `tKB` → `tPrivateKB` 로 바꿨습니다(giip 3905).

| | **tPrivateKB** (이 스크립트가 다루는 것) | **/kb** (건드리지 마십시오) |
|---|---|---|
| 정체 | 조직별 **비공개** 지식 | 누구나 보는 **공개** 기술 아티클 |
| 저장 | giipdb 테이블 `dbo.tPrivateKB` | giipv3 코드 안의 파일 `src/lib/kb/articles/*.ts` |
| 화면 | `/{locale}/admin/privatekb` (관리자) | `/{locale}/kb` (공개) |
| 내용 | 장애 노하우, 설정, 분석 결과, k_layer 노트 | 마케팅용 기술 자료 |
| 이 스크립트로 | 등록·조회 가능 | **불가능** (DB 와 무관) |

`tPrivateKB` 는 **Graphify 지식그래프의 원천**이기도 합니다.

## 이 스크립트가 왜 생겼는가

여러 k_layer 노트가 이렇게 적어두고 있었습니다.

```
node scripts/gissue/tkb.js sync-klayer --csn 47 --dir .agent/k_layer/notes
node <lowyworkenv>/scripts/gissue/tkb.js sync-klayer --csn 70424 ...
```

그런데 **`tkb.js` 는 존재하지 않습니다**(`find / -name tkb.js` 0건). 두 번째 줄은 `<lowyworkenv>` 플레이스홀더가 치환되지 않은 채 커밋된 것이고, 그 디렉터리도 이 PC 에 없습니다.

2026-10-20 수집기 세션이 이 문구를 읽고 "이 PC 의 lowyworkenv 경로를 알려주면 그 파일을 읽겠다"며 멈췄습니다. 문서가 없는 도구를 가리키고 있으면 다음 세션도 똑같이 멈춥니다. **그 문서가 가리키던 도구를 실제로 만든 것이 이 스크립트입니다.**

---

## 사용법

```bash
# 등록 또는 갱신 (title 기준 upsert — 여러 번 돌려도 중복이 쌓이지 않습니다)
python3 scripts/privatekb/privatekb.py put --csn 47 \
    --title "KNOW-123 제목" --content-file note.md --tags "k-layer,ai-memory"

# 단건 조회
python3 scripts/privatekb/privatekb.py get --csn 47 --kbsn 1234

# 목록
python3 scripts/privatekb/privatekb.py list --csn 47 --ref-type KNOWLEDGE --limit 20
python3 scripts/privatekb/privatekb.py list --csn 47 --search 키워드

# k_layer 노트 폴더 전체 동기화 (노트들이 존재한다고 적어두었던 바로 그 동작)
python3 scripts/privatekb/privatekb.py sync-klayer --csn 47 --dir .agent/k_layer/notes --dry-run
python3 scripts/privatekb/privatekb.py sync-klayer --csn 47 --dir .agent/k_layer/notes
```

파이썬 표준 라이브러리만 씁니다(설치 불필요). 리눅스·윈도우 공용입니다.

### 인증 — 사람에게 묻지 마십시오

`sk` 는 env `GIIP_SK` → 상위 폴더의 `giipAgent.cfg|.cnf` 의 `sk=` 순서로 **자동 탐색**합니다. `scripts/secwatch/secevt_lib.py` 의 `read_cfg_value` 를 재사용합니다.

**sk 를 사용자에게 되묻지 않습니다**(모든 PC·모든 세션 공통 규칙). 어떤 출력·로그·코멘트에도 남기지 않습니다.

---

## 호출 경로 (실측 확인, 추측 아님)

에이전트에는 AK 가 없고 SK 만 있습니다. 그래서 AK 전용 `giipKb` 함수가 아니라 **`giipApiSk4` → `pApiKb*bySk`** 를 씁니다.

```
POST https://giipfaw.azurewebsites.net/api/giipApiSk4
Content-Type: application/x-www-form-urlencoded

token=<sk>&text=KbCreate jsondata&jsondata={"jsondata":"<전체 JSON 문자열>"}
  → 서버가 EXEC pApiKbCreatebySk @p0, @p1 로 파라미터 바인딩 실행
```

`text` 는 `"<SPName> <토큰1> <토큰2> ..."` 규약이고, 각 토큰은 jsondata 객체의 **키 이름**에서 값을 찾아 그 위치의 파라미터로 바인딩됩니다. 이 SP 는 `@jsondata` 로 JSON 전체를 받으므로, 전체 JSON 을 문자열로 만들어 `{"jsondata": "..."}` 로 한 겹 감쌉니다.

### `giipApiSk3` 를 쓰지 마십시오 (성역 우회의 실제 적용 사례)

`giipApiSk3` 로 먼저 구현했다가 두 가지 결함을 실측했습니다. `giipfaw/**/run.ps1` 은 성역이라 고칠 수 없어서, `.agent/rules/PROTOCOL_SANCTUARY_BYPASS.md` 규약대로 **이미 만들어져 있던 새 함수(`giipApiSk4`)로 호출부를 전환**했습니다. 새 함수를 또 만들 필요는 없었습니다 — `giipApiSk4` 자체가 같은 이유(giip #1215)로 만들어진 우회 함수입니다.

| | `giipApiSk3` | `giipApiSk4` |
|---|---|---|
| 응답에 SK | **평문으로 들어옴** (`_debug_executedQuery`) | 없음 |
| 본문에 줄바꿈이 있을 때 | **응답 전체가 JSON 파싱 불가** (`Invalid \escape`). 그런데 DB 쓰기는 성공한 상태라 재시도하면 **중복이 쌓인다** | 정상 |
| 파라미터 전달 | 문자열 이어붙이기 | `SqlParameter` 진짜 바인딩 |

`giipApiSk4` 는 문자열을 이어붙이지 않아 두 결함이 구조적으로 없습니다. debug 필드에도 `EXEC pApiKbCreatebySk @p0, @p1` 처럼 **값이 아닌 플레이스홀더만** 담깁니다.

쓸 수 있는 `text` 값: `KbCreate` / `KbGet` / `KbList` / `KbUpdate` / `KbDelete` (각각 `pApiKb*bySk` 로 매핑).

> SP 이름이 `pApiKb*` 이고 giipfaw 함수가 `giipKb` 인 것은 **개명 후에도 그대로**입니다. `giipfaw/**/run.ps1` 이 성역이라 이름을 바꾸면 새 Function 을 만들어야 해서, 테이블만 바꾸고 API 이름은 유지했습니다. 그래서 이 클라이언트는 개명 전후 모두 동작합니다.

---

## 함정 5가지 (전부 실제로 겪은 것)

### 1·2. `giipApiSk3` 의 두 결함 — **`giipApiSk4` 로 전환해 해소됨**

위 "호출 경로" 의 표를 보십시오. 이 스크립트는 `giipApiSk4` 를 쓰므로 둘 다 해당되지 않습니다. 다만 **다른 SK 경로를 직접 구현할 때는 같은 함정을 만나게 되므로** 기록을 남겨둡니다.

구 경로로 되돌릴 일이 생기거나 서버가 debug 내용을 바꿔도 영향받지 않도록, 이 스크립트는 여전히 파싱 **전에** `debug` 블록을 텍스트에서 잘라냅니다(방어선). 어떤 경우에도 응답을 그대로 로그에 남기지 마십시오.

### 3. `pApiKbCreatebySk` 에는 중복 방지가 없습니다

AK 버전(`pApiKbCreatebyAk`)은 `extRefId` 로 여러 번 돌려도 안전한 upsert 를 하지만, **SK 버전은 그냥 INSERT** 입니다.

→ 이 스크립트의 `put` / `sync-klayer` 는 **title 로 먼저 찾아보고 있으면 update** 합니다(`giipdb/mgmt/sync_klayer_to_privatekb.ps1` 과 같은 방식). 직접 구현한다면 같은 처리를 하십시오.

### 4. `giipAgent.cfg|.cnf` 의 값에 따옴표가 들어 있습니다

`sk="..."` 형태입니다. 직접 파싱하면 따옴표까지 토큰에 들어가 `401 Invalid or disabled Secret Key` 가 납니다.

→ `secevt_lib.read_cfg_value` 를 쓰십시오. 거기에 따옴표 제거가 들어 있습니다.

### 5. title 의 `[` 가 검색을 깨뜨립니다

`pApiKbListbySk` 가 `LIKE '%' + @searchKeyword + '%'` 로 찾는데, 티에스큐엘 LIKE 에서 `[` 는 **문자 클래스 시작**입니다. `[giip3905] probe` 를 그대로 넘기면 아무것도 매칭되지 않습니다.

→ 이미 있는 항목을 못 찾고 새로 만들어 **중복이 쌓입니다.** `[` 를 `[[]` 로 escape 하십시오(이 스크립트가 그렇게 합니다).

---

## 검증 기록

라이브 DB·라이브 API 로 실제 확인했습니다.

**2026-10-20 (giipApiSk3 경로)**

| 항목 | 결과 |
|---|---|
| `list` / `get` | OK |
| `put` 신규 (여러 줄 한글) | `created` |
| `put` 재실행 (같은 title) | `updated` 같은 kbSn — 중복 없음 |
| 본문 왕복 | 한글·줄바꿈 보존 |
| `sync-klayer` dry-run / 1차 / 2차 | 미실행 / `created` / `updated` |
| 검증용 행 정리 | 5건 삭제, 총계 원상복귀 |

**2026-10-22 (giipApiSk4 로 전환 후 재검증)**

| 항목 | 결과 |
|---|---|
| JSON 파싱 (여러 줄 한글 본문) | **OK** — giipApiSk3 는 이 지점에서 깨졌다 |
| 응답에 SK 포함 | **없음** — giipApiSk3 는 흘렸다 |
| debug 필드 | `EXEC pApiKbCreatebySk @p0, @p1` (플레이스홀더만) |
| 줄바꿈 DB 보존 | OK |
| `put` 신규 → 재실행 | `created` → `updated` 같은 kbSn (중복 없음) |
| 검증용 행 정리 | 2건 삭제, 잔여 0 확인 |

## 관련 정본

- 테이블: `giipdb/Tables/tPrivateKB.sql` · 개명 이력 `giipdb/Tables/RENAME_20261020_tKB_to_tPrivateKB.sql`
- SP: `giipdb/SP/pApiKb{Create,Get,List,Update,Delete}bySk.sql`
- 사양서: `giipdb/docs/30_Specs/SPEC_KLAYER_PRIVATEKB_SYNC.md`
- 서버측 동기화(PowerShell, DB 직접): `giipdb/mgmt/sync_klayer_to_privatekb.ps1`
- 설정 리더: `scripts/secwatch/secevt_lib.py`
- giip 이슈: https://giip.littleworld.net/ko/admin/giip-issues/3905
