# Docker 인스턴스: 일반 사용자(dev) 생성과 sudo 권한

> claude 는 root 에서 `--dangerously-skip-permissions`(bypass)를 거부한다. 그래서 인스턴스에서는
> 일반 사용자(기본 `dev`)로 claude 를 돌린다. 이 사용자는 기본적으로 root 전용 자원(`/root/.pm2/logs`,
> root crontab 등)을 읽을 수 없으므로, 필요하면 sudo 권한을 따로 준다.
> 관련 룰: [`docker-instance-setup-rules.md`](./docker-instance-setup-rules.md)

## 스크립트 (모두 `scripts/` 아래)

| 스크립트 | 실행 주체 | 역할 |
|---|---|---|
| `scripts/docker-bypass.sh` | root 또는 dev | dev 사용자 생성, 저장소 소유권 이전, claude 를 bypass + remote-control 로 기동 |
| `scripts/setup-dev-sudo.sh` | **root 필수** | sudo 설치, `dev` 에 NOPASSWD 전체 sudo 부여 |

저장소 루트에는 `.sh` 파일을 두지 않는다. 새 셸 스크립트는 `scripts/` 에 둔다.

## 사용 순서

```bash
git clone <giip-fde-agent> && cd giip-fde-agent

# 1) dev 사용자 생성 + claude 기동 (root 로 실행하면 dev 로 전환해서 실행)
sh scripts/docker-bypass.sh

# 2) (필요 시) dev 에게 전체 sudo 권한 — root 로 실행
sh scripts/setup-dev-sudo.sh
```

WSL 에서 root 셸이 필요하면 Windows 터미널에서 `wsl -u root` 로 진입한다.
적용 확인: `su - dev -c 'sudo -n true && echo OK'`. Claude Code 는 재시작해야 새 권한을 인식한다.

## 환경변수

- 공통: `FDE_USER` 대상 사용자 (기본 `dev`)
- `docker-bypass.sh` 전용: `FDE_REMOTE_CONTROL`(1/0), `FDE_MODE`(`interactive`|`server`), `FDE_RC_NAME`

## 보안 주의

- `setup-dev-sudo.sh` 는 `/etc/sudoers.d/<user>` 에 `ALL=(ALL) NOPASSWD:ALL` 을 기록한다. 사실상 root 권한이다.
- 신뢰할 수 있는 개인 개발 환경, 또는 격리된 인스턴스에서만 쓴다. 공유/운영 서버에는 쓰지 않는다.
- sudoers 파일은 `visudo -cf` 로 문법을 검증한 뒤 440 권한으로 설치한다.
- 되돌리기: `rm /etc/sudoers.d/dev`

## 경로 변경 이력

`docker-bypass.sh` 는 저장소 루트에서 `scripts/` 로 이동했다. 스크립트 내부의 저장소 루트 계산은
`scripts/` 의 상위 디렉터리를 기준으로 하도록 수정되어 있다. 기존 실행 명령 `sh docker-bypass.sh`
는 `sh scripts/docker-bypass.sh` 로 바꿔야 한다.
