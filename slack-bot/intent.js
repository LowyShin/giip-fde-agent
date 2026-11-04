// intent.js — コマンド判定 + 意図分類（task / question）
// index.js から behavior-preserving で切り出し（ロジック変更なし）。

const crypto = require('crypto');
const http = require('http');
const https = require('https');
const path = require('path');
const { URL } = require('url');
const { spawnAsync } = require('./claude-cli');
const accounts = require('./claude-accounts');
// claude-accounts とは別物(giip 채널별 SK)なので名前で切り分ける。
const giipAccounts = require('./giip-accounts');
const { maskString } = require('./secret-mask');
const { BASE_DIR, resolveLangForProject } = require('./config');

// ── 確認コマンド判定 ──────────────────────────────────────────────────────────
const GO_WORDS = ['go', 'start', '시작', '실행', '진행', 'ok', 'yes', '예', '응', '開始', 'はい', 'よし', '実行', '進める'];
const CANCEL_WORDS = ['cancel', '취소', 'no', '아니', '중단', 'stop', 'キャンセル', '中断', 'やめ'];

function isGoCmd(text) {
  const t = text.trim().toLowerCase();
  // 完全一致 or 「<go語> 」で始まる場合のみ。以前は .includes('시작'/'진행') で
  // 部分一致していたため「…태스크 파일 만들어서 진행해줘」等の作業依頼文が
  // 誤って bare go コマンド扱いされていた（番号未発給の原因）。
  return GO_WORDS.some(w => t === w || t.startsWith(w + ' '));
}
function isCancelCmd(text) {
  const t = text.trim().toLowerCase();
  return CANCEL_WORDS.some(w => t === w || t.startsWith(w + ' '));
}

// ── 明示的タスク作成キーワード → 分類器をバイパスして強制 task 化 ──────────────
// 質問形で始まる複合文（「…맞아? … 태스크 파일 만들어」等）が classifyRequest で
// question に誤分類され、書込権限を持つ Q&A サブエージェントが番号を発給せずに
// ファイルを作ってしまう事故を防ぐ。これらの語があれば必ず管理タスク経路へ。
const FORCE_TASK_PATTERNS = [
  /태스크\s*등록/,
  /태스크\s*파일\s*(을|를)?\s*(만들|생성|작성)/,
  /태스크\s*(을|를)?\s*(만들|생성|작성)/,
  /작업\s*의뢰/,
  /タスク\s*(登録|作成|化)/,
  /task\s*(등록|추가|생성|作成|登録)/i,
  // 先頭が「태스크등록 …」または「task …」で始まる場合は強制タスク化。
  //   利用形: `<プロジェクト名> 태스크등록 <内容>` / `<プロジェクト名> task <内容>`
  //   （プロジェクト名は parseProjectPrefix で workDir に解決済み → ここでは cleanText の先頭）
  //   tasklist / taskmerge / task7days 等の管理コマンドや「task list」誤爆は否定先読みで除外。
  /^\s*(?:태스크\s*등록|task)\s+(?!list\b|리스트|목록|一覧|일람|merge\b|병합|7)\S/i,
  // 実行形(命令形)の指示 — 実装/修正/解決 等ディスク変更を伴う命令は task。
  //   命令形終結(…해줘/…해라/…해 주세요/…해봐)だけを対象にし、質問形(…돼 있어?/…했어?)と区別する。
  //   例: "…해결을 해라" / "구현해줘" / "수정해라" / "반영해 주세요"
  //   업데이트/갱신/번역/현행화 系(ディスク書込を伴う)も追加 — "…일본어로 업데이트 해줘"が
  //   決定的 fast-path を素通りして flaky LLM classifier で question に誤分類され、質問経路で
  //   ファイルが未コミットのまま残り PR 未生成になった事故(giip-629 追加依頼)を恒久修正する。
  /(구현|수정|해결|반영|적용|배포|개선|보완|생성|작성|처리|점검|리팩터링?|리팩토링|업데이트|업뎃|갱신|번역|현행화|일본어화)\s*(을|를|이|가)?\s*(해\s*줘|해라|하라|해\s*주세요|하세요|해봐|해다오|해\s*주라)/,
  //   고치다/만들다 系の命令形。
  /고쳐\s*(줘|라|주세요|주라)/,
  /만들어\s*(줘|라|주세요|주라)/,
  // 「計算/集計/推定 …(해서) 보여줘/표시/출력/노출」= ページに計算結果を描画する ⇒ コード変更(task)。
  //   「보여줘」単体は読み取り質問(例: "로그 보여줘" / "비용 보여줘")なので拾わず、計算系動詞との
  //   共起時のみ task 化して誤爆を防ぐ。恒久修正の契機: "이번 달 예상 금액을 계산해서 보여줘" が
  //   LLM classifier で question に誤分類され(実測 flaky: 프롬프트 예시조차 4/4 question)、giip issue
  //   未登録・PR 未生成のまま質問経路で直接編集される事故が起きた。決定的 fast-path で恒久化する。
  /(계산|집계|합산|추정|산출)\s*(을|를)?\s*(해서|하여|해\s*서|해|한|하도록)?\s*(보여|표시|노출|출력)\s*(해\s*)?(줘|주세요|주라|줄래|달라|다오|주세여)/,
];
function isForceTaskCmd(text) {
  const t = text.replace(/`/g, '');
  return FORCE_TASK_PATTERNS.some(re => re.test(t));
}

// ── 決定的 question fast-path: 純粋な「確認/照会」依頼 ─────────────────────────
// ユーザ指摘: 「…확인 가능해?」「…확인해줘」のような読み取り専用の確認依頼が
// LLM classifier(flaky)で task に誤分類され、不要な giip issue が発給された(#622)。
// ディスク書込を伴う動詞(구현/수정/저장/파일… force-task 相当)を一切含まず、
// 確認/照会マーカー(확인 가능/확인해줘/알려줘/뭐였는지/뭐야 等)のみで構成される
// メッセージは、LLM を呼ばず決定的に question として即答経路へ回す。
// 安全順序: 呼び出し側は必ず isForceTaskCmd を先に評価するため、書込を伴う命令形は
// ここに到達しない。加えて WRITE_INTENT_MARKERS で二重に除外し誤爆を防ぐ。
const CONFIRM_QUERY_MARKERS = [
  /확인\s*(가능|할\s*수\s*있|해\s*줄|해\s*줘|해\s*주세요|해\s*주라|좀|부탁|돼|되나|되니|가능해|가능한가|가능할까)/,
  /알려\s*(줘|주세요|주라|줄래|다오)/,
  /뭐(였|야|예요|냐|니|지)/,
  /뭔지|무엇\s*(인지|이야|인가)/,
  /어떻게\s*(돼|되나|됐|되었)/,
  /어때|어떤가|어떠니/,
];
// 書込/実装/計算を伴う「動詞(語幹)」が含まれると「単なる確認」ではない → fast-path 対象外。
// 注意: 名詞の 파일/폴더/처리/등록/추가/점검 単独では書込意図とみなさない。
//   「<isn> 의 처리 결과 파일의 github url 찾아서 보여줘」のような既存ファイルの URL/パス照会が
//   名詞一致だけで LLM(flaky) に回り task 誤分類され、新規 giip issue が発給された事故の恒久修正。
//   これらの名詞は命令/動作形(등록해/추가해/처리해서/점검하고 …)と結合した時のみ書込扱いにする。
const WRITE_INTENT_MARKERS = /(저장|구현|수정|해결|반영|적용|배포\s*(해|하)|개선|보완|생성|작성|계산|집계|합산|추정|산출|만들|고쳐|고치|리팩터|리팩토|커밋|푸시|push|업데이트|업뎃|갱신|번역|현행화|일본어화|삭제|제거|지워|변경|바꿔|바꾸|이동|옮겨|복사)|(등록|추가|처리|점검)\s*(을|를)?\s*(해|하|할|한\s*뒤)/;

// 読み取り専用の「所在/内容の照会」: 照会対象(URL/リンク/パス/住所/位置/内容)と、
// 探す/見せる/教える/確認の依頼動詞が共起する場合のみ。書込動詞が同居すれば対象外(WRITE_INTENT_MARKERS)。
const LOOKUP_TARGET = /(url|링크|경로|주소|위치|내용|path|link)/i;
const LOOKUP_VERB = /(찾아|보여|알려|확인)/;

function isReadOnlyLookup(text) {
  const t = text.replace(/`/g, '');
  if (WRITE_INTENT_MARKERS.test(t)) return false;
  return LOOKUP_TARGET.test(t) && LOOKUP_VERB.test(t);
}

function isConfirmationQuery(text) {
  const t = text.replace(/`/g, '');
  if (WRITE_INTENT_MARKERS.test(t)) return false;
  return CONFIRM_QUERY_MARKERS.some(re => re.test(t)) || isReadOnlyLookup(t);
}

// ── ② Jev 意図分類アダプタ (仕様 slack-bot/docs/INTENT_ROUTING_JEV_SPEC.md §4·§5·§6.2) ──
// チェーン上の位置: ①(決定規則) → ②(Jev) → ③(既存 LLM 分類器) → ④(案内文) のフォールバック。
//   スイッチがオフなら ② は丸ごとスキップする(現行と完全に同一にすること — 仕様 §7)。
//
// スイッチ·閾値·タイムアウトは **呼び出し時** に env から読む(モジュールロード時定数は禁止)。
//   - JEV_INTENT_ENABLED        : 1/true/yes/on(大小文字無視)。既定は OFF。
//   - GIIP_JEV_GATEWAY_URL      : ゲートウェイ URL。接続はこの環境変数だけ(ハードコード禁止)。
//                                  未設定なら ② は省略される。
//   - JEV_INTENT_TIMEOUT_MS     : 既定 3000ms(仕様 §4.5「初期提案 3 秒 — 根拠未検証」)。
//   - JEV_INTENT_T_HI/P_HI/P_LO : 既定 0.8 / 0.7 / 0.3 — これらは **仕様 §5 の提案値であって確定値ではない**
//                                  (§10-10: 確定値として引用禁止)。(C) のコーパス評価で確定する。
//
// 優先順位(仕様 §3-1·§5): ①(特に isForceTaskCmd)が常に優先。呼び出し側が isForceTaskCmd を先に評価するため、
//   Jev が受け取るのは「isForceTaskCmd が false のメッセージ」だけ(構造的に保証)。
//   Jev の question 判定が isForceTaskCmd の結果をひっくり返すことはできない。
const JEV_ENABLED_ENV = 'JEV_INTENT_ENABLED';
const JEV_GATEWAY_ENV = 'GIIP_JEV_GATEWAY_URL';
const JEV_TIMEOUT_ENV = 'JEV_INTENT_TIMEOUT_MS';
const JEV_T_HI_ENV = 'JEV_INTENT_T_HI';
const JEV_P_HI_ENV = 'JEV_INTENT_P_HI';
const JEV_P_LO_ENV = 'JEV_INTENT_P_LO';

// 既定値は仕様 §5 の提案値 — 確定値ではない(§10-10)。(C) の評価で確定する。
const JEV_T_HI_DEFAULT = 0.8;
const JEV_P_HI_DEFAULT = 0.7;
const JEV_P_LO_DEFAULT = 0.3;
const JEV_TIMEOUT_DEFAULT_MS = 3000;

function jevEnabled() {
  const v = String(process.env[JEV_ENABLED_ENV] || '').trim().toLowerCase();
  return v === '1' || v === 'true' || v === 'yes' || v === 'on';
}

function jevNumberEnv(name, dflt) {
  const raw = process.env[name];
  if (raw == null || String(raw).trim() === '') return dflt;
  const n = Number(raw);
  return Number.isFinite(n) ? n : dflt;
}

function jevTimeoutMs() {
  const n = jevNumberEnv(JEV_TIMEOUT_ENV, JEV_TIMEOUT_DEFAULT_MS);
  return n > 0 ? n : JEV_TIMEOUT_DEFAULT_MS;
}

// lang 判定(簡易ヒューリスティック): かな(漢字·ひらがな·カタカナ)優勢 → ja、
// ハングル優勢 → ko、ラテン文字優勢 → en、それ以外 → unknown。
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

// Jev ゲートウェイ送信 — Node 内蔵の http/https だけを使う(外部パッケージ追加なし)。
//   giip-api.js はここでは require しない(循環/結合リスク) — 小さな helper をローカルに持つ。
function postForm(urlStr, params, timeoutMs) {
  return new Promise((resolve, reject) => {
    let u;
    try { u = new URL(urlStr); } catch (e) { reject(e); return; }
    const body = Object.entries(params || {})
      .filter(([, v]) => v != null)
      .map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`)
      .join('&');
    const mod = u.protocol === 'http:' ? http : https;
    const req = mod.request({
      method: 'POST',
      hostname: u.hostname,
      port: u.port || (u.protocol === 'http:' ? 80 : 443),
      path: u.pathname + u.search,
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Content-Length': Buffer.byteLength(body),
      },
    }, (res) => {
      let raw = '';
      res.setEncoding('utf8');
      res.on('data', (d) => { raw += d; });
      res.on('end', () => {
        let parsed = raw;
        try { parsed = JSON.parse(raw); } catch { /* keep raw string */ }
        resolve({ status: res.statusCode, body: parsed, raw });
      });
    });
    req.on('error', reject);
    req.setTimeout(timeoutMs, () => req.destroy(new Error('jev request timeout')));
    req.write(body);
    req.end();
  });
}

// ゲートウェイの要求ボディ(仕様 §4.3)。
//   text_masked は maskString() 通過後の値。
//   **クライアントでは長さを切り詰めない** — 切り詰めはゲートウェイが Jev state を作る時に行う
//   (要求ボディ自体は呼び出し側が送ったまま受け取る — 仕様 §4.3)。
function buildJevJsondata(text, opts) {
  return {
    v: 1,
    kind: 'intent_route',
    ts: new Date().toISOString(),
    text_masked: maskString(text),
    lang: detectLang(text),
    in_thread: !!opts.inThread,
    mentions_task_id: !!opts.mentionsTaskId,
    mentions_issue_ref: !!opts.mentionsIssueRef,
  };
}

function jevProb(v) {
  return (typeof v === 'number' && Number.isFinite(v)) ? v : 0.0;
}

/**
 * ② Jev 段。
 * @returns {{intent:'task'|'question'|null, source:'jev'|null, reason:string, latencyMs:number, detail:object|null}}
 *   intent が null のときは呼び出し側が ③(既存 LLM 分類器) へフォールバックする。
 */
async function classifyWithJev(text, opts = {}) {
  const started = Date.now();
  const done = (intent, reason, detail = null) => ({
    intent,
    source: intent ? 'jev' : null,
    reason,
    latencyMs: Date.now() - started,
    detail,
  });

  // フォールバック順(各段で即 null を返す)。
  if (!jevEnabled()) return done(null, 'switch_off');

  const url = String(process.env[JEV_GATEWAY_ENV] || '').trim();
  if (!url) return done(null, 'no_gateway_url');

  // チャンネルにアカウントが無ければ Jev 段を省略して ③ へ(仕様 §7)。
  let acct = null;
  try {
    const resolver = opts.accountResolver || ((cid) => giipAccounts.resolve(cid));
    acct = resolver(opts.channelId) || null;
  } catch { acct = null; }
  const sk = acct && acct.sk;
  if (!sk) return done(null, 'no_sk');

  const jsondata = buildJevJsondata(text, opts);
  let res;
  try {
    const sender = opts.jevRequest || postForm;
    res = await sender(url, { token: sk, jsondata: JSON.stringify(jsondata) }, jevTimeoutMs());
  } catch {
    return done(null, 'jev_error');   // タイムアウトも含む
  }

  const status = res && typeof res.status === 'number' ? res.status : 0;
  if (status !== 200) return done(null, `jev_http_${status}`);

  const body = res.body;
  if (!body || typeof body !== 'object' || Array.isArray(body) || body.success !== true) {
    return done(null, 'jev_not_success');
  }

  const jevIntent = body.intent;
  if (jevIntent !== 'task' && jevIntent !== 'question') {
    return done(null, jevIntent === 'ambiguous' ? 'jev_ambiguous' : 'jev_bad_intent');
  }

  // 「分類値をでっち上げるとボットがその値を権威として信頼してしまう」(仕様 §4.5) — 推定してはいけない。
  const conf = body.intent_confidence;
  if (typeof conf !== 'number' || !Number.isFinite(conf)) return done(null, 'jev_no_confidence');

  // 値なし = 保守側(仕様 §4.5) → 0.0。
  const rfc = jevProb(body.requires_file_change);
  const lookup = jevProb(body.is_status_or_lookup);
  const detail = {
    intent: jevIntent,
    confidence: conf,
    requiresFileChange: rfc,
    isStatusOrLookup: lookup,
    engine: body.engine || null,
  };

  // ルーティング(仕様 §5 の表そのまま)。2 つの信号が矛盾する場合や信頼度が不足する場合は ③ へフォールバック。
  const tHi = jevNumberEnv(JEV_T_HI_ENV, JEV_T_HI_DEFAULT);
  const pHi = jevNumberEnv(JEV_P_HI_ENV, JEV_P_HI_DEFAULT);
  const pLo = jevNumberEnv(JEV_P_LO_ENV, JEV_P_LO_DEFAULT);

  let intent = null;
  let reason = 'jev_low_confidence';
  if (conf >= tHi) {
    if (jevIntent === 'task' && rfc >= pHi) { intent = 'task'; reason = 'jev_task'; }
    else if (jevIntent === 'question' && rfc <= pLo) { intent = 'question'; reason = 'jev_question'; }
  }
  // is_status_or_lookup はルーティングには使わない(仕様 §5 の表に無い) — 判定ログにだけ残す。
  //   新しい判定ルールは作らない。
  return done(intent, reason, detail);
}

// ── 判定ログ (仕様 §6.2) ──────────────────────────────────────────────────────
// 保存先: ボットプロセスの stdout(console.log) — 新しい保存先は作らない(§6.2)。
// 原文は出さない: メッセージ本文はログに残さない。maskString() 通過後の sha256(先頭 8 hex)と
//   長さだけを残す。
// source: rule(決定規則) | jev | llm(③ 成功) | fallback(③ 失敗 → question + 案内文)。
// スイッチ OFF でも出る(ログは判定結果に影響しない)。
function logIntentDecision({ source, intent, reason, detail, latencyMs, text }) {
  const masked = maskString(text);
  const textHash = crypto.createHash('sha256').update(masked, 'utf8').digest('hex').slice(0, 8);
  const parts = [
    '[Bot] intent-classify',
    `source=${source}`,
    `intent=${intent}`,
    `reason=${reason}`,
  ];
  if (detail) {
    parts.push(`jevIntent=${detail.intent}`);
    parts.push(`jevConf=${detail.confidence}`);
    parts.push(`jevRfc=${detail.requiresFileChange}`);
    parts.push(`jevLookup=${detail.isStatusOrLookup}`);
    parts.push(`jevEngine=${detail.engine || ''}`);
  }
  parts.push(`latencyMs=${latencyMs}`);
  parts.push(`maskedLen=${masked.length}`);
  parts.push(`textHash=${textHash}`);
  console.log(parts.join(' '));
}

// ④ フォールバック案内文(仕様 §3-4) — ③ が実際に失敗したときだけ付ける。
function emitFallbackHint(text, workDir, opts) {
  const cb = opts && opts.onFallbackHint;
  if (typeof cb !== 'function') return;
  let hint = '';
  try {
    const lang = resolveLangForProject(path.basename(workDir));
    hint = require('./i18n-ui').t(lang, 'classifyFallbackHint');
  } catch { return; }
  if (!hint) return;
  try { cb(hint); } catch { /* 案内文の失敗が判定結果を変えることはない */ }
}

// ── 意図分類 (task / question) ────────────────────────────────────────────────
// 「タスク登録」「task登録」等の明記、または明確な作業依頼 → "task"
// 曖昧・質問・情報照会 → "question"
async function classifyRequest(text, workDir = BASE_DIR, opts = {}) {
  const started = Date.now();
  // git push / pull / stash などの単純操作はタスク不要 → 即 question
  if (/^\s*(git\s+(push|pull|stash|fetch|merge|rebase|status|log|diff)|タスク(?:一覧|リスト|確認|状況)|tasklist|task7d)/i.test(text.replace(/[^\x00-\x7Fぁ-ん亜-熙ー]/g, ' '))) {
    logIntentDecision({ source: 'rule', intent: 'question', reason: 'rule_leading_regex', latencyMs: Date.now() - started, text });
    return 'question';
  }

  // 純粋な確認/照会依頼は LLM を呼ばず決定的に question へ（#622: 확인 요청が task 誤分類）。
  if (isConfirmationQuery(text)) {
    logIntentDecision({ source: 'rule', intent: 'question', reason: 'rule_confirmation_query', latencyMs: Date.now() - started, text });
    return 'question';
  }

  // ② Jev 段(仕様 §3·§4·§5)。スイッチがオフなら丸ごとスキップする(現行と同一)。
  //   Jev が intent を確定したら LLM は呼ばない。
  let jevResult = null;
  try {
    jevResult = await classifyWithJev(text, opts);
  } catch {
    jevResult = { intent: null, source: null, reason: 'jev_error', latencyMs: 0, detail: null };
  }
  if (jevResult.intent === 'task' || jevResult.intent === 'question') {
    logIntentDecision({
      source: 'jev', intent: jevResult.intent, reason: jevResult.reason,
      detail: jevResult.detail, latencyMs: jevResult.latencyMs, text,
    });
    return jevResult.intent;
  }


  const prompt = `You are an assistant that classifies the intent of Slack messages.

Message: "${text}"

Classify using the following rules:
- "task": applies when the request requires creating or modifying ANY file on disk:
  1. Explicit registration instruction such as "태스크 등록", "task 추가", "작업 의뢰" etc.
  2. Code change, feature addition, bug fix, refactoring, or configuration file modification
  3. A combination like "do A, and also git push" where A involves file changes
  4. Document/spec creation and saving: "사양서 만들어 저장", "문서로 저장", "파일로 저장해줘", "작성해서 저장", "만들어서 저장"
  5. Any request that ends with saving/writing output to a file or folder on disk

  6. Imperative requests to implement, fix, solve, add, change, or "calculate and show" a
     page / feature / behavior — even when phrased as "…보여줘", "…체크하고 해결해라",
     "…고쳐줘", "구현해줘" — because fulfilling them requires modifying code or config.
     A request that reports something is missing/broken/unimplemented and then asks to fix
     or realize it ("아직 구현이 안된 거 같아 … 계산해서 보여줘") is "task".

- "question": applies when NO file needs to be created or modified:
  1. Question, information inquiry, explanation request (no file output expected)
  2. Status check, deployment check, environment check, log review
  3. File path inquiry, dashboard check, system status confirmation
     Asking to FIND / SHOW / TELL the URL, link, path, location or content of an EXISTING
     file or result ("<isn> 의 처리 결과 파일의 github url 찾아서 보여줘") is read-only → question.
     Nouns like 파일/폴더/처리/결과 alone do NOT imply writing.
  4. Investigation or research only (no file output expected)
  5. Message consisting only of "git push" or "git pull" (no other work instructions)

Key principle: If the request involves writing, saving, or creating ANY file on disk — classify as "task".
Merely locating/showing/reading an already-existing file, URL, or result is NOT writing — classify as "question"
unless a write verb (저장/작성/생성/만들/수정/구현/등록해 …) is also present.
A read-only phrasing like "보여줘/확인해줘" does NOT make it a question when satisfying it
requires implementing or changing code.

Examples:
- "azure-cost 페이지에 이번 달 예상 금액을 계산해서 보여줘" → task (needs a code change to add the calculation)
- "csn 2 에 등록된 logical machine 이 사라진 원인 체크하고 문제 해결을 해라" → task (fix requires code/query change)
- "지금 배포 상태 어때?" → question
- "azure-cost 페이지 URL 이 뭐야?" → question
- "지금 폴더 구조 재조정 했거든 123 의 처리 결과 파일의 github url 찾아서 보여줘" → question (lookup of an existing file)
- "123 처리 결과 파일 경로 찾아서 파일로 저장해줘" → task (also asks to write a file)

Reply with only one word: "task" or "question". No explanation needed.`;

  try {
    const acct = accounts.pickAccount();
    // giip-1063: 분류(task/question 1단어 판정)에 최상위 모델을 쓰지 않는다 — MODEL_CLASSIFIER.
    const result = await (opts.spawn || spawnAsync)('claude', ['-p', '--model', require('./model-config').classifierModel()], {
      cwd: workDir,
      timeout: 60000,
      env: accounts.envFor(acct),
      input: prompt, // 프롬프트는 stdin 으로 (ENAMETOOLONG 회피)
    });
    if (result.status !== 0) {
      // 한도 메시지가 stdout에 찍히는 경우가 있어(giip-759) 두 스트림 모두 확인한다.
      const combinedOut = `${result.stdout || ''}\n${result.stderr || ''}`;
      if (accounts.isUsageLimit(combinedOut)) accounts.noteUsageLimit(acct, combinedOut);
      // 仕様 §3-4: ③ まで失敗したら question + 案内文(現行は黙って question だった)。
      logIntentDecision({ source: 'fallback', intent: 'question', reason: 'llm_failed', detail: jevResult.detail, latencyMs: Date.now() - started, text });
      emitFallbackHint(text, workDir, opts);
      return 'question';
    }
    const out = (result.stdout || '').trim().toLowerCase();
    const intent = out.startsWith('task') ? 'task' : 'question';
    logIntentDecision({ source: 'llm', intent, reason: 'llm_output', detail: jevResult.detail, latencyMs: Date.now() - started, text });
    return intent;
  } catch {
    // timeout·エラー時は質問へフォールバック + 案内文(仕様 §3-4)。
    logIntentDecision({ source: 'fallback', intent: 'question', reason: 'llm_error', detail: jevResult.detail, latencyMs: Date.now() - started, text });
    emitFallbackHint(text, workDir, opts);
    return 'question';
  }
}

// ── チャンネル Q&A (質問と判定されたときのインライン回答) ────────────────────
// git push / pull のみ（他の作業を含まない）を実行して結果を返す
// 「A機能を修正して git push して」のような複合指示には反応しない
function isPureGitOp(text) {
  // Korean/Chinese/全角を除去し、残ったテキストが git コマンドとその助詞のみか確認
  const stripped = text
    .replace(/<[^>]+>/g, '')          // Slack mrkdwn タグ除去
    .replace(/[^\x00-\x7Fぁ-ん亜-熙ー]/g, ' ')  // Korean等を空白に
    .trim();
  // "git push [して/する/お願い/etc]" のみで構成されているか
  return /^git\s+(push|pull)(\s+(して|する|してください|お願い|please|원|해줘|해주세요))?$/i.test(stripped);
}

module.exports = { isGoCmd, isCancelCmd, isForceTaskCmd, isConfirmationQuery, isReadOnlyLookup, isPureGitOp, classifyRequest };
