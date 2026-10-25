#!/usr/bin/env node
/**
 * relative-links.mjs — 마크다운 상대링크 스캐너 (저장소 정규본)
 *
 * 왜 이 파일이 필요한가 (2026-10-25 CSN 70424 저장소 정비 세션 실측):
 *   43~50차 정비 세션이 **매번 새로 짠 스캐너**로 상대링크를 스캔했다.
 *   스캐너가 회차마다 달라서 "미존재 링크 N건" 기준선이 매번 달랐다 —
 *   43차 26건 → 44차 27건 → 45차 26건 → 46차 11건 → 47차 31건 → 48차 33건 → 49차 26건 → 50차 34건.
 *   숫자가 다른 이유는 스캐너가 **서로 다른 것**을 세었기 때문이고,
 *   "N건 = 스캐폴딩 A + 코드예시 B" 식의 분류는 매 회차 사람이 손으로 했다.
 *   → 판정 로직을 **저장소에 정본으로 두고**(rule 48 single_source_safety_predicate)
 *     다음 회차가 같은 기준선으로 같은 판정을 얻게 한다.
 *
 * 판정 2개:
 *   [판정 1] 실제 결함 — 코드(펜스/인라인 스팬) 밖의 상대링크 중 대상 파일이 없는 것.
 *   [판정 2] 스캐폴딩 — 템플릿이 생성물 배치 경로로 복사된 뒤에야 성립하는 링크.
 *            `.agent/templates/` 와 `.agent/skills/bkit-templates/` 아래는 **디렉터리 단위로**
 *            예외 처리한다(파일·링크 단위 allowlist 를 만들지 않는다 — 항목이 늘면 규칙이 무너진다).
 *
 * 코드 펜스/인라인 스팬을 무시하는 이유:
 *   문서 안의 **"이런 링크는 깨진다"는 예시**는 링크가 아니라 설명이다.
 *   50차 산출물(KNOW-011)이 `[KNOW-009](../.agent/k_layer/notes/...)` 를 코드 블록 안에 적어
 *   두었는데, 코드를 무시하지 않는 스캐너는 그 예시를 **실제 결함으로 집계**했다.
 *   → 51차는 코드 블록을 제외하고 스캔하니 실제 결함 0건이 나왔다.
 *
 * 사용법:
 *   node scripts/gissue/lib/relative-links.mjs [--repo-root <경로>] [--json] [--quiet]
 *
 * 종료코드: 0 = 실제 결함 0건 / 1 = 실제 결함 있음 / 2 = 사용법 오류
 *
 * 읽기 전용이다 — 어떤 파일도 고치지 않는다.
 */

import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import { dirname, isAbsolute, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);

/** 스캐폴딩으로 예외 처리할 디렉터리 (저장소 상대 경로, forward slash). */
export const SCAFFOLD_DIRS = [
  '.agent/templates/',
  '.agent/skills/bkit-templates/',
];

/**
 * 코드 펜스(``` / ~~~)와 인라인 코드 스팬을 제거한 텍스트를 돌려준다.
 * 제거된 자리에는 빈 줄을 남겨 **라인 번호가 원본과 어긋나지 않게** 한다.
 */
export function stripCode(text) {
  const lines = text.split(/\r?\n/);
  const out = [];
  let fence = null;
  for (const line of lines) {
    const m = /^\s*(```+|~~~+)/.exec(line);
    if (m) {
      const marker = m[1][0];
      if (fence === null) fence = marker;
      else if (marker === fence) fence = null;
      out.push('');
      continue;
    }
    if (fence !== null) { out.push(''); continue; }
    // 인라인 코드 스팬 — 코드 펜스 안쪽도 여기로 들어오지만 위에서 이미 걸러진다.
    out.push(line.replace(/`[^`\n]*`/g, ''));
  }
  return out;
}

/** 저장소에서 추적 중인 마크다운 파일 목록 (git ls-files, 경로 인자 변환 함정 회피). */
export function listMarkdownFiles(repoRoot) {
  const out = execFileSync(
    'git',
    ['-C', repoRoot, '-c', 'core.quotepath=false', 'ls-files', '-z', '--', '*.md'],
    { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 },
  );
  return out.split('\0').filter(Boolean);
}

/** 링크 대상 문자열이 상대 경로 링크인지 판정한다(URL·앵커·절대경로 제외). */
export function isRelativeTarget(target) {
  if (!target) return false;
  if (/^(https?:|mailto:|data:|file:)/i.test(target)) return false;
  if (target.startsWith('#')) return false;
  if (target.startsWith('/')) return false;
  if (/^[a-zA-Z]:[\\/]/.test(target)) return false;   // Windows 절대경로
  if (isAbsolute(target)) return false;
  const clean = target.split('#')[0].split('?')[0];
  if (!clean) return false;
  // 경로 구분자가 있는 것만 — "문서명" 만 있는 것은 같은 디렉터리 상대 링크로 본다.
  return true;
}

/** 마크다운 링크 대상에서 경로 부분만 뽑는다(제목·앵커·쿼리 제거). */
export function cleanTarget(target) {
  let t = target.trim();
  // <...> 로 감싼 경로
  const angled = /^<([^>]+)>/.exec(t);
  if (angled) t = angled[1];
  // "제목" 부분 제거 (경로 뒤 공백 + 따옴표)
  t = t.replace(/\s+["'(].*$/, '');
  return t.split('#')[0].split('?')[0];
}

/** 저장소 상대 경로(forward slash)인지 판정. */
function isScaffoldPath(relPath) {
  const p = relPath.replace(/\\/g, '/');
  return SCAFFOLD_DIRS.some(d => p.startsWith(d));
}

/**
 * 마크다운 텍스트 하나에서 링크를 추출한다.
 * @returns {{links:Array<{line:number, target:string}>, total:number}}
 *   total = 코드 블록 밖의 전체 링크 수(상대/URL 모두),
 *   links = 그중 상대 링크만.
 */
export function extractLinks(text) {
  const lines = stripCode(text);
  const links = [];
  let total = 0;
  const inlineRe = /\[[^\]]*\]\(([^)\s]+)(?:\s+"[^"]*")?\)/g;
  const refRe = /^\s*\[[^\]]+\]:\s*(\S+)/gm;
  lines.forEach((line, i) => {
    let m;
    inlineRe.lastIndex = 0;
    while ((m = inlineRe.exec(line)) !== null) {
      total++;
      const target = m[1];
      if (isRelativeTarget(target)) links.push({ line: i + 1, target });
    }
    refRe.lastIndex = 0;
    let rm;
    while ((rm = refRe.exec(line)) !== null) {
      total++;
      const target = rm[1];
      if (isRelativeTarget(target)) links.push({ line: i + 1, target });
    }
  });
  return { links, total };
}

/**
 * 마크다운 텍스트 하나에서 상대링크만 추출한다.
 * @returns {Array<{line:number, target:string}>}
 */
export function extractRelativeLinks(text) {
  return extractLinks(text).links;
}

/**
 * 저장소 전체를 스캔한다.
 * @returns {{mdFiles:number, totalLinks:number, relativeLinks:number,
 *            defects:Array, scaffold:Array, scaffoldingCount:number}}
 */
export function scanRelativeLinks(repoRoot) {
  const files = listMarkdownFiles(repoRoot);
  const defects = [];
  const scaffold = [];
  let totalLinks = 0;
  let relativeLinks = 0;

  for (const rel of files) {
    const abs = resolve(repoRoot, rel);
    let text;
    try { text = readFileSync(abs, 'utf8'); } catch { continue; }

    const { links, total } = extractLinks(text);
    totalLinks += total;
    for (const link of links) {
      relativeLinks++;
      const clean = cleanTarget(link.target);
      if (!clean) continue;
      let decoded;
      try { decoded = decodeURIComponent(clean); } catch { decoded = clean; }
      const targetAbs = resolve(dirname(abs), decoded);
      const exists = existsSync(targetAbs);
      const item = {
        file: rel.replace(/\\/g, '/'),
        line: link.line,
        target: link.target,
        resolved: targetAbs.slice(repoRoot.length + 1).replace(/\\/g, '/'),
      };
      if (exists) continue;
      // 스캐폴딩 판정 — 템플릿 산출물 배치 경로(디렉터리 단위).
      if (isScaffoldPath(item.file)) { scaffold.push(item); continue; }
      defects.push(item);
    }
  }

  return {
    mdFiles: files.length,
    totalLinks,
    relativeLinks,
    defects,
    scaffold,
    scaffoldingCount: scaffold.length,
  };
}

/** CLI 진입점. */
function main(argv) {
  // scripts/gissue/lib/ → scripts/gissue/ → scripts/ → 저장소 루트 (3단계 상위)
  let repoRoot = resolve(dirname(__filename), '../../..');
  let asJson = false;
  let quiet = false;
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--repo-root' && argv[i + 1]) { repoRoot = resolve(argv[++i]); }
    else if (a === '--json') asJson = true;
    else if (a === '--quiet') quiet = true;
    else if (a === '--help' || a === '-h') {
      console.log('사용법: node relative-links.mjs [--repo-root <경로>] [--json] [--quiet]');
      return 0;
    } else {
      console.error(`알 수 없는 옵션: ${a}`);
      return 2;
    }
  }
  if (!existsSync(repoRoot)) {
    console.error(`저장소 루트를 찾을 수 없습니다: ${repoRoot}`);
    return 2;
  }

  const r = scanRelativeLinks(repoRoot);

  if (asJson) {
    console.log(JSON.stringify(r, null, 2));
  } else if (!quiet) {
    console.log(`[MD-LINK] 마크다운 ${r.mdFiles}개 · 전체 링크 ${r.totalLinks}건 · 상대링크 ${r.relativeLinks}건`);
    console.log(`[MD-LINK] 스캐폴딩(예외) ${r.scaffoldingCount}건 · 실제 결함 ${r.defects.length}건`);
    for (const d of r.defects) {
      console.log(`[MD-LINK][DEFECT] ${d.file}:${d.line} -> ${d.target} (해석: ${d.resolved})`);
    }
  }

  // rule 42 — 검사기가 아무것도 검사하지 않았는데 통과로 보이면 안 된다.
  if (r.mdFiles === 0) {
    console.error('[MD-LINK][FAIL] 검사 대상 마크다운 0건 — 통과로 읽지 않습니다');
    return 1;
  }
  if (r.relativeLinks === 0) {
    console.error('[MD-LINK][FAIL] 상대링크 0건 — 검사기가 아무것도 검사하지 않았습니다');
    return 1;
  }
  return r.defects.length > 0 ? 1 : 0;
}

const invokedDirectly = process.argv[1] &&
  resolve(process.argv[1]).replace(/\.mjs$/i, '') === resolve(__filename).replace(/\.mjs$/i, '');
if (invokedDirectly) {
  process.exit(main(process.argv.slice(2)));
}
