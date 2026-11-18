// test-resolve-actor.mjs — lib/resolve-actor.js 의 주체 해석(로컬 AI 이름) 회귀 테스트
// 실행: node scripts/gissue/tests/test-resolve-actor.mjs
// 자격증명·네트워크를 건드리지 않는다 — 순수 판정 pickActorKey 와 readLocalAiName 만 검증한다.
import { createRequire } from 'node:module';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
const here = path.dirname(fileURLToPath(import.meta.url));
const { pickActorKey, readLocalAiName } = require(path.join(here, '..', 'lib', 'resolve-actor.js'));

let pass = 0, fail = 0;
function eq(actual, expected, name) {
  if (String(actual) === String(expected)) { pass++; console.log(`  PASS: ${name}`); }
  else { fail++; console.log(`  FAIL: ${name} (기대=${expected} 실제=${actual})`); }
}
function ok(cond, name) { eq(!!cond, true, name); }

console.log('== 해석 우선순위: 인자 > 환경변수 > aiName > 기본값 ==');
let r = pickActorKey({ actorKey: 'ai.a.x', envActor: 'ai.b.y', localName: 'ai.c.z', defaultActor: 'ai.dp01.console' });
eq(r.key, 'ai.a.x', '인자가 최우선');
eq(r.source, 'arg:actorKey', '인자 출처 표기');
r = pickActorKey({ envActor: 'ai.b.y', localName: 'ai.c.z', defaultActor: 'ai.dp01.console' });
eq(r.key, 'ai.b.y', '환경변수가 aiName 보다 우선');
eq(r.source, 'env:GIIP_ACTOR', '환경변수 출처 표기');
r = pickActorKey({ envActor: '', localName: 'ai.c.z', defaultActor: 'ai.dp01.console' });
eq(r.key, 'ai.c.z', 'aiName 이 기본값보다 우선 (로컬 이름의 단일 출처)');
eq(r.source, 'config:csn-projects.json#aiName', 'aiName 출처 표기');
r = pickActorKey({ envActor: '  ', localName: null, defaultActor: 'ai.dp01.console' });
eq(r.key, 'ai.dp01.console', '전부 비면 레지스트리 기본값');
eq(r.source, 'ai-actors.json:defaultActor', '기본값 출처 표기');
r = pickActorKey({});
eq(r.key, null, '출처가 아무것도 없으면 null (임의의 이름을 만들지 않음)');

console.log('== readLocalAiName ==');
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'ainame-'));
const f1 = path.join(tmp, 'with.json');
fs.writeFileSync(f1, JSON.stringify({ aiName: '  ai.host.sched  ', csn: {} }), 'utf-8');
eq(readLocalAiName(f1), 'ai.host.sched', 'aiName 을 읽고 trim 한다');
const f2 = path.join(tmp, 'without.json');
fs.writeFileSync(f2, JSON.stringify({ csn: {} }), 'utf-8');
eq(readLocalAiName(f2), null, 'aiName 이 없으면 null');
const f3 = path.join(tmp, 'broken.json');
fs.writeFileSync(f3, '{not json', 'utf-8');
eq(readLocalAiName(f3), null, '깨진 JSON 은 throw 없이 null');
eq(readLocalAiName(path.join(tmp, 'missing.json')), null, '파일이 없으면 null');
const f4 = path.join(tmp, 'bom.json');
fs.writeFileSync(f4, '﻿' + JSON.stringify({ aiName: 'ai.bom.test' }), 'utf-8');
eq(readLocalAiName(f4), 'ai.bom.test', 'BOM 이 붙어도 읽는다');
fs.rmSync(tmp, { recursive: true, force: true });

console.log('== 소스 커플링 ==');
const src = fs.readFileSync(path.join(here, '..', 'lib', 'resolve-actor.js'), 'utf-8');
ok(src.includes("path.join(SCRIPT_DIR, '..', 'csn-projects.json')"), '해석기가 자기 위치 기준으로 csn-projects.json 을 읽는다');
ok(!/GIIP_ACTOR\s*=\s*'ai\./.test(src), '해석기에 하드코딩된 주체 이름이 없다');

console.log(`\n결과: PASS=${pass} FAIL=${fail}`);
process.exit(fail > 0 ? 1 : 0);
