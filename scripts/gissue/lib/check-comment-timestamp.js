#!/usr/bin/env node
/**
 * giip 코멘트 본문의 "이 코멘트 자신의 작성 시각"이 실제 현재 시각과 어긋나면 등록을 거부한다.
 * (giip #2442 — 사용자 직접 지시 "자꾸 실수하는 건 강제해줘")
 *
 * 배경:
 *   메모리 `feedback_timestamp_placeholder_in_gissue_comments` 가 이미 "시각을 조회 없이 추정해
 *   적지 말 것"을 규정하고 있었지만 2026-09-14 에 또 재발했다(date 조회와 코멘트 등록을 한 호출에
 *   묶어 `01:42 UTC` 로 적었으나 실제는 `01:37 UTC` — cSn 14450 을 지우고 14451 로 정정).
 *   문서 규칙은 계속 새어나가므로 `get-issue.sh` 자체가 기계적으로 막는다.
 *
 * 훅이 아니라 여기 있는 이유:
 *   PreToolUse 훅은 `--comment-file <경로>` 의 **파일 내용**을 볼 수 없다(payload 에는 명령 문자열만
 *   온다 — 2026-09-14 실측). 본문을 실제로 손에 쥐는 유일한 지점이 `get-issue.sh` 라서 여기서 검사한다.
 *
 * ⚠️ 오탐 방지 — 검사 대상을 "이 코멘트 자신의 작성 시각을 적는 자리"로만 한정한다.
 *   코멘트 본문에는 과거 사건의 시각이 정당하게 인용된다(예: "2026-09-06 22:39 에
 *   PR-GATE-HUMAN-REVIEW 가 붙었다"). 본문에 등장하는 모든 타임스탬프를 검사하면 안 된다.
 *   `.agent/rules/PROTOCOL_PROGRESS_COMMENT.md` 가 정한 두 자리만 본다:
 *     1) 대괄호 헤더      : `[착수: 2026-09-14 02:58 UTC / 11:58 +09:00 · dp01-console · orchestrator]`
 *     2) 상태전이 헤더 필드: `**시각(When)**: 2026-09-14 02:58 UTC`
 *   추가 안전장치:
 *     - 본문 첫 15줄(비어있지 않은 줄 기준)만 스캔한다. 헤더는 항상 맨 위에 온다.
 *     - ``` 코드펜스 안은 건너뛴다(과거 코멘트를 통째로 인용하는 경우).
 *     - `>` 로 시작하는 인용줄은 건너뛴다.
 *
 * 허용 오차: 기본 ±10분 (GISSUE_TIMESTAMP_TOLERANCE_MIN 으로 조정 가능).
 *   근거 — 코멘트 본문 작성부터 등록까지는 파일 쓰기/툴 왕복으로 수 분이 걸리는 게 정상이라 ±1~2분은
 *   너무 빡빡하고, 실제 사고(위 cSn 14450)는 5분 오차였다. 10분이면 정상 지연은 전부 통과시키면서
 *   "추정해서 적은 값"은 잡는다. 시/일 단위로 틀린 추정값도 당연히 걸린다.
 *
 * 사용법:
 *   node check-comment-timestamp.js "<본문>"
 *   node check-comment-timestamp.js "@<UTF-8 파일 경로>"
 * 종료코드: 0 = 통과, 2 = 거부(어긋난 시각).
 */
'use strict';

const fs = require('fs');

const TOLERANCE_MIN = Number(process.env.GISSUE_TIMESTAMP_TOLERANCE_MIN || 10);
const MAX_HEADER_LINES = 15;

// 존 토큰 → UTC 오프셋(분)
const ZONE_OFFSETS = {
  UTC: 0, Z: 0, GMT: 0, '+00:00': 0, '+0000': 0,
  KST: 540, JST: 540, '+09:00': 540, '+0900': 540,
};

const TS_RE = new RegExp(
  '(\\d{4})-(\\d{2})-(\\d{2})[ T](\\d{2}):(\\d{2})(?::\\d{2})?' + // 날짜+시각
  '\\s*(UTC|GMT|KST|JST|Z|\\+00:?00|\\+09:?00)?' +                // 1차 존(옵션)
  '(?:\\s*/\\s*(\\d{2}):(\\d{2})(?::\\d{2})?' +                   // " / HH:MM" 병기(옵션)
  '\\s*(UTC|GMT|KST|JST|Z|\\+00:?00|\\+09:?00)?)?'                // 2차 존(옵션)
);

// "이 코멘트 자신의 작성 시각"을 적는 자리 두 개만.
const HEADER_RES = [
  /^\s*\[[^\]\n]*?:\s*(?=\d{4}-)/,        // [착수: 2026-.. ] / [완료: ...] 등 대괄호 헤더
  /^\s*\*\*시각\(When\)\*\*\s*:\s*/,      // **시각(When)**: ...
];

function normZone(z) {
  if (!z) return null;
  const k = z.toUpperCase().replace(/^\+(\d\d):?(\d\d)$/, '+$1:$2');
  return Object.prototype.hasOwnProperty.call(ZONE_OFFSETS, k) ? ZONE_OFFSETS[k] : null;
}

/** 후보 epoch(분) 목록. 존이 없으면 UTC/KST 양쪽을 후보로 둔다(둘 중 하나만 맞아도 통과). */
function epochCandidates(y, mo, d, h, mi, zone) {
  const base = Date.UTC(y, mo - 1, d, h, mi) / 60000;
  const off = normZone(zone);
  const offsets = off === null ? [0, 540] : [off];
  return offsets.map((o) => base - o);
}

function readBody(arg) {
  if (arg.startsWith('@')) return fs.readFileSync(arg.slice(1), 'utf8');
  return arg;
}

function fmt(epochMin, offMin, label) {
  const d = new Date((epochMin + offMin) * 60000);
  const p = (n) => String(n).padStart(2, '0');
  return `${d.getUTCFullYear()}-${p(d.getUTCMonth() + 1)}-${p(d.getUTCDate())} ` +
         `${p(d.getUTCHours())}:${p(d.getUTCMinutes())} ${label}`;
}

function main() {
  const arg = process.argv[2];
  if (arg === undefined || arg === '') process.exit(0); // 검사할 본문 없음 = 통과
  let body;
  try {
    body = readBody(arg);
  } catch (e) {
    // 본문을 읽지 못하는 건 이 검사기의 책임 범위가 아니다(get-issue.sh 가 따로 검증한다).
    process.exit(0);
  }

  const nowMin = Math.floor(Date.now() / 60000);
  const lines = body.split(/\r?\n/);
  let inFence = false;
  let scanned = 0;
  const problems = [];

  for (const line of lines) {
    if (/^\s*```/.test(line)) { inFence = !inFence; continue; }
    if (inFence) continue;
    if (line.trim() === '') continue;
    if (scanned >= MAX_HEADER_LINES) break;
    scanned += 1;
    if (/^\s*>/.test(line)) continue; // 인용줄 = 남의 말/과거 코멘트

    const hdr = HEADER_RES.find((re) => re.test(line));
    if (!hdr) continue;
    const rest = line.replace(hdr, '');
    const m = TS_RE.exec(rest);
    if (!m) continue;

    const [, ys, mos, ds, hs, mis, z1, h2, mi2, z2] = m;
    const y = +ys, mo = +mos, d = +ds;

    // 1차 타임스탬프
    let cands = epochCandidates(y, mo, d, +hs, +mis, z1);
    let diff = Math.min(...cands.map((c) => Math.abs(c - nowMin)));
    if (diff > TOLERANCE_MIN) {
      problems.push({ line, value: m[0], diff, part: '주 타임스탬프' });
      continue;
    }

    // 병기된 2차 타임스탬프(`... UTC / 11:58 +09:00`). 날짜가 없으므로 전날/당일/다음날을 모두
    // 후보로 두고 가장 가까운 것을 쓴다(UTC↔KST 날짜 넘어감 대응).
    if (h2 !== undefined) {
      let best = Infinity;
      for (const shift of [-1, 0, 1]) {
        for (const c of epochCandidates(y, mo, d + shift, +h2, +mi2, z2)) {
          best = Math.min(best, Math.abs(c - nowMin));
        }
      }
      if (best > TOLERANCE_MIN) {
        problems.push({ line, value: `${h2}:${mi2}${z2 ? ' ' + z2 : ''}`, diff: best, part: '병기 타임스탬프' });
      }
    }
  }

  if (problems.length === 0) process.exit(0);

  const nowUtc = fmt(nowMin, 0, 'UTC');
  const nowKst = fmt(nowMin, 540, '+09:00');
  console.error('');
  console.error('[거부] 코멘트 본문의 작성 시각이 실제 현재 시각과 어긋납니다 (giip #2442 시각추정 차단 게이트).');
  console.error(`        허용 오차: +-${TOLERANCE_MIN}분`);
  for (const p of problems) {
    console.error(`  - ${p.part}: "${p.value}" -> 현재와 ${p.diff}분 차이`);
    console.error(`    해당 줄: ${p.line.trim().slice(0, 160)}`);
  }
  console.error('');
  console.error(`  실제 현재 시각: ${nowUtc} / ${nowKst}`);
  console.error('  본문의 헤더 시각을 위 값으로 고친 뒤 다시 등록하세요.');
  console.error('  (시각을 조회 없이 추정해 적는 재발 사고: cSn 14450 -> 14451 정정, 2026-09-14.');
  console.error('   date 조회와 코멘트 등록을 한 번의 도구 호출로 묶지 마세요 — 묶으면 조회 시점과 등록 시점이 벌어집니다.)');
  console.error('  검사 대상은 "이 코멘트 자신의 작성 시각" 자리(대괄호 헤더 / **시각(When)**:)뿐입니다.');
  console.error('  본문 중간에 과거 사건 시각을 인용하는 것은 검사하지 않습니다.');
  console.error('');
  process.exit(2);
}

main();
