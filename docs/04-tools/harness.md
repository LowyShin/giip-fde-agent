# 하네스(Harness) 엔지니어링 가이드

## 1) 하네스란?

소프트웨어에서 **하네스(Harness)** 는 특정 작업을 안정적으로 반복 실행할 수 있도록 묶어 둔 **실행/검증 환경**입니다.  
쉽게 말해, "사람이 매번 수동으로 하던 절차를 표준화해서 같은 방식으로 재현하게 만드는 장치"입니다.

예시:
- 테스트 하네스: 테스트를 같은 조건으로 반복 실행
- 에이전트 하네스: 작업 지시, 실행, 상태 확인을 같은 흐름으로 반복 수행

## 2) 하네스 엔지니어링이 왜 중요한가?

- **재현성**: 같은 입력이면 같은 방식으로 실행됨
- **안정성**: 실행 순서와 규칙이 고정되어 실수를 줄임
- **확장성**: 사람이 늘지 않아도 작업량 증가에 대응 가능

## 3) 이 레포지토리에서의 하네스 개념

`LowyShin/giip-dev-agent` 에서 하네스는 다음 요소들의 조합으로 동작합니다.

- `GEMINI.md`: 전체 작업 원칙(오케스트레이션, 검증, 보고)
- `.agent/dispatch/*.md`: 작업 지시서(Task Dispatch)
- `.agent/roles/*.md`: 역할별 실행 규칙
- `.agent/scripts/launch_subsession.ps1`: 대기 작업 실행
- `.agent/scripts/check_status.ps1`: 현재 작업/세션 상태 확인
- `.agent/scripts/launch_role.ps1`: 수동 핸드오프 실행

즉, 이 레포의 하네스는 "작업 문서(Dispatch) + 역할 규칙(Role) + 실행 스크립트(Script)"를 연결해 반복 가능한 멀티 에이전트 실행 흐름을 만드는 구조입니다.

## 4) 이 레포지토리에서 하네스 설정 방법

### 4-1. 프로젝트 준비

```bash
git clone https://github.com/LowyShin/giip-dev-agent.git
cd giip-dev-agent
```

### 4-2. (선택) 자동화용 API Key 설정

수동 실행만 할 경우 생략 가능합니다.

```bash
cd .agent
cp settings.json.sample settings.json
```

`settings.json` 의 `api_key` 또는 `api_keys` 값을 실제 키로 설정합니다.

> [!CAUTION]
> API Key는 민감정보입니다. 실제 키가 들어간 `settings.json` 파일은 원격 저장소에 커밋하지 마세요.  
> 가능하면 셸 환경변수(`GEMINI_API_KEY`)를 우선 사용하고, 파일 기반 설정은 로컬 개발 환경에서만 관리하세요.

### 4-3. 작업 지시서(Dispatch) 준비

`.agent/dispatch/` 에 `TASK_*.md` 형태의 파일을 두고, `Status` 를 `Pending` 으로 설정합니다.  
기본 포맷은 `.agent/dispatch/TASK_TEMPLATE.md` 를 그대로 복사해 사용하면 됩니다.

예시:

```markdown
- **Status:** Pending
- **Task ID:** TASK_001
- **Target Role:** Developer
```

`launch_subsession.ps1` 는 Pending 상태의 작업을 찾아 실행합니다.

### 4-4. 하네스 실행

PowerShell에서 프로젝트 루트 기준:

```powershell
# 자동으로 Pending 작업 실행
.\.agent\scripts\launch_subsession.ps1

# 상태 확인
.\.agent\scripts\check_status.ps1
```

### 4-5. 수동 핸드오프(필요 시)

```powershell
.\.agent\scripts\launch_role.ps1
```

## 5) 빠른 체크리스트

- [ ] `GEMINI.md`/역할 문서를 읽는 도구 환경이 준비되었는가?
- [ ] `.agent/dispatch` 에 `Pending` 작업이 있는가?
- [ ] `launch_subsession.ps1` 로 실행이 시작되는가?
- [ ] `check_status.ps1` 로 상태 추적이 가능한가?

위 항목이 모두 충족되면 이 레포지토리의 기본 하네스 설정은 완료입니다.
