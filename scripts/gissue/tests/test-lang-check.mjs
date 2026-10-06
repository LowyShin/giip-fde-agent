/**
 * lang-check.js 테스트
 * 실행: node scripts/gissue/tests/test-lang-check.mjs
 * 전부 통과하면 마지막 줄에 "PASS test-lang-check" 출력, 실패하면 exit 1
 */

import assert from 'assert';
import { execSync } from 'child_process';
import fs from 'fs';
import os from 'os';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// CommonJS 모듈 불러오기
const langCheck = (await import('../lib/lang-check.js')).default;

const { scriptOf, detect, directive, isIgnoredPath, checkGit } = langCheck;

// 임시 폴더 관리
const tempDirs = [];

function createTempDir() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'lang-check-test-'));
  tempDirs.push(dir);
  return dir;
}

function cleanupTempDirs() {
  for (const dir of tempDirs) {
    try {
      fs.rmSync(dir, { recursive: true, force: true });
    } catch (e) {
      // 무시
    }
  }
  tempDirs.length = 0;
}

// 테스트 시작
let passed = 0;
let failed = 0;

function test(name, fn) {
  try {
    fn();
    passed++;
  } catch (e) {
    console.error('FAIL:', name);
    console.error(e.message);
    failed++;
  }
}

//────────────────────────────────────────
// 1. scriptOf
//────────────────────────────────────────

test('scriptOf: 한자 (U+4E2D)', () => {
  assert.strictEqual(scriptOf(0x4E2D), 'Han');
});

test('scriptOf: 가나 あ (U+3042)', () => {
  assert.strictEqual(scriptOf(0x3042), 'Kana');
});

test('scriptOf: 반각 가나 ｶ (U+FF76)', () => {
  assert.strictEqual(scriptOf(0xFF76), 'Kana');
});

test('scriptOf: 한글 가 (U+AC00)', () => {
  assert.strictEqual(scriptOf(0xAC00), 'Hangul');
});

test('scriptOf: 키릴 д (U+0434)', () => {
  assert.strictEqual(scriptOf(0x0434), 'Cyrillic');
});

test('scriptOf: 허용 문자 (ASCII)', () => {
  assert.strictEqual(scriptOf(0x0041), null); // A
});

test('scriptOf: 허용 문자 (이모지)', () => {
  assert.strictEqual(scriptOf(0x1F600), null); // 😀
});

//────────────────────────────────────────
// 2. detect - 순수 한글+영어+코드+이모지는 ko에서 0건
//────────────────────────────────────────

test('detect: 순수 한글+영어+코드+이모지는 ko에서 0건', () => {
  const text = '안녕하세요 Hello World! function test() {} 😀 🎉';
  assert.strictEqual(detect(text, 'ko').length, 0);
});

//────────────────────────────────────────
// 3. detect - 한자/가나/키릴 검출
//────────────────────────────────────────

test('detect: 한자 검출 (ko)', () => {
  const findings = detect('中', 'ko');
  assert.strictEqual(findings.length, 1);
  assert.strictEqual(findings[0].script, 'Han');
  assert.strictEqual(findings[0].codePoint, 'U+4E2D');
});

test('detect: 가나 あ 검출 (ko)', () => {
  const findings = detect('あ', 'ko');
  assert.strictEqual(findings.length, 1);
  assert.strictEqual(findings[0].script, 'Kana');
});

test('detect: 가나 カ 검출 (반각 가나, ko)', () => {
  const findings = detect('ｶ', 'ko');
  assert.strictEqual(findings.length, 1);
  assert.strictEqual(findings[0].script, 'Kana');
});

test('detect: 키릴 д 검출 (ko)', () => {
  const findings = detect('д', 'ko');
  assert.strictEqual(findings.length, 1);
  assert.strictEqual(findings[0].script, 'Cyrillic');
});

//────────────────────────────────────────
// 4. detect - line/col 정확성
//────────────────────────────────────────

test('detect: 여러 줄에서 line/col 정확', () => {
  const text = '줄1\n줄2에 한자 中 가 있다\n줄3';
  const findings = detect(text, 'ko');
  assert.strictEqual(findings.length, 1);
  assert.strictEqual(findings[0].line, 2);
  // 줄2에 한자 中 가 있다 → 줄(1) 2(2) 에(3) space(4) 한(5) 자(6) space(7) 中(8)
  assert.strictEqual(findings[0].col, 8);
});

//────────────────────────────────────────
// 5. detect - ja/en/zh-CN 언어별 차이
//────────────────────────────────────────

test('detect: ja에서는 가나/한자 통과', () => {
  assert.strictEqual(detect('あ、中', 'ja').length, 0);
});

test('detect: ja에서는 한글 검출', () => {
  const findings = detect('가', 'ja');
  assert.strictEqual(findings.length, 1);
  assert.strictEqual(findings[0].script, 'Hangul');
});

test('detect: en에서는 한글 검출', () => {
  const findings = detect('가', 'en');
  assert.strictEqual(findings.length, 1);
  assert.strictEqual(findings[0].script, 'Hangul');
});

test('detect: zh-CN에서는 한자 통과', () => {
  assert.strictEqual(detect('中', 'zh-CN').length, 0);
});

test('detect: zh-CN에서는 가나 검출', () => {
  const findings = detect('あ', 'zh-CN');
  assert.strictEqual(findings.length, 1);
  assert.strictEqual(findings[0].script, 'Kana');
});

//────────────────────────────────────────
// 6. detect - lang-check:ignore
//────────────────────────────────────────

test('detect: lang-check:ignore 줄 건너뛰기', () => {
  const text = '한자 中 있음\nlang-check:ignore\n한자 中 있음2';
  const findings = detect(text, 'ko');
  assert.strictEqual(findings.length, 2); // ignore 줄만 빼고 2건
});

//────────────────────────────────────────
// 7. isIgnoredPath
//────────────────────────────────────────

test('isIgnoredPath: locales/ja.json 는 true', () => {
  assert.strictEqual(isIgnoredPath('locales/ja.json'), true);
});

test('isIgnoredPath: locales/zh-CN.json 는 true', () => {
  assert.strictEqual(isIgnoredPath('locales/zh-CN.json'), true);
});

test('isIgnoredPath: package-lock.json 는 true', () => {
  assert.strictEqual(isIgnoredPath('package-lock.json'), true);
});

test('isIgnoredPath: a.png 는 true', () => {
  assert.strictEqual(isIgnoredPath('a.png'), true);
});

test('isIgnoredPath: locales/ko.json 는 false', () => {
  assert.strictEqual(isIgnoredPath('locales/ko.json'), false);
});

test('isIgnoredPath: src/a.ts 는 false', () => {
  assert.strictEqual(isIgnoredPath('src/a.ts'), false);
});

//────────────────────────────────────────
// 8. directive
//────────────────────────────────────────

test('directive: ko 에 금지 문자 없음', () => {
  const text = directive('ko');
  assert.strictEqual(detect(text, 'ko').length, 0);
});

test('directive: en 비어 있지 않음', () => {
  const text = directive('en');
  assert.ok(text.length > 0);
});

test('directive: ja 비어 있지 않음', () => {
  const text = directive('ja');
  assert.ok(text.length > 0);
});

test('directive: zh-CN 비어 있지 않음', () => {
  const text = directive('zh-CN');
  assert.ok(text.length > 0);
});

//────────────────────────────────────────
// 9. checkGit
//────────────────────────────────────────

test('checkGit: 한글만 있는 커밋은 0건', () => {
  const repoDir = createTempDir();
  try {
    execSync('git init', { cwd: repoDir });
    execSync('git config user.name "Test"', { cwd: repoDir });
    execSync('git config user.email "test@test.com"', { cwd: repoDir });

    // 한글만 있는 파일
    const filePath = path.join(repoDir, 'test.txt');
    fs.writeFileSync(filePath, '안녕하세요\n');
    execSync('git add test.txt', { cwd: repoDir });
    execSync('git commit -m "초기 커밋"', { cwd: repoDir });

    const findings = checkGit(repoDir, { lang: 'ko' });
    const errors = findings.filter(f => f.error);
    if (errors.length > 0) throw new Error('git 오류: ' + errors[0].error);
    assert.strictEqual(findings.length, 0);
  } finally {
    fs.rmSync(repoDir, { recursive: true, force: true });
  }
});

test('checkGit: 가나가 든 커밋 메시지와 diff 검출', () => {
  const repoDir = createTempDir();
  try {
    execSync('git init', { cwd: repoDir });
    execSync('git config user.name "Test"', { cwd: repoDir });
    execSync('git config user.email "test@test.com"', { cwd: repoDir });

    // 첫 커밋 (깨끗한 상태)
    const filePath = path.join(repoDir, 'test.txt');
    fs.writeFileSync(filePath, '안녕하세요\n');
    execSync('git add test.txt', { cwd: repoDir });
    execSync('git commit -m "초기 커밋"', { cwd: repoDir });

    // 가나가 든 두 번째 커밋
    fs.writeFileSync(filePath, 'あいうえお\n');
    execSync('git add test.txt', { cwd: repoDir });
    execSync('git commit -m "あいうえお 커밋"', { cwd: repoDir });

    const findings = checkGit(repoDir, { lang: 'ko' });
    const errors = findings.filter(f => f.error);
    if (errors.length > 0) throw new Error('git 오류: ' + errors[0].error);

    // 메시지 1건 이상 + diff 1건 이상
    const messageFindings = findings.filter(f => f.kind === 'message');
    const diffFindings = findings.filter(f => f.kind === 'diff');
    assert.ok(messageFindings.length >= 1, '메시지 1건 이상');
    assert.ok(diffFindings.length >= 1, 'diff 1건 이상');

    // commit, char 채워졌는지 확인
    const first = findings[0];
    assert.ok(first.commit, 'commit 채워짐');
    assert.ok(first.char, 'char 채워짐');
  } finally {
    fs.rmSync(repoDir, { recursive: true, force: true });
  }
});

test('checkGit: 한자가 든 파일 변경 검출', () => {
  const repoDir = createTempDir();
  try {
    execSync('git init', { cwd: repoDir });
    execSync('git config user.name "Test"', { cwd: repoDir });
    execSync('git config user.email "test@test.com"', { cwd: repoDir });

    // 첫 커밋
    const filePath = path.join(repoDir, 'test.txt');
    fs.writeFileSync(filePath, '안녕하세요\n');
    execSync('git add test.txt', { cwd: repoDir });
    execSync('git commit -m "초기"', { cwd: repoDir });

    // 한자가 든 변경
    fs.writeFileSync(filePath, '한자 中 추가\n');
    execSync('git add test.txt', { cwd: repoDir });
    execSync('git commit -m "중간 커밋"', { cwd: repoDir });

    const findings = checkGit(repoDir, { lang: 'ko' });
    const diffFindings = findings.filter(f => f.kind === 'diff');
    assert.ok(diffFindings.length >= 1, 'diff 1건 이상');
    assert.strictEqual(diffFindings[0].char, '中');
    assert.strictEqual(diffFindings[0].file, 'test.txt');
  } finally {
    fs.rmSync(repoDir, { recursive: true, force: true });
  }
});

test('checkGit: package-lock.json 의 변경은 무시됨', () => {
  const repoDir = createTempDir();
  try {
    execSync('git init', { cwd: repoDir });
    execSync('git config user.name "Test"', { cwd: repoDir });
    execSync('git config user.email "test@test.com"', { cwd: repoDir });

    // 첫 커밋
    fs.writeFileSync(path.join(repoDir, 'a.txt'), 'a');
    execSync('git add a.txt', { cwd: repoDir });
    execSync('git commit -m "초기"', { cwd: repoDir });

    // package-lock.json 에 한자
    fs.writeFileSync(path.join(repoDir, 'package-lock.json'), '中');
    execSync('git add package-lock.json', { cwd: repoDir });
    execSync('git commit -m "패키지"', { cwd: repoDir });

    const findings = checkGit(repoDir, { lang: 'ko' });
    const packageFindings = findings.filter(f => f.file && f.file.includes('package-lock.json'));
    assert.strictEqual(packageFindings.length, 0, 'package-lock.json 은 무시됨');
  } finally {
    fs.rmSync(repoDir, { recursive: true, force: true });
  }
});

test('checkGit: git 실패 시 오류 객체 반환', () => {
  const findings = checkGit('/nonexistent-path', { lang: 'ko' });
  assert.strictEqual(findings.length, 1);
  assert.ok(findings[0].error, 'error 필드 있음');
});

//────────────────────────────────────────
// 10. CLI
//────────────────────────────────────────

test('CLI: --text-file 깨끗한 파일은 exit 0', () => {
  const tmpFile = path.join(os.tmpdir(), 'lc-test-clean-' + Date.now() + '.txt');
  fs.writeFileSync(tmpFile, '안녕하세요\n');
  try {
    const result = execSync(`node ${path.join(__dirname, '../lib/lang-check.js')} --lang ko --text-file ${tmpFile}`, { encoding: 'utf-8' });
    assert.ok(result.includes('문제 없음'), '문제 없음 출력');
  } finally {
    fs.unlinkSync(tmpFile);
  }
});

test('CLI: --text-file 한자가 든 파일은 exit 4', () => {
  const tmpFile = path.join(os.tmpdir(), 'lc-test-dirty-' + Date.now() + '.txt');
  fs.writeFileSync(tmpFile, '中\n');
  try {
    try {
      execSync(`node ${path.join(__dirname, '../lib/lang-check.js')} --lang ko --text-file ${tmpFile}`, { encoding: 'utf-8' });
      assert.fail('exit 4여야 함');
    } catch (e) {
      assert.strictEqual(e.status, 4, 'exit 4');
    }
  } finally {
    fs.unlinkSync(tmpFile);
  }
});

test('CLI: --directive 는 exit 0 이고 출력이 비어 있지 않음', () => {
  const result = execSync(`node ${path.join(__dirname, '../lib/lang-check.js')} --directive --lang ko`, { encoding: 'utf-8' });
  assert.ok(result.length > 0, '출력 있음');
});

//────────────────────────────────────────
// 결과 요약
//────────────────────────────────────────

console.log(`테스트 결과: ${passed}개 통과, ${failed}개 실패`);
if (failed > 0) {
  process.exit(1);
} else {
  console.log('PASS test-lang-check');
}
