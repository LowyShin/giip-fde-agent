#!/usr/bin/env node
// evaluate.mjs — Jev 의도 분류 정확도 평가 하니스 (giip 이슈 4222 / SPEC §8)
//
// 목적: 봇 의도 분류(task/question)의 3개 대조군을 같은 코퍼스로 돌려
//   정확도·task 재현율·question 정밀도·폴백율·지연(p50/p95)·토큰을 실측하고,
//   Jev 신뢰도 라우팅 임계값 T_hi/P_hi/P_lo 를 근거 있는 값으로 확정한다.
//
// 대조군(SPEC §8-2):
//   ① 현행      = 결정적 규칙(intent.js) + 기존 claude -p LLM 분류기(classifyRequest)
//   ② 규칙+Jev  = 결정적 규칙 → Jev(신뢰도 라우팅) → (미결 시 안전기본값 question)
//   ③ 권장 전체 = 결정적 규칙 → Jev → claude -p LLM 폴백
//
// 설계 원칙:
//   - 실제 파이프라인 함수를 그대로 재사용한다(intent.js 의 isForceTaskCmd/isConfirmationQuery/
//     classifyRequest, secret-mask 의 maskString). 하니스가 로직을 재구현하지 않는다.
//   - Jev 는 케이스당 1회만 호출하고 원응답(intent/confidence/requires_file_change)을 저장한다.
//     임계값 스윕은 저장된 원응답에 오프라인으로 적용한다(재호출 없음, 결정적).
//   - sk 는 환경변수 GIIP_SK 로만 주입한다. stdout/stderr/파일 어디에도 출력하지 않는다.
//   - 이 스크립트는 단위 테스트 스위트(node --test, 네트워크 0)와 분리된 별도 실행물이다.
//
// 사용법:
//   GIIP_SK=<sk> GIIP_JEV_GATEWAY_URL=<url> \
//   node slack-bot/eval/intent/evaluate.mjs --corpus slack-bot/eval/intent/corpus.jsonl [옵션]
// 옵션:
//   --groups 1,2,3     평가할 대조군(기본 1,2,3)
//   --t-hi/--p-hi/--p-lo <수>  고정 임계값으로 ②③ 평가(미지정이면 스윕으로 권장값 자동 선정)
//   --sweep            임계값 그리드 스윕 표를 출력(기본 on; --no-sweep 로 끔)
//   --repeat <n>       같은 입력을 Jev 에 n회 호출해 판정 일치율(flaky) 측정(기본 1)
//   --json             기계 판독용 JSON 을 마지막에 출력
//   --max-llm <n>      claude -p 호출 상한(비용·시간 보호, 기본 무제한)

import { createRequire } from 'node:module';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import https from 'node:https';
import http from 'node:http';

const require = createRequire(import.meta.url);
const __dirname = path.dirname(fileURLToPath(import.meta.url));
const BOT_DIR = path.resolve(__dirname, '..', '..'); // slack-bot/

// 실제 파이프라인 함수 재사용 (intent.js / secret-mask.js)
const { isForceTaskCmd, isConfirmationQuery, classifyRequest } = require(path.join(BOT_DIR, 'intent.js'));
const { maskString } = require(path.join(BOT_DIR, 'secret-mask.js'));

const DEFAULT_GATEWAY = 'https://giipfaw.azurewebsites.net/api/giipJevGateway';

// ── 인자 파싱 ───────────────────────────────────────────────────────────────
function parseArgs(argv) {
  const a = {
    corpus: path.join(__dirname, 'corpus.jsonl'),
    groups: [1, 2, 3],
    tHi: null, pHi: null, pLo: null,
    sweep: true, repeat: 1, json: false, maxLlm: Infinity,
  };
  for (let i = 2; i < argv.length; i++) {
    const k = argv[i];
    const next = () => argv[++i];
    if (k === '--corpus') a.corpus = next();
    else if (k === '--groups') a.groups = next().split(',').map((s) => Number(s.trim())).filter(Boolean);
    else if (k === '--t-hi') a.tHi = Number(next());
    else if (k === '--p-hi') a.pHi = Number(next());
    else if (k === '--p-lo') a.pLo = Number(next());
    else if (k === '--sweep') a.sweep = true;
    else if (k === '--no-sweep') a.sweep = false;
    else if (k === '--repeat') a.repeat = Math.max(1, Number(next()) || 1);
    else if (k === '--json') a.json = true;
    else if (k === '--max-llm') a.maxLlm = Number(next());
    else { console.error(`알 수 없는 옵션: ${k}`); process.exit(2); }
  }
  return a;
}

// ── 코퍼스 로드 ─────────────────────────────────────────────────────────────
function loadCorpus(file) {
  const lines = readFileSync(file, 'utf8').split('\n').map((l) => l.trim()).filter(Boolean);
  return lines.map((l, i) => {
    let o;
    try { o = JSON.parse(l); } catch (e) { throw new Error(`corpus ${file}:${i + 1} JSON 파싱 실패: ${e.message}`); }
    if (!o.text || !o.expected) throw new Error(`corpus ${file}:${i + 1} text/expected 누락`);
    return o;
  });
}

// ── 결정적 규칙 단계 (intent.js 와 동일 순서) ────────────────────────────────
//   호출부(handlers.js)는 isForceTaskCmd 를 먼저 보고, 아니면 classifyRequest 내부의
//   결정적 분기(선두 git/tasklist 정규식 → isConfirmationQuery)로 question 을 가린다.
//   아래 LEADING_QUESTION 는 intent.js classifyRequest 선두 정규식(현행 코드)의 복제다.
const LEADING_QUESTION = /^\s*(git\s+(push|pull|stash|fetch|merge|rebase|status|log|diff)|タスク(?:一覧|リスト|確認|状況)|tasklist|task7d)/i;
function deterministicVerdict(text) {
  if (isForceTaskCmd(text)) return 'task';
  const stripped = String(text).replace(/[^\x00-\x7Fぁ-ん亜-熙ー]/g, ' ');
  if (LEADING_QUESTION.test(stripped)) return 'question';
  if (isConfirmationQuery(text)) return 'question';
  return null; // 규칙 미결 → Jev/LLM 으로
}

// ── Jev 게이트웨이 호출 (form-urlencoded, sk 는 env 에서만) ───────────────────
function postForm(urlStr, params, timeoutMs) {
  return new Promise((resolve, reject) => {
    let u;
    try { u = new URL(urlStr); } catch (e) { reject(e); return; }
    const body = Object.entries(params || {})
      .filter(([, v]) => v != null)
      .map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`).join('&');
    const mod = u.protocol === 'http:' ? http : https;
    const req = mod.request({
      method: 'POST', hostname: u.hostname, port: u.port || (u.protocol === 'http:' ? 80 : 443),
      path: u.pathname + u.search,
      headers: { 'Content-Type': 'application/x-www-form-urlencoded', 'Content-Length': Buffer.byteLength(body) },
    }, (res) => {
      let raw = ''; res.setEncoding('utf8');
      res.on('data', (d) => { raw += d; });
      res.on('end', () => { let p = raw; try { p = JSON.parse(raw); } catch { /* keep */ } resolve({ status: res.statusCode, body: p }); });
    });
    req.on('error', reject);
    req.setTimeout(timeoutMs, () => req.destroy(new Error('jev request timeout')));
    req.write(body); req.end();
  });
}

function detectLang(text) {
  const t = String(text == null ? '' : text);
  const kana = (t.match(/[぀-ゟ゠-ヿ]/g) || []).length;
  const han = (t.match(/[一-鿿]/g) || []).length;
  const hangul = (t.match(/[가-힣ᄀ-ᇿ㄰-㆏]/g) || []).length;
  const latin = (t.match(/[A-Za-z]/g) || []).length;
  const ja = kana + han;
  if (ja > 0 && ja >= hangul && ja >= latin) return 'ja';
  if (hangul > 0 && hangul >= latin) return 'ko';
  if (latin > 0) return 'en';
  return 'unknown';
}

async function callJev(url, sk, text, lang, timeoutMs = 8000) {
  const jsondata = JSON.stringify({
    v: 1, kind: 'intent_route', ts: new Date().toISOString(),
    text_masked: maskString(text), lang: lang || detectLang(text),
    in_thread: false, mentions_task_id: false, mentions_issue_ref: false,
  });
  const started = Date.now();
  try {
    const res = await postForm(url, { token: sk, jsondata }, timeoutMs);
    const latencyMs = Date.now() - started;
    const b = res.body;
    if (res.status !== 200 || !b || typeof b !== 'object' || b.success !== true) {
      return { ok: false, reason: `http_${res.status}`, latencyMs };
    }
    return {
      ok: true, latencyMs,
      intent: b.intent,
      confidence: (typeof b.intent_confidence === 'number') ? b.intent_confidence : null,
      rfc: (typeof b.requires_file_change === 'number') ? b.requires_file_change : 0,
      lookup: (typeof b.is_status_or_lookup === 'number') ? b.is_status_or_lookup : 0,
      engine: b.engine || null,
      inTok: b.usage && b.usage.input_tokens, outTok: b.usage && b.usage.output_tokens,
    };
  } catch (e) {
    return { ok: false, reason: 'error', latencyMs: Date.now() - started };
  }
}

// ── Jev 신뢰도 라우팅 (SPEC §5 표) — 저장된 원응답에 임계값을 오프라인 적용 ──────
function jevRoute(raw, tHi, pHi, pLo) {
  if (!raw || !raw.ok) return null;
  if (raw.intent !== 'task' && raw.intent !== 'question') return null; // ambiguous/미지 → 폴백
  if (typeof raw.confidence !== 'number' || !Number.isFinite(raw.confidence)) return null;
  if (raw.confidence < tHi) return null;
  if (raw.intent === 'task' && raw.rfc >= pHi) return 'task';
  if (raw.intent === 'question' && raw.rfc <= pLo) return 'question';
  return null; // 경계·신호 모순 → 폴백
}

// ── 지표 계산 (binary: task 를 positive 로) ──────────────────────────────────
//   운영상 봇의 동작은 두 가지뿐: task=이슈 등록 / question=채널 즉답.
//   그래서 ambiguous 기대값은 운영상 "question(이슈 안 만듦)" 으로 접어 이진 평가하되,
//   ambiguous→task(불필요한 이슈=사고 A) 비율은 별도로 보고한다.
function bin(label) { return label === 'task' ? 'task' : 'question'; }
function computeMetrics(cases, predFn, stageFn) {
  let tp = 0, fp = 0, tn = 0, fn = 0; // task=positive
  let spuriousTask = 0, spuriousDenom = 0; // 사고 A: 비-task 를 task 로
  let buriedTask = 0, buriedDenom = 0;     // 사고 B/C: task 를 question 으로
  const stageCount = { rule: 0, jev: 0, llm: 0, fallback: 0 };
  for (const c of cases) {
    const pred = bin(predFn(c));
    const exp = bin(c.expected);
    if (exp === 'task') { buriedDenom++; if (pred === 'task') tp++; else { fn++; buriedTask++; } }
    else { spuriousDenom++; if (pred === 'task') { fp++; spuriousTask++; } else tn++; }
    const st = stageFn(c); if (st in stageCount) stageCount[st]++;
  }
  const total = cases.length;
  const accuracy = (tp + tn) / total;
  const taskRecall = buriedDenom ? tp / buriedDenom : null;
  const questionPrecision = (tn + fn) ? tn / (tn + fn) : null; // 예측 question 중 실제 question
  return {
    total, tp, fp, tn, fn, accuracy, taskRecall, questionPrecision,
    spuriousTaskRate: spuriousDenom ? spuriousTask / spuriousDenom : null,
    buriedTaskRate: buriedDenom ? buriedTask / buriedDenom : null,
    stageCount,
    fallbackRate: (stageCount.llm + stageCount.fallback) / total,
  };
}

function pct(x) { return x == null ? ' n/a ' : (x * 100).toFixed(1).padStart(5) + '%'; }
function percentile(arr, p) {
  if (!arr.length) return null;
  const s = [...arr].sort((a, b) => a - b);
  const idx = Math.min(s.length - 1, Math.ceil(p / 100 * s.length) - 1);
  return s[Math.max(0, idx)];
}

async function main() {
  const args = parseArgs(process.argv);
  const cases = loadCorpus(args.corpus);
  const url = (process.env.GIIP_JEV_GATEWAY_URL || DEFAULT_GATEWAY).trim();
  const sk = (process.env.GIIP_SK || '').trim();
  const wantJev = args.groups.some((g) => g === 2 || g === 3);
  const wantLlm = args.groups.some((g) => g === 1 || g === 3);

  if (wantJev && !sk) {
    console.error('✗ 대조군 ②/③ 은 Jev 호출이 필요하다. 환경변수 GIIP_SK 를 주입하라(값은 출력되지 않는다).');
    process.exit(2);
  }

  console.log(`코퍼스: ${args.corpus} (${cases.length}건)`);
  console.log(`게이트웨이: ${url}  (sk: ${sk ? '주입됨(미출력)' : '없음'})`);
  console.log(`언어 구성: ${['ko', 'ja', 'en', 'unknown'].map((L) => `${L}=${cases.filter((c) => c.lang === L).length}`).join(' ')}`);
  console.log(`기대 구성: ${['task', 'question', 'ambiguous'].map((E) => `${E}=${cases.filter((c) => c.expected === E).length}`).join(' ')}`);
  console.log('');

  // 1패스: 케이스별 det / Jev원응답 / LLM 결과 수집
  const jevLatencies = [];
  const llmLatencies = [];
  let inTokSum = 0, outTokSum = 0, jevOkCount = 0, jevFailCount = 0, llmCalls = 0;
  const flaky = { checked: 0, agreed: 0 };
  let engineSeen = null;

  for (const c of cases) {
    c._det = deterministicVerdict(c.text);
    // Jev: det 로 이미 결정된 케이스도 Jev 자체 성능 측정을 위해 호출한다(라우팅엔 안 쓰임).
    if (wantJev) {
      const reps = [];
      for (let r = 0; r < args.repeat; r++) reps.push(await callJev(url, sk, c.text, c.lang));
      c._jev = reps[0];
      if (c._jev.ok) {
        jevOkCount++; jevLatencies.push(c._jev.latencyMs);
        if (c._jev.inTok) inTokSum += c._jev.inTok;
        if (c._jev.outTok) outTokSum += c._jev.outTok;
        if (c._jev.engine) engineSeen = c._jev.engine;
      } else jevFailCount++;
      if (args.repeat > 1) {
        const intents = reps.filter((x) => x.ok).map((x) => x.intent);
        if (intents.length > 1) { flaky.checked++; if (new Set(intents).size === 1) flaky.agreed++; }
      }
    }
    // LLM: det 미결이고 ①③ 이 필요할 때만 claude -p 호출(비용·시간 절약)
    if (wantLlm && c._det === null && llmCalls < args.maxLlm) {
      const started = Date.now();
      try { c._llm = await classifyRequest(c.text); } catch { c._llm = 'question'; }
      c._llmLatency = Date.now() - started;
      llmLatencies.push(c._llmLatency); llmCalls++;
    } else if (wantLlm && c._det === null) {
      c._llm = 'question'; // 상한 초과 시 현행 실패 폴백(§2.2)과 동일하게 question
    }
  }

  // 임계값: 고정값이 주어지면 사용, 아니면 스윕으로 권장값 선정(③ 기준)
  let tHi = args.tHi, pHi = args.pHi, pLo = args.pLo;
  const haveFixed = [tHi, pHi, pLo].every((v) => typeof v === 'number' && Number.isFinite(v));
  const sweepRows = [];
  if (wantJev) {
    const T = [0.6, 0.7, 0.8, 0.85, 0.9];
    const PH = [0.5, 0.6, 0.7, 0.8];
    const PL = [0.2, 0.3, 0.4];
    for (const t of T) for (const ph of PH) for (const pl of PL) {
      const predG3 = (c) => c._det ?? (jevRoute(c._jev, t, ph, pl) ?? c._llm ?? 'question');
      const stageG3 = (c) => c._det ? 'rule' : (jevRoute(c._jev, t, ph, pl) ? 'jev' : 'llm');
      const m = computeMetrics(cases, predG3, stageG3);
      const jevUse = m.stageCount.jev / m.total;
      // Jev 가 "실제로 라우팅한" 케이스만의 오류(이 임계값에서 Jev 를 신뢰했을 때의 정밀도).
      //   jevErr = 라우팅 결과가 기대값(이진)과 다른 건수. 임계값 선정의 핵심 안전지표.
      let jevRouted = 0, jevErr = 0;
      for (const c of cases) {
        if (c._det) continue;
        const jr = jevRoute(c._jev, t, ph, pl);
        if (!jr) continue;
        jevRouted++;
        if (bin(jr) !== bin(c.expected)) jevErr++;
      }
      sweepRows.push({ t, ph, pl, ...m, jevUse, jevRouted, jevErr });
    }
    if (!haveFixed) {
      // 권장 선정 원칙(SPEC §5 비대칭 비용, 근거 명시):
      //   ①(1차 제약) Jev 라우팅 오류 0 — 코퍼스에서 Jev 를 신뢰해 라우팅한 건이 전부 정답.
      //      (오류가 있으면 그 임계값은 Jev 를 과신하는 것 → LLM 폴백만 못하므로 배제)
      //   ②(목표)   그 안에서 Jev 커버리지(jevRouted) 최대 — flaky 한 LLM 폴백 의존을 줄인다.
      //   ③(동률)   accuracy 높은 것 → 그래도 동률이면 **보수적으로 더 높은 T_hi**(미지 입력 과신 방지).
      const safe = sweepRows.filter((r) => r.jevErr === 0);
      const pool = safe.length ? safe : sweepRows;
      pool.sort((a, b) =>
        (a.jevErr - b.jevErr) ||
        (b.jevRouted - a.jevRouted) ||
        (b.accuracy - a.accuracy) ||
        (b.t - a.t) || (b.ph - a.ph) || (a.pl - b.pl));
      tHi = pool[0].t; pHi = pool[0].ph; pLo = pool[0].pl;
    }
  }

  // 대조군별 예측/단계 함수 (확정 임계값 사용)
  const g1pred = (c) => c._det ?? c._llm ?? 'question';
  const g1stage = (c) => (c._det ? 'rule' : 'llm');
  const g2pred = (c) => c._det ?? (jevRoute(c._jev, tHi, pHi, pLo) ?? 'question');
  const g2stage = (c) => (c._det ? 'rule' : (jevRoute(c._jev, tHi, pHi, pLo) ? 'jev' : 'fallback'));
  const g3pred = (c) => c._det ?? (jevRoute(c._jev, tHi, pHi, pLo) ?? c._llm ?? 'question');
  const g3stage = (c) => (c._det ? 'rule' : (jevRoute(c._jev, tHi, pHi, pLo) ? 'jev' : 'llm'));

  const results = {};
  if (args.groups.includes(1)) results.g1 = computeMetrics(cases, g1pred, g1stage);
  if (args.groups.includes(2)) results.g2 = computeMetrics(cases, g2pred, g2stage);
  if (args.groups.includes(3)) results.g3 = computeMetrics(cases, g3pred, g3stage);

  // ── 출력 ──
  const labels = { g1: '① 현행(규칙+claude-p)', g2: '② 규칙+Jev', g3: '③ 전체(규칙→Jev→LLM)' };
  const cols = ['정확도', 'task재현율', 'question정밀도', '사고A(불필요이슈)', '사고B/C(작업묻힘)', '폴백율'];
  console.log('── 대조군 지표 ' + '─'.repeat(50));
  console.log(['대조군'.padEnd(26), ...cols.map((c) => c.padStart(16))].join(''));
  for (const key of ['g1', 'g2', 'g3']) {
    if (!results[key]) continue;
    const m = results[key];
    console.log([
      labels[key].padEnd(24),
      pct(m.accuracy).padStart(16), pct(m.taskRecall).padStart(16), pct(m.questionPrecision).padStart(16),
      pct(m.spuriousTaskRate).padStart(16), pct(m.buriedTaskRate).padStart(16), pct(m.fallbackRate).padStart(16),
    ].join(''));
  }
  console.log('');
  for (const key of ['g1', 'g2', 'g3']) {
    if (!results[key]) continue;
    const s = results[key].stageCount;
    console.log(`  ${labels[key]} 단계별 판정: rule=${s.rule} jev=${s.jev} llm=${s.llm} fallback=${s.fallback}`);
  }
  console.log('');

  if (wantJev) {
    console.log('── Jev 실측 ' + '─'.repeat(54));
    console.log(`  호출 성공/실패: ${jevOkCount}/${jevFailCount}   engine: ${engineSeen || 'n/a'}`);
    console.log(`  지연 p50=${percentile(jevLatencies, 50)}ms  p95=${percentile(jevLatencies, 95)}ms  (min=${Math.min(...jevLatencies)}ms max=${Math.max(...jevLatencies)}ms)`);
    console.log(`  토큰(합계) 입력=${inTokSum} 출력=${outTokSum}  건당평균 입력=${(inTokSum / Math.max(1, jevOkCount)).toFixed(0)} 출력=${(outTokSum / Math.max(1, jevOkCount)).toFixed(0)}`);
    if (args.repeat > 1) console.log(`  반복 판정 일치율(flaky): ${flaky.checked ? (flaky.agreed / flaky.checked * 100).toFixed(1) + '%' : 'n/a'} (${flaky.agreed}/${flaky.checked}, repeat=${args.repeat})`);
    console.log('');
  }
  if (wantLlm) {
    console.log('── claude -p (LLM 분류기) 실측 ' + '─'.repeat(36));
    console.log(`  호출수=${llmCalls}  지연 p50=${percentile(llmLatencies, 50)}ms p95=${percentile(llmLatencies, 95)}ms`);
    console.log('');
  }

  console.log(`── 확정 임계값 ${'─'.repeat(52)}`);
  console.log(`  T_hi=${tHi}  P_hi=${pHi}  P_lo=${pLo}  ${haveFixed ? '(고정 입력)' : '(스윕 자동 선정)'}`);
  console.log('');

  if (args.sweep && wantJev && sweepRows.length) {
    console.log('── 임계값 스윕(③ 기준, 상위 후보) ' + '─'.repeat(30));
    console.log(['T_hi P_hi P_lo'.padEnd(18), '정확도', ' task재현', ' Q정밀', 'Jev라우팅(오류)', ' Jev사용', ' 폴백'].join('  '));
    const sorted = [...sweepRows].sort((a, b) =>
      (a.jevErr - b.jevErr) || (b.jevRouted - a.jevRouted) || (b.accuracy - a.accuracy) || (b.t - a.t));
    for (const r of sorted.slice(0, 12)) {
      console.log([
        `${r.t} ${r.ph} ${r.pl}`.padEnd(18),
        pct(r.accuracy), pct(r.taskRecall), pct(r.questionPrecision),
        `${String(r.jevRouted).padStart(6)}(${r.jevErr})`.padStart(16), pct(r.jevUse), pct(r.fallbackRate),
      ].join('  '));
    }
    console.log('');
  }

  if (args.json) {
    const out = {
      corpus: args.corpus, total: cases.length, gateway: url, engine: engineSeen,
      thresholds: { T_hi: tHi, P_hi: pHi, P_lo: pLo, source: haveFixed ? 'fixed' : 'swept' },
      jev: { ok: jevOkCount, fail: jevFailCount, p50: percentile(jevLatencies, 50), p95: percentile(jevLatencies, 95), inTokAvg: inTokSum / Math.max(1, jevOkCount), outTokAvg: outTokSum / Math.max(1, jevOkCount), flaky: args.repeat > 1 ? (flaky.checked ? flaky.agreed / flaky.checked : null) : null },
      llm: { calls: llmCalls, p50: percentile(llmLatencies, 50), p95: percentile(llmLatencies, 95) },
      groups: results,
    };
    console.log('JSON_RESULT_BEGIN');
    console.log(JSON.stringify(out, null, 2));
    console.log('JSON_RESULT_END');
  }
}

main().catch((e) => { console.error('평가 실패:', e && e.message ? e.message : e); process.exit(1); });
