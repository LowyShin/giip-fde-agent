#!/usr/bin/env node
/*
 * check-slackbot-deploy-parity.mjs — slack-bot 기능이 "라이브 배포 트리"에 반영됐는지 판정 (giip 6713)
 *
 * ── 왜 필요한가 ─────────────────────────────────────────────────────────────────
 * 이 저장소(giip-fde-agent)는 slack-bot 코드의 **참조 원본**이다. 실제로 pm2 로 돌아가는
 * 프로세스는 **배포 트리**(예: 사내 오케스트레이션 저장소의 slack-bot/ 복사본)의 코드를 실행한다.
 * 두 트리는 서로 다른 저장소/포크라서, **원본에 머지된 기능이 배포 트리에 반영되지 않은 채**
 * 몇 주·몇 달 방치될 수 있다.
 *
 * 실측 사고(giip 6713): 무수신(connected-but-no-inbound) 자가복구 워치독이 참조 원본에는
 * PR #420 으로 머지됐고 사양·회귀 테스트까지 갖춰졌지만, 라이브 배포 트리에는 모듈도 배선도
 * 없었고 라이브 로그에도 판단 로그가 0건이었다. 즉 "감지 로직이 고장났다"가 아니라
 * **"감지 로직이 애초에 배포본에 없었다"** 였다 — 사양 §5.2 0단계가 FAIL 인 상태였다.
 * 이 갭을 사람이 수동으로 눈으로 확인해야만 드러나는 구조가 원인이었다.
 *
 * 이 스크립트는 사양 `slack-bot/docs/INBOUND_IDLE_WATCHDOG.md` §7.1 "저장소 밖(배포본)에서
 * 확인하는 것" 의 수동 확인 표를 **실행 가능한 검사**로 바꾼다.
 *
 * ── 판정 방식 ───────────────────────────────────────────────────────────────────
 *  · 매니페스트(slackbot-deploy-features.json)의 각 feature 마다:
 *      files  — 런타임 모듈이 배포 트리에 존재하는가
 *      wiring — 배포 트리의 파일에 배선 패턴이 있는가
 *      docs   — 권장 문서(있으면 좋고, 없으면 WARN)
 *  · **참조 원본(this repo)에도 같은 판정을 돌린다.** 참조는 PASS 인데 배포만 FAIL 이면
 *    그 자체가 "머지됨 ≠ 반영됨" 인 사고의 증거가 된다.
 *
 * ── 읽기 전용 ───────────────────────────────────────────────────────────────────
 * 이 스크립트는 **아무것도 쓰지 않는다**(배포 트리·참조 트리 모두 읽기 전용). 그래서
 * 라이브 배포 트리를 지정해 검사해도 그 트리에 변형이 생기지 않는다.
 *
 * ── 사용법 ──────────────────────────────────────────────────────────────────────
 *   node scripts/gissue/check-slackbot-deploy-parity.mjs --deploy-root <배포트리루트>
 *   node scripts/gissue/check-slackbot-deploy-parity.mjs --deploy-root <경로> --json
 *   node scripts/gissue/check-slackbot-deploy-parity.mjs --deploy-root <경로> --feature inbound-idle-watchdog
 *
 *   --deploy-root <path>  검사 대상 배포 트리 루트 (그 아래에 slack-bot/ 이 있어야 한다) [필수]
 *   --source-root <path>  참조 원본 루트 (기본: 이 저장소 루트)
 *   --manifest <path>     기능 매니페스트 (기본: scripts/gissue/slackbot-deploy-features.json)
 *   --feature <id>        특정 feature 만 검사
 *   --json                기계 판독용 JSON 출력
 *
 * ── 종료 코드 ───────────────────────────────────────────────────────────────────
 *   0 = 참조 원본 · 배포 트리 모두 통과
 *   1 = 누락 있음(배포 반영 안 됨 / 매니페스트-원본 불일치)
 *   2 = 사용법·입력 오류(매니페스트 없음, --deploy-root 누락, 알 수 없는 feature id)
 */
'use strict';

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const DEFAULT_MANIFEST = path.join(HERE, 'slackbot-deploy-features.json');
const DEFAULT_SOURCE_ROOT = path.resolve(HERE, '..', '..'); // scripts/gissue -> scripts -> 저장소 루트

export function parseArgs(argv) {
  const a = {
    deployRoot: '',
    sourceRoot: DEFAULT_SOURCE_ROOT,
    manifest: DEFAULT_MANIFEST,
    feature: '',
    json: false,
    help: false,
  };
  for (let i = 0; i < argv.length; i++) {
    const k = argv[i];
    const next = () => argv[++i];
    if (k === '--deploy-root') a.deployRoot = next() ?? '';
    else if (k === '--source-root') a.sourceRoot = next() ?? '';
    else if (k === '--manifest') a.manifest = next() ?? '';
    else if (k === '--feature') a.feature = next() ?? '';
    else if (k === '--json') a.json = true;
    else if (k === '--help' || k === '-h') a.help = true;
  }
  return a;
}

/**
 * feature 하나를 root 트리에 대해 판정한다. 순수 함수(파일시스템 읽기만).
 * @returns {{id:string, ok:boolean, missingFiles:string[], missingWiring:object[], missingDocs:string[]}}
 */
export function checkFeature(feature, root) {
  const missingFiles = [];
  for (const rel of feature.files || []) {
    if (!fs.existsSync(path.join(root, rel))) missingFiles.push(rel);
  }

  const missingWiring = [];
  for (const w of feature.wiring || []) {
    const abs = path.join(root, w.file);
    let text = null;
    try {
      text = fs.readFileSync(abs, 'utf8');
    } catch {
      text = null; // 파일 없음/읽기 실패 → 배선 누락으로 처리
    }
    let found = false;
    try {
      found = text !== null && new RegExp(w.pattern).test(text);
    } catch {
      found = false; // 잘못된 정규식은 '미검출'으로 처리한다(오류로 죽이지 않는다)
    }
    if (!found) {
      missingWiring.push({
        file: w.file,
        desc: w.desc || '',
        pattern: w.pattern,
        reason: text === null ? '파일 없음' : '패턴 미검출',
      });
    }
  }

  const missingDocs = [];
  for (const rel of feature.docs || []) {
    if (!fs.existsSync(path.join(root, rel))) missingDocs.push(rel);
  }

  return {
    id: feature.id,
    title: feature.title || '',
    issue: feature.issue || '',
    ok: missingFiles.length === 0 && missingWiring.length === 0,
    missingFiles,
    missingWiring,
    missingDocs,
  };
}

/** 매니페스트의 feature 목록을 root 에 대해 검사한다. */
export function checkManifest(manifest, root, onlyId) {
  const features = (manifest.features || []).filter((f) => !onlyId || f.id === onlyId);
  return features.map((f) => checkFeature(f, root));
}

function printHuman(report) {
  const line = (s) => console.log(s);
  line(`[deploy-parity] 참조 원본 : ${report.sourceRoot}`);
  line(`[deploy-parity] 배포 트리 : ${report.deployRoot}`);
  line(`[deploy-parity] 매니페스트 : ${report.manifestPath}`);
  line('');
  for (const f of report.features) {
    line(`== ${f.id} — ${f.title}${f.issue ? ` (${f.issue})` : ''} ==`);
    const s = report.source.find((x) => x.id === f.id);
    const d = report.deploy.find((x) => x.id === f.id);
    line(`  [참조] ${s && s.ok ? 'PASS' : 'FAIL'}`);
    if (s && !s.ok) {
      for (const m of s.missingFiles) line(`         파일 없음: ${m}`);
      for (const m of s.missingWiring) line(`         배선 누락: ${m.file} — ${m.desc} (${m.reason})`);
    }
    line(`  [배포] ${d && d.ok ? 'PASS' : 'FAIL'}`);
    if (d && !d.ok) {
      for (const m of d.missingFiles) line(`         파일 없음: ${m}`);
      for (const m of d.missingWiring) line(`         배선 누락: ${m.file} — ${m.desc} (${m.reason})`);
    }
    if (d && d.missingDocs.length) {
      for (const m of d.missingDocs) line(`         [WARN] 권장 문서 없음: ${m}`);
    }
    line('');
  }
  const sp = report.source.filter((x) => x.ok).length;
  const dp = report.deploy.filter((x) => x.ok).length;
  line(`요약: 참조 ${sp}/${report.features.length} 통과 · 배포 ${dp}/${report.features.length} 통과`);
  if (sp === report.features.length && dp < report.features.length) {
    line('→ 참조 원본은 갖췄지만 배포 트리에 반영되지 않았다 = "머지됨 ≠ 반영됨" 상태다.');
    line('  사양 slack-bot/docs/INBOUND_IDLE_WATCHDOG.md §5.2 0단계가 FAIL 이므로 §5.2 왕복 검증은 아직 실행 불가다.');
  }
}

function main(argv) {
  const a = parseArgs(argv);
  if (a.help) {
    console.log(
      '사용법: node scripts/gissue/check-slackbot-deploy-parity.mjs --deploy-root <배포트리루트> ' +
        '[--source-root <경로>] [--manifest <경로>] [--feature <id>] [--json]'
    );
    return 0;
  }
  if (!a.deployRoot) {
    console.error('❌ --deploy-root <배포트리루트> 가 필요합니다(검사 대상 배포 트리).');
    return 2;
  }
  if (!fs.existsSync(a.manifest)) {
    console.error(`❌ 매니페스트를 찾을 수 없습니다: ${a.manifest}`);
    return 2;
  }
  let manifest;
  try {
    manifest = JSON.parse(fs.readFileSync(a.manifest, 'utf8'));
  } catch (e) {
    console.error(`❌ 매니페스트 JSON 파싱 실패: ${e.message}`);
    return 2;
  }
  const knownIds = (manifest.features || []).map((f) => f.id);
  if (a.feature && !knownIds.includes(a.feature)) {
    console.error(`❌ 알 수 없는 feature id: ${a.feature} (사용 가능: ${knownIds.join(', ') || '(없음)'})`);
    return 2;
  }
  if (!fs.existsSync(a.deployRoot)) {
    console.error(`❌ 배포 트리를 찾을 수 없습니다: ${a.deployRoot}`);
    return 2;
  }

  const features = (manifest.features || []).filter((f) => !a.feature || f.id === a.feature);
  const report = {
    sourceRoot: path.resolve(a.sourceRoot),
    deployRoot: path.resolve(a.deployRoot),
    manifestPath: path.resolve(a.manifest),
    features,
    source: checkManifest(manifest, path.resolve(a.sourceRoot), a.feature),
    deploy: checkManifest(manifest, path.resolve(a.deployRoot), a.feature),
  };
  report.ok = report.source.every((x) => x.ok) && report.deploy.every((x) => x.ok);

  if (a.json) {
    console.log(JSON.stringify(report, null, 2));
  } else {
    printHuman(report);
  }
  return report.ok ? 0 : 1;
}

// 직접 실행일 때만 CLI 로 동작한다(테스트에서 require 하면 main 을 돌리지 않는다).
if (process.argv[1] && path.resolve(process.argv[1]) === path.resolve(fileURLToPath(import.meta.url))) {
  process.exit(main(process.argv.slice(2)));
}
