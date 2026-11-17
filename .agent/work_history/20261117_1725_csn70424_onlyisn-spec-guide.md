# 작업 기록 — -OnlyIsn 사양서 §18 + AI 인스턴스용 유저가이드 (giip 5544 후속)

- 일시: 2026-11-17 17:25 JST
- 근거: 사용자 직접 지시 — "이 처리도 사양서 업데이트 및 ai를 위한 유저가이드를 만들어줘.
  인스턴스에서 참고해야 할 경우 참고 시킬 수 있어야해". 대상 처리는 giip 5544 로 구현한
  러너 이슈 번호 지정 실행(-OnlyIsn). 같은 이슈 후속으로 진행한다.

## 변경 파일 (5건)

1. `docs/60-operations/hourly-issue-scheduler.md`
   - §18 신설: 목적, 파라미터 표(-OnlyIsn/-OnlyCsn/-DryRun 조합), 처리 흐름(Phase 1
     기동 판정 → 잡 큐 교체 → 이력 기록), 판정표(우회 2종 + SKIP 사유 코드 8종과 조건),
     쿨다운이 판정 대상이 아니라는 명시, 로그·운영 코멘트 형식, scheduler_run_history
     의 trigger/onlyIsn 필드, 호출 예시 3종, 동시 실행(lock) 주의, 테스트.
   - §3 의 -OnlyIsn 요약에 "상세 사양은 §18, 사용법은 AI 가이드" 연결 추가.
   - §14 연결 문서에 AI 가이드 항목 추가.
2. `docs/60-operations/only-isn-ai-guide.md` (신규) — AI 인스턴스용 유저가이드.
   독자 명시(스케줄러 호스트의 AI 에이전트·감지기 AI), 써도 되는/안 되는 경우, 호출
   3형태, 결과 표식별 대응표, 감지기 연동 규칙 4개(중복 트리거 방지·판정 분담·SKIP
   해석·이력 대조), 금지 사항 5개, FAQ 4개, 관련 문서. 형식은 같은 폴더의
   secwatch-ai-onboarding.md(AI 실행용 지시서)의 관례를 따랐다.
3. `docs/60-operations/README.md` — 운영 문서 색인에 가이드 등록(발견 경로).
4. `docs/WHATS_NEW.md` — 2026-11-17 항목.
5. 이 작업 기록.

## 발견·참조 경로 (인스턴스가 참고할 수 있게)

- 레포 안: 사양서 §3 요약 → §18 정본, §14 연결 문서, 60-operations README 색인,
  가이드 ↔ 사양서 상호 링크. 인스턴스는 self-pull 로 레포를 받으므로 이 경로로 닿는다.
- 레포 밖: CSN 70424 tPrivateKB 에 가이드 요지를 등록했다 — kbSn 7295
  ("-OnlyIsn 이슈 번호 지정 실행 — 사양 §18과 AI 인스턴스용 유저가이드 위치",
  2026-11-17 17:28 등록, 기존 85건 전수 확인 후 중복 없음).

## 검증

- 커밋 전 `git diff` 로 추가 줄에 타 CSN 번호·고객 식별 문자열이 없는지 확인한다.
- 상대 링크(only-isn-ai-guide.md, hourly-issue-scheduler.md, gissue-scheduler-run-history.md)가
  실재 파일로 연결되는지 확인한다.
- 이 작업의 worktree(`wt-onlyisn-docs`)는 PR 머지 후 rule 57 에 따라 정리한다.
