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
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /work

COPY entrypoint.sh /entrypoint.sh
COPY fetch-instance-env.sh /fetch-instance-env.sh
COPY setup-registration.js /setup-registration.js
RUN chmod +x /entrypoint.sh /fetch-instance-env.sh

ENTRYPOINT ["/entrypoint.sh"]
