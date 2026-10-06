'use strict';

/**
 * 언어 검사기 - MiniMax 같은 모델이 쓴 글에 금지 문자가 섞였는지 검사한다.
 * 코드포인트 기준 문자 분류와 언어별 허용/금지 규칙을 제공한다.
 */

//────────────────────────────────────────
// 문자 분류 (코드포인트 기준)
//────────────────────────────────────────

/**
 * 코드포인트로 스크립트 이름 반환. 없으면 null.
 * @param {number} codePoint
 * @returns {string|null}
 */
function scriptOf(codePoint) {
  // 숫자가 아닌 경우
  if (typeof codePoint !== 'number' || Number.isNaN(codePoint)) return null;

  // 한자 (CJK Unified Ideographs, Extension A, Compatibility)
  if (
    (codePoint >= 0x4E00 && codePoint <= 0x9FFF) ||
    (codePoint >= 0x3400 && codePoint <= 0x4DBF) ||
    (codePoint >= 0xF900 && codePoint <= 0xFAFF) ||
    (codePoint >= 0x20000 && codePoint <= 0x2A6DF)
  ) {
    return 'Han';
  }
  // 가나 (히라가나 + 카타카나 + 반각 가나)
  if (
    (codePoint >= 0x3040 && codePoint <= 0x30FF) ||
    (codePoint >= 0x31F0 && codePoint <= 0x31FF) ||
    (codePoint >= 0xFF66 && codePoint <= 0xFF9F)
  ) {
    return 'Kana';
  }
  // 한글 (한글 음절 + 초성/중성/종성 + 한글 자모)
  if (
    (codePoint >= 0xAC00 && codePoint <= 0xD7A3) ||
    (codePoint >= 0x1100 && codePoint <= 0x11FF) ||
    (codePoint >= 0x3130 && codePoint <= 0x318F)
  ) {
    return 'Hangul';
  }
  // 키릴 문자
  if (codePoint >= 0x0400 && codePoint <= 0x04FF) {
    return 'Cyrillic';
  }
  // 기타 스크립트
  if (codePoint >= 0x0E00 && codePoint <= 0x0E7F) return 'Thai';
  if (codePoint >= 0x0600 && codePoint <= 0x06FF) return 'Arabic';
  if (codePoint >= 0x0590 && codePoint <= 0x05FF) return 'Hebrew';
  if (codePoint >= 0x0900 && codePoint <= 0x097F) return 'Devanagari';
  return null; // ASCII, 라틴, 숫자, 이모지 등은 항상 허용
}

//────────────────────────────────────────
// 언어별 금지 스크립트
//────────────────────────────────────────

/** @type {Record<string, string[]>} */
const FORBIDDEN_SCRIPTS = {
  ko: ['Han', 'Kana', 'Cyrillic', 'Thai', 'Arabic', 'Hebrew', 'Devanagari'],
  en: ['Han', 'Kana', 'Hangul', 'Cyrillic', 'Thai', 'Arabic', 'Hebrew', 'Devanagari'],
  ja: ['Hangul', 'Cyrillic', 'Thai', 'Arabic', 'Hebrew', 'Devanagari'],
  'zh-CN': ['Hangul', 'Kana', 'Cyrillic', 'Thai', 'Arabic', 'Hebrew', 'Devanagari'],
  'zh-TW': ['Hangul', 'Kana', 'Cyrillic', 'Thai', 'Arabic', 'Hebrew', 'Devanagari'],
};

/**
 * 언어 코드에 따른 금지 스크립트 배열 반환.
 * 모르는 코드는 'ko'로 취급.
 * @param {string} lang
 * @returns {string[]}
 */
function getForbiddenScripts(lang) {
  return FORBIDDEN_SCRIPTS[lang] || FORBIDDEN_SCRIPTS['ko'];
}

//────────────────────────────────────────
// detect
//────────────────────────────────────────

/**
 * 텍스트에서 금지 문자를 찾아 배열로 반환.
 * @param {string} text
 * @param {string} lang
 * @returns {Array<{line:number, col:number, char:string, codePoint:string, script:string, excerpt:string}>}
 */
function detect(text, lang = 'ko') {
  // 결함 2: 비문자열 입력 방어
  if (text == null) return [];
  if (typeof text !== 'string') text = String(text);

  const forbidden = new Set(getForbiddenScripts(lang));
  /** @type {Array<{line:number, col:number, char:string, codePoint:string, script:string, excerpt:string}>} */
  const results = [];
  const lines = text.split('\n');

  for (let lineIdx = 0; lineIdx < lines.length; lineIdx++) {
    const line = lines[lineIdx];
    const lineNum = lineIdx + 1; // 1부터 시작

    // lang-check:ignore 줄 건너뛰기
    if (line.includes('lang-check:ignore')) continue;

    // 결함 1: UTF-16 코드 유닛 대신 코드포인트 단위 순회
    // colUtf16은 excerpt 계산을 위한 UTF-16 코드 유닛 인덱스
    let colUtf16 = 0;
    for (const char of line) {
      const codePoint = char.codePointAt(0);
      if (codePoint === undefined) {
        colUtf16 += char.length;
        continue;
      }

      const script = scriptOf(codePoint);
      if (script && forbidden.has(script)) {
        // 서러게이트 쌍(char.length === 2)이면 완전한 문자로서 1건
        // excerpt: UTF-16 슬라이스 (기존 col语义 유지)
        const start = Math.max(0, colUtf16 - 20);
        const end = Math.min(line.length, colUtf16 + 21);
        const excerpt = line.slice(start, end);

        results.push({
          line: lineNum,
          col: colUtf16 + 1, // 1부터 시작 (UTF-16 코드 유닛 단위)
          char,
          codePoint: 'U+' + codePoint.toString(16).toUpperCase().padStart(4, '0'),
          script,
          excerpt,
        });
      }

      colUtf16 += char.length; // 서러게이트 쌍은 2, 그 외는 1
    }
  }

  return results;
}

//────────────────────────────────────────
// directive
//────────────────────────────────────────

/** @type {Record<string, string>} */
const DIRECTIVES = {
  ko: `[출력 언어 규칙 — 최우선]
이 작업에서 네가 쓰는 모든 글(코드 주석, 커밋 메시지, PR 본문, 문서, 이슈 코멘트, 최종 보고)은 100% 한국어(한글)로 쓴다.
한자, 일본어 가나, 중국어, 러시아어(키릴 문자) 등 다른 문자는 한 글자도 섞지 마라. 한국어가 어색하면 영어 단어를 그대로 쓰거나 한글로 소리 나는 대로 써라(다른 문자로 바꾸지 마라).
코드 식별자와 영어 고유명사는 그대로 둔다. 이 규칙은 응답 문장에도 적용된다.`,

  en: `[Output Language Rules — Highest Priority, Read Before Starting]
All text you write in this task (code comments, commit messages, documentation, test names, final reports) must be in English.
Do not mix in Korean Hangul, Chinese characters (Han), Japanese Kana, Cyrillic, or other scripts. Use English words directly if Korean sounds awkward.`,

  ja: `[出力言語ルール — 最重要、作業前に必ず読んでください]
このタスクで書くすべての文章（コードコメント、コミットメッセージ、ドキュメント、テスト名、最終報告など）は日本語で書いてください。
ハングル、漢字、キリル文字などは一字も混ぜないでください。英語が適切な場合は英語の単語をそのまま使ってください。`,

  'zh-CN': `[输出语言规则 — 最高优先级，作业前请先阅读]
此任务中您写的所有文字（代码注释、提交信息、文档、测试名称、最终报告等）必须使用简体中文。
请勿混入韩文字符、汉字假名、西里尔字母等其他文字。英语单词请直接使用原文。`,

  'zh-TW': `[輸出語言規則 — 最高優先級，作業前請先閱讀]
此任務中您寫的所有文字（代碼注釋、提交訊息、文檔、測試名稱、最終報告等）必須使用繁體中文。
請勿混入韓文字元、漢字假名、西里爾字母等其他文字。英語單詞請直接使用原文。`,
};

/**
 * 해당 언어의 출력 언어 규칙 머리말 문자열 반환.
 * @param {string} lang
 * @returns {string}
 */
function directive(lang = 'ko') {
  return DIRECTIVES[lang] || DIRECTIVES['ko'];
}

//────────────────────────────────────────
// isIgnoredPath
//────────────────────────────────────────

/**
 * 검사에서 제외할 경로인지 반환.
 * @param {string} filePath
 * @returns {boolean}
 */
function isIgnoredPath(filePath) {
  // 결함 2: 비문자열 입력 방어
  if (typeof filePath !== 'string') return false;

  // package-lock.json, pnpm-lock.yaml
  if (filePath.endsWith('package-lock.json')) return true;
  if (filePath.endsWith('pnpm-lock.yaml')) return true;

  // 특정 확장자
  const ignoreExts = ['.lock', '.snap', '.png', '.jpg', '.ico', '.woff', '.woff2', '.pdf', '.zip'];
  for (const ext of ignoreExts) {
    if (filePath.endsWith(ext)) return true;
  }

  // node_modules
  if (filePath.includes('node_modules')) return true;

  // /locales/ 경로 + ja/zh 파일
  if (filePath.includes('locales/')) {
    const base = filePath.split('/').pop() || '';
    if (/^(ja|zh)/.test(base) && base.endsWith('.json')) return true;
    if (base === 'giip.extra.ja.json') return true;
    if (base === 'giip.extra.zh.json') return true;
  }

  return false;
}

//────────────────────────────────────────
// checkGit
//────────────────────────────────────────

const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

/**
 * git log 레코드 파서. 해시 앞에 붙은 개행과 필드 앞뒤 공백을 정리한다.
 * @param {string} logOutput
 * @returns {Array<{hash:string, subject:string, body:string, raw:string}>}
 */
function _parseLogRecords(logOutput) {
  if (!logOutput || !logOutput.trim()) return [];
  const rawRecords = logOutput.trim().split('\x1e');
  const results = [];
  for (const record of rawRecords) {
    if (!record.trim()) continue;
    const parts = record.split('\x1f');
    if (parts.length < 3) continue;
    const hash = parts[0].trim();
    const subject = (parts[1] || '').trim();
    const body = (parts[2] || '').replace(/\r?\n$/, '').trim();
    results.push({ hash, subject, body, raw: record });
  }
  return results;
}

/**
 * git 저장소에서 since 이후 커밋과 diff를 검사.
 * @param {string} repoDir
 * @param {{since?:string, lang?:string, maxFindings?:number}} options
 * @returns {Array<Object>}
 */
function checkGit(repoDir, options = {}) {
  const { since, lang = 'ko', maxFindings = 50 } = options;
  /** @type {Array<Object>} */
  const findings = [];

  // since 값에 셸 특수문자(含 세미콜론) 있으면 실행하지 않고 오류 반환
  if (since && /[;`$|<>]/.test(since)) {
    return [{ error: `since 값에 셸 특수문자가 포함되어 있습니다: ${since}` }];
  }

  try {
    // 비병합 커밋 가져오기: 모든 브랜치(--all) 대상
    // 병합 커밋 제외(--no-merges), since 이후 커밋만
    const logArgs = ['log', '--all', '--no-merges', `--format=%H%x1f%s%x1f%b%x1e`];
    if (since) {
      logArgs.push(`--since=${since}`);
    }
    const logOutput = execFileSync('git', logArgs, {
      cwd: repoDir,
      encoding: 'utf-8',
      timeout: 30000,
      maxBuffer: 64 * 1024 * 1024,
      stdio: ['ignore', 'pipe', 'pipe'],
    });

    if (!logOutput.trim()) {
      return findings;
    }

    // _parseLogRecords로 파싱 (개행 정리 + 해시 검증)
    const records = _parseLogRecords(logOutput);

    for (const record of records) {
      if (findings.length >= maxFindings) break;

      // 해시 유효성 검증
      if (!/^[0-9a-f]{40}$/.test(record.hash)) {
        findings.push({ error: '잘못된 커밋 해시 레코드' });
        continue;
      }

      const commitShort = record.hash.slice(0, 8);
      const message = record.subject + '\n' + record.body;

      // 메시지 검사 (제목 + 본문 전체)
      const messageFindings = detect(message, lang);
      for (const f of messageFindings) {
        if (findings.length >= maxFindings) break;
        findings.push({
          commit: commitShort,
          kind: 'message',
          file: null,
          line: null,
          char: f.char,
          codePoint: f.codePoint,
          script: f.script,
          excerpt: f.excerpt,
        });
      }

      // diff 검사
      let diffOk = true;
      try {
        const diffArgs = [
          'show', record.hash,
          '--unified=0', '--no-color', '--format=', '--diff-filter=AMR',
          ':(exclude)*.lock', ':(exclude)package-lock.json', ':(exclude)pnpm-lock.yaml',
        ];
        const diffOutput = execFileSync('git', diffArgs, {
          cwd: repoDir,
          encoding: 'utf-8',
          timeout: 30000,
          maxBuffer: 64 * 1024 * 1024,
          stdio: ['ignore', 'pipe', 'pipe'],
        });
        const diffLines = diffOutput.split('\n');

        let currentFile = null;
        let inDiff = false;
        let newFileLineNum = 0;

        for (let i = 0; i < diffLines.length; i++) {
          if (findings.length >= maxFindings) break;
          const dLine = diffLines[i];

          // 파일 헤더 (--- a/... +++ b/...)
          const fileMatch = dLine.match(/^\+\+\+ b\/(.+)/);
          if (fileMatch) {
            currentFile = fileMatch[1];
            inDiff = false;
            newFileLineNum = 0;
            if (isIgnoredPath(currentFile)) {
              currentFile = null; // 무시
            }
            continue;
          }

          // 새 파일의 diff 시작
          const diffStartMatch = dLine.match(/^@@ -\d+(?:,\d+)? \+(\d+)/);
          if (diffStartMatch && currentFile) {
            inDiff = true;
            newFileLineNum = parseInt(diffStartMatch[1], 10);
            continue;
          }

          // 바이너리 파일 건너뛰기
          if (dLine.startsWith('Binary files')) {
            inDiff = false;
            continue;
          }

          // + 줄만 검사 (추가된 줄)
          if (inDiff && dLine.startsWith('+') && !dLine.startsWith('+++')) {
            if (currentFile) {
              const lineContent = dLine.slice(1); // + 제거
              const lineFindings = detect(lineContent, lang);
              for (const f of lineFindings) {
                if (findings.length >= maxFindings) break;
                findings.push({
                  commit: commitShort,
                  kind: 'diff',
                  file: currentFile,
                  line: newFileLineNum,
                  char: f.char,
                  codePoint: f.codePoint,
                  script: f.script,
                  excerpt: f.excerpt,
                });
              }
            }
            newFileLineNum++;
          }
        }
      } catch (diffErr) {
        // git show 실패 시 조용히 오류 레코드를 결과에 추가하고 계속
        findings.push({ error: `커밋 ${commitShort}: ${diffErr.message || diffErr}` });
        diffOk = false;
      }
    }
  } catch (err) {
    // git 실패 시 오류 객체 반환
    return [{ error: String(err.message || err) }];
  }

  return findings;
}

//────────────────────────────────────────
// CLI
//────────────────────────────────────────

/** @type {string[]} */
const CLI_ARGS = process.argv.slice(2);

function cliHelp() {
  console.log(`사용법:
  node lang-check.js --lang <코드> --text-file <파일>
  node lang-check.js --lang <코드> --stdin
  node lang-check.js --lang <코드> --git <저장소경로> --since <ISO시각>
  node lang-check.js --directive --lang <코드>
  node lang-check.js --json ...

옵션:
  --lang <코드>     대상 언어 (ko, en, ja, zh-CN, zh-TW)
  --text-file <파일> 텍스트 파일 검사
  --stdin           표준입력 검사
  --git <경로>      git 저장소 검사 (여러 번 지정 가능)
  --since <ISO시각>  검사할 커밋 범위 (ISO 8601)
  --directive       출력 언어 규칙 머리말 출력
  --json            JSON 출력 형식
  --max-findings <N> 최대 발견 건수 (기본 50)`);
}

/**
 * CLI 실행.
 */
function runCli() {
  if (require.main !== module) return;

  const lang = extractFlag('--lang') || 'ko';
  const textFile = extractFlag('--text-file');
  const stdin = hasFlag('--stdin');
  const gitDirs = extractFlags('--git');
  const since = extractFlag('--since');
  const directiveFlag = hasFlag('--directive');
  const asJson = hasFlag('--json');
  const maxFindings = parseInt(extractFlag('--max-findings') || '50', 10);

  let text = '';

  if (directiveFlag) {
    text = directive(lang);
    if (asJson) {
      console.log(JSON.stringify({ directive: text }, null, 2));
    } else {
      console.log(text);
    }
    process.exit(0);
  }

  if (textFile) {
    try {
      text = fs.readFileSync(textFile, 'utf-8');
    } catch (e) {
      console.error('파일을 읽을 수 없습니다: ' + textFile);
      process.exit(2);
    }
  } else if (stdin) {
    text = fs.readFileSync(0, 'utf-8'); // stdin
  } else if (gitDirs.length > 0) {
    /** @type {Array<Object>} */
    let allFindings = [];
    for (const gitDir of gitDirs) {
      const findings = checkGit(gitDir, { since, lang, maxFindings: maxFindings - allFindings.length });
      allFindings = allFindings.concat(findings);
      if (allFindings.length >= maxFindings) break;
    }
    allFindings = allFindings.slice(0, maxFindings);

    // error 항목과 금지 문자 항목 분리
    const errorItems = allFindings.filter(f => f.error);
    const forbiddenItems = allFindings.filter(f => !f.error);

    if (asJson) {
      console.log(JSON.stringify({ findings: allFindings }, null, 2));
    } else {
      if (errorItems.length > 0) {
        console.log(`검사 오류 ${errorItems.length}건`);
        console.log('  ' + errorItems[0].error);
      }
      if (forbiddenItems.length > 0) {
        printHumanOutput(forbiddenItems, maxFindings);
      } else if (errorItems.length === 0) {
        console.log('문제 없음 (0건)');
      }
    }

    // 금지 문자가 있으면 4, 오류만 있으면 2, 둘 다 있으면 4
    if (forbiddenItems.length > 0) {
      process.exit(4);
    } else if (errorItems.length > 0) {
      process.exit(2);
    } else {
      process.exit(0);
    }
  } else {
    cliHelp();
    process.exit(2);
  }

  const findings = detect(text, lang).slice(0, maxFindings);

  if (asJson) {
    console.log(JSON.stringify({ findings }, null, 2));
  } else {
    printHumanOutput(findings, maxFindings);
  }

  process.exit(findings.length > 0 ? 4 : 0);
}

/** @type {string|null} */
function extractFlag(/** @type {string} */ flag) {
  const idx = CLI_ARGS.indexOf(flag);
  if (idx === -1 || idx + 1 >= CLI_ARGS.length) return null;
  return CLI_ARGS[idx + 1];
}

/** @type {string[]} */
function extractFlags(/** @type {string} */ flag) {
  /** @type {string[]} */
  const result = [];
  for (let i = 0; i < CLI_ARGS.length; i++) {
    if (CLI_ARGS[i] === flag && i + 1 < CLI_ARGS.length) {
      result.push(CLI_ARGS[i + 1]);
    }
  }
  return result;
}

/** @type {boolean} */
function hasFlag(/** @type {string} */ flag) {
  return CLI_ARGS.includes(flag);
}

/**
 * 사람이 읽는 형식으로 결과 출력.
 * @param {Array<Object>} findings
 * @param {number} maxFindings
 */
function printHumanOutput(findings, maxFindings) {
  if (findings.length === 0) {
    console.log('문제 없음 (0건)');
    return;
  }

  console.log(`금지 문자 발견: ${findings.length}건`);

  const shown = findings.slice(0, 20);
  for (const f of shown) {
    const loc = f.file
      ? `${f.file}@${f.line || '?'}:${f.col || '?'}`
      : f.commit
        ? `커밋 ${f.commit} (${f.kind})`
        : `줄 ${f.line}:${f.col}`;
    console.log(`  [${loc}] ${f.char} (${f.codePoint}) — ${f.script}`);
    console.log(`    "${f.excerpt}"`);
  }

  const rest = findings.length - 20;
  if (rest > 0) {
    console.log(`외 ${rest}건`);
  }
}

//────────────────────────────────────────
// exports
//────────────────────────────────────────

module.exports = {
  scriptOf,
  detect,
  directive,
  isIgnoredPath,
  checkGit,
  _parseLogRecords,
};

// CLI 실행
runCli();
