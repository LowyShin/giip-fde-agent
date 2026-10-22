/** Keep human instructions separate from model-authored plans and summaries. */
function extract(taskContent) {
  const text = String(taskContent || '');
  const entries = [];
  const request = text.match(/^request:\s*("(?:\\.|[^"\\])*"|[^\r\n]*)/m);
  if (request) {
    let value = request[1];
    if (value.startsWith('"')) {
      try { value = JSON.parse(value); } catch { value = value.slice(1, -1); }
    }
    if (value.trim()) entries.push({ source: '원 요청', text: value.trim() });
  }
  // Revisions and Slack notes are human instructions; task plans are not.
  for (const match of text.matchAll(/^### 추가 요청\s*\r?\n([\s\S]*?)(?=^### 갱신된 계획|^## 개정 |^## 추가 지시 \(Slack,|^## 작업 완료 보고서|(?![\s\S]))/gm)) {
    if (match[1].trim()) entries.push({ source: '개정 요청', text: match[1].trim() });
  }
  for (const match of text.matchAll(/^## 추가 지시 \(Slack,[^\n]*\)\s*\r?\n([\s\S]*?)(?=^## 추가 지시 \(Slack,|^## 개정 |^## 작업 완료 보고서|(?![\s\S]))/gm)) {
    if (match[1].trim()) entries.push({ source: 'Slack 추가 지시', text: match[1].trim() });
  }
  return entries;
}

function render(taskContent) {
  const entries = extract(taskContent);
  const value = entries.map(e => `[${e.source}]\n${e.text}`).join('\n\n');
  if (value.length > 12000) {
    throw new Error('사용자 지시 원문이 12,000자를 초과함 — 요약으로 대체하지 말고 태스크를 분리해야 함');
  }
  return value;
}

module.exports = { extract, render };
