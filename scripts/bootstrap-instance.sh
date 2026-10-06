#!/usr/bin/env bash
# bootstrap-instance.sh — docker 인스턴스를 어디서 새로 띄워도 "한 번 실행하면 작업 가능한 상태"로 맞춘다(giip #3535).
#
# 원칙: 인스턴스에는 수동 설정을 남기지 않는다. 인스턴스가 가진 것은 (1) 이 저장소 + 허브 저장소 (git),
#   (2) 환경변수/.env(인스턴스별 instances/<diSn>.env) 또는 영속 볼륨 /work/.secrets 의 비밀값 — 둘뿐이다.
#   그래서 인스턴스를 옮기거나 새로 만들어도 이 스크립트 한 번이면 같은 상태가 된다. 멱등이고 값(SK/비밀번호)은 출력하지 않는다.
# 언제 도나: entrypoint.sh 기동 시 자동. 수동: `bash /work/giip-fde-agent/scripts/bootstrap-instance.sh`
# 하는 일: 1) root 소유 파일 회수  2) powershell→pwsh 링크  3) SqlServer 모듈  4) 허브 저장소 clone(없을 때만)
#          5) giipdb/mgmt/dbconfig.json 생성(없을 때만, 환경변수 또는 $SECRETS/dbconfig.json)  6) 허브의 환경 점검 실행
# 환경변수: GIIP_DB_SERVER GIIP_DB_NAME GIIP_DB_LOGIN GIIP_DB_PASSWORD (DB 직접 접속, 선택)
#           GIIP_HUB_URL(기본 https://github.com/LowyShin/giipprj-hub.git) GIIP_HUB_DIR(기본 /work/giipprj-hub) GIIP_SECRETS_DIR(기본 /work/.secrets)
# 정본 설명: giipprj-hub .agent/k_layer/notes/KNOW-096_docker_instance_environment_and_linux_script_pitfalls.md
FDE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HUB="${GIIP_HUB_DIR:-/work/giipprj-hub}"
SECRETS="${GIIP_SECRETS_DIR:-/work/.secrets}"
HUB_URL="${GIIP_HUB_URL:-https://github.com/LowyShin/giipprj-hub.git}"
log(){ printf '[bootstrap] %-6s %s\n' "$1" "$2"; }
SUDO=""; [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null && SUDO="sudo -n"

# 1) root 소유 파일 회수(dev 세션의 Permission denied 방지)
bash "$FDE/scripts/fix-root-owned.sh" 2>&1 | grep -v setlocale | sed 's/^/[bootstrap] /'

# 2) `& powershell -File ...` 호출 호환(Linux 에는 powershell 실행 파일이 없다)
if command -v powershell >/dev/null 2>&1; then log OK "powershell 링크"
elif ! command -v pwsh >/dev/null 2>&1; then log WARN "pwsh 없음"
elif [ "$(id -u)" -eq 0 ] || [ -n "$SUDO" ]; then $SUDO ln -sf "$(command -v pwsh)" /usr/local/bin/powershell && log FIXED "powershell → pwsh 링크"
else log WARN "powershell 링크 불가(root/sudo 필요) — Dockerfile 에 포함됨(이미지 재빌드)"; fi

# 3) SqlServer 모듈(Invoke-Sqlcmd). sqlcmd/ODBC 없이 DB 직접 접속 스크립트가 돈다.
if pwsh -NoProfile -Command 'if (Get-Module -ListAvailable SqlServer) { exit 0 } else { exit 1 }' >/dev/null 2>&1; then log OK "SqlServer 모듈"
elif pwsh -NoProfile -Command 'Set-PSRepository PSGallery -InstallationPolicy Trusted; Install-Module SqlServer -Scope CurrentUser -Force -AcceptLicense -ErrorAction Stop' >/dev/null 2>&1; then log FIXED "SqlServer 모듈 설치"
else log WARN "SqlServer 모듈 설치 실패(네트워크?)"; fi

# 4) 허브 저장소(AI 지침의 정본) — 없을 때만 clone. 이미 있으면 작업 중일 수 있으니 건드리지 않는다.
if [ -d "$HUB/.git" ]; then log OK "허브 저장소 $HUB"
elif git clone --quiet "$HUB_URL" "$HUB" 2>/dev/null; then log FIXED "허브 저장소 clone → $HUB"
else log WARN "허브 저장소 clone 실패($HUB_URL) — GH_TOKEN/네트워크 확인"; fi

# 5) DB 직접 접속 정보 — 비밀값이라 저장소에 없다. 환경변수 → 영속 볼륨(/work/.secrets) 순으로 구한다. 이미 있으면 그대로 둔다.
DBCFG="$HUB/giipdb/mgmt/dbconfig.json"
if [ -f "$DBCFG" ]; then log OK "dbconfig.json"
elif [ ! -d "$HUB/giipdb/mgmt" ]; then log SKIP "giipdb/mgmt 없음(허브의 giipdb 클론 필요) — dbconfig.json 생성 보류"
elif [ -n "${GIIP_DB_SERVER:-}" ] && [ -n "${GIIP_DB_LOGIN:-}" ] && [ -n "${GIIP_DB_PASSWORD:-}" ]; then
  python3 - "$DBCFG" <<'PY' && chmod 600 "$DBCFG" && log FIXED "dbconfig.json ← 환경변수(GIIP_DB_*)"
import json,os,sys
json.dump({"serverName":os.environ["GIIP_DB_SERVER"],"databaseName":os.environ.get("GIIP_DB_NAME","giipdb"),
           "login":os.environ["GIIP_DB_LOGIN"],"password":os.environ["GIIP_DB_PASSWORD"]},open(sys.argv[1],"w"),indent=2)
PY
elif [ -f "$SECRETS/dbconfig.json" ]; then cp "$SECRETS/dbconfig.json" "$DBCFG" && chmod 600 "$DBCFG" && log FIXED "dbconfig.json ← $SECRETS/dbconfig.json"
else log WARN "dbconfig.json 없음 — GIIP_DB_SERVER/LOGIN/PASSWORD 를 .env 에 넣거나 $SECRETS/dbconfig.json 으로 두거나, 사용자에게 한 번 요청해 저장(DB 직접 접속 스크립트만 불가, API 경로는 영향 없음)"; fi
# 한 번 만든 접속 정보는 영속 볼륨에도 보관해 같은 볼륨을 쓰는 다음 인스턴스가 재사용하게 한다.
if [ -f "$DBCFG" ] && [ ! -f "$SECRETS/dbconfig.json" ]; then
  mkdir -p "$SECRETS" && cp "$DBCFG" "$SECRETS/dbconfig.json" && chmod 600 "$SECRETS/dbconfig.json" && log OK "dbconfig.json 사본 보관($SECRETS)"
fi

# 6) 현재 상태 점검(읽기 전용) — 허브의 정본 점검 스크립트
[ -f "$HUB/.agent/scripts/check_instance_env.sh" ] && FDE_DIR="$FDE" bash "$HUB/.agent/scripts/check_instance_env.sh" 2>&1 | grep -v setlocale
exit 0
