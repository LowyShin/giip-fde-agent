# giip-fde-agent — slack-bot + hourly-issue-scheduler runtime (Linux/pwsh)
#
# Base image already ships PowerShell 7 (pwsh), which the scheduler needs
# (see docs/60-operations/hourly-issue-scheduler.md §13-1-1 for why Windows
# PowerShell 5.1-only assumptions were removed from run-gissue-claude.ps1).
FROM mcr.microsoft.com/powershell:7.4-debian-12

RUN apt-get update \
    && apt-get install -y --no-install-recommends git curl wget procps iproute2 ca-certificates cron gnupg \
    && curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && npm install -g @anthropic-ai/claude-code pm2 \
    # GitHub CLI (gh): PR 생성/병합 자동화에 필요. 이미지에 구워넣어 컨테이너 재생성해도 유지된다
    # (giip #3405: 세션마다 수동 설치하던 것을 영속화). 인증은 GH_TOKEN env 또는 gh auth login 로 별도 수행.
    && mkdir -p -m 755 /etc/apt/keyrings \
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends gh \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# giipdb/mgmt/execSQLFile.ps1 등 DB 직접 접속 스크립트는 Invoke-Sqlcmd(SqlServer 모듈)를 우선 쓴다. sqlcmd/ODBC 설치
# 없이 pwsh 만으로 동작하고(Linux 에서 실측: giipdb 접속·조회 성공) 스크립트 수정이 필요 없다. 이미지에 구워 컨테이너를
# 재생성해도 유지한다. 접속 정보(mgmt/dbconfig.json)는 비밀값이라 이미지에 넣지 않고 컨테이너에서 별도로 둔다.
RUN pwsh -NoProfile -Command "Set-PSRepository PSGallery -InstallationPolicy Trusted; Install-Module SqlServer -Scope AllUsers -Force -AcceptLicense -ErrorAction Stop"
# Windows 전제로 작성된 스크립트가 `& powershell -File ...` 로 자식 스크립트를 부른다(giipdb/mgmt/updateIssueStatus.ps1,
# scripts/gissue/pr-gate-sweep.ps1 등). Linux 에는 powershell 실행 파일이 없어 조용히 실패하므로 pwsh 로 연결한다
# (-ExecutionPolicy 는 Linux 에서 무시되어 같은 인자로 동작한다).
RUN ln -sf "$(command -v pwsh)" /usr/local/bin/powershell

WORKDIR /work

COPY entrypoint.sh /entrypoint.sh
COPY fetch-instance-env.sh /fetch-instance-env.sh
COPY setup-registration.js /setup-registration.js
RUN chmod +x /entrypoint.sh /fetch-instance-env.sh

ENTRYPOINT ["/entrypoint.sh"]
