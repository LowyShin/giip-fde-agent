#!/usr/bin/env python3
"""privatekb.py — tPrivateKB(조직별 비공개 지식 베이스) 등록·조회 클라이언트. giip 3905.

이 스크립트가 왜 생겼는가
------------------------
여러 k_layer 노트가 `node scripts/gissue/tkb.js sync-klayer --csn 47 --dir ...` 로
"동기화했다"고 적어두고 있었지만 **tkb.js 는 존재하지 않았다**(find / -name tkb.js 0건).
`<lowyworkenv>` 플레이스홀더가 치환되지 않은 채 커밋된 줄도 있었다. 2026-10-20 수집기
세션이 그 문구를 읽고 "경로를 알려주면 읽겠다"며 멈췄다. 문서가 가리키던 도구를 실제로
만든 것이 이 파일이다.

tPrivateKB 와 /kb 는 다른 것이다
-------------------------------
- **tPrivateKB** (이 스크립트가 다루는 것) = 조직(csn)별 **비공개** 지식. DB 테이블.
  관리 화면 `/{locale}/admin/privatekb`. Graphify 지식그래프의 원천.
- **/kb** = 누구나 보는 **공개** 기술 아티클. giipv3 코드 안의 타입스크립트 파일
  (`src/lib/kb/articles/*.ts`). DB 와 무관하고 이 스크립트로 건드릴 수 없다.

호출 경로 (실측 확인, 추측 아님)
------------------------------
에이전트는 AK 가 없고 SK 만 있다. 그래서 AK 전용 `giipKb` 함수가 아니라
**giipApiSk3 디스패처 → pApiKb*bySk** 를 쓴다.

    POST https://giipfaw.azurewebsites.net/api/giipApiSk3
    Content-Type: application/x-www-form-urlencoded
    token=<sk>&text=KbCreate jsondata&jsondata={...}
      -> 서버가 exec pApiKbCreatebySk '<sk>', N'{...}' 로 변환

`text` 에 `jsondata` 라는 낱말이 있으면 디스패처가 그 자리를 실제 JSON 으로 치환한다
(giipApiSk3/run.ps1 의 치환 로직). 이 낱말을 빼면 jsondata 가 마지막 인자로 자동
추가되는 다른 경로를 타므로, 명시적으로 넣는 쪽이 안전하다.

함정 (실제로 겪은 것)
-------------------
1. **응답 `debug` 필드에 SK 가 그대로 담겨 온다.** giipApiSk3 가
   `_debug_executedQuery` 에 `exec pApiKbCreatebySk '<sk>', ...` 를 넣어 돌려준다.
   giipfaw run.ps1 은 성역이라 고칠 수 없으므로 **클라이언트가 버려야 한다** — 이
   스크립트는 출력 전에 항상 `debug` 를 제거한다. 로그에 남기지 말 것.
2. **giipAgent.cnf 의 값에 따옴표가 포함돼 있다**(`sk="..."`). 직접 파싱하지 말고
   `secevt_lib.read_cfg_value` 를 쓸 것 — 거기에 따옴표 제거가 들어 있다.
3. **`pApiKbCreatebySk` 에는 중복 방지가 없다.** AK 버전(`pApiKbCreatebyAk`)은
   `extRefId` 로 여러 번 돌려도 안전한 upsert 를 하지만 SK 버전은 그냥 INSERT 다.
   그래서 이 스크립트의 `put` 은 **title 로 먼저 찾아보고 있으면 update** 한다
   (giipdb/mgmt/sync_klayer_to_privatekb.ps1 과 같은 방식).

사용법
-----
    privatekb.py put    --csn 47 --title "제목" --content-file note.md [--tags "a,b"]
    privatekb.py get    --csn 47 --kbsn 1234
    privatekb.py list   --csn 47 [--ref-type KNOWLEDGE] [--search 키워드] [--limit 20]
    privatekb.py sync-klayer --csn 47 --dir .agent/k_layer/notes [--dry-run]

sk 는 env `GIIP_SK` 또는 상위 폴더의 `giipAgent.cfg|.cnf` 에서 자동으로 찾는다.
**사람에게 묻지 않고, 어디에도 출력하지 않는다.**
"""
import argparse
import json
import os
import re
import sys
import urllib.parse
import urllib.request

# scripts/secwatch/secevt_lib.py 의 설정 리더를 재사용한다 — 같은 로직을 두 번 쓰지
# 않기 위해서다. read_cfg_value 는 secwatch 전용이 아니라 범용 에이전트 설정 리더다.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "secwatch"))
try:
    from secevt_lib import read_cfg_value  # noqa: E402
except ImportError:
    read_cfg_value = None

API_URL = "https://giipfaw.azurewebsites.net/api/giipApiSk3"
TIMEOUT = 60


def die(msg, code=1):
    print(msg, file=sys.stderr)
    sys.exit(code)


def resolve_sk():
    sk = os.environ.get("GIIP_SK")
    if not sk and read_cfg_value:
        sk = read_cfg_value("sk")
    if not sk:
        die("sk 를 찾지 못했습니다 (env GIIP_SK 또는 상위 giipAgent.cfg/.cnf 의 sk=).", 3)
    return sk.strip().strip('"').strip()


def call(sp_name, jsondata, sk):
    """giipApiSk3 로 pApi{sp_name}bySk 를 호출하고 행 목록을 돌려준다."""
    body = urllib.parse.urlencode({
        "token": sk,
        "text": "%s jsondata" % sp_name,
        "jsondata": json.dumps(jsondata, ensure_ascii=False),
    }).encode("utf-8")
    req = urllib.request.Request(
        API_URL, data=body,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
    )
    with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
        raw = resp.read().decode("utf-8", errors="replace")

    # 함정 1·4: debug 블록을 **파싱 전에 텍스트에서 잘라낸다.**
    #   (1) 거기에 sk 가 담겨 오므로 애초에 메모리에 올리지 않는 쪽이 낫다.
    #   (4) 더 중요한 이유: giipApiSk3 의 _debug_executedQuery 가 JSON 이스케이프를
    #       잘못한다. 본문에 줄바꿈이 있으면 `\` + 실제 개행을 내보내 **응답 전체가
    #       파싱 불가**가 된다(Invalid \escape). DB 쓰기는 성공했는데 클라이언트만
    #       실패로 보게 되어, 재시도하면 중복 행이 쌓인다. k_layer 노트는 전부
    #       여러 줄 마크다운이라 이 경로를 반드시 지나간다.
    #       giipfaw run.ps1 은 성역이라 고칠 수 없으므로 여기서 막는다.
    raw = re.sub(r',\s*"debug"\s*:\s*\{.*$', "}", raw, flags=re.S)

    try:
        parsed = json.loads(raw)
    except ValueError as e:
        die("응답을 해석하지 못했습니다 (%s). 쓰기는 성공했을 수 있으니 "
            "재시도 전에 list 로 확인하십시오." % e, 4)

    if isinstance(parsed, dict):
        parsed.pop("debug", None)
        rows = parsed.get("data", parsed)
    else:
        rows = parsed
    if isinstance(rows, dict):
        rows = [rows]
    if not isinstance(rows, list):
        rows = []

    for r in rows:
        if isinstance(r, dict) and r.get("RstVal") not in (None, 200):
            die("API 오류 %s: %s" % (r.get("RstVal"), r.get("RstMsg")), 5)
    return rows


def find_by_title(csn, title, sk):
    """같은 csn 안에서 title 이 완전히 일치하는 항목의 kbSn (없으면 None).

    함정 5: SP 가 `LIKE '%' + @searchKeyword + '%'` 로 찾으므로 title 에 들어 있는
    `[` 는 티에스큐엘 LIKE 의 **문자 클래스 시작**으로 해석된다. 예를 들어
    `[giip3905] client probe` 를 그대로 넘기면 아무것도 매칭되지 않아, 이미 있는
    항목을 못 찾고 새로 만들어 중복이 쌓인다(실제로 겪음). `[` 를 `[[]` 로 escape 한다.
    """
    needle = title.replace("[", "[[]")
    rows = call("KbList", {"csn": csn, "searchKeyword": needle}, sk)
    for r in rows:
        if isinstance(r, dict) and r.get("title") == title:
            return r.get("kbSn")
    return None


def cmd_put(a, sk):
    content = a.content
    if a.content_file:
        with open(a.content_file, "r", encoding="utf-8") as f:
            content = f.read()
    if content is None:
        die("--content 또는 --content-file 중 하나가 필요합니다.", 2)

    existing = find_by_title(a.csn, a.title, sk)
    if existing:
        call("KbUpdate", {"kbSn": existing, "title": a.title,
                          "content": content, "tags": a.tags}, sk)
        print("updated kbSn=%s" % existing)
        return existing

    rows = call("KbCreate", {"csn": a.csn, "refType": a.ref_type, "title": a.title,
                             "content": content, "tags": a.tags}, sk)
    kbsn = next((r.get("kbSn") for r in rows if isinstance(r, dict) and r.get("kbSn")), None)
    print("created kbSn=%s" % kbsn)
    return kbsn


def cmd_get(a, sk):
    rows = call("KbGet", {"kbSn": a.kbsn}, sk)
    print(json.dumps(rows, ensure_ascii=False, indent=2, default=str))


def cmd_list(a, sk):
    payload = {"csn": a.csn}
    if a.ref_type:
        payload["refType"] = a.ref_type
    if a.search:
        payload["searchKeyword"] = a.search
    rows = call("KbList", payload, sk)
    rows = [r for r in rows if isinstance(r, dict) and r.get("kbSn")]
    for r in rows[: a.limit]:
        print("%-8s %-16s %s" % (r.get("kbSn"), r.get("refType"), str(r.get("title"))[:70]))
    print("-- %d건 표시 (전체 %d건)" % (min(len(rows), a.limit), len(rows)))


def cmd_sync_klayer(a, sk):
    """k_layer 노트 폴더를 tPrivateKB 에 title 기준으로 올린다.

    노트들이 존재한다고 적어두었던 바로 그 동작이다. title = 파일명(확장자 포함)으로
    두어, 파일을 고쳐 다시 돌리면 새 행이 쌓이지 않고 같은 행이 갱신된다.
    """
    if not os.path.isdir(a.dir):
        die("폴더가 없습니다: %s" % a.dir, 2)
    names = sorted(n for n in os.listdir(a.dir) if n.endswith(".md"))
    if not names:
        die("대상 .md 파일이 없습니다: %s" % a.dir, 2)

    done = 0
    for n in names:
        path = os.path.join(a.dir, n)
        with open(path, "r", encoding="utf-8") as f:
            content = f.read()
        if a.dry_run:
            print("[dry-run] %s (%d자)" % (n, len(content)))
            continue
        existing = find_by_title(a.csn, n, sk)
        if existing:
            call("KbUpdate", {"kbSn": existing, "title": n,
                              "content": content, "tags": a.tags}, sk)
            print("updated %-60s kbSn=%s" % (n, existing))
        else:
            rows = call("KbCreate", {"csn": a.csn, "refType": a.ref_type, "title": n,
                                     "content": content, "tags": a.tags}, sk)
            kbsn = next((r.get("kbSn") for r in rows if isinstance(r, dict) and r.get("kbSn")), None)
            print("created %-60s kbSn=%s" % (n, kbsn))
        done += 1
    print("-- %d/%d 처리" % (done, len(names)))


def main():
    p = argparse.ArgumentParser(
        description="tPrivateKB(조직별 비공개 지식 베이스) 등록·조회 클라이언트. 공개 /kb 와 다른 기능이다.")
    sub = p.add_subparsers(dest="cmd", required=True)

    def add_csn(sp):
        sp.add_argument("--csn", type=int, required=True, help="조직 번호. SK 소속 csn 과 달라도 403 이다.")

    sp = sub.add_parser("put", help="등록 또는 갱신 (title 기준 upsert)")
    add_csn(sp)
    sp.add_argument("--title", required=True)
    sp.add_argument("--content")
    sp.add_argument("--content-file", help="한글 본문은 커맨드라인 대신 이 옵션을 쓸 것")
    sp.add_argument("--tags", default="")
    sp.add_argument("--ref-type", default="GENERAL")
    sp.set_defaults(fn=cmd_put)

    sp = sub.add_parser("get", help="단건 조회")
    add_csn(sp)
    sp.add_argument("--kbsn", type=int, required=True)
    sp.set_defaults(fn=cmd_get)

    sp = sub.add_parser("list", help="목록 조회")
    add_csn(sp)
    sp.add_argument("--ref-type")
    sp.add_argument("--search")
    sp.add_argument("--limit", type=int, default=20)
    sp.set_defaults(fn=cmd_list)

    sp = sub.add_parser("sync-klayer", help="k_layer 노트 폴더를 올린다")
    add_csn(sp)
    sp.add_argument("--dir", default=".agent/k_layer/notes")
    sp.add_argument("--ref-type", default="KNOWLEDGE")
    sp.add_argument("--tags", default="k-layer,ai-memory")
    sp.add_argument("--dry-run", action="store_true")
    sp.set_defaults(fn=cmd_sync_klayer)

    a = p.parse_args()
    a.fn(a, resolve_sk())


if __name__ == "__main__":
    main()
