---
name: 러너 내부 마감은 작업 스케줄러 제한과 같은 시계(프로세스 시작)를 써야 하고, 외부 종료 전에 정리해야 한다
description: 잡 launch 기준 105분 마감은 사전 단계만큼 밀려 PT2H 외부 강제 종료에 못 미쳤다. 직렬 후처리가 마감 판정을 막고, 외부 종료는 락·잡 출력을 남긴다 (giip 4428/4429)
metadata:
  type: project
---

# 러너 자기 마감시각과 외부 강제 종료 (giip 4428 → 4429)

## 핵심

1. **마감은 한도와 같은 시계로 잰다.** 작업 스케줄러 `ExecutionTimeLimit` 은 프로세스 시작 시각부터 센다. 러너 안의 `RunTimeoutMin` 이 잡 launch 시각부터 세면
   launch 전 사전 단계(자기 갱신·guard·merge-sweep·reaper)만큼 마감이 늦어져 "한도보다 15분 먼저 만료"라는 설계 의도(giip 1572)가 깨진다.
   실측 사전 단계 1~21분. 해법: 프로세스 시작 시각 기준 마감(`GISSUE_OVERTIME_RUN_DEADLINE_MIN`, 기본 105).
2. **직렬 후처리는 마감 판정을 막는다.** 한 잡이 끝나 `Complete-Run`(게이트 스윕·감사·정리)이 돌면 메인 루프가 그 시간 동안 다른 잡의 TIMEOUT 판정을 못 한다.
   마감은 후처리와 독립적으로 *먼저* 검사해야 한다.
3. **외부 강제 종료는 락·잡 출력·고아 프로세스를 남긴다.** 다음 인스턴스의 reaper 가 고아를 종료하느라 사전 단계가 길어지면 (1) 이 더 나빠지는 악순환이 된다.
4. **"2시간 초과 → 분할 → DONE" 은 감사 면제 마커가 있어야 닫힌다.** DONE 의 근거가 PR 이 아니라 *DB 의 서브 이슈*이므로, 감사가 이를 "PR 없음"으로 되돌리지 않게
   `[SPLIT-CLOSE]`(첫 줄 + "분할 이전" + 서브 이슈 번호)를 면제 조건으로 인식시킨다(`[NO-PR-REASON]` 과 같은 방식).
5. **기본은 Shadow.** 이슈를 DONE 으로 올리는 자동 동작은 로그만 남기는 모드로 먼저 돌려 본다. Live 는 사람이 명시적으로 켠다.

## 근거·위치

- 구현: `scripts/gissue/lib/overtime-split.ps1`, `scripts/gissue/run-gissue-claude.ps1`(Phase 2 `Invoke-GissueOvertimeCheck`), `scripts/gissue/gissue-audit-lib.ps1`(`Test-HasSplitCloseMarker`)
- 테스트: `scripts/gissue/tests/test-overtime-split.ps1`
- 사양: `docs/60-operations/hourly-issue-scheduler.md` §13-5
- 같은 계열: KNOW-021(스케줄러 생존은 처리 산출물 신선도로 판정).
