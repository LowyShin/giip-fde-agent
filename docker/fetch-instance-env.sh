#!/usr/bin/env bash
# Fetches env values from GIIP's dockerInstanceFetch API using GIIP_INSTANCE_TOKEN and prints
# `export KEY='VALUE'` lines to stdout — nothing else. No-op (empty output) if GIIP_INSTANCE_TOKEN
# is unset, so existing per-field env vars keep working as-is (purely additive).
#
# Run in its own process and eval the output — do NOT `source` this file directly, since its
# `exit` on error would otherwise terminate the calling shell too:
#   eval "$(/fetch-instance-env.sh)"
set -euo pipefail

GIIP_INSTANCE_API_BASE="${GIIP_INSTANCE_API_BASE:-https://giipfaw.azurewebsites.net/api}"

if [ -z "${GIIP_INSTANCE_TOKEN:-}" ]; then
  exit 0
fi

echo "[fetch-instance-env] fetching env via GIIP_INSTANCE_TOKEN" >&2
RESPONSE=$(curl -fsS -G "$GIIP_INSTANCE_API_BASE/dockerInstanceFetch" --data-urlencode "token=$GIIP_INSTANCE_TOKEN")

echo "$RESPONSE" | node -e '
  let data = "";
  process.stdin.on("data", (c) => { data += c; });
  process.stdin.on("end", () => {
    const parsed = JSON.parse(data);
    if (Number(parsed.RstVal) !== 200 || !parsed.env) {
      console.error(`dockerInstanceFetch failed: RstVal=${parsed.RstVal} ${parsed.Proc_MSG || ""}`);
      process.exit(1);
    }
    // Locally-set env vars win over the fetched ones (explicit .env override), so callers can
    // mix GIIP_INSTANCE_TOKEN with a handful of manual overrides without editing the GIIP record.
    const lines = Object.entries(parsed.env)
      .filter(([k, v]) => v !== null && v !== undefined && v !== "" && !process.env[k])
      .map(([k, v]) => `export ${k}=${JSON.stringify(String(v))}`);
    process.stdout.write(lines.join("\n") + "\n");
  });
'
echo "[fetch-instance-env] env applied from GIIP_INSTANCE_TOKEN" >&2
