// dump-argv.mjs — PowerShell → node 네이티브 인자 경계 관찰용 픽스처 (giip 6620)
//
// 왜 필요한가 (실측 재현, 2026-11-28):
//   Windows PowerShell 5.1 이 네이티브 명령에 인자를 넘길 때, 값 안에 큰따옴표(")가 있으면
//   명령줄 재구성 단계에서 따옴표가 인자 구분자로 취급되어 **값이 두 토큰으로 쪼개진다.**
//   node 가 받는 process.argv 를 그대로 파일로 적어 그 사실을 관찰 가능하게 만든다.
//
// 사용: node dump-argv.mjs <outJsonFile> [--flag value ...]
//   → <outJsonFile> 에 {"args":[...]} 를 UTF-8 로 적는다(한글 손실 방지를 위해 stdout 이 아니라 파일).
//
// 注意: 이 픽스처는 아무 원격 호출도 하지 않는다 — 오직 인자가 어떻게 도착했는지만 기록한다.
import fs from 'fs';

const argv = process.argv.slice(2);
const out = argv.shift();
if (!out) {
  console.error('usage: node dump-argv.mjs <outJsonFile> [--flag value ...]');
  process.exit(1);
}
fs.writeFileSync(out, JSON.stringify({ args: argv }, null, 0), 'utf8');
