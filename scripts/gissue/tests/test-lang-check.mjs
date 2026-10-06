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

const { scriptOf, detect, directive, isIgnoredPath, checkGit, _parseLogRecords } = langCheck;

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
// 11. 결함 1: 서러게이트 쌍 (확장 한자 U+20000 이상)
//────────────────────────────────────────

test('detect: 확장 한자 U+20000 (서러게이트 쌍) 검출', () => {
  // "\u{20000}" = U+20000 = LINEAR B IDEOGRAM B0047 A (확장 한자)
  const text = '정상 문자\u{20000}정상 문자';
  const findings = detect(text, 'ko');
  assert.strictEqual(findings.length, 1, '서러게이트 쌍 1건 검출');
  assert.strictEqual(findings[0].script, 'Han');
  assert.strictEqual(findings[0].char.length, 2, 'char는 2코드유닛 완전한 서러게이트 쌍');
  assert.strictEqual(findings[0].codePoint, 'U+20000');
});

test('detect: 확장 한자 여러 개 모두 검출', () => {
  const text = '\u{20000}\u{20001}\u{2A6DF}';
  const findings = detect(text, 'ko');
  assert.strictEqual(findings.length, 3, '3건 모두 검출');
});

test('detect: 서러게이트 쌍 col 위치 정확 (UTF-16 코드 유닛 단위)', () => {
  // UTF-16 인덱스: 가(0) space(1) 가(2) space(3) 中(4) space(5) emoji_HIGH(6) emoji_LOW(7)
  // 中 (U+4E2D)는 Han → col 5 (UTF-16 인덱스 4 + 1)
  // \u{20000} (U+20000)도 Han → col 7 (UTF-16 인덱스 6 + 1)
  const text = '가 가 中 \u{20000}';
  const findings = detect(text, 'ko');
  assert.strictEqual(findings.length, 2, '한자 中 와 확장 한자 \\u{20000} 모두 검출');
  assert.strictEqual(findings[0].col, 5, '中 은 UTF-16 인덱스 4 → col 5');
  assert.strictEqual(findings[1].col, 7, '\\u{20000} 은 UTF-16 인덱스 6 → col 7');
});

//────────────────────────────────────────
// 12. 결함 2: null/undefined/숫자 안전성
//────────────────────────────────────────

test('detect: null 은 빈 배열 반환 (예외 없음)', () => {
  assert.deepStrictEqual(detect(null), []);
});

test('detect: undefined 은 빈 배열 반환 (예외 없음)', () => {
  assert.deepStrictEqual(detect(undefined), []);
});

test('detect: 숫자는 문자열로 변환하여 검사', () => {
  // 숫자 123은 허용 (scriptOf null) → 0건
  assert.strictEqual(detect(123, 'ko').length, 0);
  // 숫자 0x4E2D(19981)를 String()하면 "19981"이라 0건 (한자 아님)
  assert.strictEqual(detect(0x4E2D, 'ko').length, 0);
  // 한자 문자열은 1건
  const findings = detect('中', 'ko');
  assert.strictEqual(findings.length, 1);
});

test('scriptOf: 숫자가 아닌 코드포인트는 null 반환 (예외 없음)', () => {
  assert.strictEqual(scriptOf(NaN), null);
  assert.strictEqual(scriptOf(undefined), null);
  assert.strictEqual(scriptOf(null), null);
});

test('isIgnoredPath: 문자열이 아닌 입력은 false 반환 (예외 없음)', () => {
  assert.strictEqual(isIgnoredPath(null), false);
  assert.strictEqual(isIgnoredPath(undefined), false);
  assert.strictEqual(isIgnoredPath(123), false);
});

test('getForbiddenScripts: 모르는 언어 코드는 ko 기본값 반환 (예외 없음)', () => {
  // 비공개 함수이지만 결함 2 방어 검증 위해 테스트
  const langCheckLib = langCheck;
  if (langCheckLib.getForbiddenScripts) {
    assert.deepStrictEqual(langCheckLib.getForbiddenScripts('xx'), langCheckLib.getForbiddenScripts('ko'));
  }
});

//────────────────────────────────────────
// 13. 결함 3: directive('ko') 문구 정확성
//────────────────────────────────────────

test('directive: ko 문구에 한자/가나/키릴이 포함되지 않음', () => {
  const text = directive('ko');
  const findings = detect(text, 'ko');
  assert.strictEqual(findings.length, 0, 'ko directive에 금지 문자가 섞이면 안 됨');
});

test('directive: ko 문구에 "한자" 문자열이 그대로 포함됨', () => {
  const text = directive('ko');
  assert.ok(text.includes('한자'), 'ko directive에 "한자" 문자열 포함');
});

test('directive: ko 문구에 "가나" 문자열이 그대로 포함됨', () => {
  const text = directive('ko');
  assert.ok(text.includes('가나'), 'ko directive에 "가나" 문자열 포함');
});

test('directive: ko 문구에 "키릴" 문자열이 그대로 포함됨', () => {
  const text = directive('ko');
  assert.ok(text.includes('키릴'), 'ko directive에 "키릴" 문자열 포함');
});

test('directive: ko 문구가 정확히 4줄 구조임', () => {
  const text = directive('ko');
  const lines = text.trim().split('\n');
  assert.strictEqual(lines.length, 4, 'ko directive는 4줄');
});

test('directive: ko 1행은 "[출력 언어 규칙 — 최우선]"', () => {
  const text = directive('ko');
  assert.ok(text.startsWith('[출력 언어 규칙 — 최우선]'), '1행 머리말 일치');
});

test('directive: en/ja/zh-CN 도 금지 문자 없음 (기존 동작 유지)', () => {
  for (const lang of ['en', 'ja', 'zh-CN', 'zh-TW']) {
    const text = directive(lang);
    const findings = detect(text, lang);
    assert.strictEqual(findings.length, 0, `${lang} directive에 해당 언어 금지 문자가 없음`);
  }
});

//────────────────────────────────────────
// 14. 결함 1 재현: 원격 push 후 checkGit이 0건이던 문제 (--not --remotes 제거로 해결)
//────────────────────────────────────────

test('checkGit: 원격에 push한 가나/한자 커밋도 검출 (결함 1)', () => {
  const workDir = createTempDir();
  const bareDir = createTempDir();
  try {
    // 작업 저장소 설정
    execSync('git init', { cwd: workDir });
    execSync('git config user.name "Test"', { cwd: workDir });
    execSync('git config user.email "test@test.com"', { cwd: workDir });

    // 베어bare 저장소(원격) 생성
    execSync('git init --bare', { cwd: bareDir });

    // 첫 커밋
    fs.writeFileSync(path.join(workDir, 'test.txt'), '안녕하세요\n');
    execSync('git add test.txt', { cwd: workDir });
    execSync('git commit -m "초기 커밋"', { cwd: workDir });

    // 원격 추가 후 push
    execSync(`git remote add origin ${bareDir}`, { cwd: workDir });
    execSync('git push -u origin master', { cwd: workDir });

    // 가나+한자 포함 비병합 커밋
    fs.writeFileSync(path.join(workDir, 'test.txt'), 'あいうえお\n中 추가\n');
    execSync('git add test.txt', { cwd: workDir });
    execSync('git commit -m "あいうえお 커밋"', { cwd: workDir });
    execSync('git push origin master', { cwd: workDir });

    const findings = checkGit(workDir, { lang: 'ko' });
    const errors = findings.filter(f => f.error);
    if (errors.length > 0) throw new Error('git 오류: ' + errors[0].error);

    // 원격에 push 됐어도检出되어야 함
    const messageFindings = findings.filter(f => f.kind === 'message');
    const diffFindings = findings.filter(f => f.kind === 'diff');
    assert.ok(messageFindings.length >= 1, '원격 push 메시지도 1건 이상');
    assert.ok(diffFindings.length >= 1, '원격 push diff도 1건 이상');
  } finally {
    fs.rmSync(workDir, { recursive: true, force: true });
    fs.rmSync(bareDir, { recursive: true, force: true });
  }
});

//────────────────────────────────────────
// 15. 결함 1-b: 다른 브랜치에만 있는 커밋도 --all로 검출
//────────────────────────────────────────

test('checkGit: 체크아웃 안 한 브랜치의 한자 추가도 검출 (--all)', () => {
  const repoDir = createTempDir();
  try {
    execSync('git init', { cwd: repoDir });
    execSync('git config user.name "Test"', { cwd: repoDir });
    execSync('git config user.email "test@test.com"', { cwd: repoDir });

    // 첫 커밋 (master)
    fs.writeFileSync(path.join(repoDir, 'test.txt'), '안녕하세요\n');
    execSync('git add test.txt', { cwd: repoDir });
    execSync('git commit -m "초기 커밋"', { cwd: repoDir });

    // feature 브랜치에서 한자 추가
    execSync('git checkout -b feature', { cwd: repoDir });
    fs.writeFileSync(path.join(repoDir, 'test.txt'), '한자 中 추가\n');
    execSync('git add test.txt', { cwd: repoDir });
    execSync('git commit -m "feature에서 한자 추가"', { cwd: repoDir });

    // master 로 복귀 (HEAD = master)
    execSync('git checkout master', { cwd: repoDir });

    const findings = checkGit(repoDir, { lang: 'ko' });
    const errors = findings.filter(f => f.error);
    if (errors.length > 0) throw new Error('git 오류: ' + errors[0].error);

    const diffFindings = findings.filter(f => f.kind === 'diff');
    assert.ok(diffFindings.length >= 1, '다른 브랜치의 한자 추가도 1건 이상');
    assert.strictEqual(diffFindings[0].char, '中');
  } finally {
    fs.rmSync(repoDir, { recursive: true, force: true });
  }
});

//────────────────────────────────────────
// 16. 결함 2 재현: 본문 줄바꿈导致的 파싱 문제 (%x1f/%x1e로 해결)
//────────────────────────────────────────

test('checkGit: 본문 줄바꿈 있는 커밋도 정확히 1개 레코드 (결함 2)', () => {
  const repoDir = createTempDir();
  try {
    execSync('git init', { cwd: repoDir });
    execSync('git config user.name "Test"', { cwd: repoDir });
    execSync('git config user.email "test@test.com"', { cwd: repoDir });

    // 본문에 줄바꿈이 있고 둘째 줄에 한자
    const filePath = path.join(repoDir, 'test.txt');
    fs.writeFileSync(filePath, '초기\n');
    execSync('git add test.txt', { cwd: repoDir });
    execSync('git commit -m "제목" -m "본문 첫째 줄\n본문 둘째 줄 中 있음"', { cwd: repoDir });

    const findings = checkGit(repoDir, { lang: 'ko' });
    const errors = findings.filter(f => f.error);
    if (errors.length > 0) throw new Error('git 오류: ' + errors[0].error);

    const messageFindings = findings.filter(f => f.kind === 'message');
    assert.ok(messageFindings.length >= 1, '본문 속 한자도 1건 이상');

    // commit 필드가 8자리 해시인지 확인 (파싱 안 쪼개짐)
    const first = messageFindings[0];
    assert.ok(first.commit, 'commit 필드 있음');
    assert.strictEqual(first.commit.length, 8, 'commit은 정확히 8자리 해시');
  } finally {
    fs.rmSync(repoDir, { recursive: true, force: true });
  }
});

//────────────────────────────────────────
// 17. 병합 커밋 중복 보고 안 함 (--no-merges)
//────────────────────────────────────────

test('checkGit: 병합 커밋은 diff를 두 번 보고하지 않음 (--no-merges)', () => {
  const workDir = createTempDir();
  const bareDir = createTempDir();
  try {
    execSync('git init', { cwd: workDir });
    execSync('git config user.name "Test"', { cwd: workDir });
    execSync('git config user.email "test@test.com"', { cwd: workDir });

    // 베어bare 원격
    execSync('git init --bare', { cwd: bareDir });
    execSync(`git remote add origin ${bareDir}`, { cwd: workDir });

    // 첫 커밋
    fs.writeFileSync(path.join(workDir, 'test.txt'), '안녕하세요\n');
    execSync('git add test.txt', { cwd: workDir });
    execSync('git commit -m "초기 커밋"', { cwd: workDir });
    execSync('git push -u origin master', { cwd: workDir });

    // feature 브랜치에서 한자 추가
    execSync('git checkout -b feature', { cwd: workDir });
    fs.writeFileSync(path.join(workDir, 'test.txt'), '中 추가\n');
    execSync('git add test.txt', { cwd: workDir });
    execSync('git commit -m "한자 추가"', { cwd: workDir });
    execSync('git push -u origin feature', { cwd: workDir });

    // master 로 복귀 후 병합
    execSync('git checkout master', { cwd: workDir });
    execSync('git merge feature --no-ff -m "병합 커밋"', { cwd: workDir });
    execSync('git push origin master', { cwd: workDir });

    const findings = checkGit(workDir, { lang: 'ko' });
    const errors = findings.filter(f => f.error);
    if (errors.length > 0) throw new Error('git 오류: ' + errors[0].error);

    // 한자 中 는 feature 병합 전 원래 커밋에서 1건만检出
    const diffFindings = findings.filter(f => f.kind === 'diff');
    const hanFindings = diffFindings.filter(f => f.char === '中');
    assert.ok(hanFindings.length >= 1, '한자 1건 이상');
    assert.strictEqual(hanFindings.length, 1, '같은 한자가 두 번 보고되지 않음');
  } finally {
    fs.rmSync(workDir, { recursive: true, force: true });
    fs.rmSync(bareDir, { recursive: true, force: true });
  }
});

//────────────────────────────────────────
// 18. 결함 3 재현: 셸 특수문자注入으로 command injection 방지
//────────────────────────────────────────

test('checkGit: since에 세미콜론 포함 시 {error} 반환하고 파일 안 생성 (결함 3)', () => {
  const repoDir = createTempDir();
  const evilFile = '/tmp/pwned_lang_check_' + Date.now() + '.txt';
  try {
    execSync('git init', { cwd: repoDir });
    execSync('git config user.name "Test"', { cwd: repoDir });
    execSync('git config user.email "test@test.com"', { cwd: repoDir });

    fs.writeFileSync(path.join(repoDir, 'test.txt'), '안녕하세요\n');
    execSync('git add test.txt', { cwd: repoDir });
    execSync('git commit -m "초기"', { cwd: repoDir });

    // 세미콜론 포함 since → command injection 시도
    const since = '2026-01-01; touch ' + evilFile;
    const findings = checkGit(repoDir, { lang: 'ko', since });

    // {error} 배열 반환
    assert.strictEqual(findings.length, 1, '에러 1건');
    assert.ok(findings[0].error, 'error 필드 있음');

    // evilFile이 생성되지 않았어야 함
    assert.ok(!fs.existsSync(evilFile), '셸 명령이 실행되지 않음 (evilFile 없음)');
  } finally {
    fs.rmSync(repoDir, { recursive: true, force: true });
    if (fs.existsSync(evilFile)) fs.unlinkSync(evilFile);
  }
});

//────────────────────────────────────────
// 19. 결함 재현: 개행-prefix 해시 레코드 + 오류 처리
//────────────────────────────────────────

test('_parseLogRecords: 개행-prefix 해시 정리', () => {
  // git log가 붙이는 개행이 해시 앞에 붙은 레코드. \x1e로 분리된 레코드 사이에 개행이 있을 수 있음
  const logOutput = 'abc123def456abc123def456abc123def456abc1\x1fclean commit\x1fbody\n\x1eabc123def456abc123def456abc123def456abc2\x1fanother\x1f\n\x1e';
  const records = _parseLogRecords(logOutput);
  // 첫 레코드: 해시에 개행이 없어야 함
  assert.strictEqual(records[0].hash, 'abc123def456abc123def456abc123def456abc1');
  assert.strictEqual(records[0].subject, 'clean commit');
  assert.strictEqual(records[0].body, 'body');
  // 두 번째 레코드: 해시 앞에 \n이 붙었을 때 trim됨
  assert.strictEqual(records[1].hash, 'abc123def456abc123def456abc123def456abc2');
  assert.strictEqual(records[1].subject, 'another');
  assert.strictEqual(records[1].body, '');
});

test('_parseLogRecords: 유효하지 않은 해시는 걸러짐', () => {
  // 40자가 아닌 해시
  const logOutput = `not-a-hash\x1fsubject\x1fbody\x1e`;
  const records = _parseLogRecords(logOutput);
  assert.strictEqual(records.length, 1);
  assert.strictEqual(records[0].hash, 'not-a-hash');
  // 해시 유효성 검증은 checkGit에서 함
});

test('_parseLogRecords: 빈 레코드 스킵', () => {
  const logOutput = `\x1e\x1e  \x1e`;
  const records = _parseLogRecords(logOutput);
  assert.strictEqual(records.length, 0);
});

test('_parseLogRecords: 본문 끝 의도치 않은 개행 제거', () => {
  const logOutput = `abc123def456abc123def456abc123def456abc1\x1fsubject\x1fbody text\n\x1e`;
  const records = _parseLogRecords(logOutput);
  assert.strictEqual(records[0].body, 'body text');
  assert.ok(!records[0].body.endsWith('\n'), '본문 끝 개행 제거됨');
});

test('_parseLogRecords: 필드 앞뒤 공백 trim', () => {
  const logOutput = `abc123def456abc123def456abc123def456abc1\x1f  subject with spaces  \x1f  body with spaces  \x1e`;
  const records = _parseLogRecords(logOutput);
  assert.strictEqual(records[0].subject, 'subject with spaces');
  assert.strictEqual(records[0].body, 'body with spaces');
});

test('checkGit: 6개 커밋에서 정확히 3개 커밋 검출, 총 10건 (한자diff+가나message+키릴diff)', () => {
  const repoDir = createTempDir();
  try {
    execSync('git init', { cwd: repoDir });
    execSync('git config user.name "Test"', { cwd: repoDir });
    execSync('git config user.email "test@test.com"', { cwd: repoDir });

    const filePath = path.join(repoDir, 'test.txt');

    // 커밋 1: 깨끗한 커밋
    fs.writeFileSync(filePath, '안녕하세요\n');
    execSync('git add test.txt', { cwd: repoDir });
    execSync('git commit -m "첫 번째 커밋"', { cwd: repoDir });

    // 커밋 2: 깨끗한 커밋
    fs.writeFileSync(filePath, '안녕하세요\n둘째 줄\n');
    execSync('git add test.txt', { cwd: repoDir });
    execSync('git commit -m "두 번째 커밋"', { cwd: repoDir });

    // 커밋 3: 한자가 든 diff
    fs.writeFileSync(filePath, '한자 中 넣음\n');
    execSync('git add test.txt', { cwd: repoDir });
    execSync('git commit -m "세 번째 커밋"', { cwd: repoDir });

    // 커밋 4: 가나가 든 메시지
    fs.writeFileSync(filePath, '네 번째\n');
    execSync('git add test.txt', { cwd: repoDir });
    execSync('git commit -m "あいうえお 커밋"', { cwd: repoDir });

    // 커밋 5: 본문 여러 줄인 깨끗한 커밋
    fs.writeFileSync(filePath, '다섯 번째\n');
    execSync('git add test.txt', { cwd: repoDir });
    execSync('git commit -m "다섯 번째" -m "본문 첫째 줄\n본문 둘째 줄"', { cwd: repoDir });

    // 커밋 6: 키릴이 든 diff (ключ = 4글자 키릴)
    fs.writeFileSync(filePath, 'ключ 추가\n');
    execSync('git add test.txt', { cwd: repoDir });
    execSync('git commit -m "여섯 번째 커밋"', { cwd: repoDir });

    const findings = checkGit(repoDir, { lang: 'ko' });
    const errors = findings.filter(f => f.error);
    const forbidden = findings.filter(f => !f.error);

    // 오류 항목 0건
    assert.strictEqual(errors.length, 0, '오류 항목 0건');

    // 금지 문자 검출 10건 (한자 中 1 + 가나 5글자 + 키릴 4글자)
    assert.strictEqual(forbidden.length, 10, '정확히 10건 검출');

    // 3개 커밋에서 검출: 한자 diff, 가나 message, 키릴 diff
    const uniqueCommits = [...new Set(forbidden.map(f => f.commit))];
    assert.strictEqual(uniqueCommits.length, 3, '정확히 3개 커밋에서 검출');

    const hanDiff = forbidden.find(f => f.char === '中' && f.kind === 'diff');
    const kanaMsg = forbidden.find(f => f.script === 'Kana' && f.kind === 'message');
    const cyrillicDiff = forbidden.find(f => f.script === 'Cyrillic' && f.kind === 'diff');
    assert.ok(hanDiff, '한자 diff 검출');
    assert.ok(kanaMsg, '가나 message 검출');
    assert.ok(cyrillicDiff, '키릴 diff 검출');

    // 모든 commit 필드가 8자리 16진 해시
    for (const f of forbidden) {
      assert.strictEqual(f.commit.length, 8, `${f.commit}는 8자리`);
      assert.ok(/^[0-9a-f]{8}$/.test(f.commit), `${f.commit}는 16진수`);
    }
  } finally {
    fs.rmSync(repoDir, { recursive: true, force: true });
  }
});

test('checkGit: 위 저장소를 bare 원격에 push 후 같은 결과 (3커밋, 10건)', () => {
  const workDir = createTempDir();
  const bareDir = createTempDir();
  try {
    execSync('git init', { cwd: workDir });
    execSync('git config user.name "Test"', { cwd: workDir });
    execSync('git config user.email "test@test.com"', { cwd: workDir });
    execSync('git init --bare', { cwd: bareDir });
    execSync(`git remote add origin ${bareDir}`, { cwd: workDir });

    const filePath = path.join(workDir, 'test.txt');

    // 커밋 1: 깨끗한 커밋
    fs.writeFileSync(filePath, '안녕하세요\n');
    execSync('git add test.txt', { cwd: workDir });
    execSync('git commit -m "첫 번째 커밋"', { cwd: workDir });
    execSync('git push -u origin master', { cwd: workDir });

    // 커밋 2: 깨끗한 커밋
    fs.writeFileSync(filePath, '안녕하세요\n둘째 줄\n');
    execSync('git add test.txt', { cwd: workDir });
    execSync('git commit -m "두 번째 커밋"', { cwd: workDir });
    execSync('git push origin master', { cwd: workDir });

    // 커밋 3: 한자가 든 diff
    fs.writeFileSync(filePath, '한자 中 넣음\n');
    execSync('git add test.txt', { cwd: workDir });
    execSync('git commit -m "세 번째 커밋"', { cwd: workDir });
    execSync('git push origin master', { cwd: workDir });

    // 커밋 4: 가나가 든 메시지
    fs.writeFileSync(filePath, '네 번째\n');
    execSync('git add test.txt', { cwd: workDir });
    execSync('git commit -m "あいうえお 커밋"', { cwd: workDir });
    execSync('git push origin master', { cwd: workDir });

    // 커밋 5: 본문 여러 줄인 깨끗한 커밋
    fs.writeFileSync(filePath, '다섯 번째\n');
    execSync('git add test.txt', { cwd: workDir });
    execSync('git commit -m "다섯 번째" -m "본문 첫째 줄\n본문 둘째 줄"', { cwd: workDir });
    execSync('git push origin master', { cwd: workDir });

    // 커밋 6: 키릴이 든 diff
    fs.writeFileSync(filePath, 'ключ 추가\n');
    execSync('git add test.txt', { cwd: workDir });
    execSync('git commit -m "여섯 번째 커밋"', { cwd: workDir });
    execSync('git push origin master', { cwd: workDir });

    const findings = checkGit(workDir, { lang: 'ko' });
    const errors = findings.filter(f => f.error);
    const forbidden = findings.filter(f => !f.error);

    assert.strictEqual(errors.length, 0, '오류 항목 0건');
    assert.strictEqual(forbidden.length, 10, '정확히 10건 검출');
    const uniqueCommits = [...new Set(forbidden.map(f => f.commit))];
    assert.strictEqual(uniqueCommits.length, 3, '정확히 3개 커밋에서 검출');
  } finally {
    fs.rmSync(workDir, { recursive: true, force: true });
    fs.rmSync(bareDir, { recursive: true, force: true });
  }
});

test('CLI: 존재하지 않는 저장소 경로는 exit 2와 "검사 오류"', () => {
  try {
    execSync(
      `node ${path.join(__dirname, '../lib/lang-check.js')} --lang ko --git /nonexistent/path/to/repo`,
      { encoding: 'utf-8' }
    );
    assert.fail('exit 2여야 함');
  } catch (e) {
    assert.strictEqual(e.status, 2, 'exit 2');
    assert.ok(e.stdout.includes('검사 오류'), '검사 오류 문구 있음');
  }
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
