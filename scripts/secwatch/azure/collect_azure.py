#!/usr/bin/env python3
"""secwatch Azure 収集器 (giip-3869 / PoC).

Azure Log Analytics から PostgreSQL 文ログ / App Service HTTP ログを `az monitor
log-analytics query` で取り出し、secwatch の §5 正規化イベント(JSON-lines, `generic`)に
変換して stdout へ出す。出力はそのまま `secevt_collect.py --source generic --stdin` に流せる。

秘密は持たない(az 認証のみ)。本体 scripts/secwatch/ は非改変で、その手前の供給役。

使い方:
  # PG 文ログ(直近 N 分)
  python3 collect_azure.py --kind pg   --workspace <LA_GUID> --system pg-dev   --minutes 15
  # App Service HTTP(直近 N 分)
  python3 collect_azure.py --kind http --workspace <LA_GUID> --system ss-dev   --minutes 15
  # オフライン検証(az を叩かず、az query 相当の JSON 行配列から正規化だけ試す)
  python3 collect_azure.py --kind pg --from-json rows.json --system pg-dev

  # パイプライン(docs/60-operations/secwatch-agent.md §3):
  python3 collect_azure.py --kind pg --workspace <GUID> --system pg-dev \
    | python3 ../secevt_collect.py --source generic --stdin \
    | python3 ../secevt_agent.py --lssn <LSSN> --stdin --dry-run
"""
import argparse, json, subprocess, sys, re
from urllib.parse import unquote_plus

# PostgreSQL Flexible Server のログは AzureDiagnostics(Category=PostgreSQLLogs)。
# Message 例: "... LOG:  statement: SELECT ..." / "... LOG:  execute <unnamed>: SELECT ..."
PG_KQL = (
    'AzureDiagnostics | where Category == "PostgreSQLLogs" '
    '| where TimeGenerated > ago({m}m) '
    '| where Message has "statement:" or Message has "execute" '
    '| project TimeGenerated, Message, LogicalServerName_s, errorLevel_s '
    '| order by TimeGenerated asc | take 2000'
)
HTTP_KQL = (
    'AppServiceHTTPLogs | where TimeGenerated > ago({m}m) '
    '| project TimeGenerated, CsUriStem, CsUriQuery, ScStatus, CIp, UserAgent, CsMethod '
    '| order by TimeGenerated asc | take 2000'
)

_STMT_RE = re.compile(r'(?:statement:|execute[^:]*:)\s*(.*)$', re.I | re.S)


def az_query(workspace, kql, subscription=None):
    # --subscription は必須級: 既定サブスクが WS と異なると LA データプレーン token が
    # "InvalidTokenError (not valid for this resource)" になる(giip-3869 PoC で実測)。
    cmd = ["az", "monitor", "log-analytics", "query", "-w", workspace,
           "--analytics-query", kql, "-o", "json", "--only-show-errors"]
    if subscription:
        cmd += ["--subscription", subscription]
    out = subprocess.run(cmd, capture_output=True, text=True)
    if out.returncode != 0:
        sys.stderr.write("az query failed: %s\n" % out.stderr.strip()[:300])
        return []
    try:
        return json.loads(out.stdout or "[]")
    except Exception as e:
        sys.stderr.write("parse error: %s\n" % e)
        return []


def norm_pg(rows, system):
    """PostgreSQLLogs 行 → §5 event(sql_shape に生SQL。マスキングはエージェントが行う)。"""
    evts = []
    for r in rows:
        msg = r.get("Message") or ""
        m = _STMT_RE.search(msg)
        sql = (m.group(1).strip() if m else msg.strip())
        if not sql:
            continue
        evts.append({
            "src": "generic", "ts": r.get("TimeGenerated"),
            "op": "QUERY", "sql_shape": sql,
            "db": r.get("LogicalServerName_s"),
            "origin": {"source": "azure_pg_audit", "system": system,
                       "location": "LogAnalytics:AzureDiagnostics/PostgreSQLLogs",
                       "ref": "ts#%s" % r.get("TimeGenerated"), "ts": r.get("TimeGenerated")},
        })
    return evts


def norm_http(rows, system):
    evts = []
    for r in rows:
        # Azure の CsUriStem/CsUriQuery は URL エンコード済み(例 UNION%20SELECT)。
        # prefilter の正規表現(UNION\s+SELECT 等)に当てるためデコードする(giip-3869 ライブ検証)。
        uri = unquote_plus(r.get("CsUriStem") or "")
        q = unquote_plus(r.get("CsUriQuery") or "")
        try:
            status = int(r.get("ScStatus")) if r.get("ScStatus") not in (None, "") else None
        except (ValueError, TypeError):
            status = None
        evts.append({
            "src": "generic", "ts": r.get("TimeGenerated"),
            "req_uri": uri, "req_args_shape": q, "retcode": status,
            "client_ip_class": "external", "ua_class": "script",
            "origin": {"source": "azure_appsvc_http", "system": system,
                       "location": "LogAnalytics:AppServiceHTTPLogs",
                       "ref": "ts#%s" % r.get("TimeGenerated"), "ts": r.get("TimeGenerated")},
        })
    return evts


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--kind", required=True, choices=["pg", "http"])
    ap.add_argument("--workspace", help="Log Analytics customerId (GUID)")
    ap.add_argument("--system", required=True, help="origin.system ラベル(例 pg-dev / ss-dev)")
    ap.add_argument("--minutes", type=int, default=15)
    ap.add_argument("--subscription", help="az subscription (WS と同じサブスク)")
    ap.add_argument("--from-json", help="az を叩かず、この JSON(行配列)から正規化のみ(検証用)")
    args = ap.parse_args()

    if args.from_json:
        rows = json.load(open(args.from_json, encoding="utf-8"))
    else:
        if not args.workspace:
            ap.error("--workspace is required unless --from-json is given")
        kql = (PG_KQL if args.kind == "pg" else HTTP_KQL).format(m=args.minutes)
        rows = az_query(args.workspace, kql, args.subscription)

    evts = norm_pg(rows, args.system) if args.kind == "pg" else norm_http(rows, args.system)
    for e in evts:
        sys.stdout.write(json.dumps(e, ensure_ascii=False) + "\n")
    sys.stderr.write("collected %d event(s) [kind=%s system=%s]\n" % (len(evts), args.kind, args.system))


if __name__ == "__main__":
    main()
