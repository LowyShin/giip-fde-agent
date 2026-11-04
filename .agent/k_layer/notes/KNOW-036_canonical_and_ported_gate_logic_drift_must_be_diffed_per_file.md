# KNOW-036 — 정본과 이식본의 판정 로직은 "이식 시점 커밋 일치"로 끝나지 않는다 — 뒤늦은 정본 PR 은 이식본에 영구히 따라오지 않는다

> 근거: 2026-11-04 CSN 70424 저장소 정비 99차 세션 실측 · 발행: 2026-11-04 · 상태: 검증됨(두 저장소 파일 직접 대조)

## 요지

이 저장소(`giip-fde-agent`)는 **판정 로직의 정본**이고, 다른 저장소(`lowyworkenv/scripts/gissue`)는
그 로직의 **이식본**이다. 이식할 때 한 번 대조하고 끝내면, **그 뒤 정본에 들어온 PR 은 이식본에
영구히 따라오지 않는다.** "이식 완료" 라는 기록은 **이식 시점의 커밋까지** 일치했다는 뜻일 뿐이다.

그래서 판정 로직이 갈라지면 **두 저장소가 동시에 살아 있고, 나중에 켜진 쪽만 조용히 잘못된다.**
감지는 **커밋이 아니라 파일 내용**(diff) 단위로 해야 한다.

## 사례 (2026-11-04 99차 실측 — `giip 4335` 규칙이 이식본에 없음)

정본은 `giip 4335` 규칙(issue 본문/코멘트에 링크된 PR 도 "레포 스캔 밖 PR" 로 증거로 인정)을
PR #334(공유 라이브러리) + PR #345(비교 스크립트 배선) 로 반영했다. **이식본에는 반영되지 않았다.**

| 확인 지점 | 정본(`giip-fde-agent` origin/main) | 이식본(`lowyworkenv` origin/main) |
|---|---|---|
| `scripts/gissue/gissue-audit-lib.ps1` — `Get-ChecklistPrEvidence` | `($isn, $repos, $LinkTexts = @())` | `($isn, $repos)` |
| 같은 파일 — `Test-IssueHasPr` / `Test-IssueHasMergedPr` | `$LinkTexts` 선택 인자 있음 | **없음** |
| `scripts/gissue/compare-checklist-vs-legacy.ps1` | 110-111행에 `$linkTexts` 배선 | **배선 없음**(109행이 곧바로 2인자 호출) |
| `scripts/gissue/pr-gate-sweep.ps1` — 증거 수집 호출 | `$linkTexts` 를 넘김 | **2인자 호출만** |

대조 명령(두 저장소 중 어느 쪽이든 **경로가 다른** 같은 파일을 `git show origin/main:<path>` 로
받아 **바이트 diff** 한다 — 커밋 해시 비교는 이식본에 없는 커밋 때문에 조용히 실패한다:

```bash
# 정본
git -C <canonical> show origin/main:scripts/gissue/gissue-audit-lib.ps1 > /tmp/a.ps1
# 이식본
git -C <port>     show origin/main:scripts/gissue/gissue-audit-lib.ps1 > /tmp/b.ps1
diff /tmp/a.ps1 /tmp/b.ps1
```

> Git Bash 에서 `git show origin/main:<path>` 를 쓸 때는 `MSYS2_ARG_CONV_EXCL="*"` 를 먼저 설정한다
> (없으면 `origin\main;path` 로 깨진다).

### 영향

이식본에서 **제품 레포(giipv3/giipdb/giipfaw 등) PR 이 이슈 본문·코멘트의 링크로만 남은 경우**,
체크리스트 판정이 그 PR 을 증거로 인식하지 못한다 → 의뢰 항목이 미충족으로 판정될 수 있다 →
되돌림(REVERT) 오판의 입력. 판정 로직을 **Live 로 켠 호스트에서 특히 위험**하다.

## 규칙

1. **이식 여부의 판정 단위는 커밋이 아니라 파일 diff 다.** "이식 PR 이 머지됐다" 는 사실이
   "이식본이 정본과 같다" 를 뜻하지 않는다.
2. **정본에 PR 이 하나라도 더 들어간 뒤에는 이식본 대조를 다시 돌린다.** 대조는 같은 저장소 쌍의
   **같은 파일 경로** 를 양쪽에서 뽑아 diff 한다(아래 감지 절차).
3. **이식본이 더 오래된 파일을 "통과한 상태"로 두지 않는다.** 판정 로직이 갈라진 채로는
   "정본 기준선 확정" 이라는 표현이 성립하지 않는다 — 어느 쪽이 기준선인지 먼저 정한다.
4. **파일:라인 인용은 substance 판정과 분리한다.** 다른 세션 기록이 인용한 행 번호는 파일이 바뀌면
   어긋난다 → **행 번호가 틀려도 substance(그 기능이 존재하는가)가 참이면 오진단이 아니다.**
   반대로 substance 가 거짓이면 행 번호와 무관하게 오진단이다.
5. **공개 저장소 기록에는 다른 환경의 CSN 번호를 넣지 않는다.** 대조 대상이 다른 CSN 이면
   저장소·파일 경로로만 기술한다(저장소 자기 CSN 기재는 예외).

## 감지 절차 (이식 대조)

1. 정본에서 **판정 로직 파일 목록**을 뽑는다(예: `scripts/gissue/gissue-audit-lib.ps1` ·
   `scripts/gissue/pr-gate-sweep.ps1` · `scripts/gissue/compare-checklist-vs-legacy.ps1`).
2. 같은 경로를 이식본에서 뽑아 **바이트 diff** 한다.
3. 차이가 있으면 **정본 쪽이 기준선**인지 이식본 쪽이 기준선인지 먼저 정한 뒤,뒤처진 쪽을 갱신한다.
4. 갱신 후 같은 diff 를 **0건**으로 만든다. 남은 차이는 "의도적 차이" 라고 **근거와 함께** 남긴다.

## 관련

- `KNOW-046` (lowyworkenv) — 이식된 판정 로직이 로컬 집계·쓰기 경로와 달라야 한다(이식 대조의 큰 틀)
- `KNOW-016` — 되돌림 판정의 단위는 "PR 유무" 가 아니라 의뢰 항목 이행 여부
- `KNOW-028` — 기록의 규칙 인용은 이 저장소에 실제로 존재하는 파일명만 쓴다
- 정본 `scripts/gissue/gissue-audit-lib.ps1` · `scripts/gissue/pr-gate-sweep.ps1` ·
  `scripts/gissue/compare-checklist-vs-legacy.ps1`
- 이식본 `lowyworkenv/scripts/gissue/` 하위 동명 파일들
