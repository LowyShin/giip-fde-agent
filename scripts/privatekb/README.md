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

에이전트에는 AK 가 없고 SK 만 있습니다. 그래서 AK 전용 `giipKb` 함수가 아니라 **`giipApiSk3` 디스패처 → `pApiKb*bySk`** 를 씁니다.

```
POST https://giipfaw.azurewebsites.net/api/giipApiSk3
Content-Type: application/x-www-form-urlencoded

token=<sk>&text=KbCreate jsondata&jsondata={"csn":47,...}
  → 서버가 exec pApiKbCreatebySk '<sk>', N'{...}' 로 변환
```

`text` 에 `jsondata` 라는 낱말이 있으면 디스패처가 그 자리를 실제 JSON 으로 치환합니다. 이 낱말을 빼면 jsondata 가 마지막 인자로 자동 추가되는 다른 경로를 타므로 **명시적으로 넣으십시오.**

쓸 수 있는 `text` 값: `KbCreate` / `KbGet` / `KbList` / `KbUpdate` / `KbDelete` (각각 `pApiKb*bySk` 로 매핑).

> SP 이름이 `pApiKb*` 이고 giipfaw 함수가 `giipKb` 인 것은 **개명 후에도 그대로**입니다. `giipfaw/**/run.ps1` 이 성역이라 이름을 바꾸면 새 Function 을 만들어야 해서, 테이블만 바꾸고 API 이름은 유지했습니다. 그래서 이 클라이언트는 개명 전후 모두 동작합니다.

---

## 함정 5가지 (전부 실제로 겪은 것)

### 1. 응답에 SK 가 그대로 담겨 옵니다

`giipApiSk3` 가 `_debug_executedQuery` 에 `exec pApiKbCreatebySk '<sk>', ...` 를 넣어 돌려줍니다. `giipfaw/**/run.ps1` 은 성역이라 고칠 수 없습니다.

→ **클라이언트가 버려야 합니다.** 이 스크립트는 파싱 전에 텍스트에서 `debug` 블록을 잘라냅니다. 직접 구현한다면 응답을 **절대 그대로 로그에 남기지 마십시오.**

### 2. 응답이 JSON 으로 파싱되지 않는 경우가 있습니다 (가장 위험)

같은 `_debug_executedQuery` 가 **JSON 이스케이프를 잘못합니다.** 본문에 줄바꿈이 있으면 `\` + 실제 개행을 내보내 응답 전체가 깨집니다.

```
json.decoder.JSONDecodeError: Invalid \escape: line 10 column 189
```

**그런데 DB 쓰기는 성공한 상태입니다.** 클라이언트만 실패로 보고, 그대로 재시도하면 **중복 행이 쌓입니다.** k_layer 노트는 전부 여러 줄 마크다운이라 이 경로를 반드시 지나갑니다.

→ 파싱 **전에** `debug` 블록을 텍스트에서 제거하십시오(함정 1 과 같은 조치로 둘 다 해결됩니다).

→ 그래도 파싱이 실패하면 **재시도하기 전에 `list` 로 이미 들어갔는지 확인**하십시오.

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

## 검증 기록 (2026-10-20)

라이브 DB·라이브 API 로 실제 확인했습니다.

| 항목 | 결과 |
|---|---|
| `list` | OK |
| `put` 신규 (여러 줄 한글) | `created kbSn=...` |
| `put` 재실행 (같은 title) | `updated kbSn=` 같은 값 — **중복 생성 없음** |
| 본문 왕복 | 한글·줄바꿈 보존 확인 (`'검증 2차 — 갱신됨.\n\n줄바꿈 유지.\n'`) |
| `get` | OK |
| `sync-klayer` dry-run / 1차 / 2차 | 미실행 / `created` / `updated` (중복 없음) |
| 검증용 행 정리 | 5건 삭제, 총계 6,171 로 원상복귀 |

## 관련 정본

- 테이블: `giipdb/Tables/tPrivateKB.sql` · 개명 이력 `giipdb/Tables/RENAME_20261020_tKB_to_tPrivateKB.sql`
- SP: `giipdb/SP/pApiKb{Create,Get,List,Update,Delete}bySk.sql`
- 사양서: `giipdb/docs/30_Specs/SPEC_KLAYER_PRIVATEKB_SYNC.md`
- 서버측 동기화(PowerShell, DB 직접): `giipdb/mgmt/sync_klayer_to_privatekb.ps1`
- 설정 리더: `scripts/secwatch/secevt_lib.py`
- giip 이슈: https://giip.littleworld.net/ko/admin/giip-issues/3905
