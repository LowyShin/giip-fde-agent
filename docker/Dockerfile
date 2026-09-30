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

WORKDIR /work

COPY entrypoint.sh /entrypoint.sh
COPY fetch-instance-env.sh /fetch-instance-env.sh
COPY setup-registration.js /setup-registration.js
RUN chmod +x /entrypoint.sh /fetch-instance-env.sh

ENTRYPOINT ["/entrypoint.sh"]
