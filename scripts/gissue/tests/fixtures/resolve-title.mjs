// resolve-title.mjs — register-issue.js 의 순수 함수(parseArgs/resolveTitle)를 임의 인자 배열에
// 적용해 "그 인자로 등록됐을 때 제목이 무엇이 되는지"를 계산한다 (giip 6620).
//
// 왜 필요한가:
//   register-issue.js 의 제목 결정은 `parseArgs` → `resolveTitle` 두 단계로 이루어져 있고
//   `--title` 의 **바로 다음 토큰 하나만** 제목으로 읽는다. 따라서 PowerShell 인자 경계에서
//   값이 쪼개졌을 때(큰따옴표) 제목이 첫 조각으로 잘리고 '(원본 giip #NNNN)' 표식이 사라진다.
//   이 픽스처는 등록을 하지 않고 그 결과만 계산한다.
//
// 사용: node resolve-title.mjs <argsSpecJson> <outTxt>
//   argsSpecJson = {"args":["--title","값"]} 또는 {"args":["--title-file","C:/path.txt"]}
//                 (선택) "content" 키로 본문을 줄 수 있다(없으면 빈 문자열).
//
// 注意: register-issue.js 는 `require.main === module` 일 때만 main() 을 돌리므로 여기서는
//   절대 등록(issueCreate) 이 일어나지 않는다.
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { createRequire } from 'module';

const here = path.dirname(fileURLToPath(import.meta.url));
const require = createRequire(import.meta.url);
const { parseArgs, resolveTitle } = require(path.join(here, '..', '..', 'register-issue.js'));

const [specFile, outFile] = process.argv.slice(2);
if (!specFile || !outFile) {
  console.error('usage: node resolve-title.mjs <argsSpecJson> <outTxt>');
  process.exit(1);
}
const spec = JSON.parse(fs.readFileSync(specFile, 'utf8'));
const args = Array.isArray(spec.args) ? spec.args : [];
const a = parseArgs(['node', 'register-issue.js', ...args]);
const title = resolveTitle(a, typeof spec.content === 'string' ? spec.content : '');
fs.writeFileSync(outFile, title, 'utf8');
