# 서비스 계정 git 1회성 셋업 (작성자 + HTTPS push 자격증명)

새 host 또는 새 clone 에서 봇/무인 처리기가 커밋·push 를 하려면 아래 두 가지를 **한 번** 설정해야 한다.
설정하지 않으면 다음 오류로 커밋·push 가 중단된다(giip 4045 4절 실측).

| 증상 | 원인 |
|---|---|
| `Please tell me who you are` (커밋 실패) | 저장소에 `user.name` / `user.email` 이 없음 |
| `could not read Username for 'https://github.com'` (push 실패) | `gh auth status` 는 정상이어도 git 의 credential helper 가 gh 를 가리키지 않음 |

## 1. git 작성자 (서비스 계정 기준)

저장소별(권장) 또는 `--global` 로 1회 설정한다. 값은 이 host 의 서비스 계정 정보를 쓴다.

```bash
git config user.name  "<service-account-name>"
git config user.email "<service-account-email>"
git config --get user.name && git config --get user.email   # 확인: 두 줄이 모두 출력돼야 한다
```

## 2. HTTPS push 자격증명

먼저 `gh auth status` 로 GitHub CLI 로그인을 확인한다(로그인이 안 돼 있으면 `gh auth login`).
그 다음 **둘 중 하나**를 1회 실행한다.

```bash
# 방법 A (권장): gh 가 github.com 용 credential helper 를 ~/.gitconfig 에 등록
gh auth setup-git

# 방법 B: 저장소/전역에 직접 고정
git config --global credential.helper ""        # 기존 helper 체인 초기화(선택)
git config --global --add credential.helper "!gh auth git-credential"
```

확인:

```bash
git config --get-all credential.helper          # gh 를 가리키는 줄이 있어야 한다
git ls-remote origin HEAD                       # 프롬프트/오류 없이 해시가 나오면 인증 정상
```

## 3. 함께 점검할 것 (재발 방지)

- 작업 전 `git fetch origin` 후 `origin/main` 기준 최신본에서 시작한다. 로컬 `main` 이 뒤처지거나 다른 세션의 미커밋 변경이 쌓인 공유 체크아웃에서는 직접 커밋하지 말고 별도 worktree/브랜치에서 작업한다.
- main 직접 push 는 하지 않고 PR 로 올린다.
- 이 문서에는 실제 계정명·이메일·토큰을 적지 않는다(PUBLIC 저장소). 값은 각 host 에서만 설정한다.

관련: [`docker-instance-setup-rules.md`](./docker-instance-setup-rules.md) (Docker 인스턴스 세팅), [`../../QUICK_START.md`](../../QUICK_START.md).
