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

/** PR 상태 등급(정본). 0=가장 우선. */
const STATE_RANK = { MERGED: 0, OPEN: 1, CLOSED: 2 };

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

/**
 * gh 실행 주입점 — **테스트 전용**.
 *
 * 왜 필요한가: gh 를 진짜로 부르면 회귀 테스트가 네트워크·인증에 의존한다(PATH 에 가짜 gh 를 끼우면
 * OS 별 동작이 달라 Windows CI 에서 깨진다 — 실측 2026-11-11). 그래서 gh 호출을 한 함수로 모으고
 * 테스트가 그 자리를 갈아끼우게 한다. 프로덕션 경로는 그대로 spawnSync 다.
 *
 * 주입 함수 계약: (args: string[], cwd?: string) => { ok: boolean; rows: any[]; err?: string }
 */
let ghSpawn = null;

/** 테스트에서만 쓰는 gh 주입기. null 을 넣으면 원래의 spawnSync 로 돌아간다. */
export function setGhSpawn(fn) { ghSpawn = typeof fn === 'function' ? fn : null; }

/** gh 를 실행해 JSON 행 배열로 돌려준다(성공/실패를 예외 대신 값으로 표현). */
function execGh(args, cwd) {
  if (ghSpawn) {
    try {
      const r = ghSpawn(args, cwd);
      if (!r || typeof r !== 'object') return { ok: false, rows: [], err: 'no result' };
      return { ok: r.ok !== false, rows: Array.isArray(r.rows) ? r.rows : [], err: r.err || '' };
    } catch (e) {
      return { ok: false, rows: [], err: (e && e.message ? e.message : String(e)).slice(0, 160) };
    }
  }
  const r = spawnSync('gh', args, { cwd, encoding: 'utf8', windowsHide: true, env: ghEnv() });
  if (r.status !== 0) return { ok: false, rows: [], err: (r.stderr || '').trim().slice(0, 160) };
  try {
    const rows = JSON.parse(r.stdout || '[]');
    // gh 가 객체 1건(배열 아닌 JSON)만 주면 1행짜리 배열로 감싼다. null/스칼라는 행 배열이 아니다 →
    // 호출부가 .map/.filter 를 못 하므로 빈 배열로 정규화한다(생성자 crash 방지).
    if (Array.isArray(rows)) return { ok: true, rows };
    if (rows && typeof rows === 'object') return { ok: true, rows: [rows] };
    return { ok: true, rows: [] };
  } catch { return { ok: false, rows: [], err: 'json parse' }; }
}

function runGh(repoSpec, args) {
  const { cwd, extraArgs } = parseRepoSpec(repoSpec);
  return execGh([...args, ...extraArgs], cwd);
}

/**
 * cwd/--repo 스코프가 없는 gh 호출(조직 전 검색처럼 레포 스코프가 없는 명령).
 * `runGh` 는 로컬 경로면 cwd 를 잡기 때문에 조직 전 검색에는 쓸 수 없다.
 */
function runGhRaw(args) {
  return execGh(args, undefined);
}

/** gh search 결과의 `repository` 필드에서 owner/repo 슬러그를 뽑는다. */
function slugFromRepository(repo) {
  if (!repo) return '';
  if (typeof repo === 'string') return repo;
  return repo.fullName || repo.nameWithOwner || (repo.owner && repo.name ? `${repo.owner.login}/${repo.name}` : '');
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
  if (!pr || !isn) return false;
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

// ════════════════════════════════════════════════════════════════════════════
// [giip #4840/#4839] 증거 기반 귀속 — 브랜치명 / PR 제목·본문 / 커밋 메시지 3면
//
// 왜 이 구역이 생겼나 (2026-11-11 실측):
//   "대응 PR 없음" 되돌림이 27건 이상 누적됐다. 근본 원인은 귀속(attribution) 탐색면이
//   **기대 head 브랜치(`bot/task-giip-<isn>`) 1개**에 묶여 있었기 때문이다.
//   실제로는 (a) 다른 브랜치명(`docs/giip-4219-…`), (b) 다른 레포(제품 레포/스케줄러 레포),
//   (c) 수동 PR, (d) 커밋 메시지에만 isn 이 있는 PR 이 전부 "PR 없음"으로 오판됐다.
//
// 탐색면 4개(요구사항):
//   1) 브랜치명      : 기대 브랜치(`head:` 한정) + 레포 브랜치 열거로 isn 을 담는 브랜치 전부
//   2) PR 제목/본문   : `gh search prs --owner <org>` (조직 전 레포)
//   3) 커밋 메시지    : `gh search commits --owner <org>` → 커밋에 딸린 PR
//   4) 이슈 코멘트의 PR 링크 : PowerShell 쪽(Get-PrLinksFromText) — 이 파일은 다루지 않는다
// ════════════════════════════════════════════════════════════════════════════

/**
 * 이 PR 이 **이 isn 을 담당한다**고 브랜치/제목으로 선언하는가(강한 귀속 증거).
 *
 * `prDeclaresIssue`(어떤 giip 이슈든 선언했는가)와 다른 점: 여기서는 **이 isn** specifically 를 본다.
 * 대표 PR 선택에서 "본문에다만 isn 을 인용한 PR"(참조)보다 "브랜치/제목으로 이 isn 을 선언한 PR"을
 * 먼저 고르기 위해 쓴다 — giip #4840(판정 대상이 아닌 PR을 근거로 한 오탐)의 직접 원인.
 */
export function prDeclaresIsn(pr, isn) {
  if (!pr || !isn) return false;
  const nameRe = new RegExp(`(?<!\\d)${isn}(?!\\d)`);
  return Boolean((pr.headRefName && nameRe.test(pr.headRefName)) || (pr.title && nameRe.test(pr.title)));
}

/**
 * 커밋 메시지가 이 isn 을 giip 컨벤션으로 참조하는가.
 * 허용: `giip 4840` / `giip-4840` / `giip#4840` / `giip:4840` / `#4840`.
 * 거부: `giip 48401`(숫자 경계), `4840` 단독(다른 숫자일 수 있음).
 */
export function commitMatchesIsn(message, isn) {
  if (!message || !isn) return false;
  // JS 정규식에 `(?i)` 인라인 플래그는 없다 — `i` 플래그로 준다(.NET habit 금지).
  const giipRe = new RegExp(`giip[\\s#:_-]*${isn}(?!\\d)`, 'i');
  const hashRe = new RegExp(`#${isn}(?!\\d)`);
  return giipRe.test(message) || hashRe.test(message);
}

/** 브랜치명이 이 isn 을 담는가(숫자 경계). */
export function branchMatchesIsn(branch, isn) {
  if (!branch || !isn) return false;
  return new RegExp(`(?<!\\d)${isn}(?!\\d)`).test(branch);
}

/** repoSpec(로컬 경로 또는 `slug:OWNER/REPO`)에서 owner/repo 슬러그를 얻는다. 실패 시 null. */
export function repoSlugOf(repoSpec) {
  const s = String(repoSpec || '');
  const m = /^slug:(.+)$/.exec(s);
  if (m) return m[1].trim();
  if (!s) return null;
  const r = spawnSync('git', ['-C', s, 'remote', 'get-url', 'origin'], { encoding: 'utf8', windowsHide: true });
  if (r.status !== 0) return null;
  const url = String(r.stdout || '').trim();
  const mm = /github\.com[:/]([^/]+\/[^/]+?)(?:\.git)?$/i.exec(url);
  return mm ? mm[1] : null;
}

/**
 * 레포 1개의 **브랜치명**으로 이 isn 의 PR 을 찾는다.
 *
 * 왜 필요한가: GitHub 검색은 PR 제목/본문/댓글만 색인한다 — **브랜치명은 색인되지 않는다.**
 * 그래서 `gh pr list --search "giip-<isn>"` 로는 `docs/giip-4219-…` 같은 브랜치의 PR 을
 * 제목/본문에 isn 이 없으면 못 잡는다(실측 2026-11-11). 브랜치를 직접 열거해서
 * `gh pr list --head <브랜치>` 로 질의해야 잡힌다.
 *
 * @returns {{ok: boolean, prs: Array, how: 'branch'|'none', errors: string[]}}
 */
export function findIssuePrsByBranchInRepo(repoSpec, isn, opts = {}) {
  const slug = repoSlugOf(repoSpec);
  if (!slug) return { ok: false, prs: [], how: 'none', errors: [`slug 확인 실패: ${repoSpec}`] };
  const perPage = opts.perPage || 100;
  const maxBranches = opts.maxBranches || 10;
  const errors = [];
  const res = runGhRaw(['api', `repos/${slug}/branches?per_page=${perPage}`]);
  if (!res.ok) return { ok: false, prs: [], how: 'none', errors: [`branches: ${res.err}`] };
  const branches = res.rows.map((b) => b && b.name).filter((n) => branchMatchesIsn(n, isn));
  const prs = [];
  for (const b of branches.slice(0, maxBranches)) {
    const r = runGh(`slug:${slug}`, ['pr', 'list', '--head', b, '--state', 'all',
      '--json', 'number,state,url,title,body,headRefName', '--limit', '20']);
    if (!r.ok) { errors.push(`pr list --head ${b}: ${r.err}`); continue; }
    for (const row of r.rows) {
      if (!Number.isInteger(row.number) || row.number <= 0) continue;
      prs.push({
        number: row.number, state: String(row.state || '').toUpperCase(), url: row.url || '',
        title: row.title || '', body: row.body || '', headRefName: row.headRefName || '',
        slug, repo: `slug:${slug}`, how: 'branch',
      });
    }
  }
  return { ok: true, prs, how: prs.length ? 'branch' : 'none', errors };
}

/**
 * **조직 전 레포**에서 이 isn 의 PR 을 찾는다. 탐색면: PR 제목/본문 + 커밋 메시지 + 규약 브랜치.
 *
 * 왜 필요한가: `Get-NestedRepoPaths` 는 "workdir + 바로 아래 nested + 이 레포 자신 + 수동 등록 목록"
 * 뿐이다. 제품 레포(SHINSEMA/giipv3 등)나 다른 프로젝트 레포에 올라간 PR 은 **어떤 탐지기에도**
 * 안 잡혀 "PR 없음"으로 REVIEW 가 되돌려졌다(giip #4335/#4840 실측).
 *
 * 비용控制: 조직 1개당 PR 검색 4회(질의 2종 × 상태 2종) + 커밋 검색 2회 + 커밋별 PR 조회(상한).
 * 규약 브랜치(`bot/task-giip-<isn>`)는 `head:` 한정으로 1회에 조직 전을 훑는다.
 * **조직의 모든 브랜치를 열거하지는 않는다**(LowyShin 조직은 272개 레포 — 무한대 비용).
 * 비규약 브랜치(`docs/giip-4219-…`)는 ①커밋 메시지 경로 ②제목/본문 경로로 잡힌다.
 *
 * @returns {{ok: boolean, prs: Array, sources: string[], errors: string[]}}
 */
export function findIssuePrsInOrg(org, isn, opts = {}) {
  const limit = opts.limit || 50;
  const maxCommits = opts.maxCommits || 10;
  const prs = [];
  const sources = [];
  const errors = [];
  const seen = new Set();
  const add = (pr, how) => {
    if (!pr || !Number.isInteger(pr.number) || pr.number <= 0) return;
    const slug = pr.slug || '';
    const key = `${slug}#${pr.number}`;
    if (seen.has(key)) return;
    seen.add(key);
    const { body, ...rest } = pr;
    prs.push({ ...rest, slug, how });
    if (!sources.includes(how)) sources.push(how);
  };

  // ── (1) PR 제목/본문 (조직 전 레포) ──
  // GitHub 검색은 제목·본문·댓글을 색인한다. 질의는 `giip-<isn>`(하이픈/공백 모두 토큰 분리된다)와
  // `#<isn>` 두 종을 쓴다 — 하나만 쓰면 "#4334" 만 쓴 PR 을 놓친다.
  for (const q of [`giip-${isn}`, `#${isn}`]) {
    for (const state of ['open', 'closed']) {
      const res = runGhRaw(['search', 'prs', q, '--owner', org, '--state', state,
        '--limit', String(limit), '--json', 'number,state,url,title,body,repository']);
      if (!res.ok) { errors.push(`search prs "${q}"(${state}): ${res.err}`); continue; }
      for (const row of res.rows) {
        const pr = {
          number: row.number, state: String(row.state || '').toUpperCase(), url: row.url || '',
          title: row.title || '', body: row.body || '', headRefName: '', slug: slugFromRepository(row.repository),
        };
        // 재필터는 정본 규칙(prMatchesIsn)을 그대로 쓴다 — 본문 폴백은 "담당 이슈를 선언하지 않은 PR" 에만.
        if (!prMatchesIsn(pr, isn)) continue;
        add(pr, 'org-pr');
      }
    }
  }

  // ── (2) 커밋 메시지 → 연관 PR ──
  const seenCommits = new Set();
  for (const q of [`giip-${isn}`, `#${isn}`]) {
    const res = runGhRaw(['search', 'commits', q, '--owner', org, '--limit', String(maxCommits),
      '--json', 'sha,url,repository,commit']);
    if (!res.ok) { errors.push(`search commits "${q}": ${res.err}`); continue; }
    for (const row of res.rows) {
      const msg = (row.commit && row.commit.message) || '';
      if (!commitMatchesIsn(msg, isn)) continue;
      const slug = slugFromRepository(row.repository);
      if (!slug || !row.sha) continue;
      const ckey = `${slug}@${row.sha}`;
      if (seenCommits.has(ckey)) continue;
      seenCommits.add(ckey);
      const prRes = runGhRaw(['api', `repos/${slug}/commits/${row.sha}/pulls`]);
      if (!prRes.ok) { errors.push(`commits/${row.sha}/pulls: ${prRes.err}`); continue; }
      for (const p of prRes.rows) {
        const headSha = p && p.head && p.head.sha ? p.head.sha : '';
        const headRef = p && p.head && p.head.ref ? p.head.ref : '';
        const subject = { headRefName: headRef, title: p.title || '' };
        const declaresThis = prDeclaresIsn(subject, isn);
        // 다른 이슈를 선언한 PR(브랜치/제목에 다른 giip 이슈가 있음)은 이 isn 의 **참조**다 —
        // 커밋 메시지에 이 isn 이 인용돼 있어도 담당 산출물로 삼지 않는다(giip #2464 정본 규칙과 동일).
        if (!declaresThis && prDeclaresIssue(subject)) continue;
        // 이 커밋이 PR 의 head 커밋이거나, PR 이 이 isn 을 선언할 때만 후보로 쓴다.
        // (그 외에는 "이 커밋을 포함한 무관한 PR" 이 후보가 되는 오탐이다.)
        if (headSha !== row.sha && !declaresThis) continue;
        add({
          number: p.number, state: p.merged_at ? 'MERGED' : String(p.state || '').toUpperCase(),
          url: p.html_url || '', title: p.title || '', body: p.body || '',
          headRefName: headRef, slug, repo: `slug:${slug}`,
        }, 'org-commit');
      }
    }
  }

  // ── (3) 규약 head 브랜치 (조직 어디서든) ──
  // `head:` 한정 검색은 정확한 브랜치명만 찾지만, 그 제약이 "이 isn 의 PR" 을 확정해 준다.
  const headRes = runGhRaw(['search', 'prs', '--owner', org, '--limit', String(limit),
    '--json', 'number,state,url,title,body,repository', '--', `head:bot/task-giip-${isn}`]);
  if (!headRes.ok) errors.push(`search prs head:: ${headRes.err}`);
  else {
    for (const row of headRes.rows) {
      add({
        number: row.number, state: String(row.state || '').toUpperCase(), url: row.url || '',
        title: row.title || '', body: row.body || '', headRefName: `bot/task-giip-${isn}`,
        slug: slugFromRepository(row.repository),
      }, 'org-branch');
    }
  }

  return { ok: errors.length === 0 || prs.length > 0, prs, sources, errors };
}


/**
 * 대표 PR(판정 대상) 선택 규칙 — **정본**(CLI/대시보드가 공유한다).
 *
 * 1) **이 isn 을 브랜치/제목으로 선언한 PR** 우선 — 본문에만 isn 을 인용한 PR 은 "참조"이지 담당
 *    산출물이 아니다(giip #4840: 인용만 한 PR 을 판정 대상으로 삼으면 무관한 diff 로 scope MISMATCH →
 *    잘못된 되돌림).
 * 2) MERGED > OPEN > CLOSED (이미 머지된 PR 이 실제 완료 여부 판정에 정확하다).
 * 3) PR 번호 큰 쪽(더 최근).
 *
 * @param {Array} prs 후보 배열 @param {number} isn
 * @returns {object|null} 대표 PR
 */
export function selectPrimaryPr(prs, isn) {
  const list = (prs || []).filter((p) => p && Number.isInteger(p.number) && p.number > 0);
  if (list.length === 0) return null;
  const rank = (pr) => {
    const declares = prDeclaresIsn(pr, isn) ? 0 : 1;
    const s = String(pr.state || '').toUpperCase();
    const state = Object.prototype.hasOwnProperty.call(STATE_RANK, s) ? STATE_RANK[s] : 3;
    return [declares, state, -Number(pr.number || 0)];
  };
  const sorted = list.slice().sort((a, b) => {
    const ra = rank(a);
    const rb = rank(b);
    for (let i = 0; i < ra.length; i++) if (ra[i] !== rb[i]) return ra[i] - rb[i];
    return 0;
  });
  return sorted[0];
}
