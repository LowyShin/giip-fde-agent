# 작업 기록 — GitHub 디자인 리소스 8종 추천 링크 등록 (giip 5930)

- 일시: 2026-11-20 16:36 JST (Lowy님 지시, 이 채팅)
- 이슈: giip 5930 (CSN 70424)
- 계기: LinkedIn 게시물(이상선, 2026-11-18, "Claude Code를 디자인 스튜디오로
  만들어주는 무료 GitHub 프로젝트")의 링크를 Lowy님이 전달하며, 이 레포에
  소개해도 좋은지 검토해 좋으면 추천 링크에 등록하라고 지시.

## 검토 (2026-11-20, LinkedIn 단축 링크 전수 해석 + GitHub API 실측)

게시물 본문에 링크가 걸린 8개 주소를 전부 실제 주소로 풀어 확인했다.
(DESIGN.md 글자에 걸린 링크는 http://DESIGN.md 로 잘못 걸려 있었고, 옆의
단축 링크가 진짜 레포였다.)

| 리소스 | 스타 | 라이선스 | 최종 갱신 |
|---|---|---|---|
| nextlevelbuilder/ui-ux-pro-max-skill | 151,906 | MIT | 2026-11-19 |
| anthropics/skills (frontend-design·canvas-design·pptx) | 197,816 | Anthropic 공식 공개 레포 | 2026-11-16 |
| google-labs-code/design.md | 28,974 | Apache-2.0 | 2026-11-18 |
| meta/astryx | 31,120 | MIT | 2026-11-20 |
| GLips/Figma-Context-MCP | 16,265 | MIT | 2026-11-15 |
| vercel-labs/agent-browser | 52,940 | Apache-2.0 | 2026-11-20 |

판정: 8종 전부 등록 적합. 근거 — 전부 실재·활성·오픈 라이선스이고,
DESIGN.md 규격은 이 레포 design-md 스킬의 근간 규격 원본, Anthropic 스킬
3종은 이 레포가 이미 도입한 스킬들의 원본(정본 링크 가치), 나머지는
디자인 시스템·Figma 연동·구현 검증으로 디자인 워크플로를 보완한다.
게시물의 "UI UX Pro Max 스타 15만 개 이상" 주장도 실측과 일치했다.

## 변경

- docs/DESIGN_DISCOVERY_GUIDE.md: "GitHub 디자인 리소스 (에이전트용 추천
  링크)" 섹션 신설 (8행 표). 기존 5대 플랫폼 매트릭스는 무변경.
- docs/02-design/DesignMD_Source_Matrix.md: "GitHub Design Resources for
  Agents" 섹션 신설 (영문판 동일 내용).
- docs/WHATS_NEW.md, 이 작업 기록.

등록 위치는 giip 5153(DesignBookmark Motion)과 같은 자리 — 디자인 발견
가이드 2종이 이 레포의 디자이너용 추천 링크 표면이다.
