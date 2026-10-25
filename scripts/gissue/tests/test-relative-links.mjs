#!/usr/bin/env node
/**
 * test-relative-links.mjs — 상대링크 스캐너 회귀 테스트 (2026-10-25 CSN 70424 저장소 정비 51차)
 *
 * 왜 이 테스트가 필요한가:
 *   43~50차 정비 세션이 매번 다른 스캐너로 상대링크를 세어 기준선이 11↔34 사이를 흔들렸다.
 *   스캐너를 저장소 정규본으로 고정했으므로 이제 **그 스캐너의 판정 규칙 자체를** 고정해야 한다.
 *   규칙이 조용히 바뀌면 "스캔 결과 0건" 이나 "결함 N건" 이 틀린 근거로 다음 세션에 인계된다.
 *
 * 고정하는 규칙:
 *   ① 코드 펜스(```) 안의 링크는 링크가 아니라 "깨진 링크의 예시" 다 → 결함 아님
 *   ② 인라인 코드 스팬(`) 안의 링크도 동일 → 결함 아님
 *   ③ 템플릿 디렉터리(.agent/templates/, .agent/skills/bkit-templates/) 아래의 미존재 링크
 *      → 스캐폴딩(예외). 디렉터리 단위 판정이며 파일 단위 allowlist 가 아니다.
 *   ④ 그 외 미존재 상대링크 → 실제 결함
 *   ⑤ 링크 기준은 "링크가 있는 파일의 위치"다 (KNOW-011) —
 *      `../` 는 링크가 있는 파일의 디렉터리의 부모를 가리킨다.
 *
 * 실행: node scripts/gissue/tests/test-relative-links.mjs
 * 종료코드: 0 = 전부 통과 / 1 = 실패 있음
 */
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  stripCode, extractRelativeLinks, isRelativeTarget, cleanTarget, scanRelativeLinks,
} from '../lib/relative-links.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));

let pass = 0, fail = 0;
function check(name, actual, expected) {
  if (JSON.stringify(actual) === JSON.stringify(expected)) {
    pass++; console.log(`  PASS  ${name}`);
  } else {
    fail++; console.log(`  FAIL  ${name} — expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
  }
}

console.log('\n=== 단위: stripCode (코드 펜스/인라인 스팬 제거) ===');
const stripSrc = [
  '위 텍스트 [A](../a.md) 링크',
  '',
  '```markdown',
  '[B](../b.md) 는 코드 예시',
  '```',
  '',
  '인라인 `[C](../c.md)` 예시',
].join('\n');
const stripped = stripCode(stripSrc);
check('펜스 안의 줄은 빈 줄로 대체(라인 번호 보존)', stripped[3], '');
check('펜스 안의 링크 텍스트가 사라짐', stripped[3].includes('b.md'), false);
check('일반 텍스트의 링크는 남음', stripped[0].includes('a.md'), true);
check('인라인 스팬 안의 링크는 사라짐', stripped[5].includes('c.md'), false);
check('줄 수가 유지됨(라인 번호 왜곡 없음)', stripped.length, 7);

console.log('\n=== 단위: isRelativeTarget ===');
check('상대 경로 링크는 대상', isRelativeTarget('../a.md'), true);
check('같은 디렉터리 링크도 대상', isRelativeTarget('a.md'), true);
check('https 는 제외', isRelativeTarget('https://x.com/a.md'), false);
check('mailto 는 제외', isRelativeTarget('mailto:a@b.c'), false);
check('앵커만 은 제외', isRelativeTarget('#section'), false);
check('루트 절대경로는 제외', isRelativeTarget('/a.md'), false);
check('Windows 절대경로는 제외', isRelativeTarget('C:/a.md'), false);
check('file: URL 은 제외', isRelativeTarget('file:///a.md'), false);

console.log('\n=== 단위: cleanTarget ===');
check('앵커 제거', cleanTarget('../a.md#sec'), '../a.md');
check('쿼리 제거', cleanTarget('../a.md?x=1'), '../a.md');
check('제목 부분 제거', cleanTarget('../a.md "제목"'), '../a.md');
check('꺾쇠 괄호 경로', cleanTarget('<../a b.md>'), '../a b.md');

console.log('\n=== 단위: extractRelativeLinks (코드 제외) ===');
const links = extractRelativeLinks([
  '실제 링크 [X](../x.md) 여기',
  '```',
  '코드 예시 [Y](../y.md) 여기',
  '```',
  '인라인 `[Z](../z.md)` 예시',
].join('\n'));
const targets = links.map(l => l.target).sort();
check('코드 펜스 안의 링크는 추출되지 않음', targets.includes('../y.md'), false);
check('인라인 스팬 안의 링크는 추출되지 않음', targets.includes('../z.md'), false);
check('일반 링크는 추출됨', targets.includes('../x.md'), true);

console.log('\n=== 통합: 임시 저장소 스캔 ===');
const tmp = mkdtempSync(join(tmpdir(), 'rel-links-test-'));
try {
  // git 저장소로 초기화 — 스캐너가 git ls-files 로 대상을 뽑기 때문이다.
  const { execFileSync } = await import('node:child_process');
  const git = (...args) => execFileSync('git', ['-C', tmp, ...args], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
  git('init', '-q');
  git('config', 'user.email', 'test@example.com');
  git('config', 'user.name', 'test');
  git('config', 'commit.gpgsign', 'false');

  const write = (rel, content) => {
    const p = join(tmp, rel);
    mkdirSync(dirname(p), { recursive: true });
    writeFileSync(p, content, 'utf8');
  };

  write('target.md', '# 존재하는 대상\n');
  write('docs/ok.md', '[정상](../target.md)\n');
  write('docs/broken.md', '[깨짐](../nope.md)\n');
  write('docs/codeblock.md', '```\n[예시](../nope.md)\n```\n');
  write('docs/inline.md', '`[예시](../nope.md)`\n');
  write('.agent/templates/tpl.md', '[생성물](../nope.md)\n');
  write('.agent/skills/bkit-templates/SKILL.md', '[생성물](../nope.md)\n');
  // KNOW-011 규칙 — 링크 기준은 "링크가 있는 파일의 위치"
  write('.agent/work_history/hist.md', '[KNOW](../.agent/target.md)\n');
  write('.agent/target.md', '# k-layer 정본\n');
  git('add', '-A');
  git('commit', '-q', '-m', 'test fixtures');

  const r = scanRelativeLinks(tmp);
  check('마크다운 9개 수집', r.mdFiles, 9);
  const defectFiles = r.defects.map(d => d.file).sort();
  // hist.md 는 **의도적으로 깨진 링크**를 담고 있다(KNOW-011 규칙 검증용 픽스처).
  check('실제 결함은 docs/broken.md + KNOW-011 픽스처', defectFiles,
    ['.agent/work_history/hist.md', 'docs/broken.md']);
  check('전체 링크 수는 상대 링크 수 이상', r.totalLinks >= r.relativeLinks, true);
  check('코드 펜스 안 링크는 결함 아님', r.defects.some(d => d.file === 'docs/codeblock.md'), false);
  check('인라인 스팬 안 링크는 결함 아님', r.defects.some(d => d.file === 'docs/inline.md'), false);
  check('템플릿 아래 링크는 스캐폴딩으로 분류', r.scaffold.some(s => s.file.startsWith('.agent/templates/')), true);
  check('bkit-templates 아래 링크도 스캐폴딩', r.scaffold.some(s => s.file.includes('bkit-templates')), true);
  check('스캐폴딩이 결함으로 새지 않음', r.defects.some(d => d.file.includes('templates')), false);
  // KNOW-011: `.agent/work_history/` 아래의 `../.agent/target.md` → `.agent/.agent/target.md` = 미존재
  check('KNOW-011 규칙 — 링크 기준은 링크가 있는 파일의 위치', r.defects.some(d => d.file === '.agent/work_history/hist.md'), true);
  check('정상 링크는 결함 아님', r.defects.some(d => d.file === 'docs/ok.md'), false);
} finally {
  rmSync(tmp, { recursive: true, force: true });
}

console.log(`\n결과: PASS ${pass} / FAIL ${fail}\n`);
process.exit(fail ? 1 : 0);
