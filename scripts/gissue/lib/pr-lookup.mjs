/**
 * pr-lookup.mjs — "이 giip isn 에 대응하는 PR 이 있는가" 판정 (Node 쪽 정본)
 *
 * 배경 (giip #2464, 2026-09-14):
 *   대시보드 ③층 "막힌 이슈"의 `REVIEW_NO_PR` 배지는 giipdb SP
 *   `pApiGIIPDashboardBlockedIssuesbyAK` → `tAuditReviewPrsResult(has_pr=0)` 에서 나오고,
 *   그 테이블을 채우는 것은 `run-audit-review-prs.ps1` → **`audit-review-prs.mjs`** 다.
 *   그런데 이 mjs 의 판정은 `gh pr list --head bot/task-giip-<isn>` **정확 브랜치 1회 조회뿐**이었다.
 *   실제 오늘자 PR 브랜치는 `fix/giip-2438-2440-junction-exception`, `feat/giip-2445-...` 형태라
 *   MERGED 된 PR 이 멀쩡히 있는데도 전부 has_pr=0 으로 적재됐다(2026-09-14 실측: csn 47
 *   REVIEW 29건 중 23건이 "PR 없음"으로 적재).
 *
 *   같은 판정을 하는 PowerShell 쪽(`gissue-audit-lib.ps1` 의 `Test-IssueHasPr`)은 giip #2077/#2083
 *   에서 이미 (a) 넓은검색 폴백 (b) PR 본문(body) 매칭 (c) lowyworkenv 저장소 포함 을 갖췄는데,
 *   Node 쪽 감사기만 그 보강을 못 받아 **두 탐지기의 기준이 갈라져 있었다**. 이 모듈은 그 PowerShell
 *   판정 로직을 Node 로 그대로 옮긴 것이다 — 새 기준을 창작하지 않는다.
 *
 * 판정 순서(Test-IssueHasPr 와 동일):
 *   1) 정확한 head 브랜치 `bot/task-giip-<isn>` 매치 (가장 신뢰도 높음, 이 코드베이스의 브랜치 규약)
 *   2) 넓은 검색 `gh pr list --state all --search "giip-<isn>"` 폴백 →
 *      GitHub 검색은 토큰 기반이라 무관한 PR 도 섞여 오므로 아래 정규식으로 **반드시 재필터**한다:
 *        - headRefName / title : /(?<!\d)<isn>(?!\d)/   (숫자 경계 — 2438 이 24380/12438 에 안 걸림)
 *        - body                : /#<isn>(?!\d)/         (본문은 자유 텍스트라 "#<isn>" 관용표기만)
 *
 * ⚠️ 재필터를 빼면 "PR 없는 이슈도 PR 있음"으로 뒤집혀 게이트가 무력화된다. 회귀 테스트는
 *    `scripts/gissue/tests/test-pr-lookup.mjs` (양방향: 있는 PR 은 찾고, 없는 PR 은 못 찾는다).
 */
import { spawnSync } from 'node:child_process';

/** gh 호출 시 봇 PAT 이 아니라 gh 자체 로그인(SHINSEMA 조직 권한)을 쓰도록 토큰 env 를 제거한다. */
function ghEnv() {
  const env = { ...process.env };
  delete env.GITHUB_TOKEN;
  delete env.GH_TOKEN;
  return env;
}

/**
 * repoSpec 을 gh 호출 방식으로 해석한다 (giip #2504).
 *
 * - 로컬 체크아웃 절대경로  → 그 디렉터리를 cwd 로 두고 호출(기존 동작).
 * - `slug:OWNER/REPO`      → cwd 와 무관하게 `--repo OWNER/REPO` 로 호출.
 *
 * 후자가 필요한 이유: giipAgentLinux 처럼 giip 이슈의 산출물 PR 이 올라가지만 어느 프로젝트
 * workdir 아래에도 clone 되지 않은 레포가 있다. 로컬 경로 기반 탐색만으로는 그 PR 이 영원히
 * 안 잡혀 "PR 없음"으로 REVIEW 가 되돌려진다(2026-09-14 실측: giip #2477 ↔ giipAgentLinux #33).
 */
function parseRepoSpec(repoSpec) {
  const s = String(repoSpec || '');
  const m = /^slug:(.+)$/.exec(s);
  if (m) return { cwd: undefined, extraArgs: ['--repo', m[1].trim()] };
  return { cwd: s, extraArgs: [] };
}

function runGh(repoSpec, args) {
  const { cwd, extraArgs } = parseRepoSpec(repoSpec);
  const r = spawnSync('gh', [...args, ...extraArgs], { cwd, encoding: 'utf8', windowsHide: true, env: ghEnv() });
  if (r.status !== 0) return { ok: false, rows: [], err: (r.stderr || '').trim().slice(0, 160) };
  try { return { ok: true, rows: JSON.parse(r.stdout || '[]') }; }
  catch { return { ok: false, rows: [], err: 'json parse' }; }
}

/**
 * 이 PR 이 **자기가 어느 giip 이슈의 산출물인지 브랜치명/제목으로 이미 선언**하고 있는가.
 *
 * 이 코드베이스의 PR 관행은 브랜치 `bot/task-giip-<isn>` / `fix/giip-<isn>-…` 또는 제목
 * `… (giip #<isn>)` 로 담당 이슈를 밝히는 것이다. 그렇게 선언한 PR 의 **본문에 등장하는 다른
 * 이슈 번호는 "참조"이지 "그 이슈의 산출물"이 아니다.**
 *
 * 왜 필요했나(giip #2464 후속, 2026-09-14 실측 오탐): body 매칭을 무조건 적용했더니, 이 갭을
 * 고친 PR #750 이 본문에 증거로 인용한 `#2456`/`#2457`(둘 다 실제로 PR 이 없는 이슈)까지
 * "PR 있음"으로 뒤집혀 대시보드에서 사라졌다. 이는 "진짜 미완료 이슈를 놓치는" 방향의 오탐이라
 * 오히려 REVIEW_NO_PR 오탐보다 위험하다.
 *
 * 반대로 giip #2077 (2) 가 살리려던 케이스 — 브랜치/제목에 이슈번호가 **전혀 없고** 본문에만
 * `#<isn>` 이 있는 PR(예: PR #666, 브랜치 `fix/gissue-audit-pr-body-match`) — 은 여기서
 * `false` 가 나오므로 body 폴백이 그대로 적용된다. 두 요구가 모두 만족된다.
 */
export function prDeclaresIssue(pr) {
  const decl = /giip[\s#_-]*\d{3,6}(?!\d)/i;
  if (pr.headRefName && decl.test(pr.headRefName)) return true;
  if (pr.title && decl.test(pr.title)) return true;
  return false;
}

/**
 * 넓은검색 결과 1건이 이 isn 에 실제로 대응하는지 재필터.
 * Test-IssueHasPr 의 `$isnRe` / `$isnBodyRe` 규칙 + 위 `prDeclaresIssue` 좁히기.
 */
export function prMatchesIsn(pr, isn) {
  const nameRe = new RegExp(`(?<!\\d)${isn}(?!\\d)`);
  const bodyRe = new RegExp(`#${isn}(?!\\d)`);
  if (pr.headRefName && nameRe.test(pr.headRefName)) return true;
  if (pr.title && nameRe.test(pr.title)) return true;
  // body 폴백은 "담당 이슈를 브랜치/제목으로 선언하지 않은 PR" 에 한해 적용한다.
  if (prDeclaresIssue(pr)) return false;
  if (pr.body && bodyRe.test(pr.body)) return true;
  return false;
}

/**
 * 한 레포에서 이 isn 에 대응하는 PR 목록을 찾는다(open/merged/closed 전부).
 * @returns {{ok: boolean, prs: Array, how: 'exact'|'broad'|'none', err?: string}}
 *   how = 어떤 경로로 찾았는지(로그/증적용).
 */
export function findIssuePrsInRepo(repoRoot, isn) {
  // 1) 정확한 head 브랜치
  const exact = runGh(repoRoot, ['pr', 'list', '--head', `bot/task-giip-${isn}`,
    '--state', 'all', '--json', 'number,state,url,title,headRefName', '--limit', '10']);
  if (exact.ok && exact.rows.length) return { ok: true, prs: exact.rows, how: 'exact' };

  // 2) 넓은 검색 폴백 + 정규식 재필터
  const broad = runGh(repoRoot, ['pr', 'list', '--state', 'all', '--search', `giip-${isn}`,
    '--json', 'number,state,url,title,headRefName,body', '--limit', '30']);
  if (!broad.ok) {
    // exact 도 실패했으면 그 에러를 우선 보고(레포 접근 자체가 안 되는 상황).
    return { ok: exact.ok, prs: [], how: 'none', err: exact.err || broad.err };
  }
  const hits = broad.rows.filter((pr) => prMatchesIsn(pr, isn))
    // body 는 수십 KB 가 될 수 있어 호출부(JSON 보존/DB 적재)로 흘려보내지 않는다.
    .map(({ body, ...rest }) => rest);
  if (hits.length) return { ok: true, prs: hits, how: 'broad' };
  return { ok: true, prs: [], how: 'none' };
}
