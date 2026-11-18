# 작업 기록 — 프로젝트 정보 로딩 개편: GIIP 매핑 조회 폴백 (giip 5664)

- 일시: 2026-11-18 15:54 JST (ssm-front-fde 채팅에서 Lowy님 지시로 이관)
- 이슈: giip 5664 (CSN 70424). 읽기 경로(SP·엔드포인트)는 giip 5665 로 분리해
  양쪽에 연결 코멘트를 남겼다.

## 설계 결정

1. 동기화 복구가 아니라 조회 폴백으로 대체. 근거: 이 레포에는 DB 직접 접근이 없고
   sync-csn-mapping-from-db.ps1 은 DB 직접 접속 전제라 이식 대상이 아니다(사양서
   §13-2 격차). 폴백은 필요한 CSN 만 필요한 순간에 조회하고, 결과를 로컬 캐시에
   써 넣어 다음 실행부터 로컬로 동작한다(점진적 자기 복구).
2. 읽기 경로는 스코프드 byAK 계약: GET /api/giipGissueCsnMapping?csn=<n> +
   x-api-key(그 CSN 의 SK). AK 에서 도출되는 CSN 과 요청 CSN 이 일치할 때만 행 1건
   반환. sysadmin 전용 전체 반환(pApiGissueCsnMappingListbyAK)은 쓰지 않는다.
   #5572 의 읽기도 같은 패턴으로 통일(5665 본문에 명시).

## 변경 파일

- scripts/gissue/lib/csn-mapping.ps1 (신규): Get-GissueCsnMappingRemote(전송 주입
  가능), Merge-GissueCsnEntryFromRemote(로컬 전용 필드 보존), Resolve-GissueCsnMapEntry
  (LOCAL/REMOTE/UNMAPPED 판정 정본 — 충분 판정은 러너의 Test-GissueCsnEntryValid 를
  -Validator 로 주입받아 복제하지 않음), Update-GissueCsnProjectsCache(원자적 교체),
  Get-GissueCandidateCsnList(Phase -2.5 와 같은 두 출처), Resolve-GissueCsnMappings.
- scripts/gissue/lib/get-csn-mapping.js (신규): 계약 호출 + parseMappingResponse
  (csn 불일치 scope_mismatch, gcm 접두사·래핑 허용, enabled 강제 변환).
- scripts/gissue/run-gissue-claude.ps1: lib dot-source, Phase -3 직후 패스
  (placeholder 검사보다 먼저), Phase -2.5 사전 패스. DryRun 에서는 캐시 미기록.
- scripts/gissue/tests/test-csn-mapping-fallback.ps1, test-csn-mapping.mjs (신규).
  mjs 는 로컬 실행으로 17/17 PASS 확인. ps1 은 CI 로 검증한다.
- scripts/gissue/run-repo-gates.ps1: 기대 건수 ps1 45→46, mjs 8→9.
- docs/60-operations/hourly-issue-scheduler.md: §19 신설.
- docs/WHATS_NEW.md, 이 작업 기록.

## 검증·주의

- 커밋 전 git diff 로 추가 줄의 타 CSN 번호·고객 식별 문자열을 확인한다(이 레포
  자신의 CSN 과, 분리 이슈·선행 이슈로 공개 참조되는 giip 번호만 허용).
- 엔드포인트(5665)가 배포되기 전까지 폴백은 fail-soft 로만 동작한다(로그만 남고
  현행 동작 유지) — 배포 후 실효가 난다. 이 순서를 이슈와 사양 §19 에 명시했다.
- Phase -2.5 사전 패스로 결정된 CSN 은 처리 대상으로 다음 실행부터 들어간다
  (Phase 1 의 맵 스냅샷이 패스보다 앞). Phase -3 패스 결정분은 이번 실행부터 적용.
- 이 worktree(wt-csnmap)는 PR 머지 후 rule 57 에 따라 정리한다.
