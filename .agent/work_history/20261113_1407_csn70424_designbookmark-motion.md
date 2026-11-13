# 작업 기록 — DesignBookmark Motion을 디자인 소스 5번째로 편입 (giip 5153)

- 일시: 2026-11-13 14:07 JST
- 근거: 사용자 직접 지시 — designbookmark.com/motion 을 공유하며 "giip-fde-agent 이용자 중
  디자이너에게 도움이 되니 AI FDE 활용 대상으로 추가"하라고 함. 등록 이슈 giip 5153
  (PENDING · 상세 페이지 재확인済).

## 사실 확인 (2026-11-13, 사이트 직접 열람)

- 루트: "DesignBookmark, All-in-one design resources for designers" — 디자이너용 리소스
  큐레이션 사이트.
- `/motion`: "Animated components, running live. Copy one for Claude or Codex, paste it
  into your project, and it builds it for you." 라이브 애니메이션 컴포넌트 약 48종
  (Letter limit, Pull cord, Morph tooltip, Spring dropdown, File drop, Command button,
  Morph island, Jelly slider, Hold to publish, Swipe deck, Springy input, Rubber dock,
  Parallax ticket, Glass lens, Pull to refresh, Word roll, Weight wave, Goo morph,
  Scramble text, Read along, Roll links, Prompt box, Streaming reply, Ghost suggestion,
  Goo thinking, Expand card, Fan cards, Stat card, Profile card, Magnetic button,
  Loading to success, Copy button, Like burst, Tab pill, Bottom bar, Segmented control,
  Command palette, Step progress, OTP code, Toggle switch, Star rating, Tag input,
  Number stepper, Range slider, Password strength, Checkbox list).
- 성격 판단: 사람이 눈으로 보는 갤러리가 아니라, Claude/Codex 같은 AI 코딩 에이전트가
  복사 명세를 받아 구현하는 **에이전트 소비형 모션 소스**. 기존 4종(designmd.ai/.app,
  getdesign.md, designmd.me)이 디자인 시스템(토큰 · 스타일) 소스인 것과 역할이 겹치지
  않는다 — 이 소스는 "움직임"만 담당한다.

## 변경 파일 (5건)

1. `.agent/skills/design-md/SKILL.md` — frontmatter 설명에 designbookmark.com 추가 +
   소스 선택표에 Motion 행 + 스카우팅 단계 4번(Motion Check) + Selection & Setup 지침
   (복사 명세의 스프링 · 타이밍 · 이징을 그대로 따를 것, 미리보기로 어림 금지).
2. `docs/DESIGN_DISCOVERY_GUIDE.md` — 4대→5대 플랫폼, 매트릭스 행, 활용법 5번
   "모션 컴포넌트 적용하기" 신설 (DESIGN.md 토큰 우선 경계 포함).
3. `docs/02-design/DesignMD_Source_Matrix.md` — 행 + 추천 사례 추가.
4. `docs/WHATS_NEW.md` — 2026-11-13 항목 추가.
5. 이 작업 기록.

## 검증

- 커밋 전 `git diff` 로 추가 줄에 고객 식별 문자열 · 타 CSN 번호가 없는지 확인한다
  (외부 사이트의 공개 사실과 URL만 기재).
- 상대 링크(designbookmark.com 외부 링크 · work_history 상대 링크) 확인.
- 이 작업의 worktree(`wt-designbookmark`)는 PR 머지 후 rule 57 에 따라 정리한다.
