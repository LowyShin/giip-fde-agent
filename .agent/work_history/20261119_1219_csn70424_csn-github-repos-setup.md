# 작업 기록 — 초기 설정 시 CSN의 GitHub repo 일괄 clone (giip 5783)

- 일시: 2026-11-19 12:19 JST (Lowy님 직접 지시, 이 채팅)
- 이슈: giip 5783 (CSN 70424). 조회 API(repo+PAT)는 giip 5782로 분리해
  양쪽에 연결 코멘트를 남겼고, giipprj 채팅에도 알린다.

## 콘솔 실측 (2026-11-19, 읽기 전용)

- GitHub repo 관리는 "GitHub Actions" 화면 /en/project/{CSN}/github, CSN별 분리.
- 설정 1건 = Configuration Name(프로젝트 내 유일) + Owner + Repo Name + PAT(필수)
  + Description + Active + Deployment Service Type. 대표 지정·기본 브랜치 필드 없음.
- PAT 는 설정(repo) 단위다. 기존 토큰은 편집 화면에서도 표시되지 않는다.
- 등록 현황: lw-giip 프로젝트에 2건, 이 레포의 CSN과 front-fde CSN은 0건.
- 중복 검색에서 완료 이슈 giip #1051(GitHubConfigs 토큰 암호화 전환)을 확인 —
  #5782 의 보안 조건(PAT 암호화 저장)은 그 연장선이다.

## 설계 결정

1. 위치 저장 = csn-projects.json 의 CSN 항목에 repos 배열. workdir 는 기존 유효
   workdir 유지(운영자 우선, giip 5664 의 로컬 우선 원칙) → repo 1개면 그 repo,
   여러 개면 워크스페이스 폴더.
2. PAT 는 clone 에 extraHeader 로 1회 주입(원격 URL 에 남기지 않음), 저장은
   scripts/gissue/.secrets/github-pats.json(gitignore)만. 로그 출력 금지.
3. 진입점은 독립 스크립트 setup-csn-repos.ps1 로 두고, docker 부트스트랩은
   GIIP_SETUP_CSN 환경이 있을 때만 호출한다(선택 단계·fail-soft).

## 변경 파일

- scripts/gissue/lib/get-github-configs.js (신규): 스코프드 조회 + 응답 해석
  (Active 필터, slug 해석, csn 대조 scope_mismatch). mjs 테스트 로컬 15/15 PASS.
- scripts/gissue/lib/github-repos.ps1 (신규): clone 계획·중복 제거, workdir 판정
  4경우, csn-projects 병합 기록, PAT 저장, clone 실행(extraHeader 주입).
- scripts/gissue/setup-csn-repos.ps1 (신규): 초기 설정 진입점.
- scripts/bootstrap-instance.sh: 8번 선택 단계(GIIP_SETUP_CSN/GIIP_SK).
- scripts/gissue/csn-projects.json.example: repoBaseDir·repos 설명.
- .gitignore: scripts/gissue/.secrets/* 추가.
- scripts/gissue/tests/test-github-configs.mjs, test-github-repos.ps1 (신규).
  게이트 기대 건수 ps1 47→48, mjs 10→11.
- docs/60-operations/hourly-issue-scheduler.md: §21 신설.
- docs/WHATS_NEW.md, 이 작업 기록.

## 주의

- API(giip 5782)가 배포되기 전까지 setup 은 조회 실패를 로그만 남기고 끝난다.
  실효 검증(clone 실제 동작)은 API 배포 후 등록된 CSN 으로 1회 수행할 것.
- PAT 가 든 get-github-configs.js 의 stdout 은 setup 스크립트 내부에서만 소비되고
  로그로 나가지 않는다 — 다른 호출자를 만들 때도 이 전제를 지킬 것.
- 이 worktree(wt-ghsetup)는 PR 머지 후 rule 57 에 따라 정리한다.
