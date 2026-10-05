// log-ship.js 순수 함수 단위 테스트(네트워크 없음). 실행: node scripts/gissue/tests/test-log-ship.mjs
import { createRequire } from 'module';
import assert from 'assert';
import fs from 'fs';
import os from 'os';
import path from 'path';
const require = createRequire(import.meta.url);
const { maskLine, readNewLines, lineTs } = require('../lib/log-ship.js');

// 비밀 마스킹
assert.strictEqual(maskLine('a sk=abc123 b'), 'a sk=*** b');
assert.ok(!maskLine('Authorization: Bearer abc.def').includes('abc'));
assert.ok(!maskLine('Server=x;Password=P@ss;').includes('P@ss'));
assert.ok(!maskLine('t ffd96879858fe73fc31d923a74ae23b5 e').includes('ffd968'));
assert.strictEqual(maskLine('isn=3535 처리 시작'), 'isn=3535 처리 시작');   // 일반 로그는 그대로
assert.ok(maskLine('x'.repeat(5000)).length < 4100);                          // 길이 상한

// 줄 시각
assert.strictEqual(lineTs('[2026-10-05 04:08:32] [CSN 47] x', 'F'), '2026-10-05T04:08:32Z');
assert.strictEqual(lineTs('시각 없음', 'F'), 'F');

// 증분 읽기: 개행으로 끝난 줄만, 마지막 미완결 줄은 다음 회차로
const f = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'logship-')), 't.log');
fs.writeFileSync(f, 'a\nb\npartial');
let r = readNewLines(f, 0, 1 << 20);
assert.deepStrictEqual(r.lines, ['a', 'b']);
fs.appendFileSync(f, ' done\nc\n');
r = readNewLines(f, r.newOffset, 1 << 20);
assert.deepStrictEqual(r.lines, ['partial done', 'c']);
r = readNewLines(f, r.newOffset, 1 << 20);
assert.deepStrictEqual(r.lines, []);
console.log('PASS test-log-ship');
