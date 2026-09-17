# AI 행위자 계정 — 운영 절차서 (giip #2613)

> 정본 사양서: `giipprj/giipdb/docs/30_Specs/SPEC_AiActorAccounts.md`
> 이 문서는 **그대로 복사해 실행하면 되는 절차**만 담는다. 판단할 것이 없게 쓴다.

---

## 0. 한 줄 요약

AI 자동화는 사람 계정(`lowyshin.giip`, `Lowy Shin`)으로 giip 코멘트를 남기지 않는다.
실행 주체마다 `ai.<host>.<process>` 계정이 있고, 코멘트 쓰기는 그 계정의 AccessToken 으로 인증한다.

---

## 0-1. 이 레포(giip-fde-agent)에서의 제약 — 먼저 읽는다 (giip #2645)

이 레포에는 **DB 직접접속 수단이 없다**(`giipdb/mgmt/*.ps1`, `dbconfig.json`, `execSQLFile.ps1` 미포함).
그래서 아래 절 중 일부는 이 레포만 클론한 PC 에서 **그대로 실행할 수 없다** — 어느 절이 어느 호스트
소관인지를 먼저 확인하고 읽는다(존재하지 않는 경로를 그대로 부르면 매 실행이 그 단계에서 조용히 실패한다).

| 절 | 이 레포에서 | 비고 |
| :-- | :-- | :-- |
| §2.1 / §2.2 (get-issue.sh 코멘트) | 가능 | giipfaw API 경로만 쓴다 |
| §2.3 (직접-DB `addIssueComment.ps1`) | 불가 | 이 레포의 게이트는 전부 `lib/post-comment.js` 로 쓴다 |
| §3-1 / §3-2 (계정 생성 마이그레이션) | 불가 | giipdb 체크아웃과 DB 접속이 있는 호스트에서 수행한다 |
| §3-3 (AK 동기화 `sync-ai-actor-credentials.ps1`) | 미이식 | DB 직접접속 전용이라 이식 대상에서 제외됐다(giip #2645) |
| §3-4 / §3-5 (레지스트리 등록 / 확인) | 가능 | 파일 편집 + node 확인만 한다 |
| §6 (점검 쿼리) | 불가 | 같은 이유. giipv3 어드민 화면 또는 DB 호스트에서 본다 |

**이 레포에서 AK 를 넣는 방법**: DB 접근 권한이 있는 호스트에서 §3-1~3-3 을 끝낸 뒤,
그 결과물인 `slack-bot/.secrets/giip-accounts.json` 을 이 체크아웃으로 가져오거나,
환경변수 `GIIP_ACCOUNTS_FILE` 로 그 파일 경로를 가리킨다(`lib/resolve-actor.js` 가 그 순서로 찾는다).
이 파일은 git 비추적이며 **절대 커밋하지 않는다**.

## 1. 현재 등록된 주체

| 주체 (`GIIP_ACTOR` 값) | usn | 누가 쓰나 |
| :-- | --: | :-- |
| `ai.dp01.console` | 2416 | Lowy-DP01 대화형 Claude Code 세션 (기본값) |
| `ai.dp01.gissue-scheduler` | 2417 | 매시 :07 `GIIP_Gissue_Claude` 스케줄러 + 부속 게이트 |
| `ai.dp01.gissue-watchdog` | 2418 | 스케줄러 감시 워치독 |
| `ai.svc.slack-bot` | 2420 | Slack 봇 |
| `ai.svc.antigravity` | 2419 | 외부 IDE 에이전트(Antigravity / Codex / ChatGPT Work) |

기계가 읽는 정본 목록: `scripts/gissue/ai-actors.json`

## 2. 코멘트를 남길 때 (일상 사용)

### 2.1 대화형 세션 — 아무것도 안 해도 된다

```bash
bash scripts/gissue/get-issue.sh <isn> <csn> --comment-file <본문파일> --role <역할키>
```

`GIIP_ACTOR` 가 없으면 `ai-actors.json` 의 `defaultActor`(=`ai.dp01.console`)로 등록된다.
등록 직전에 아래 한 줄이 출력되므로 어느 계정으로 나갔는지 눈으로 확인할 수 있다.

```
[ACTOR] ai.dp01.console (usn=2416, 출처=ai-actors.json:defaultActor) 계정으로 등록합니다.
```

### 2.2 다른 주체로 남길 때

```bash
GIIP_ACTOR=ai.dp01.gissue-scheduler bash scripts/gissue/get-issue.sh <isn> <csn> --comment-file <본문파일> --role <역할키>
```

PowerShell 에서는:

```powershell
$env:GIIP_ACTOR = 'ai.dp01.gissue-scheduler'
```

한 번 설정하면 **자식 프로세스가 전부 상속**한다 — 그 아래에서 부르는
`get-issue.sh` 와 `addIssueComment.ps1` 이 모두 이 주체로 기록된다.

### 2.3 직접-DB 경로(`addIssueComment.ps1`)

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<giipdb 체크아웃>\mgmt\addIssueComment.ps1" -isn <isn> -ContentFile "<본문파일>" -issuetype note -Actor "ai.dp01.gissue-scheduler" -ExpectedCsn <csn>
```

- `-Actor` 를 주면 `author` 가 그 계정명이 되고 `authorUsn` 이 채워진다.
- 게이트 스크립트처럼 **표시 라벨을 따로 유지해야 하면** `-author` 를 같이 준다.
  그러면 `author` 는 라벨 그대로, `authorUsn` 은 `-Actor` 계정으로 기록된다.

  ```powershell
  ... -author "gissue-review-audit" -Actor "ai.dp01.gissue-scheduler" ...
  ```

- `-Actor` 를 생략하면 환경변수 `GIIP_ACTOR` 를 쓴다. 둘 다 없으면 `authorUsn` 이 비고 경고가 뜬다.

## 3. 새 AI 주체를 추가할 때 (4단계, 순서대로)

예시로 `ai.dp01.mailcheck` 라는 주체를 추가한다고 하자. **아래 4단계를 이 순서대로 전부 한다.**
하나라도 빠지면 코멘트 등록이 실패하거나 주체가 기록되지 않는다.

### 3-1. 마이그레이션에 이름을 추가한다

`giipprj/giipdb/migrations/20260916_giip2613_ai_actor_accounts.sql` 의 `@actors` INSERT 목록에
한 줄 추가한다. **이름은 `ai.<host>.<process>` 이고 32자를 넘으면 안 된다**(`uloginid varchar(32)`).

```sql
INSERT INTO @actors (uloginid) VALUES
    ('ai.dp01.console'),
    ('ai.dp01.gissue-scheduler'),
    ('ai.dp01.gissue-watchdog'),
    ('ai.svc.slack-bot'),
    ('ai.svc.antigravity'),
    ('ai.dp01.mailcheck');          -- <-- 이 줄을 추가
```

### 3-2. 마이그레이션을 실행한다 (멱등 — 기존 계정은 건너뛴다)

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<giipdb 체크아웃>\mgmt\execSQLFile.ps1" -sqlfile "<giipdb 체크아웃>\migrations\20260916_giip2613_ai_actor_accounts.sql"
```

출력에서 새 계정의 `usn`, `akLength=32`, `relCount=14` 를 확인한다.
`akLength` 가 0 이면 AccessToken 이 안 만들어진 것이므로 다음 단계로 넘어가지 말고 원인을 본다.

### 3-3. AccessToken 을 자격증명 파일에 반영한다

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<스케줄러 원본 체크아웃(lowyworkenv)>\scripts\gissue\sync-ai-actor-credentials.ps1"   # 주의: 이 레포에는 없다 — §0-1 참고
```

- DB 의 `uloginid LIKE 'ai.%'` 전체를 읽어 `slack-bot/.secrets/giip-accounts.json` 의 `actors` 키에 넣는다.
- **AccessToken 은 화면에 출력되지 않는다**(길이만). 이 파일은 git 비추적이다 —
  `.gitignore:18` 로 제외되며 **절대 커밋하지 않는다**(`.agent/rules/49_no_plaintext_credential_persist.md`).

### 3-4. 공개 레지스트리에 등록한다

`scripts/gissue/ai-actors.json` 의 `actors` 에 항목을 추가한다. `usn` 은 3-2 출력값을 그대로 쓴다.

```json
    "ai.dp01.mailcheck": {
      "usn": 2421,
      "host": "Lowy-DP01",
      "process": "매시 메일 점검 자동화",
      "replaces": ["codex-mailcheck"],
      "env": "GIIP_ACTOR=ai.dp01.mailcheck"
    }
```

**이 등록을 빠뜨리면** `resolve-actor.js` 가 "등록된 AI 행위자가 아닙니다"로 거부한다
(오타난 주체명으로 조용히 계속 쓰는 것을 막기 위한 의도된 동작이다).

### 3-5. 확인

```bash
cd <이 레포 체크아웃 루트>
GIIP_ACTOR=ai.dp01.mailcheck node scripts/gissue/lib/resolve-actor.js --json
```

기대 출력: `{"actor":"ai.dp01.mailcheck","usn":2421,"akLength":32,"source":"env:GIIP_ACTOR"}`

## 4. 새 CSN 을 추가할 때

`ai.*` 계정은 `uLevel=1`(비-sysadmin)이라 `tCorpUserRel` 멤버십이 유일한 권한 경로다.
**멤버십이 없는 CSN 이슈에는 코멘트를 남길 수 없다**(`404 Issue not found or no permission`).

1. `scripts/gissue/csn-projects.json` 에 CSN 을 추가한다(기존 절차).
2. `scripts/gissue/ai-actors.json` 의 `csnScope` 배열에 같은 CSN 을 추가한다.
3. `giipprj/giipdb/migrations/20260916_giip2613_ai_actor_accounts.sql` 의 `@csns` VALUES 에 추가한다.
4. 3-2 의 명령으로 마이그레이션을 다시 실행한다(멱등 — 기존 소속은 건너뛰고 새 CSN 만 추가된다).

## 5. 문제가 생겼을 때

| 증상 | 원인 | 조치 |
| :-- | :-- | :-- |
| `'<이름>' 는 등록된 AI 행위자가 아닙니다` | `ai-actors.json` 에 없음(오타 포함) | 3-4 단계 수행, 또는 `GIIP_ACTOR` 오타 수정 |
| `'<이름>' 의 AccessToken 이 자격증명 파일에 없습니다` | 3-3 을 안 했거나 새 PC 라 `.secrets` 가 없음 | 3-3 실행 |
| 코멘트 등록이 `404 Issue not found or no permission` | 그 CSN 에 `tCorpUserRel` 멤버십 없음 | §4 수행 |
| `[giip #2613] 행위자 계정 '<이름>' 를 tCorpUser 에서 찾지 못했습니다` | DB 에 계정이 없음 | 3-1 ~ 3-2 수행 |
| `authorUsn 이 비어 있습니다` 경고 | `-Actor` 도 `GIIP_ACTOR` 도 없이 `addIssueComment.ps1` 호출 | 호출부에 `-Actor` 추가 |

**절대 하지 말 것**: 위 오류를 피하려고 예전 SK 인증으로 되돌리는 것.
되돌아가는 순간 코멘트가 다시 사람 계정(`lowyshin.giip`)으로 기록되기 시작하는데,
그게 **아무 신호 없이** 일어나기 때문에 시끄럽게 실패하는 것보다 나쁘다.

## 6. 제대로 동작하는지 점검하는 쿼리

```powershell
# 파일에 아래 SQL 을 쓴 뒤
powershell -NoProfile -ExecutionPolicy Bypass -File "<giipdb 체크아웃>\mgmt\execSQLFile.ps1" -sqlfile "<파일경로>"
```

```sql
-- 배포 이후 신규 코멘트 중 주체가 기록 안 된 것 = 아직 안 고친 경로
SELECT author, COUNT(*) AS cnt, MAX(regdate) AS latest
FROM tGiipIssueComment WITH(NOLOCK)
WHERE regdate > '2026-09-16' AND authorUsn IS NULL
GROUP BY author ORDER BY cnt DESC;
```

```sql
-- 사람 계정으로 새로 들어온 코멘트(0 이어야 정상. giipv3 어드민 화면에서 사람이 직접 쓴 것은 예외)
SELECT COUNT(*) AS humanWrites FROM tGiipIssueComment WITH(NOLOCK)
WHERE regdate > '2026-09-16' AND authorUsn IN (29, 47, 156);
```
