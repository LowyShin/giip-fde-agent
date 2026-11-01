---
name: 스케줄러 생존은 태스크 결과코드가 아니라 처리 산출물(로그) 신선도로 판정하고, 감시자는 독립 태스크로 둔다
description: 태스크가 엉뚱한 스크립트를 가리켜도 LastTaskResult=0 이라 6일간 무소식이었다. 처리 로그 mtime + 락 상태로 판정하는 읽기 전용 점검기와 독립 태스크 원칙 (giip 4411)
metadata:
  type: project
---

# 스케줄러 생존 판정 (giip 4411)

## 핵심

1. Windows 작업 스케줄러에서 `LastTaskResult=0` 은 "태스크가 가리키는 프로그램이 정상 종료했다"일 뿐, "이슈 처리 본체가 돌았다"가 아니다.
   태스크 대상이 다른 스크립트로 바뀌면(실사고: 처리 본체가 6일 넘게 미실행) 매시 2초 만에 0 으로 끝나며 아무 경보도 없다.
2. 생존은 **처리 산출물이 신선한가**로 판정한다: CSN 별 `gissue_csn<N>.log` mtime(처리 본체는 이슈 0건이어도 매 실행 로그를 남긴다)
   + `.lock`(`PID|시작|마지막로그`)의 PID 생존/나이. 살아있는 락은 "처리 중"이므로 오탐하지 않는다.
3. 전체 무소식(`ALL_SILENT`)은 스케줄러 정지, 일부 무소식(`PARTIAL_SILENT`)은 해당 CSN 만 건너뜀으로 구분한다. 점검 대상 0건은 정상이 아니다.
4. **감시자는 감시 대상과 다른 독립 태스크**로 둔다(`GIIP_GissueLiveness_Hourly`, :37). 같은 태스크·러너 안에 두면 같은 장애에 같이 죽는다.
5. 알림은 기본 꺼짐(출력만), `-Notify -OpsCsn` 명시 시에만 작업 CSN 에 `[OPS]` 이슈 1건(열린 동일 제목 있으면 생략, 동일 상태 쿨다운 6h).

## 근거·위치

- 구현: `scripts/gissue/check-gissue-liveness.ps1`, `scripts/gissue/lib/gissue-liveness-lib.ps1`, `scripts/gissue/register-gissue-liveness-task.ps1`(사람이 실행)
- 테스트: `scripts/gissue/tests/test-gissue-liveness.ps1`
- 사양: `docs/60-operations/hourly-issue-scheduler.md` §16
- 같은 계열 교훈: 이름과 주기 불일치 `task-cadence-guard.ps1`(giip #2480) — 등록은 성공하고 결과코드는 0 인데 의도와 다르게 도는 태스크.
